#!/bin/sh
#
# by Matt Simerson
# Source Code: https://github.com/msimerson/jailmanage
# Install/Update:
#	fetch -o /usr/local/sbin/jailmanage https://raw.githubusercontent.com/msimerson/jailmanage/master/jailmanage.sh
#   chmod 755 /usr/local/sbin/jailmanage

# configurable settings
JAILBASE="/jails"
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
	echo " cleanup     - purges file caches"
	echo " "
	exit
}

if [ -z "$1" ];
then
	usage
fi

fix_jailname()
{
	# renames chars - and . to _
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

	local _jail_fixed; _jail_fixed=$(fix_jailname "$1")
	local _jail_root_path; _jail_root_path=$(jail_root_path "$_jail_fixed")

	if [ ! -d "$_jail_root_path" ]; then
		echo "skipping $_jail, non-existent $_jail_root_path root path"
		return
	fi

	_mount_ports "$_jail_fixed" "$_jail_root_path"
	local _i_mounted=$?
	_mount_pkg_cache "$_jail_fixed" "$_jail_root_path"

	if [ ! -f "$_jail_root_path/usr/local/etc/pkg/repos/FreeBSD.conf" ]; then
		$SUDO mkdir -p "$_jail_root_path/usr/local/etc/pkg/repos" || exit
		$SUDO tee "$_jail_root_path/usr/local/etc/pkg/repos/FreeBSD.conf" <<EO_PKG_CONF
FreeBSD: {
  url: "pkg+http://pkg.FreeBSD.org/\${ABI}/latest"
}
EO_PKG_CONF
	fi

	local _pkg_dir="$_jail_root_path/var/db/pkg"
	if [ -f "$_pkg_dir/local.sqlite" ]; then
		if [ ! -f "$_pkg_dir/vuln.xml" ]; then
			# shellcheck disable=SC2086
			$SUDO $_jexec pkg audit -F
		else
			# shellcheck disable=SC2086
			$SUDO $_jexec pkg audit
		fi
	fi
	# shellcheck disable=SC2086
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
	if [ -z "$1" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jail_root_path;
	_jail_root_path=$(jail_root_path "$(fix_jailname "$1")")

	local CMD="mergemaster -FU -D $_jail_root_path"
	echo "$SUDO $CMD"
	sleep 2
	# shellcheck disable=SC2086
	$SUDO $CMD

	echo "all done with $1!"
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
	# shellcheck disable=SC2086
	$SUDO $_jexec /usr/local/sbin/tripwire -m c

	# update the database
	local _last_report
	_last_report=$($SUDO /bin/ls "$_jaildir/var/db/tripwire/report" | tail -n1)
	# shellcheck disable=SC2086
	$SUDO $_jexec /usr/local/sbin/tripwire -m u -a -r \
		"$_jaildir/var/db/tripwire/report/$_last_report"
}

jail_update()
{
	if [ -z "$1" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jail_fixed; _jail_fixed=$(fix_jailname "$1")
	local _jail_root_path; _jail_root_path=$(jail_root_path "$_jail_fixed")
	local _jexec="/usr/sbin/jexec $_jail_id"

	if [ ! -d "$_jail_root_path" ]; then
		echo "skipping $1, non-existent $_jail_root_path root path"
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
		# shellcheck disable=SC2086
		$SUDO $_update fetch install
	else
		local HOST_VER JAIL_VER
		HOST_VER=$(/bin/freebsd-version)
		JAIL_VER=$("$_jail_root_path/bin/freebsd-version")
		echo "   jail $1 at version $JAIL_VER"

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
			$SUDO env UNAME_r="$JAIL_VER $_upcmd"
			# shellcheck disable=SC2086
			$SUDO $_update install
			# shellcheck disable=SC2086
			$SUDO $_update install
		fi
	fi

	echo "   done with $1"
}

jail_cleanup()
{
	if [ -z "$1" ]; then
		echo " didn't receive the jail name!" && echo
		return
	fi

	local _jail_root_path;
	_jail_root_path=$(jail_root_path "$(fix_jailname "$1")")

	DIRS="/var/cache/pkg /var/db/freebsd-update"
	for dir in $DIRS
	do
		local CMD="rm -rf $_jailpath$dir/*"
		echo "	$SUDO $CMD"
		sleep 1
		# shellcheck disable=SC2086
		$SUDO $CMD
	done

	echo "    done with $1!"
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
	local _uid; _uid=$(whoami)
	if [ "$_uid" = 'root' ];
	then
		return
	fi
	echo "running as $_uid, using sudo"

	if [ -x "/usr/local/bin/sudo" ];
	then
		SUDO="/usr/local/bin/sudo"
	fi
}

jail_root_path()
{
	local _jailpath

	# look for a path declaration in jails declaration block
	_jailpath=$(grep -A10 "^$1" /etc/jail.conf \
		| awk '{if ($0 ~ /{/) {found=1;} if (found) {print; if ($0 ~ /}/) { exit;}}}' \
		| grep -E '^[[:space:]]*path' \
		| cut -f2 -d= | cut -f2 -d'"')

	# no declaration, use default
	if [ -z "$_jailpath" ]; then
		echo "$JAILBASE/$1"
		return
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

		if [ ! -z "$_fstab_dir" ];
		then
			_mnt_cmd="/sbin/mount -F /etc/fstab.$_jail $_fstab_dir"
		fi
	fi

	echo "    $_mnt_cmd"
	# shellcheck disable=2086
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
	if [ -f "/etc/jail.conf" ];
	then
		ALL_JAILS=$(grep '{' /etc/jail.conf | grep -v '^#' | awk '{ print $1 }')
		return
	fi

	if [ -d "/usr/local/etc/ezjail" ];
	then
		ALL_JAILS=$(grep _hostname /usr/local/etc/ezjail/* | cut -f2 -d'=' | sed -e 's/"//g')
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
			jail_manage "$_j"
		done
	;;
	"mergemaster"   )
		_get_all_jails
		for _j in $ALL_JAILS;
		do
			echo "Doing mergemaster for jail $_j"
			jail_mergemaster "$_j"
		done
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
	"cleanup"   )
		_get_all_jails
		for _j in $ALL_JAILS;
		do
			echo "Doing cleanup for jail $_j"
			jail_cleanup "$_j"
		done
	;;
	*)
		echo "Entering jail $1"
		jail_manage "$1"
	;;
esac

exit
