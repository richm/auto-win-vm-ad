auto-win-vm-ad
==============

Automatically create Windows Virtual Machines with Active Directory
and Certificate Services

This allows you to create a Windows VM complete with Active Directory
and Certificate Services, and Active Directory TLS/SSL enabled,
completely automated and unattended.

Currently only tested on RHEL 6.X and Fedora 20 with
kvm/qemu virtualization, Windows Server 2008 R2 Enterprise
Datacenter 64-bit, and Windows Server 2012 Enterprise Datacenter 64-bit

Now supports using Windows disk images, including with backing images.
WARNING: Using backing images may not work when testing for VM install/setup completion using VM_WAIT_FILE.  On Fedora 20, virt-win-reg --merge will somehow corrupt the registry SOFTWARE hive, leading to hivex errors when using virt-ls and virt-cat to test for existence of the VM_WAIT_FILE.  For now, if you want to reuse a Windows disk image, make a copy, and do not use a backing file (WIN_VM_BACKING_DISKFILE).  This is slower but more robust.

Pre-Requisites
==============

These are the tools I've used so far:
* Fedora 20 64-bit packages and commands with KVM/QEMU
| Package            | Commands         | Notes                                                    |
|--------------------|------------------|----------------------------------------------------------|
| libvirt-daemon     | libvirtd         | virtual machine service daemon                           |
| libvirt-client     | virsh            | virtual machine/network management                       |
| virt-install       | virt-install     | virtual machine creation                                 |
| libguestfs-tools   | virt-win-reg     | windows vm registry reader                               |
| libguestfs-tools-c | virt-cat         | used to check for the wait file                          |
| qemu-system        | qemu-kvm, others | core virt package                                        |
| openldap-clients   | ldapsearch       | for testing AD connection and getting AD CA cert         |
| genisoimage        | genisoimage      | for creating the CD-ROM answerfile disk                  |
| dosfstools         | mkfs.vfat        | OPTIONAL: if you need to make a floppy  based answerfile |

* RHEL 6.x 64-bit with KVM/QEMU
** qemu-kvm - the basic virtualization packages
** python-virtinst - virt-install
** qemu-img
** libvirt-client - virsh
** dosfstools - mkfs.vfat
** openldap-clients - for testing the AD connection and getting the AD CA cert
** genisoimage - "extras" CD
** virt-win-reg, virt-cat

* Make sure libvirtd is running::

    # systemctl start libvirtd.service
    OR
    # service libvirtd start

* en_windows_server_2008_r2_standard_enterprise_datacenter_web_x64_dvd_x15-50365.iso
** an MSDN subscription is required for access to Windows ISO files
   and product keys
** I know 2008 R2 Enterprise Datacenter comes with Active Directory
   and Certificate Services
** Not sure what other versions contain these
** autounattend.xml, dcinstall.ini, adcertreq.inf, and the cmd scripts
   depend on this version
* en_windows_server_2012_x64_dvd_915478.iso
** an MSDN subscription is required for access to Windows ISO files
   and product keys
** I know 2012 Datacenter comes with Active Directory and Certificate Services
** Not sure what other versions contain these
** autounattend.xml, setupad.ps1, setupca.ps1, adcertreq.inf, and the cmd scripts
   depend on this version

* Windows Server 2008 image files
** See http://www.freeipa.org/page/Setting_up_Active_Directory_domain_for_testing_purposes
** NOTE: This script basically automates those steps
** Use 'unar' instead of 'unrar' on Fedora 20

* KVM/Machine setup
** In addition to the below, you can create a new virtual network with
   (e.g. virsh net-define and net-start), and pass in the name of the
   network using VM_NETWORK_NAME
   - advantage - no messing around with your system
   - disadvantage - host resolution doesn't just work automatically
                    need to use the IP address of the network e.g.
                    $ dig @192.168.122.1 ad.domain.local
** In order to easily keep track of the VM hostname/IP address I have
   done the following:
** edit /etc/hosts - assign an IP address and FQDN for the VM
   e.g. something like this:
 192.168.122.2 ad.test.example.com ad
** The FQDN must be the first one listed (just like for SSL/Kerberos
   testing)
** add your new vm/ip addr/mac address
*** virsh net-destroy default - virt network must be stopped first
*** virsh net-edit default - add a name, the IP address from above, and
    a unique MAC address to the <dhcp> section like this::

    <mac address='52:54:00:xx:xx:xx'/>
    <ip address='192.168.122.1' netmask='255.255.255.0'>
      <dhcp>
        <range start='192.168.122.128' end='192.168.122.254' />
        <host mac='54:52:00:xx:yy:zz' name='win2k8' ip='192.168.122.2' />

   That is, add a new <host ...> entry with a unique IP address and mac address
   The mac address must start with 54:52:00: and must be unique.
   The VM name (name='win2k8') does not have to match the hostname, but it must be
   the same as the VM_NAME parameter (see below)
*** you can generate a random qemu MAC address like this::

    gen_virt_mac() {
      echo 54:52:00`hexdump -n3 -e '/1 ":%02x"' /dev/random`
    }
    VM_MAC=`gen_virt_mac`

*** virsh net-start default - start up virt network
*** virsh net-dumpxml default - verify that your new host entry is listed

You will need to provide at least the name of the VM to the script.
The script will attempt to find the FQDN, the IP address, and the MAC
address (or you can provide these).

Running
=======

1) Create your config file using the variables listed below
2) Create additional setupscriptN.cmd.in files to be run post-setup
3) make-ad-vm.sh windows.conf . . . fileN.conf setupscript4.cmd.in ... setupscriptN.cmd.in

There are many, many parameters you can pass as environment variables or
in a config file.  Parameters passed in the environment override those
in a config file.

PRODUCT_KEY - 25 character product key which must correspond exactly to the windows iso you are installing
* no default - must be provided or use PRODUCT_KEY_FILE
PRODUCT_KEY_FILE - can put the product key in a file instead of passing in PRODUCT_KEY
* no default - must be provided or use PRODUCT_KEY
VM_NAME - name of virtual machine
* default - ad
VM_IMG_DIR - path to your KVM/QEMU disk images
* default - /var/lib/libvirt/images
ANS_FILE_DIR - path to the config files and scripts used during Windows install/setup
* default - `dirname $0`/answerfiles
WIN_VER_REL_ARCH - windows version, release, arch
* default - win2k8x8664
* must correspond to the WIN_ISO
WIN_ISO - the full path and file name of the Windows install ISO
* default - $VM_IMG_DIR/en_windows_server_2008_r2_standard_enterprise_datacenter_web_x64_dvd_x15-50365.iso
WIN_VM_DISKFILE - the full path and file name of the Windows VM disk image
* default - $VM_IMG_DIR/$VM_NAME.qcow2
WIN_VM_DISKFILE_BACKING - use this as the backing file for WIN_VM_DISKFILE
* no default - if you specify this, then this will be the read-onlh "base"
* image, and WIN_VM_DISKFILE will be the writable image, containing only
* the changes
* WARNING: May not work with VM_WAIT_FILE - see above
VM_WAIT_FILE - The presence of this file is how make-ad-vm.sh knows that
setup is complete.  The very last setup phase will create a dummy file with
this name.   
* default - \\\\installcomplete
** NOTE: In your config, you must use 4 backslashes for every backslash
in the real file as it will be in Windows, in order to preserve them through
all of the layers of shell/sed indirection and processing e.g.::

    VM_WAIT_FILE="\\\\installcomplete"

VM_RAM - amount of RAM to use for VM, in MB
* default - 2048 (2GB)
VM_CPUS - number of CPUs to use for VM
* default - 2
VM_DISKSIZE - size of WIN_VM_DISKFILE in GB
* default - 16
** NOTE: Windows Server needs a lot of disk space
ADMINNAME - user of Windows admin account
* default - Administrator
ADMINPASSWORD - password for ADMINNAME account
* no default - must be provided
VM_MAC - MAC address for VM
* default - will lookup from virsh net-dumpxml default for the VM name
VM_FQDN - fully qualified host and domain name for the VM
* default - will lookup from virsh net-dumpxml and getent hosts from the VM name
VM_CA_NAME - the name of the CA that will be created
* default - LMDN-LMHN-ca - where
** LMDN is the leftmost part of the domain name e.g. if your VM_FQDN is ad.test.example.com
** then the LMDN is "test"
** LMHN is the leftmost part of the FQDN e.g. if your VM_FQDN is ad.test.example.com
** then the LMHN is "ad"
** so the VM_CA_NAME would be test-ad-ca
VM_DOMAIN - the domain of the AD server
* default - the part of VM_FQDN after the hostname part e.g. if VM_FQDN is ad.test.example.com
* the domain is test.example.com
VM_AD_SUFFIX - the AD root suffix
* default - derived from the VM_AD_DOMAIN - e.g. test.example.com -> dc=test,dc=example,dc=com
VM_NETBIOS_NAME - the NETBIOS domain name
* default - derived from VM_AD_DOMAIN e.g. test.example.com -> TESTEXAMPLECOM
ADMIN_DN - the full AD DN of the Windows Administrator
* default - cn=$ADMINNAME,cn=users,$VM_AD_SUFFIX
AD_DOMAIN_LEVEL - 4 == 2008 R2, Win2012 == 2012
* default - same as version specifed in WIN_VER_REL_ARCH
AD_FOREST_LEVEL - 4 == 2008 R2, Win2012 == 2012
* default - same as version specifed in WIN_VER_REL_ARCH

Windows
=======
Windows supports unattended install and setup.  In 2008 and some other
new-ish versions, this is done via a file called autounattend.xml.
When Windows boots off of the ISO, it looks for a file called
autounattend.xml in the root directory of all removable media.  We use
a virtual CD-ROM as drive D:\ or E:\ in Windows and put the file there.

Setup goes through several different phases, or "passes" in Windows
parlance.  The last pass is oobeSystem.  It is during this pass that
we set the first of our "callback" scripts, postinstall.cmd.  We first
set Windows to AutoLogin the Administrator so that we can use the
FirstLogonCommands and later RunOnce commands, and tell it to
AutoLogin up to 999 times.  We use the FirstLogonCommands SynchronousCommand
to run the postinstall.cmd script.  This activates windows with the
given PRODUCT_KEY, creates the RunOnce script for the next setup pass
(setupscript1.cmd), and reboots.

The setupscripts provided by the project, and any that you provide, are
usually going to be templates (.cmd.in).  The ".in" means that any tokens
in the file (e.g. @ADMINNAME@) will be replaced with the actual value
provided in the config (e.g. the value of $ADMINNAME e.g. "Administrator")
during writing the files to the virtual CD-ROM.  For example, the answerfile
setupscript1.cmd.in will be written as D:\setupscript1.cmd.  Any text files
not ending in .in will not have substitution performed on them, but will be
converted from unix LF to Windows CRLF line endings.  Any non text files
such as .exe, .msi, etc. will just be copied directly to the virtual CD-ROM.

When using a disk image that has already been setup, it may still run
the oobe phase.  The sample ad.conf file shows how to use virt-win-reg
to set the registry after the disk image has been created, to tell
setup to use the unattend.xml we provide, which will complete the
unattended setup.  For example::

    [HKLM\SYSTEM\Setup]
    "UnattendFile"="$SETUP_PATH\\autounattend.xml"

Where $SETUP_PATH is the virtual CD-ROM drive created by make-ad-vm.sh.
Using a disk image will also require setting up Windows to do
AutoAdminLogin::

    [HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon]
    "AutoAdminLogon"="1"
    "DefaultUserName"="$ADMINNAME"
    "DefaultPassword"="$ADMINPASSWORD"

During setupscript1 pass, setupscript1.cmd uses dcpromo.exe (2008) or
setupad.ps1 (2012) to setup Active Directory with our chosen domain.
It also activates Windows with the specified product key (if any - the
2008 evaluation disk images do not require a key, but pay attention to
the terms of the EULA!).  At the end, it creates the RunOnce script for
the next setup pass (setupscript1.cmd), and tells Windows to reboot in
2 minutes.  Active Directory requires a reboot in order to complete the
setup process.

During the setupscript2 pass at next login, we install and configure
Certificate Services in Standalone Root CA mode - setupca.vbs /IS
(2008) or setupca.ps1 (2012) - then set the RunOnce to run
setupscript3.cmd, and reboot again in 2 minutes.

During the setupscript3 pass at next login, we generate an AD server
cert request, submit it to the CA, sign it, and install it in the AD
cert repo, using certreq and certutil.  Once this is done, AD will
automatically configure itself to be a TLS/SSL server.

If you want to perform additional post-setup tasks, create setupscript files
starting with number 4 e.g. setupscript4.cmd.in, setupscript5.cmd.in, etc.
and pass these to make-ad-vm.sh after the config files.  These additional files
will be placed on the virtual CD-ROM and run.

The different Windows files are:
PLATFORM.xml - e.g. win2k8x8664.xml - this is copied to the virtual CD-ROM as the main
autounattend.xml file
postinstall.cmd - activate Windows with the specified product key, reboot
setupscript2.cmd - install and setup AD, setup pass2, reboot
setupscript2.cmd - install and setup Cert Services, setup pass3, reboot
setupscript3.cmd - request and install AD server cert
dcinstall.ini - unattended setup file for AD (2008)
adcertreq.inf - unattended AD cert request file
Setupca.vbs - Virtual Basic script that installs and sets up Cert Services (2008)
setupad.ps1 - unattended setup file for AD (2012)
setupca.ps1 - unattended setup file for CA (2012)

Windows Troubleshooting
=======================
For general setup issues, look in c:\windows\panther\setup*.log

dcpromo - c:\dcinstall.log (2008 only)
setupca.vbs - c:\_setupca.log (2008 only)
postinstall - c:\postinstall.log
setupscript1 - c:\setupscript1.log
setupscript2 - c:\setupscript2.log
setupscript3 - c:\setupscript3.log

References
==========
Windows Unattended Installation Information for 2008
* http://technet.microsoft.com/en-us/library/cc730695%28v=WS.10%29.aspx
Sample Unattend.xml files for 2008
* http://technet.microsoft.com/en-us/library/cc732280(v=ws.10)
Enabling TLS/SSL in Active Directory
* http://www.richardhyland.com/diary/2009/05/12/installing-a-ssl-certificate-on-your-domain-controller/
* http://support.microsoft.com/default.aspx?scid=kb;en-us;321051
Windows certreq reference
* http://technet.microsoft.com/en-us/library/cc736326%28v=ws.10%29
Source for Setupca.vbs
* http://blogs.technet.com/b/pki/archive/2009/09/18/automated-ca-installs-using-vb-script-on-windows-server-2008-and-2008r2.aspx
* http://technet.microsoft.com/en-us/library/ee918754(WS.10).aspx
Info for 2012 Active Directory
* http://technet.microsoft.com/en-us/library/hh472162.aspx
