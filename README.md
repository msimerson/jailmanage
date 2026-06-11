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

### Upgrade FreeBSD version in every jail

```sh
jailmanage update
```

This runs a command like this command for each jail:

```sh
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
```

If `jailmanage` detects that the jail is running an older major version of
FreeBSD than the host (ex: host is running 14.2 and jail is running 14.1),
then jailmanage will perform a binary upgrade of FreeBSD using these commands:

```
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf -r 14.2-RELEASE upgrade install
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
freebsd-update -b /jails/dns -f /jails/dns/etc/freebsd-update.conf install
```

### Audit installed packages

```sh
jailmanage audit
```

Runs `pkg audit` against the host and every jail, reporting packages with
known vulnerabilities.

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

### Delete caches

```sh
jailmanage clean
```

This command empties /var/cache/pkg and /var/db/freebsd-update in every jail.
