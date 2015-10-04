#!/bin/sh
#
# by Matt Simerson
#   Sep 27, 2007 - added all target
#   Sep 23, 2007 - added tripwire
#   Sep 18, 2007 - added sudo
#   Sep 16, 2007 - initial authoring

# configurable settings
JAILBASE="/usr/jails"
JAILRC="/usr/local/etc/rc.d/ezjail.sh"
SUDO=''

usage() {
	echo "   usage: $0 [ jailname ]"
	echo ""
	exit
}

if [ -z $1 ];
then
    usage
fi

jail_manage()
{
    _jail="$1"

    echo "processing jail $_jail"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    _pid="/var/run/jail_${_jail}.id"

    if [ ! -f $_pid ]; then
        echo "    not running: $_jail" && echo
        return
    fi

    _jail_id=`/usr/bin/head -n1 $_pid`
    _jexec="/usr/sbin/jexec $_jail_id"

    _mount_ports $_jail
    _i_mounted=$?

    $SUDO $_jexec su

    echo "all done!"

    if [ $_i_mounted -eq 1 ];
    then
        _unmount_ports $_jail
    fi
}

check_tripwire()
{
    _jail="$1"
    _jaildir="$JAILBASE/$_jail"

    if [ ! -d "$_jaildir/var/db/tripwire" ];
    then
        echo "consider installng tripwire in jail $_jail"
        return
    fi

    dialog --yesno "The jail $_jail has tripwire installed. If you made changes to the file system, you should update the tripwire database. Do you want to update now?" 7 70
    if [ $? -eq 0 ]; then
        echo "updating tripwire databases..."
    else
        return
    fi

    # check email report sending prefs
    _tw_cfg="$_jaildir/usr/local/etc/tripwire/twcfg.txt"
    MAIL_VIOL=`$SUDO grep LNOV $_tw_cfg | grep -v true`

    if [ -z "$MAIL_VIOL" ]; then
        dialog --yesno "Tripwire is configured to spam you daily. Would you like to only get emails if violations are found?" 7 70
        if [ $? -eq 0 ]; then
            echo "sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' $_tw_cfg"
            $SUDO sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' $_tw_cfg
        fi
        #echo "mail_viol: $MAIL_VIOL"
    fi

    # run the tripwire check script
    _pid="/var/run/jail_${_jail}.id"
    _jail_id=`/usr/bin/head -n1 $_pid`
    _jexec="/usr/sbin/jexec $_jail_id"

    $SUDO $_jexec /usr/local/sbin/tripwire -m c

    # update the database
    _last_report=`$SUDO /bin/ls $_jaildir/var/db/tripwire/report | tail -n1`
    $SUDO $_jexec /usr/local/sbin/tripwire -m u -a -r $jail_dir/var/db/tripwire/report/$_last_report
}

check_base()
{
    if [ ! -d $JAILBASE ]; then
        echo "Oops! please edit this script and set JAILBASE!"
        exit
    fi
}

check_sudo()
{
    _uid=`whoami`
    if [ "$_uid" != 'root' ];
    then
        echo "running as $_uid, using sudo"

        if [ -x "/usr/local/bin/sudo" ];
        then
            SUDO="/usr/local/bin/sudo"
        fi
    fi
}

_mount_ports()
{
    _jail="$1"

    # there's a good chance ezjail renamed any - to _ chars
    _fixed_jail=`echo "$_jail" | sed -e 's/_/-/g'`

    _ports_dir="$JAILBASE/$_fixed_jail/usr/ports"

    if [ -f "$_ports_dir/INDEX" ]; 
    then
        echo "    already mounted: $JAILBASE/$_jail/usr/ports"
        return 0
    else 
        _fstab_dir=`grep ports /etc/fstab.$_jail | cut -f2 -d" "`

        if [ ! -z "$_fstab" ];
        then
            echo "    mount -F /etc/fstab.$_jail $_fstab_dir"
            $SUDO mount -F /etc/fstab.$_jail $_fstab_dir
        else

            echo "    mount_nullfs /usr/ports $_ports_dir"
            $SUDO mount_nullfs /usr/ports $_ports_dir
        fi
    fi
    return 1
}

_unmount_ports()
{
    _jail="$1"

    # there's a good chance ezjail renamed any - to _ chars
    _fixed_jail=`echo "$_jail" | sed -e 's/_/-/g'`

    _ports_dir="$JAILBASE/$_fixed_jail/usr/ports"
    #echo "    ports_dir: $_ports_dir"

    if [ -f "$_ports_dir/INDEX" ]; 
    then
        echo "    /sbin/umount $_ports_dir"
        $SUDO /sbin/umount $_ports_dir
    fi

    if [ -f "$_ports_dir/INDEX" ]; then
        echo "    ERR: failed to unmount $_ports_dir"
        return 0
    else
        #echo "    unmounted /usr/ports for $_jail"
        return 1
    fi
}


check_base
check_sudo

for _j in `ls /usr/local/etc/ezjail`;
do
    case "$1" in
        "$_j"    )
            jail_manage $_j
            check_tripwire $_j
        ;;
        "all"   )
            echo "Entering jail $_j"
            sleep 2
            jail_manage $_j
            check_tripwire $_j
        ;;
    esac
done

exit;
