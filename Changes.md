## Changes


### 2022-06-21

- add send


### 2021-11-01

- update uses PAGER=cat to lessen human babysitting
- move shellcheck lines into .shellcheckrc
- \_get_all_jails: skip jails where dir doesn't exist
- audit: only check running jails


### 2021-04-22

- added audit


### 2020-02-11

- added versions (by @Infern1)


### 2019-11-07

- added selfupdate()


### 2018-01-19

- fix quoting for 'jailmanage update'


### 2017-02-27

- consistently use tabs for indent
- update() can now specify a single jail to update
- check jail.conf jail declaration for path setting


### 2016-12-29

- better parsing of jail names
- lint cleanups
- mount hosts pkg cache


### 2016-01-18

- name parsing, lint, pkg cache


### Dec 29, 2015

- better parsing of jail names
- lint cleanups
- mount hosts pkg cache

- Oct 04, 2015 - added 'cleanup' target
- Dec 19, 2014 - 'update' optimizes freebsd-update.conf in jails
- Dec 07, 2014 - improvements for 'update'
- Nov 14, 2014 - added 'update' target
- Aug 24, 2014 - only run pkg audit when pkgng installed
- Mar  2, 2014
    - build list of jails from /etc/jail.conf (and legacy ezjail)
    - run "pkg audit" within the jail before entry
- Jan  2, 2014 - removed ezjail dependency
- Dec  1, 2013 - fixed typo: installng -> installing
- Feb 12, 2013 - use local vars, added fix_jailname()
- Oct 19, 2012 - compatible with jail names with a . in them
- Apr 22, 2010 - added mergemaster feature
- Feb 02, 2009 - added support for jail names with - in name (ezjail compat)
- Sep 27, 2007 - added all target
- Sep 23, 2007 - added tripwire
- Sep 18, 2007 - added sudo
- Sep 16, 2007 - initial authoring

