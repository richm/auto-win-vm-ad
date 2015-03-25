#!/bin/sh

set -o errexit

# USAGE:
# $0 file1.conf file2.conf ... fileN.conf setupscript4.cmd.in ... setupscriptN.cmd.in
while [ -n "$1" ] ; do
    case "$1" in
    *.conf) . $1 ; shift ;;
    *) break ;;
    esac
done

if [ -n "$VM_DEBUG" ] ; then
    set -x
fi

if $SUDOCMD virsh dominfo $VM_NAME ; then
    echo VM $VM_NAME already exists
    echo If you want to recreate it, do
    echo  $SUDOCMD virsh destroy $VM_NAME
    echo  $SUDOCMD virsh undefine $VM_NAME --remove-all-storage
    echo and re-run this script
    exit 0
fi

MAKE_AD_VM_DIR=${MAKE_AD_VM_DIR:-`dirname $0`}
# lots of parameters to set or override
VM_IMG_DIR=${VM_IMG_DIR:-/var/lib/libvirt/images}
ANS_FLOPPY=${ANS_FLOPPY:-$VM_IMG_DIR/answerfloppy.vfd}
FLOPPY_MNT=${FLOPPY_MNT:-/mnt/floppy}
WIN_VER_REL_ARCH=${WIN_VER_REL_ARCH:-win2k8x8664}
ANS_FILE_DIR=${ANS_FILE_DIR:-$MAKE_AD_VM_DIR/answerfiles}
PRODUCT_KEY_FILE=${PRODUCT_KEY_FILE:-$ANS_FILE_DIR/$WIN_VER_REL_ARCH.key}
#WIN_ISO=${WIN_ISO:-$VM_IMG_DIR/en_windows_server_2008_r2_standard_enterprise_datacenter_web_x64_dvd_x15-50365.iso}
# windows server needs lots of ram, cpu, disk
# size in MB
VM_RAM=${VM_RAM:-2048}
VM_CPUS=${VM_CPUS:-2}
# size in GB
VM_DISKSIZE=${VM_DISKSIZE:-16}
VM_NAME=${VM_NAME:-ad}
WIN_VM_DISKFILE=${WIN_VM_DISKFILE:-$VM_IMG_DIR/$VM_NAME.qcow2}
ADMINNAME=${ADMINNAME:-Administrator}
SETUP_PATH=${SETUP_PATH:-"E:"}
VM_OS_VARIANT=${VM_OS_VARIANT:-win2k8}
VM_WAIT_FILE=${VM_WAIT_FILE:-"\\\\installcomplete"}
VM_TIMEOUT=${VM_TIMEOUT:-120}

# fix .in files
do_subst()
{
    $SUDOCMD sed -e "s/@ADMINPASSWORD@/$ADMINPASSWORD/g" \
        -e "s/@DOMAINNAME@/$VM_DOMAIN/g" \
        -e "s/@ADMINNAME@/$ADMINNAME/g" \
        -e "s/@VM_AD_DOMAIN@/$VM_DOMAIN/g" \
        -e "s/@VM_NETBIOS_NAME@/$VM_NETBIOS_NAME/g" \
        -e "s/@VM_NAME@/$VM_NAME/g" \
        -e "s/@VM_FQDN@/$VM_FQDN/g" \
        -e "s/@VM_AD_SUFFIX@/$VM_AD_SUFFIX/g" \
        -e "s/@PRODUCT_KEY@/$PRODUCT_KEY/g" \
        -e "s/@SETUP_PATH@/$SETUP_PATH/g" \
        -e "s/@VM_WAIT_FILE@/$VM_WAIT_FILE/g" \
        -e "s/@AD_FOREST_LEVEL@/$AD_FOREST_LEVEL/g" \
        -e "s/@AD_DOMAIN_LEVEL@/$AD_DOMAIN_LEVEL/g" \
        $1
}

wait_for_completion() {
    # $VM_NAME $VM_TIMEOUT $VM_WAIT_FILE
    # wait up to VM_TIMEOUT minutes for VM_NAME to be
    # done with installation - this method uses
    # virt-ls to look for a file in the vm - when
    # the file is present, installation/setup is
    # complete - keep polling every minute until
    # the file is found or we hit the timeout
    slash='\\'
    # wait_file uses windows style paths, but
    # virt-ls needs *nix style paths
    my_wait_file=`echo "$VM_WAIT_FILE" | tr -s "$slash" /`
    ii=$VM_TIMEOUT
    while [ $ii -gt 0 ] ; do
        if $SUDOCMD virt-cat -d $VM_NAME "$my_wait_file" > /dev/null 2>&1 ; then
            return 0
        fi
        ii=`expr $ii - 1`
        sleep 60
    done
    echo Error: $VM_NAME $VM_WAIT_FILE not found after $VM_TIMEOUT minutes
    return 1
}

if [ -z "$ADMINPASSWORD" ] ; then
    echo Error: you must supply the password for $ADMINNAME
    echo in the ADMINPASSWORD environment variable
    exit 1
fi

if [ -z "$PRODUCT_KEY" -a -f $PRODUCT_KEY_FILE ] ; then
    read PRODUCT_KEY < $PRODUCT_KEY_FILE
fi

if [ -z "$PRODUCT_KEY" ] ; then
    case $WIN_VER_REL_ARCH in
    win2012*) echo Error: Windows 2012 requires a product key for installation ; exit 1 ;;
    esac
fi

VM_NETWORK_NAME=${VM_NETWORK_NAME:-default}
VM_NETWORK=${VM_NETWORK:-"network=$VM_NETWORK_NAME,model=rtl8139"}
#VM_NETWORK=bridge=virbr0,model=rtl8139
if [ -z "$VM_NO_MAC" -a -z "$VM_MAC" ] ; then
    # try to get the mac addr from virsh
    VM_MAC=`$SUDOCMD virsh net-dumpxml $VM_NETWORK_NAME | grep "'"$VM_NAME"'"|sed "s/^.*mac='\([^']*\)'.*$/\1/"`
    if [ -z "$VM_MAC" ] ; then
        echo Error: your machine $VM_MAC has no mac address in virsh net-dumpxml $VM_NETWORK_NAME
        echo Please use virsh net-edit $VM_NETWORK_NAME to specify the mac address for $VM_MAC
        echo or set VM_MAC=mac:addr in the environment
        exit 1
    fi
fi

if [ -n "$VM_MAC" ] ; then
    VM_NETWORK="$VM_NETWORK,mac=$VM_MAC"
fi

if [ -z "$VM_FQDN" ] ; then
    # try to get the ip addr from virsh
    VM_IP=`$SUDOCMD virsh net-dumpxml $VM_NETWORK_NAME | grep "'"$VM_NAME"'"|sed "s/^.*ip='\([^']*\)'.*$/\1/"`
    if [ -z "$VM_IP" ] ; then
        echo Error: your machine $VM_NAME has no IP address in virsh net-dumpxml $VM_NETWORK_NAME
        echo Please use virsh net-edit $VM_NETWORK_NAME to specify the IP address for $VM_NAME
        echo or set VM_FQDN=full.host.domain in the environment
        exit 1
    fi
    VM_FQDN=`getent hosts $VM_IP|awk '{print $2}'`
    echo using hostname $VM_FQDN for $VM_NAME with IP address $VM_IP
fi

# now that we have the fqdn, construct our suffix
lmhn=`echo $VM_FQDN | sed -e 's/^\([^.]*\).*$/\1/'`
domain=`echo $VM_FQDN | sed -e 's/^[^.]*\.//'`
VM_DOMAIN=${VM_DOMAIN:-"$domain"}
lmdn=`echo $VM_DOMAIN | sed -e 's/^\([^.]*\).*$/\1/'`
suffix=`echo $VM_DOMAIN | sed -e 's/^/dc=/' -e 's/\./,dc=/g'`
netbios=`echo $VM_DOMAIN | sed -e 's/\.//g' | tr '[a-z]' '[A-Z]'`
VM_CA_NAME=${VM_CA_NAME:-"$lmdn-$lmhn-ca"}
VM_AD_SUFFIX=${VM_AD_SUFFIX:-"$suffix"}
VM_NETBIOS_NAME=${VM_NETBIOS_NAME:-"$netbios"}
ADMIN_DN=${ADMIN_DN:-"cn=$ADMINNAME,cn=users,$VM_AD_SUFFIX"}

if [ -z "$AD_FOREST_LEVEL" -o -z "$AD_DOMAIN_LEVEL" ] ; then
    case $WIN_VER_REL_ARCH in
    win2k8*) AD_FOREST_LEVEL=${AD_FOREST_LEVEL:-4}
             AD_DOMAIN_LEVEL=${AD_DOMAIN_LEVEL:-4} ;;
    win2012*) AD_FOREST_LEVEL=${AD_FOREST_LEVEL:-Win2012}
              AD_DOMAIN_LEVEL=${AD_DOMAIN_LEVEL:-Win2012} ;;
    *) echo Error: unknown windows version $WIN_VER_REL_ARCH
       echo Please set AD_FOREST_LEVEL and AD_DOMAIN_LEVEL ;;
    esac
fi

if [ -d $ANS_FILE_DIR/$WIN_VER_REL_ARCH ] ; then
    WIN_VER_REL_ARCH_DIR=$ANS_FILE_DIR/$WIN_VER_REL_ARCH
else
    case $WIN_VER_REL_ARCH in
    win2012*) WIN_VER_REL_ARCH_DIR=$ANS_FILE_DIR/win2012x8664 ;;
    esac
fi

if [ -n "$USE_FLOPPY" ] ; then
    if [ ! -f $ANS_FLOPPY ] ; then
        $SUDOCMD mkfs.vfat -C $ANS_FLOPPY 1440 || { echo error $? from mkfs.vfat -C $ANS_FLOPPY 1440 ; exit 1 ; }
    fi

    if [ ! -d $FLOPPY_MNT ] ; then
        $SUDOCMD mkdir -p $FLOPPY_MNT || { echo error $? from mkdir -p $FLOPPY_MNT ; exit 1 ; }
    fi

    $SUDOCMD mount -o loop -t vfat $ANS_FLOPPY $FLOPPY_MNT || { echo error $? from mount -o loop -t vfat $ANS_FLOPPY $FLOPPY_MNT ; exit 1 ; }

    # replace .in files with the real data
    # convert to DOS format to make them easier to read in Windows
    # files in answerfiles/winverrel/ will override files in answerfiles/ if
    # they have the same name - this allow to provide version specific files
    # to override the more general ones in answerfiles/
    for file in $ANS_FILE_DIR/* $WIN_VER_REL_ARCH_DIR/* "$@" ; do
        if [ ! -f "$file" ] ; then continue ; fi
        err=
        case $file in
            *$WIN_VER_REL_ARCH.xml*) outfile=$FLOPPY_MNT/autounattend.xml ;;
            *) outfile=$FLOPPY_MNT/`basename $file .in` ;;
        esac
        case $file in
            *.in) do_subst $file | $SUDOCMD sed 's/$//' > $outfile || err=$? ;;
            *) $SUDOCMD sed 's/$//' $file > $outfile || err=$? ;;
        esac
        if [ -n "$err" ] ; then
            echo error $err copying $file to $outfile  ; $SUDOCMD umount $FLOPPY_MNT ; exit 1
        fi
    done

    $SUDOCMD umount $FLOPPY_MNT || { echo error $? from umount $FLOPPY_MNT ; exit 1 ; }
    VI_FLOPPY="--disk path=$ANS_FLOPPY,device=floppy"
else
    # just put everything on the CD
    # first need a staging area
    # files in answerfiles/winverrel/ will override files in answerfiles/ if
    # they have the same name - this allow to provide version specific files
    # to override the more general ones in answerfiles/
    staging=`mktemp -d`
    for file in $ANS_FILE_DIR/* $WIN_VER_REL_ARCH_DIR/* "$@" ; do
        if [ ! -f "$file" ] ; then continue ; fi
        err=
        case $file in
            *$WIN_VER_REL_ARCH.xml*) outfile=$staging/autounattend.xml ;;
            *) outfile=$staging/`basename $file .in` ;;
        esac
        case $file in
            *.in) do_subst $file | $SUDOCMD sed 's/$//' > $outfile || err=$? ;;
            *.vbs|*.cmd|*.txt|*.inf|*.ini|*.xml) $SUDOCMD sed 's/$//' $file > $outfile || err=$? ;;
            # just assume everything else is binary or we don't want to convert it
            *) $SUDOCMD cp -p $file $outfile || err=$? ;;
        esac
        if [ -n "$err" ] ; then
            echo error $err copying $file to $outfile  ; exit 1
        fi
    done
    EXTRAS_CD_ISO=${EXTRAS_CD_ISO:-$VM_IMG_DIR/$VM_NAME-extra-cdrom.iso}
    $SUDOCMD rm -f $EXTRAS_CD_ISO
    $SUDOCMD genisoimage -iso-level 4 -J -l -R -o $EXTRAS_CD_ISO $staging/* || { echo Error $? from genisoimage $EXTRAS_CD_ISO $staging/* ; exit 1 ; }
    # this does not work - causes windows to display an error dialog if set not complete
    # also get this error:
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] In-use cached unattend file for [oobeSystem] is still present at [C:\Windows\panther\unattend.xml].
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] Running oobeSystem pass with discovered unattend file [C:\Windows\panther\unattend.xml]...
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] Caching copy of unattend file: [C:\Windows\panther\unattend.xml] -- cached at --> [C:\Windows\panther\unattend.xml]
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] Source and destination paths are identical; skipping file copy.
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] Cached unattend file, returned: [%windir%\panther\unattend.xml]
# 2014-06-05 10:40:55, Info                         [oobeldr.exe] Current pass status for [oobeSystem] is [0x1]
# 2014-06-05 10:40:55, Error                        [oobeldr.exe] Pass has failed status; system is in an invalid state.

    # if [ -f $WIN_VM_DISKFILE ] ; then
    #     # write the autounattend.xml to c:\Windows\Panther\unattend.xml
    #     $SUDOCMD cp -p $staging/autounattend.xml $staging/unattend.xml
    #     $SUDOCMD virt-copy-in -a $WIN_VM_DISKFILE $staging/unattend.xml /Windows/Panther
    # fi
    if [ "$VM_DEBUG" = "2" ] ; then
        echo examine staging $staging
    else
        rm -rf $staging
    fi
    VI_EXTRAS_CD="--disk path=$EXTRAS_CD_ISO,device=cdrom"
fi

serialpath=/tmp/serial-`date +'%Y%m%d%H%M%S'`.$$

if $SUDOCMD test -n "$WIN_VM_DISKFILE_BACKING" -a -f "$WIN_VM_DISKFILE_BACKING" ; then
    # use the given diskfile as our backing file
    # make a new one based on the vm name
    # NOTE: We cannot create an image which is _smaller_ than the backing image
    # we have to grab the current size of the backing file, and omit the disk size
    # argument if VM_DISKSIZE is less than or equal to the backing file size
    # strip the trailing M, G, etc.
    bfsize=`$SUDOCMD qemu-img info $WIN_VM_DISKFILE_BACKING | awk '/virtual size/ {print gensub(/[a-zA-Z]/, "", "g", $3)}'`
    if [ $VM_DISKSIZE -gt $bfsize ] ; then
        sizearg=${VM_DISKSIZE}G
    else
        echo disk size $VM_DISKSIZE for $WIN_VM_DISKFILE is smaller than the size $bfsize of the backing file $WIN_VM_DISKFILE_BACKING
        echo the given disk size cannot be smaller than the backing file size
        echo new vm will use size $bfsize
    fi
    $SUDOCMD qemu-img create -f qcow2 -b $WIN_VM_DISKFILE_BACKING $WIN_VM_DISKFILE $sizearg
    post_disk_image_create $WIN_VM_DISKFILE
elif $SUDOCMD test -n "$WIN_VM_DISKFILE" -a -f "$WIN_VM_DISKFILE" ; then
    post_disk_image_create $WIN_VM_DISKFILE
fi

if $SUDOCMD test ! -f "$WIN_VM_DISKFILE" ; then
    VM_CDROM="--cdrom $WIN_ISO"
fi

$SUDOCMD virt-install --connect=qemu:///system --hvm \
    --accelerate --name "$VM_NAME" --ram=$VM_RAM --vcpu=$VM_CPUS \
    $VM_CDROM --vnc --os-variant ${VM_OS_VARIANT}  \
    --serial file,path=$serialpath --serial pty \
    --disk path=$WIN_VM_DISKFILE,bus=ide,size=$VM_DISKSIZE,format=qcow2,cache=none \
    $VI_FLOPPY $VI_EXTRAS_CD \
    --network=$VM_NETWORK \
    ${VM_DEBUG:+"-d"} --noautoconsole || { echo error $? from virt-install ; exit 1 ; }

echo now we wait for everything to be set up
wait_for_completion $VM_NAME $VM_TIMEOUT "$VM_WAIT_FILE"

LDAPREQCERT=demand
if [ -n "$VM_NO_MAC" ] ; then
    # there is no resolvable fqdn for the new host - grab the
    # mac from the domain, then grab the ip from arp
    macaddr=`$SUDOCMD virsh dumpxml "$VM_NAME"|awk -F"[ =']+" '/mac address/ {print $4}'`
    ipaddr=`arp -e|awk '/'"$macaddr"'/ {print $1}'`
    LDAPURL="ldap://$ipaddr"
    LDAPREQCERT=never
else
    # can't use the hostname if using a private network - grab the ip address
    # from the network
    if [ -z "$VM_IP" ] ; then
        VM_IP=`$SUDOCMD virsh net-dumpxml $VM_NETWORK_NAME | grep "'"$VM_NAME"'"|sed "s/^.*ip='\([^']*\)'.*$/\1/"`
    fi
    LDAPURL="ldap://$VM_IP"
    LDAPREQCERT=never
fi
CA_CERT_DN="cn=$VM_CA_NAME,cn=certification authorities,cn=public key services,cn=services,cn=configuration,$VM_AD_SUFFIX"

TMP_CACERT=/tmp/cacert.`date +'%Y%m%d%H%M%S'`.$$.pem
echo "-----BEGIN CERTIFICATE-----" > $TMP_CACERT
ldapsearch -xLLL -H $LDAPURL -D "$ADMIN_DN" -w "$ADMINPASSWORD" -s base \
    -b "$CA_CERT_DN" "objectclass=*" cACertificate | perl -p0e 's/\n //g' | \
    sed -e '/^cACertificate/ { s/^cACertificate:: //; s/\(.\{1,64\}\)/\1\n/g; p }' -e 'd' | \
    grep -v '^$' >> $TMP_CACERT
echo "-----END CERTIFICATE-----" >> $TMP_CACERT

echo Now test our CA cert
if LDAPTLS_REQCERT=$LDAPREQCERT LDAPTLS_CACERT=$TMP_CACERT ldapsearch -xLLL -ZZ -H $LDAPURL \
    -D "$ADMIN_DN" -w "$ADMINPASSWORD" -s base -b "" \
    "objectclass=*" currenttime > /dev/null 2>&1 ; then
    echo Success - the CA cert in $TMP_CACERT is working
else
    echo Error: the CA cert in $TMP_CACERT is not working
    LDAPTLS_REQCERT=$LDAPREQCERT LDAPTLS_CACERT=$TMP_CACERT ldapsearch -d 1 -xLLL -ZZ -H $LDAPURL -s base \
        -b "" "objectclass=*" currenttime
fi

if [ -n "$WIN_CA_CERT_FILE" ] ; then
    cp -p $TMP_CACERT $WIN_CA_CERT_FILE
    rm -f $TMP_CACERT
fi

exit 0
