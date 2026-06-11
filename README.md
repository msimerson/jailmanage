# jailmanage

Manage FreeBSD jails

## Install

```sh
fetch -o /usr/local/bin/jailmanage https://raw.githubusercontent.com/msimerson/jailmanage/master/jailmanage.sh
chmod 755 /usr/local/bin/jailmanage
```

## Upgrade

```sh
jailmanage selfupgrade
```

## Usage

```sh
$ jailmanage
   usage: jailmanage [ jailname ]

 jailname has several special jail names:

 all         - consecutively log into each jail
 audit       - run 'pkg audit' in each jail
 vulnerable  - drop into each jail with vulnerable packages
 versions    - report versions of each jail
 update      - run freebsd-update in each jail
 clean       - purge pkg and freebsd-update caches
 send        - ship a jail between hosts
 mergemaster - run mergemaster in each jail
 selfupgrade - upgrade jailmanage script
```

### Enter each jail

```sh
jailmanage all
```

### Report OS version of each jail

```sh
➜ jailmanage versions  
v: 2026-06-10

host.****.net       15.0-RELEASE-p10
--------------      ---------------
dns                 15.0-RELEASE-p10
postfix             15.0-RELEASE-p10
nagios              15.0-RELEASE-p10
haproxy             15.0-RELEASE-p10
influxdb            15.0-RELEASE-p10
grafana             15.0-RELEASE-p10
mongodb             15.0-RELEASE-p10
```

### Upgrade FreeBSD version(s)

```sh
jailmanage update [jail]
```

Runs a command like this command for the specified jail, or each jail:

```sh
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
```

If `jailmanage` detects that the jail is running an older major version of
FreeBSD than the host (ex: host is running 14.2 and jail is running 14.1),
then it will perform a binary upgrade using these commands:

```sh
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf -r 14.2-RELEASE upgrade install
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
```

### Audit installed packages

Runs `pkg audit` against the host and every jail, reporting packages with
known vulnerabilities.

```sh
➜ jailmanage audit   
v: 2026-06-10

⚠️    host.****.net
	python311-3.11.15_2
✅   dns
✅   postfix
✅   nagios
✅   influxdb
✅   grafana
⚠️    mongodb
	mongodb80-8.0.12_10
```

To then log into each jail that has vulnerable packages:

```sh
jailmanage vulnerable
```

### Ship a jail to another host

```sh
jailmanage send [jail name] [dest host] [dest ZVOL] [JAIL TOO]
```

Uses `zfs send` over `ssh` to replicate a jail's datasets to another host. By
default only the data filesystem is sent; pass a value for `JAIL TOO` to also
send the jail root filesystem.

### Clean caches

```sh
jailmanage clean
```

This command empties /var/cache/pkg and /var/db/freebsd-update in every jail.
