#!/bin/sh
#
# by Matt Simerson
# Feb 12, 2013 - use local vars, added fix_jailname()
# Oct 19, 2012 - compatible with jail names with a . in them
# Apr 22, 2010 - added mergemaster feature
# Feb 02, 2009 - added support for jail names with - in name (ezjail compat)
# Sep 27, 2007 - added all target
# Sep 23, 2007 - added tripwire
# Sep 18, 2007 - added sudo
# Sep 16, 2007 - initial authoring

# configurable settings
JAILBASE="/usr/jails"
JAILRC="/usr/local/etc/rc.d/ezjail"
SUDO=''

usage() {
    echo "   usage: $0 [ jailname ]"
    echo " "
    echo " jailname has two special options: all, mergemaster"
    echo " "
    echo " all         - consecutively log into each jail "
    echo " mergemaster - run mergemaster for each jail"
    echo " "
    exit
}

if [ -z $1 ];
then
    usage
fi

fix_jailname()
{
    # ezjail renames char - to _
    _jail_fixed=`echo "$1" | sed -e 's/\-/_/g'`
    _jail_fixed=`echo "$_jail_fixed" | sed -e 's/\./_/g'`
    echo $_jail_fixed
}

jail_manage()
{
    local _jail="$1"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    local _pid="/var/run/jail_${_jail}.id"

    if [ ! -f $_pid ]; then
        #echo "    no PID found for $_jail" && echo
        local _jail_fixed=`fix_jailname $1`

        _pid="/var/run/jail_${_jail_fixed}.id"
        if [ ! -f $_pid ]; then
            echo "    not running: $_jail" && echo
            return
        fi
    fi

    local _jail_id=`/usr/bin/head -n1 $_pid`
    local _jexec="/usr/sbin/jexec $_jail_id"

    _mount_ports $_jail
    local _i_mounted=$?

    $SUDO $_jexec su

    echo "all done!"

    if [ $_i_mounted -eq 1 ];
    then
        _unmount_ports $_jail
    fi

    check_tripwire $_jail
}

jail_mergemaster()
{
    local _jail="$1"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    local CMD="mergemaster -FU -D $JAILBASE/$1"
    echo "$SUDO $CMD"
    $SUDO $CMD

    echo "all done with $1!"
    #check_tripwire $_jail
}

check_tripwire()
{
    local _jail="$1"
    local _jaildir="$JAILBASE/$_jail"

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
    local _tw_cfg="$_jaildir/usr/local/etc/tripwire/twcfg.txt"
    local MAIL_VIOL=`$SUDO grep LNOV $_tw_cfg | grep -v true`

    if [ -z "$MAIL_VIOL" ]; then
        dialog --yesno "Tripwire is configured to spam you daily. Would you like to only get emails if violations are found?" 7 70
        if [ $? -eq 0 ]; then
            echo "sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' $_tw_cfg"
            $SUDO sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' $_tw_cfg
        fi
        #echo "mail_viol: $MAIL_VIOL"
    fi

    # run the tripwire check script
    local _pid="/var/run/jail_${_jail}.id"
    local _jail_id=`/usr/bin/head -n1 $_pid`
    local _jexec="/usr/sbin/jexec $_jail_id"

    $SUDO $_jexec /usr/local/sbin/tripwire -m c

    # update the database
    local _last_report=`$SUDO /bin/ls $_jaildir/var/db/tripwire/report | tail -n1`
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
    local _uid=`whoami`
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
    local _jail="$1"
    local _jail_fixed=`fix_jailname $1`
    local _ports_dir="$JAILBASE/$_jail/usr/ports"

    if [ -f "$_ports_dir/Makefile" ];
    then
        echo "    already mounted: $JAILBASE/$_jail/usr/ports"
        return 0
    else
        _fstab_dir=`grep ports /etc/fstab.$_jail_fixed | cut -f2 -d" "`

        if [ ! -z "$_fstab" ];
        then
            echo "    mount -F /etc/fstab.$_jail_fixed $_fstab_dir"
            $SUDO mount -F /etc/fstab.$_jail_fixed $_fstab_dir
        else
            echo "    mount_nullfs /usr/ports $_ports_dir"
            $SUDO mount_nullfs /usr/ports $_ports_dir
        fi
    fi
    return 1
}

_unmount_ports()
{
    local _jail="$1"
    local _ports_dir="$JAILBASE/$_jail/usr/ports"

    if [ -f "$_ports_dir/Makefile" ];
    then
        echo "    /sbin/umount $_ports_dir"
        $SUDO /sbin/umount $_ports_dir
    fi

    if [ -f "$_ports_dir/Makefile" ]; then
        echo "    ERR: failed to unmount $_ports_dir"
        return 0
    else
        #echo "    unmounted /usr/ports for $_jail"
        return 1
    fi
}


check_base
check_sudo

case "$1" in
    "all"   )
        for _j in `grep _hostname /usr/local/etc/ezjail/* | cut -f2 -d'=' | sed -e 's/"//g'`;
        do
            echo "Entering jail $_j"
            sleep 2
            jail_manage $_j
        done
    ;;
    "mergemaster"   )
        for _j in `grep _hostname /usr/local/etc/ezjail/* | cut -f2 -d'=' | sed -e 's/"//g'`;
        do
            echo "Doing mergemaster for jail $_j"
            sleep 2
            jail_mergemaster $_j
        done
    ;;
    *)
        echo "Entering jail $1"
        jail_manage $1
    ;;
esac

exit;
