#!/bin/sh

# lots of parameters to set or override
VM_IMG_DIR=${VM_IMG_DIR:-/var/lib/libvirt/images}
ANS_FLOPPY=${ANS_FLOPPY:-$VM_IMG_DIR/answerfloppy.vfd}
FLOPPY_MNT=${FLOPPY_MNT:-/mnt/floppy}
WIN_VER_REL_ARCH=${WIN_VER_REL_ARCH:-win2k8x8664}
ANS_FILE_DIR=${ANS_FILE_DIR:-/share/auto-win-vm-ad/answerfiles}
PRODUCT_KEY_FILE=${PRODUCT_KEY_FILE:-$ANS_FILE_DIR/$WIN_VER_REL_ARCH.key}
WIN_ISO=${WIN_ISO:-$VM_IMG_DIR/en_windows_server_2008_r2_standard_enterprise_datacenter_web_x64_dvd_x15-50365.iso}
# windows server needs lots of ram, cpu, disk
# size in MB
VM_RAM=${VM_RAM:-2048}
VM_CPUS=${VM_CPUS:-2}
# size in GB
VM_DISKSIZE=${VM_DISKSIZE:-16}
VM_NAME=${VM_NAME:-ad}
WIN_VM_DISKFILE=${WIN_VM_DISKFILE:-$VM_IMG_DIR/$VM_NAME.raw}
ADMINNAME=${ADMINNAME:-Administrator}
SETUP_PATH=${SETUP_PATH:-"E:"}

# fix .in files
do_subst()
{
    $SUDOCMD sed -e "s/@ADMINPASSWORD@/$ADMINPASSWORD/g" \
        -e "s/@DOMAINNAME@/$VM_AD_DOMAIN/g" \
        -e "s/@ADMINNAME@/$ADMINNAME/g" \
        -e "s/@VM_AD_DOMAIN@/$VM_AD_DOMAIN/g" \
        -e "s/@VM_NETBIOS_NAME@/$VM_NETBIOS_NAME/g" \
        -e "s/@VM_NAME@/$VM_NAME/g" \
        -e "s/@VM_FQDN@/$VM_FQDN/g" \
        -e "s/@VM_AD_SUFFIX@/$VM_AD_SUFFIX/g" \
        -e "s/@PRODUCT_KEY@/$PRODUCT_KEY/g" \
        -e "s/@SETUP_PATH@/$SETUP_PATH/g" \
        -e "s/@AD_FOREST_LEVEL@/$AD_FOREST_LEVEL/g" \
        -e "s/@AD_DOMAIN_LEVEL@/$AD_DOMAIN_LEVEL/g" \
        $1
}

if [ -z "$ADMINPASSWORD" ] ; then
    echo Error: you must supply the password for $ADMINNAME
    echo in the ADMINPASSWORD environment variable
    exit 1
fi

if [ -z "$PRODUCT_KEY" -a -f $PRODUCT_KEY_FILE ] ; then
    read PRODUCT_KEY < $PRODUCT_KEY_FILE
fi

if [ -z "$VM_MAC" ] ; then
    # try to get the mac addr from virsh
    VM_MAC=`$SUDOCMD virsh net-dumpxml default | grep "'"$VM_NAME"'"|sed "s/^.*mac='\([^']*\)'.*$/\1/"`
    if [ -z "$VM_MAC" ] ; then
        echo Error: your machine $VM_MAC has no mac address in virsh net-dumpxml default
        echo Please use virsh net-edit default to specify the mac address for $VM_MAC
        echo or set VM_MAC=mac:addr in the environment
        exit 1
    fi
fi

if [ -z "$VM_FQDN" ] ; then
    # try to get the ip addr from virsh
    VM_IP=`$SUDOCMD virsh net-dumpxml default | grep "'"$VM_NAME"'"|sed "s/^.*ip='\([^']*\)'.*$/\1/"`
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
VM_AD_DOMAIN=${VM_AD_DOMAIN:-"$domain"}
lmdn=`echo $VM_AD_DOMAIN | sed -e 's/^\([^.]*\).*$/\1/'`
suffix=`echo $VM_AD_DOMAIN | sed -e 's/^/dc=/' -e 's/\./,dc=/g'`
netbios=`echo $VM_AD_DOMAIN | sed -e 's/\.//g' | tr '[a-z]' '[A-Z]'`
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
    for file in $ANS_FILE_DIR/* $ANS_FILE_DIR/$WIN_VER_REL_ARCH/* "$@" ; do
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
    for file in $ANS_FILE_DIR/* $ANS_FILE_DIR/$WIN_VER_REL_ARCH/* "$@" ; do
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
    if [ -z "$VI_DEBUG" ] ; then
        rm -rf $staging
    fi
    VI_EXTRAS_CD="--disk path=$EXTRAS_CD_ISO,device=cdrom"
fi

serialpath=/tmp/serial-`date +'%Y%m%d%H%M%S'`.$$

$SUDOCMD virt-install --connect=qemu:///system --hvm \
    --accelerate --name "$VM_NAME" --ram=$VM_RAM --vcpu=$VM_CPUS \
    --cdrom $WIN_ISO --vnc --os-type windows  \
    --serial file,path=$serialpath --serial pty \
    --disk path=$WIN_VM_DISKFILE,bus=ide,size=$VM_DISKSIZE,format=raw,cache=none \
    $VI_FLOPPY $VI_EXTRAS_CD \
    --network=bridge=virbr0,model=rtl8139,mac=$VM_MAC \
    $VI_DEBUG --noautoconsole || { echo error $? from virt-install ; exit 1 ; }

echo now we wait for everything to be set up
TRIES=100
SLEEPTIME=30
ii=0
SETUPCOMPLETEDN="cn=SetupComplete,cn=Users,$VM_AD_SUFFIX"
while [ $ii -lt $TRIES ] ; do
    # this will only return success if AD is TLS enabled and the setup complete entry is available
    if LDAPTLS_REQCERT=never ldapdelete -x -ZZ -H ldap://$VM_FQDN \
        -D "$ADMIN_DN" -w "$ADMINPASSWORD" "$SETUPCOMPLETEDN" > /dev/null 2>&1 ; then
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
ldapsearch -xLLL -H ldap://$VM_FQDN -D "$ADMIN_DN" -w "$ADMINPASSWORD" -s base \
    -b "$CA_CERT_DN" "objectclass=*" cACertificate | perl -p0e 's/\n //g' | \
    sed -e '/^cACertificate/ { s/^cACertificate:: //; s/\(.\{1,64\}\)/\1\n/g; p }' -e 'd' | \
    grep -v '^$' >> $TMP_CACERT
echo "-----END CERTIFICATE-----" >> $TMP_CACERT

echo Now test our CA cert
if LDAPTLS_CACERT=$TMP_CACERT ldapsearch -xLLL -ZZ -H ldap://$VM_FQDN \
    -D "$ADMIN_DN" -w "$ADMINPASSWORD" -s base -b "" \
    "objectclass=*" currenttime > /dev/null 2>&1 ; then
    echo Success - the CA cert in $TMP_CACERT is working
else
    echo Error: the CA cert in $TMP_CACERT is not working
    LDAPTLS_CACERT=$TMP_CACERT ldapsearch -d 1 -xLLL -ZZ -H ldap://$VM_FQDN -s base \
        -b "" "objectclass=*" currenttime
    exit 1
fi

if [ -n "$WIN_CA_CERT_FILE" ] ; then
    cp -p $TMP_CACERT $WIN_CA_CERT_FILE
    rm -f $TMP_CACERT
fi

exit 0
