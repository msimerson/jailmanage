#!/bin/sh
#
# Install/update with this command:
#   fetch -o /usr/local/sbin/jailmanage http://www.tnpi.net/computing/freebsd/jail_manage.txt
#   chmod 755 /usr/local/sbin/jailmanage
#
# by Matt Simerson
# Dec 19, 2014 - 'update' optimizes freebsd-update.conf in jails
# Dec 07, 2014 - improvements for 'update'
# Nov 14, 2014 - added 'update' target
# Aug 24, 2014 - only run pkg audit when pkgng installed
# Mar  2, 2014 - build list of jails from /etc/jail.conf (and legacy ezjail)
#              - run "pkg audit" within the jail before entry
# Jan  2, 2014 - removed ezjail dependency
# Dec  1, 2013 - fixed typo: installng -> installing
# Feb 12, 2013 - use local vars, added fix_jailname()
# Oct 19, 2012 - compatible with jail names with a . in them
# Apr 22, 2010 - added mergemaster feature
# Feb 02, 2009 - added support for jail names with - in name (ezjail compat)
# Sep 27, 2007 - added all target
# Sep 23, 2007 - added tripwire
# Sep 18, 2007 - added sudo
# Sep 16, 2007 - initial authoring

# configurable settings
JAILBASE="/jails"
JAILRC="/etc/rc.d/jail"
ALL_JAILS=''
SUDO=''

usage() {
    echo "   usage: $0 [ jailname ]"
    echo " "
    echo " jailname has several special jail names:"
    echo " "
    echo " all         - consecutively log into each jail "
    echo " mergemaster - run mergemaster in each jail"
    echo " update      - run freebsd-update in each jail"
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

get_jail_id()
{
    # No longer used
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

    return `/usr/bin/head -n1 $_pid`
}

jail_manage()
{
    local _jail="$1"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    if [ -f "/etc/jail.conf" ];
    then
        local _jexec="/usr/sbin/jexec $_jail"
    else
        local _jail_fixed=`fix_jailname $_jail`
        local _jexec="/usr/sbin/jexec $_jail_fixed"
    fi

    _mount_ports $_jail
    local _i_mounted=$?

    local _pkg_dir="$JAILBASE/$_jail/var/db/pkg"
    if [ -f "$_pkg_dir/local.sqlite" ]; then
        if [ ! -f "$_pkg_dir/vuln.xml" ]; then
            $SUDO $_jexec pkg audit -F
        else
            $SUDO $_jexec pkg audit
        fi
    fi
    $SUDO $_jexec su -

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
    local _jaildir="$JAILBASE/$_jail"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    local CMD="mergemaster -FU -D $_jaildir"
    echo "$SUDO $CMD"
    $SUDO $CMD

    echo "all done with $1!"
}

check_tripwire()
{
    local _jail="$1"
    local _jaildir="$JAILBASE/$_jail"

    if [ ! -d "$_jaildir/var/db/tripwire" ];
    then
        # echo "consider installing tripwire in jail $_jail"
        return
    fi

    dialog --yesno "The jail $_jail has tripwire installed. If you made changes to the file system, you should update the tripwire database. Do you want to update now?" 8 60
    if [ $? -ne 0 ]; then
        return
    fi

    echo "updating tripwire databases..."

    # check email report sending prefs
    local _tw_cfg="$_jaildir/usr/local/etc/tripwire/twcfg.txt"
    local MAIL_VIOL=`$SUDO grep LNOV $_tw_cfg | grep -v true`

    if [ -z "$MAIL_VIOL" ]; then
        dialog --yesno "Tripwire is configured to spam you daily. Would you like to only get emails if violations are found?" 8 60
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

    echo "$SUDO $_jexec /usr/local/sbin/tripwire -m c"
    $SUDO $_jexec /usr/local/sbin/tripwire -m c

    # update the database
    local _last_report=`$SUDO /bin/ls $_jaildir/var/db/tripwire/report | tail -n1`
    $SUDO $_jexec /usr/local/sbin/tripwire -m u -a -r $jail_dir/var/db/tripwire/report/$_last_report
}

jail_update()
{
    local _jail="$1"

    if [ -z "$_jail" ]; then
        echo " didn't receive the jail name!" && echo
        return
    fi

    local _jaildir="$JAILBASE/$_jail"
    local _jexec="/usr/sbin/jexec $_jail_id"

	local HOST_MAJ_VER=`/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-'`
	local JAIL_MAJ_VER=`$_jaildir/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-'`

	local _fuconf="$_jaildir/etc/freebsd-update.conf"
	local _update="freebsd-update -b $_jaildir -f $_fuconf"

    if [ "$HOST_MAJ_VER" == "$JAIL_MAJ_VER" ];
    then
        echo "$SUDO $_update fetch install"
        $SUDO $_update fetch install
    else
		local HOST_VER=`/bin/freebsd-version`
        local JAIL_VER=`$_jaildir/bin/freebsd-version`
        echo "   jail $1 at version $JAIL_VER"

		if [ "$HOST_VER" == "$JAIL_VER" ];
        then
            echo "   upgrade complete, skipping"
        else
            sed -i .bak -e 's/^Components.*/Components world kernel/' $_fuconf
			sed -i .bak -e 's/^# BackupKernel .*/BackupKernel no/' $_fuconf
			sed -i .bak -e 's/^MergeChanges \/etc\/ \/boot.*/MergeChanges \/etc\//' $_fuconf
			local _upcmd="$_update -r $HOST_MAJ_VER upgrade install"
            echo "   $SUDO $_upcmd"
            $SUDO env UNAME_r=$JAIL_VER $_upcmd
            $SUDO $_update install
            $SUDO $_update install
        fi
    fi

    echo "   done with $1"
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
    fi

    local _mnt_cmd="mount_nullfs /usr/ports $_ports_dir"

    if [ -f "/etc/fstab.$_jail_fixed" ];
    then
        _fstab_dir=`grep ports /etc/fstab.$_jail_fixed | cut -f2 -d" "`

        if [ ! -z "$_fstab_dir" ];
        then
            _mnt_cmd="mount -F /etc/fstab.$_jail_fixed $_fstab_dir"
        fi
    fi

    echo "    $_mnt_cmd"
    $SUDO $_mnt_cmd
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
        return 1
    fi
}

_get_all_jails()
{
    if [ -f "/etc/jail.conf" ];
    then
        ALL_JAILS=`grep { /etc/jail.conf | grep -v '^#' | cut -d' ' -f1`
        return
    fi

    if [ -d "/usr/local/etc/ezjail" ];
    then
        ALL_JAILS=`grep _hostname /usr/local/etc/ezjail/* | cut -f2 -d'=' | sed -e 's/"//g'`;
        return
    fi

    echo "Unable to build list of jails"
}

check_base
check_sudo

case "$1" in
    "all"   )
        _get_all_jails
        for _j in $ALL_JAILS;
        do
            echo "Entering jail $_j"
            sleep 1
            jail_manage $_j
        done
    ;;
    "mergemaster"   )
        _get_all_jails
        for _j in $ALL_JAILS;
        do
            echo "Doing mergemaster for jail $_j"
            sleep 2
            jail_mergemaster $_j
        done
    ;;
    "update"   )
        _get_all_jails
        for _j in $ALL_JAILS;
        do
            echo "freebsd-update for jail $_j"
            sleep 2
            jail_update $_j
        done
    ;;
    *)
        echo "Entering jail $1"
        jail_manage $1
    ;;
esac

exit;
