#!/bin/sh

# lots of parameters to set or override
VM_IMG_DIR=${VM_IMG_DIR:-/export1/kvmimages}
ANS_FLOPPY=${ANS_FLOPPY:-$VM_IMG_DIR/answerfloppy.vfd}
ANS_FILE_DIR=${ANS_FILE_DIR:-/share/auto-win-vm-ad}
FLOPPY_MNT=${FLOPPY_MNT:-/mnt/floppy}
WIN_VER_REL_ARCH=${WIN_VER_REL_ARCH:-win2k8x8664}
WIN_ISO=${WIN_ISO:-$VM_IMG_DIR/en_windows_server_2008_r2_standard_enterprise_datacenter_web_x64_dvd_x15-50365.iso}
WIN_VM_DISKFILE=${WIN_VM_DISKFILE:-$VM_IMG_DIR/ad.raw}
# windows server needs lots of ram, cpu, disk
VM_RAM=${VM_RAM:-2048}
VM_CPUS=${VM_CPUS:-2}
VM_DISKSIZE=${VM_DISKSIZE:-16}
VM_NAME=${VM_NAME:-ad}

if [ -z "$AD_ROOTPW" ] ; then
    echo Error: you must supply the password for $AD_ROOTDN
    echo in the AD_ROOTPW environment variable
    exit 1
fi

if [ -z "$VM_MAC" ] ; then
    # try to get the mac addr from virsh
    VM_MAC=`virsh net-dumpxml default | grep "'"$VM_NAME"'"|sed "s/^.*mac='\([^']*\)'.*$/\1/"`
    if [ -z "$VM_MAC" ] ; then
        echo Error: your machine $VM_MAC has no mac address in virsh net-dumpxml default
        echo Please use virsh net-edit default to specify the mac address for $VM_MAC
        echo or set VM_MAC=mac:addr in the environment
        exit 1
    fi
fi

if [ -z "$VM_FQDN" ] ; then
    # try to get the ip addr from virsh
    VM_IP=`virsh net-dumpxml default | grep "'"$VM_NAME"'"|sed "s/^.*ip='\([^']*\)'.*$/\1/"`
    if [ -z "$VM_IP" ] ; then
        echo Error: your machine $VM_NAME has no IP address in virsh net-dumpxml default
        echo Please use virsh net-edit default to specify the IP address for $VM_NAME
        echo or set VM_FQDN=full.host.domain in the environment
        exit 1
    fi
    VM_FQDN=`getent hosts $VM_IP|awk '{print $2}'`
    echo using hostname $VM_FQDN for $VM_NAME with IP address $VM_IP
fi

# now that we have the fqdn, construct our suffix
lmhn=`echo $VM_FQDN | sed -e 's/^\([^.]*\).*$/\1/'`
domain=`echo $VM_FQDN | sed -e 's/^[^.]*\.//'`
lmdn=`echo $domain | sed -e 's/^\([^.]*\).*$/\1/'`
suffix=`echo $domain | sed -e 's/^/dc=/' -e 's/\./,dc=/g'`
VM_CA_NAME=${VM_CA_NAME:-"$lmdn-$lmhn-ca"}
VM_AD_SUFFIX=${VM_AD_SUFFIX:-"$suffix"}
AD_ROOTDN=${AD_ROOTDN:-"cn=administrator,cn=users,$VM_AD_SUFFIX"}


if [ ! -f $ANS_FLOPPY ] ; then
    mkfs.vfat -C $ANS_FLOPPY 1440 || { echo error $! from mkfs.vfat -C $ANS_FLOPPY 1440 ; exit 1 ; }
fi

if [ ! -d $FLOPPY_MNT ] ; then
    mkdir -p $FLOPPY_MNT || { echo error $! from mkdir -p $FLOPPY_MNT ; exit 1 ; }

fi

mount -o loop -t vfat $ANS_FLOPPY $FLOPPY_MNT || { echo error $! from mount -o loop -t vfat $ANS_FLOPPY $FLOPPY_MNT ; exit 1 ; }

cp $ANS_FILE_DIR/$WIN_VER_REL_ARCH.xml $FLOPPY_MNT/autounattend.xml || { echo error $! from cp $ANS_FILE_DIR/$WIN_VER_REL_ARCH.xml $FLOPPY_MNT/autounattend.xml ; umount $FLOPPY_MNT ; exit 1 ; }

# convert to DOS format to make it easier to read on windows
for file in adcertreq.inf setuppass3.cmd setuppass2.cmd dcinstall.ini postinstall.cmd specialize.cmd Setupca.vbs SetupComplete.cmd audituser.cmd ; do
    sed 's/$//' $ANS_FILE_DIR/$file > $FLOPPY_MNT/$file || { echo error $! from sed $ANS_FILE_DIR/$file to $FLOPPY_MNT/$file  ; umount $FLOPPY_MNT ; exit 1 ; }
done

umount $FLOPPY_MNT || { echo error $! from umount $FLOPPY_MNT ; exit 1 ; }

serialpath=/tmp/serial-`date +'%Y%m%d%H%M%S'`.$$

virt-install --connect=qemu:///system --hvm \
    --accelerate --name "$VM_NAME" --ram=$VM_RAM --vcpu=$VM_CPUS \
    --cdrom $WIN_ISO --vnc --os-type windows  \
    --serial file,path=$serialpath --serial pty \
    --disk path=$WIN_VM_DISKFILE,bus=ide,size=$VM_DISKSIZE,format=raw,cache=none \
    --disk path=$ANS_FLOPPY,device=floppy \
    --network=bridge=virbr0,model=rtl8139,mac=$VM_MAC \
    $VI_DEBUG --noautoconsole || { echo error $! from virt-install ; exit 1 ; }

echo now we wait for everything to be set up
TRIES=100
SLEEPTIME=30
ii=0
while [ $ii -lt $TRIES ] ; do
    # this search will only return success if AD is TLS enabled
    if LDAPTLS_REQCERT=never ldapsearch -xLLL -ZZ -H ldap://$VM_FQDN -s base -b "" currenttime > /dev/null 2>&1 ; then
        echo Server is running and configured
        break
    else
        ii=`expr $ii + 1`
        echo Try $ii - waiting
        sleep $SLEEPTIME
    fi
done

if [ $ii -ge $TRIES ] ; then
    echo Error: VM AD not responding after $TRIES tries
    exit 1
fi

CA_CERT_DN="cn=$VM_CA_NAME,cn=certification authorities,cn=public key services,cn=services,cn=configuration,$VM_AD_SUFFIX"

TMP_CACERT=/tmp/cacert.`date +'%Y%m%d%H%M%S'`.$$.pem
echo "-----BEGIN CERTIFICATE-----" > $TMP_CACERT
ldapsearch -xLLL -H ldap://$VM_FQDN -D "$AD_ROOTDN" -w "$AD_ROOTPW" -s base -b "$CA_CERT_DN" "objectclass=*" cACertificate | perl -p0e 's/\n //g' | sed -e '/^cACertificate/ { s/^cACertificate:: //; s/\(.\{1,64\}\)/\1\n/g; p }' -e 'd' | grep -v '^$' >> $TMP_CACERT
echo "-----END CERTIFICATE-----" >> $TMP_CACERT

echo Now test our CA cert
if LDAPTLS_CACERT=$TMP_CACERT ldapsearch -xLLL -ZZ -H ldap://$VM_FQDN -s base -b "" currenttime > /dev/null 2>&1 ; then
    echo Success - the CA cert in $TMP_CACERT is working
else
    echo Error: the CA cert in $TMP_CACERT is not working
    LDAPTLS_CACERT=$TMP_CACERT ldapsearch -d 1 -xLLL -ZZ -H ldap://$VM_FQDN -s base -b "" currenttime
    exit 1
fi
