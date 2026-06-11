#!/bin/sh
#
echo "VERSION: 2026-06-10"; echo
#
# by Matt Simerson
# Source: https://github.com/msimerson/jailmanage
# to INSTALL or upgrade, copy/paste the commands in selfupgrade()

# configurable settings
ALL_JAILS=''
RUNNING_JAILS=''
SUDO=''
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
	# renames - and . chars to _
	# shellcheck disable=SC2001,SC3060
	echo "$1" | sed -e 's/[-.]/_/g'
}

jail_is_running()
{
	jls -d -j $1 name 2>/dev/null | grep -q $1
}

jail_manage()
{
	local _jail="$1"

	if [ -z "$_jail" ]; then
		echo " didn't receive a jail name!" && echo
		return
	fi

	local _jexec="/usr/sbin/jexec $_jail"
	local _jail_fixed; _jail_fixed=$(fix_jailname "$_jail")

	local _jrpath; _jrpath=$(jail_root_path "$_jail")
	if [ ! -d "$_jrpath" ]; then
		echo "skipping $_jail, non-existent root path: $_jrpath"
		return
	fi

	echo "Entering jail $_jail"

	_mount_ports "$_jail_fixed" "$_jrpath"
	local _i_mounted=$?
	_mount_pkg_cache "$_jail_fixed" "$_jrpath"

	jail_audit_one "$_jail"
	$SUDO /usr/sbin/jexec "$_jail_fixed" su -

	echo "all done!"

	if [ "$_i_mounted" -eq 1 ]; then
		_unmount_ports "$_jrpath"
	fi

	_unmount_pkg_cache "$_jrpath"

	check_tripwire "$_jail" "$_jrpath"
}

jail_mergemaster()
{
	_get_all_jails
	for _j in $ALL_JAILS;
	do
		echo "Doing mergemaster for jail $_j"

		local _jrpath; _jrpath=$(jail_root_path "$(fix_jailname "$_j")")

		local CMD="mergemaster -FU -D $_jrpath"
		echo "$SUDO $CMD"
		sleep 2
		$SUDO $CMD

		echo "done."
	done
}

_get_jexec()
{
	local _jail="$1"
	local _safe; _safe=$(fix_jailname "$_jail")
	local _jail_id; _jail_id=$(/usr/bin/head -n1 "/var/run/jail_${_safe}.id")
	echo "/usr/sbin/jexec $_jail_id"
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
	echo "$SUDO $_jexec /usr/local/sbin/tripwire -m c"
	$SUDO $_jexec /usr/local/sbin/tripwire -m c

	# update the database
	local _last_report
	_last_report=$($SUDO /bin/ls "$_jaildir/var/db/tripwire/report" | tail -n1)
	$SUDO $_jexec /usr/local/sbin/tripwire -m u -a -r \
		"$_jaildir/var/db/tripwire/report/$_last_report"
}

jail_update_one()
{
	local _jail="$1"

	if [ -z "$_jail" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jrpath; _jrpath=$(jail_root_path "$_jail")

	if [ ! -d "$_jrpath" ]; then
		echo "skipping $_jail, non-existent root path: $_jrpath"
		return
	fi

	echo "freebsd-update for jail $_jail"

	local HOST_MAJ_VER JAIL_MAJ_VER
	HOST_MAJ_VER=$(/bin/freebsd-version | /usr/bin/cut -f1-2 -d'-')
	JAIL_MAJ_VER=$("$_jrpath/bin/freebsd-version" | /usr/bin/cut -f1-2 -d'-')

	local _fuconf="$_jrpath/etc/freebsd-update.conf"
	local _update="/usr/sbin/freebsd-update -b $_jrpath -f $_fuconf"

	if [ "$HOST_MAJ_VER" = "$JAIL_MAJ_VER" ];
	then
		echo "$SUDO $_update fetch install"
		$SUDO env PAGER=cat $_update fetch install
	else
		local HOST_VER JAIL_VER
		HOST_VER=$(/bin/freebsd-version)
		JAIL_VER=$("$_jrpath/bin/freebsd-version")
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

	local _jrpath

	for _j in $ALL_JAILS;
	do
		echo "Cleaning jail $_j"
		echo "    $SUDO pkg --jail $_j clean -yaq"
		$SUDO pkg --jail $_j clean -yaq

		_jrpath=$(jail_root_path "$(fix_jailname "$_j")")

		DIRS="/var/db/freebsd-update"
		for dir in $DIRS
		do
			local CMD="rm -rf $_jrpath$dir/*"
			echo "    $SUDO $CMD"
			sleep 1
			$SUDO $CMD
		done

		echo "        done."
	done
}

jail_audit()
{
	if [ -n "$1" ]; then
		printf "jail pkg audit: "
		jail_audit_one "$1"
		echo
	else
		jail_audit_one "$(hostname)" "$SUDO pkg audit -F"

		_get_running_jails
		for _j in $RUNNING_JAILS;
		do
			jail_audit_one "$_j"
		done
		echo
	fi
}

jail_audit_one()
{
	local _j="$1"
	local _cmd="$2"

	if [ -z "$_cmd" ]; then
		_cmd="$SUDO pkg --jail $_j audit -F"
	fi

	local r; r=$(eval "$_cmd")

	if [ $? -eq 0 ]; then
		printf "✅   %s\n" "$_j"
		return 0
	else
		printf "⚠️    %s\n" "$_j"
		echo "$r" | grep 'is vulnerable' | sed 's/ is vulnerable://' | sed -E 's/^[[:space:]]*/\t/'
		return 1
	fi
}

jail_update()
{
	local _name; _name="$1"
	if [ -n "$_name" ];
	then
		jail_update_one "$_name"
	else
		echo "No jail specified, updating all of them."
		sleep 3

		_get_all_jails
		for _j in $ALL_JAILS;
		do
			jail_update_one "$_j"
			sleep 2
		done
	fi
}

jail_vulnerable()
{
	_get_running_jails
	for _j in $RUNNING_JAILS;
	do
		_r=$(jail_audit_one "$_j" "$SUDO pkg --jail $_j audit")
		# shellcheck disable=SC2181
		if [ $? -ne 0 ]; then
			printf "    jail %s\n\n%s\n" "$_j" "$_r"
			$SUDO /usr/sbin/jexec "${_j}" su -
		fi
	done
}

jail_send()
{
	local _jail_name="$1"
	local _dest_host="$2"
	local _dest_zroot="$3"
	local _jail_too="$4"  # default is DATA FS only

	local _snap
	local _match

	if [ -z "$_dest_zroot" ]; then
		echo "usage: jailmanage send [jail name] [dest host] [dest ZVOL] [JAIL TOO]"
		exit
	fi

	if [ ! -f "/etc/jail.conf.d/${_jail_name}.conf" ]; then
		echo "ERR: missing /etc/jail.conf.d/${_jail_name}.conf"
		exit
	fi

	local MOUNTS="$ZFS_DATA_MNT/$_jail_name"
	if [ -n "$_jail_too" ]; then
		MOUNTS="$MOUNTS $ZFS_JAIL_MNT/$_jail_name"
	fi

	echo "checking for remote FS"

	for _m in $MOUNTS; do
		echo "  ssh $_dest_host zfs get -H -o name mountpoint $_m"
		_match=$(ssh "$_dest_host" -- "zfs get -H -o name mountpoint $_m")
		if echo "$_match" | grep -q $_jail_name; then
			echo "remote FS exists: $_match"
			exit
		fi
	done

	local TODAY
	TODAY=$(date +%Y-%m-%d)

	jail_is_running "$_jail_name"
	_was_running=$?

	echo "checking for local snapshots"
	for _m in $MOUNTS; do
		_snap=$(zfs get -H -o name mountpoint $_m)

		echo "  zfs list -t snapshot | grep $_snap@$TODAY"
		_match=$(zfs list -t snapshot | grep "$_snap@$TODAY")

		if [ -n "$_match" ]; then
			echo "local snapshot exists: $_snap"
		else
			echo "creating local snapshot"
			if jail_is_running "$_jail_name"; then
				service jail stop "$_jail_name"
			fi
			sleep 1
			echo "  zfs snapshot $_snap@$TODAY"
			zfs snapshot "$_snap@$TODAY"
		fi
	done

	if [ "$_was_running" = "1" ]; then
		service jail start "$_jail_name"
	fi

	echo "sending filesystems to $_dest_host"
	for _m in $MOUNTS; do
		local _local_snap
		local _remote_snap

		_local_snap="$(zfs get -H -o name mountpoint $_m)@$TODAY"
		_remote_snap=$(ssh "$_dest_host" -- "zfs get -H -o name mountpoint $_dest_zroot/$_m")

		echo "  zfs send $_local_snap | ssh $_dest_host zfs receive $_remote_snap/$_jail_name"
		# shellcheck disable=SC2029
		zfs send "$_local_snap" | ssh "$_dest_host" zfs receive "$_remote_snap/$_jail_name"
	done

	echo "scp /etc/jail.conf.d/$_jail_name.conf $_dest_host:/etc/jail.conf.d/"
	scp "/etc/jail.conf.d/$_jail_name.conf" "$_dest_host:/etc/jail.conf.d/"
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
	local _name="$1"
	local _path

	if [ -f "/etc/jail.conf.d/${_name}.conf" ]; then
		# look for a path declaration
		_path=$(grep -E '^[[:space:]]*path' "/etc/jail.conf.d/${_name}.conf" | cut -f2 -d= | cut -f2 -d'"')
	fi

	if [ -z "$_path" ] && [ -f /etc/jail.conf ]; then
		# look for a path declaration in jail.conf declaration block
		_path=$(grep -A10 "^$_name" /etc/jail.conf \
			| awk '{if ($0 ~ /{/) {found=1;} if (found) {print; if ($0 ~ /}/) { exit;}}}' \
			| grep -E '^[[:space:]]*path' \
			| cut -f2 -d= | cut -f2 -d'"')
	fi

	if [ -n "$_path" ]; then
		# shellcheck disable=SC2001
		_path=$(echo "$_path" | head -n1 | sed -e "s|\$name|$_name|" )
	fi

	# no explicit declaration, use default
	if [ -z "$_path" ]; then
		_path="$ZFS_JAIL_MNT/$_name"
	fi

	if [ ! -d "$_path" ]; then
		_path="$ZFS_JAIL_MNT/$(fix_jailname "$_name")"
	fi

	echo "$_path"
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
	local _host_ver; _host_ver=$(/bin/freebsd-version -u)
	VERSION_REPORT="$(hostname) ${_host_ver}\n"
	VERSION_REPORT="${VERSION_REPORT}-------------- ---------------\n"
	_get_running_jails
	for _j in $RUNNING_JAILS;
	do
		JAILSTATUS=$($SUDO /usr/sbin/jexec "${_j}" /bin/freebsd-version -u)
		if [ -z "${JAILSTATUS}" ]; then
			continue
		fi
		if [ "${JAILSTATUS}" != "${_host_ver}" ]; then
			JAILSTATUS="${JAILSTATUS} ⚠️"
		fi
		VERSION_REPORT="${VERSION_REPORT}${_j} ${JAILSTATUS}\n"
	done
	echo -e "$VERSION_REPORT" | column -t
}

if [ "$1" != "test" ] && [ "$1" != "" ]; then
	check_base
	check_sudo
fi

case "$1" in
	"all")
		_get_running_jails
		for _j in $RUNNING_JAILS;
		do
			jail_manage "$_j"
		done
	;;
	"audit"       ) jail_audit "$2"   ;;
	"vulnerable"  ) jail_vulnerable   ;;
	"update"      ) jail_update "$2"  ;;
	"versions"    ) _version_report   ;;
	"send"        ) jail_send "$2" "$3" "$4" "$5" ;;
	"selfupgrade" | "selfupdate" ) selfupgrade ;;
	"clean" | "cleanup" ) jail_cleanup "$2" ;;
	"mergemaster" ) jail_mergemaster  ;;
	*) jail_manage "$1" ;;
esac
