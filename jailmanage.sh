#!/bin/sh
#
# VERSION: 2023-12-03
#
# by Matt Simerson
# Source: https://github.com/msimerson/jailmanage
# to INSTALL or upgrade, copy/paste the commands in selfupgrade()

# configurable settings
ALL_JAILS=''
RUNNING_JAILS=''
SUDO=''
ZFS_VOL="zroot"
ZFS_DATA_MNT="/data"
ZFS_JAIL_MNT=${ZFS_JAIL_MNT:="/jails"}

usage() {
	echo "   usage: $0 [ jailname ]"
	echo " "
	echo " jailname has several special jail names:"
	echo " "
	echo " all         - consecutively log into each jail"
	echo " audit       - run 'pkg audit' in each jail"
	echo " vulnerable  - drop into each jail with vulnerable packages"
	echo " versions    - report versions of each jail"
	echo " update      - run freebsd-update in each jail"
	echo " clean       - purge pkg and freebsd-update caches"
	echo " send        - ship a jail between hosts"
	echo " mergemaster - run mergemaster in each jail"
	echo " selfupgrade - upgrade jailmanage script"
	echo " "
	exit 1
}

if [ -z "$1" ]; then usage; fi

selfupgrade()
{
	local _jm=/usr/local/bin/jailmanage
	local _jmurl=https://raw.githubusercontent.com/msimerson/jailmanage/master/jailmanage.sh
	fetch -o $_jm -m $_jmurl && chmod 755 $_jm
}

fix_jailname()
{
	# renames chars - and . chars to _
	# shellcheck disable=SC2001,SC3060
	echo "$1" | sed -e 's/\-\./_/g'
}

jail_manage()
{
	local _jail="$1"

	if [ -z "$_jail" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jexec
	if [ -f "/etc/jail.conf" ];
	then
		_jexec="/usr/sbin/jexec $_jail"
	else
		_jexec="/usr/sbin/jexec $(fix_jailname "$_jail")"
	fi

	local _jail_fixed; _jail_fixed=$(fix_jailname "$_jail")
	local _jail_root_path; _jail_root_path=$(jail_root_path "$_jail_fixed")

	if [ ! -d "$_jail_root_path" ]; then
		echo "skipping $_jail, non-existent $_jail_root_path root path"
		return
	fi

	_mount_ports "$_jail_fixed" "$_jail_root_path"
	local _i_mounted=$?
	_mount_pkg_cache "$_jail_fixed" "$_jail_root_path"

	local _pkg_dir="$_jail_root_path/var/db/pkg"
	if [ -f "$_pkg_dir/local.sqlite" ]; then
		if [ ! -f "$_pkg_dir/vuln.xml" ]; then
			$SUDO $_jexec pkg audit -F
		else
			$SUDO $_jexec pkg audit
		fi
	fi
	$SUDO $_jexec su -

	echo "all done!"

	if [ "$_i_mounted" -eq 1 ]; then
		_unmount_ports "$_jail_root_path"
	fi

	_unmount_pkg_cache "$_jail_root_path"

	check_tripwire "$_jail" "$_jail_root_path"
}

jail_mergemaster()
{
	_get_all_jails
	for _j in $ALL_JAILS;
	do
		echo "Doing mergemaster for jail $_j"

		local _jail_root_path;
		_jail_root_path=$(jail_root_path "$(fix_jailname "$_j")")

		local CMD="mergemaster -FU -D $_jail_root_path"
		echo "$SUDO $CMD"
		sleep 2
		$SUDO $CMD

		echo "done."
	done
}

check_tripwire()
{
	local _jail="$1"
	local _jaildir="$2"

	if [ ! -d "$_jaildir/var/db/tripwire" ];
	then
		# echo "consider installing tripwire in jail $_jail"
		return
	fi

	local _updmsg="The jail $_jail has tripwire installed. If you made changes to the file system, you should update the tripwire database. Do you want to update now?"
	if ! dialog --yesno "$_updmsg" 8 60; then
		return
	fi

	echo "updating tripwire databases..."

	# check email report sending prefs
	local _tw_cfg="$_jaildir/usr/local/etc/tripwire/twcfg.txt"
	local MAIL_VIOL; MAIL_VIOL=$($SUDO grep LNOV "$_tw_cfg" | grep -v true)

	if [ -z "$MAIL_VIOL" ]; then
		local _emailmsg="Tripwire is configured to spam you daily. Would you like to only get emails if violations are found?"
		if dialog --yesno "$_emailmsg" 8 60; then
			echo "sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' $_tw_cfg"
			$SUDO sed -i .bak -e 's/MAILNOVIOLATIONS =true/MAILNOVIOLATIONS =false/g' "$_tw_cfg"
		fi
		#echo "mail_viol: $MAIL_VIOL"
	fi

	# run the tripwire check script
	local _pid="/var/run/jail_${_jail}.id"
	local _jail_id; _jail_id=$(/usr/bin/head -n1 "$_pid")
	local _jexec="/usr/sbin/jexec $_jail_id"

	echo "$SUDO $_jexec /usr/local/sbin/tripwire -m c"
	$SUDO $_jexec /usr/local/sbin/tripwire -m c

	# update the database
	local _last_report
	_last_report=$($SUDO /bin/ls "$_jaildir/var/db/tripwire/report" | tail -n1)
	$SUDO $_jexec /usr/local/sbin/tripwire -m u -a -r \
		"$_jaildir/var/db/tripwire/report/$_last_report"
}

jail_update()
{
	local _jail="$1"

	if [ -z "$_jail" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jail_fixed; _jail_fixed=$(fix_jailname "$_jail")
	local _jail_root_path; _jail_root_path=$(jail_root_path "$_jail_fixed")
	local _jexec="/usr/sbin/jexec $_jail_id"

	if [ ! -d "$_jail_root_path" ]; then
		echo "skipping $_jail, non-existent $_jail_root_path root path"
		return
	fi

	local HOST_MAJ_VER JAIL_MAJ_VER
	HOST_MAJ_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
	JAIL_MAJ_VER=$("$_jail_root_path/bin/freebsd-version" | /usr/bin/cut -f1-2 -d'-')

	local _fuconf="$_jail_root_path/etc/freebsd-update.conf"
	local _update="/usr/sbin/freebsd-update -b $_jail_root_path -f $_fuconf"

	if [ "$HOST_MAJ_VER" = "$JAIL_MAJ_VER" ];
	then
		echo "$SUDO $_update fetch install"
		$SUDO env PAGER=cat $_update fetch install
	else
		local HOST_VER JAIL_VER
		HOST_VER=$(/bin/freebsd-version)
		JAIL_VER=$("$_jail_root_path/bin/freebsd-version")
		echo "   jail $_jail at version $JAIL_VER"

		if [ "$HOST_VER" = "$JAIL_VER" ];
		then
			echo "   upgrade complete, skipping"
		else
			sed -i .bak \
				-e 's/^Components.*/Components world kernel/' \
				-e 's/^# BackupKernel .*/BackupKernel no/' \
				-e 's/^MergeChanges \/etc\/ \/boot.*/MergeChanges \/etc\//' \
				"$_fuconf"

			local _upcmd="$_update -r $HOST_MAJ_VER upgrade install"
			echo "    $SUDO $_upcmd"
			$SUDO env PAGER=cat UNAME_r=$JAIL_VER $_upcmd
			$SUDO $_update install
			$SUDO $_update install
		fi
	fi

	echo "   done with $_jail"
}

jail_cleanup()
{
	if [ -z "$1" ]; then
		_get_all_jails
	else
		ALL_JAILS="$1"
	fi

	for _j in $ALL_JAILS;
	do
		echo "Cleaning jail $_j"
		echo "    $SUDO pkg --jail $_j clean -yaq"
		$SUDO pkg --jail $_j clean -yaq

		local _jail_root_path;
		_jail_root_path=$(jail_root_path "$(fix_jailname "$1")")

		DIRS="/var/db/freebsd-update"
		for dir in $DIRS
		do
			local CMD="rm -rf $_jailpath$dir/*"
			echo "    $SUDO $CMD"
			sleep 1
			$SUDO $CMD
		done

		echo "        done."
	done
}

jail_audit()
{
	if [ -z "$1" ]; then
		echo -e "$(hostname)\n\t$(pkg audit)\n"
		_get_running_jails
		for _j in $RUNNING_JAILS;
		do
			_r=$(pkg --jail "$_j" audit)
			# shellcheck disable=SC2181
			if [ $? -eq 0 ]; then
				echo -e "  jail ${_j} ok"
			else
				echo -e "  jail ${_j} \n\t${_r}"
			fi
		done
	else
		echo "pkg audit for jail $1"
		pkg --jail "$1" audit -F
		echo ""
	fi
}

jail_vulnerable()
{
	_get_running_jails
	for _j in $RUNNING_JAILS;
	do
		_r=$(pkg --jail "$_j" audit)
		# shellcheck disable=SC2181
		if [ $? -ne 0 ]; then
			echo -e "    jail ${_j}"
			echo -e ""
			pkg --jail "$_j" audit
			jexec ${_j}
		fi
	done
}

jail_send()
{
	if [ -z "$2" ]; then
		echo "usage: jailmanage [jail name] [target host]"
		exit
	fi

	echo " ***  send jail $1 to $2  ***"

	TODAY=$(date +%Y-%m-%d)
	JAIL_SNAP="${ZFS_VOL}${ZFS_JAIL_MNT}/${1}@${TODAY}"
	DATA_SNAP="${ZFS_VOL}${ZFS_DATA_MNT}/${1}@${TODAY}"

	# see if remote snapshot exists
	_match=$(ssh "$2" zfs list -t snapshot | grep "$JAIL_SNAP")
	if [ -n "$_match" ]; then
		echo "remote snapshot exists: $JAIL_SNAP"
		exit
	fi

	_match=$(zfs list -t snapshot | grep "$JAIL_SNAP")
	if [ -n "$_match" ]; then
		echo "local snapshot exists: $JAIL_SNAP"
	else
		echo "creating local snapshot: $JAIL_SNAP"
		service jail stop "$1"
		sleep 1
		zfs snapshot "$JAIL_SNAP"
		zfs snapshot "$DATA_SNAP"
		service jail start "$1"
	fi

	echo "zfs send snapshot: $JAIL_SNAP"
	# shellcheck disable=SC2029
	zfs send "$JAIL_SNAP" | ssh "$2" zfs receive "$JAIL_SNAP"
	# shellcheck disable=SC2029
	zfs send "$DATA_SNAP" | ssh "$2" zfs receive "$DATA_SNAP"
}

check_base()
{
	if [ ! -d $ZFS_JAIL_MNT ]; then
		echo "Err! please edit this script and set ZFS_JAIL_MNT!"
		exit
	fi
}

check_sudo()
{
	local _uid; _uid=$(whoami)
	if [ "$_uid" = 'root' ]; then return; fi
	echo "running as $_uid, using sudo"

	if [ -x "/usr/local/bin/sudo" ];
	then
		SUDO="/usr/local/bin/sudo"
	fi
}

jail_root_path()
{
	local _jailpath

	if [ -f "/etc/jail.conf.d/$1.conf" ]; then
		# look for a path declaration
		_jailpath=$(grep -E '^[[:space:]]*path' "/etc/jail.conf.d/$1.conf" | cut -f2 -d= | cut -f2 -d'"')
	fi

	if [ -z "$_jailpath" ] && [ -f /etc/jail.conf ]; then
		# look for a path declaration in jail.conf declaration block
		_jailpath=$(grep -A10 "^$1" /etc/jail.conf \
			| awk '{if ($0 ~ /{/) {found=1;} if (found) {print; if ($0 ~ /}/) { exit;}}}' \
			| grep -E '^[[:space:]]*path' \
			| cut -f2 -d= | cut -f2 -d'"')
	fi

	if [ -n "$_jailpath" ]; then
		# shellcheck disable=SC2001
		_jailpath=$(echo "$_jailpath" | sed -e "s|\$name|$1|" )
	fi

	# no explicit declaration, use default
	if [ -z "$_jailpath" ]; then
		_jailpath="$ZFS_JAIL_MNT/$1"
	fi

	echo "$_jailpath"
}

_mount_ports()
{
	local _jail; _jail=$(fix_jailname "$1")
	local _ports_dir="$2/usr/ports"

	if mount -t nullfs | grep -q "$_ports_dir"; then
		echo "ports dir already mounted"
		return 0
	fi

	local _mnt_cmd="/sbin/mount_nullfs /usr/ports $_ports_dir"

	if [ -f "/etc/fstab.$_jail" ];
	then
		_fstab_dir=$(grep ports "/etc/fstab.$_jail" | cut -f2 -d" ")

		if [ -n "$_fstab_dir" ];
		then
			_mnt_cmd="/sbin/mount -F /etc/fstab.$_jail $_fstab_dir"
		fi
	fi

	echo "    $_mnt_cmd"
	$SUDO $_mnt_cmd || exit
	return 1
}

_unmount_ports()
{
	local _ports_dir="$1/usr/ports"

	if ! mount -t nullfs | grep -q "$_ports_dir"; then
		echo "ports dir not mounted"
		return
	fi

	echo "    /sbin/umount $_ports_dir"
	$SUDO /sbin/umount "$_ports_dir"

	if mount -t nullfs | grep -q "$_ports_dir"; then
		echo "    ERR: failed to unmount $_ports_dir"
		return 0
	else
		return 1
	fi
}

_mount_pkg_cache()
{
	local _jail; _jail=$(fix_jailname "$1")
	local _cache_dir="$2/var/cache/pkg"

	if mount -t nullfs | grep -q "$_cache_dir"; then
		echo "$_cache_dir already mounted"
		return
	fi

	echo "    /sbin/mount_nullfs /var/cache/pkg $_cache_dir"
	$SUDO /sbin/mount_nullfs /var/cache/pkg "$_cache_dir" || exit
}

_unmount_pkg_cache()
{
	local _cache_dir="$1/var/cache/pkg"

	if ! mount -t nullfs | grep -q "$_cache_dir"; then
		echo "$_cache_dir not mounted"
		return
	fi

	echo "    /sbin/umount $_cache_dir"
	$SUDO /sbin/umount "$_cache_dir" || exit
}

_get_all_jails()
{
	ALL_JAILS=""

	if [ -d "/etc/jail.conf.d" ]; then
		DEFINED_JAILS=$(ls /etc/jail.conf.d/*.conf)
		for _j in ${DEFINED_JAILS}
		do
			_j=$(basename "$_j" .conf)
			if [ -d "$(jail_root_path $_j)" ]; then
				ALL_JAILS="${ALL_JAILS} ${_j}"
			fi
		done
	fi

	if [ -f "/etc/jail.conf" ];
	then
		DEFINED_JAILS=$(grep '{' /etc/jail.conf | grep -v '^#' | awk '{ print $1 }')
		for _j in ${DEFINED_JAILS}
		do
			if [ -d "$(jail_root_path $_j)" ]; then
				ALL_JAILS="${ALL_JAILS} ${_j}"
			fi
		done
		return
	fi

	if [ -d "/usr/local/etc/ezjail" ];
	then
		ALL_JAILS=$(grep _hostname /usr/local/etc/ezjail/* | cut -f2 -d'=' | sed -e 's/"//g')
		return
	fi

	echo "Unable to build list of jails"
}

_get_running_jails()
{
	RUNNING_JAILS=$(jls name)
}

_version_report()
{
	VERSION_REPORT="$(hostname) $(/bin/freebsd-version -u)\n"
	VERSION_REPORT="${VERSION_REPORT}-------------- ---------------\n"
	_get_running_jails
	for _j in $RUNNING_JAILS;
	do
		JAILSTATUS=$($SUDO /usr/sbin/jexec "${_j}" /bin/freebsd-version -u)
		if [ "${JAILSTATUS}" != "" ]; then
			VERSION_REPORT="${VERSION_REPORT}${_j} ${JAILSTATUS}\n"
		fi
	done
	echo -e "$VERSION_REPORT" | column -t
}

if [ "$1" != "test" ] && [ "$1" != "" ]; then
	check_base
	check_sudo
fi

case "$1" in
	"all"   )
		_get_running_jails
		for _j in $RUNNING_JAILS;
		do
			echo "Entering jail $_j"
			sleep 1
			jail_manage "$_j"
		done
	;;
	"audit"   )
		jail_audit "$2"
	;;
	"vulnerable"   )
		jail_vulnerable
	;;
	"update"   )
		if [ -z "$2" ];
		then
			_get_all_jails
			for _j in $ALL_JAILS;
			do
				echo "freebsd-update for jail $_j"
				sleep 2
				jail_update "$_j"
			done
		else
			echo "freebsd-update for jail $2"
			jail_update "$2"
		fi
	;;
	"versions"   )
		_version_report
	;;
	"send"   )
		jail_send "$2" "$3"
	;;
	"selfupgrade" | "selfupdate"  )
		selfupgrade
	;;
	"clean" | "cleanup"   )
		jail_cleanup "$2"
	;;
	"mergemaster"   )
		jail_mergemaster
	;;
	"test" )
		# echo "doing test"
	;;
	*)
		echo "Entering jail $1"
		jail_manage "$1"
	;;
esac
