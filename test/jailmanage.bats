# https://bats-core.readthedocs.io/en/stable/writing-tests.html

#setup() {
#  load ../jailmanage.sh
#}

@test "test arg exits 0" {
  run ./jailmanage.sh test
  [ "$status" -eq 0 ]
}

@test "test arg prints version banner" {
  run ./jailmanage.sh test
  [[ "${lines[0]}" == v:* ]]
}

@test "no arg prompts for usage" {
  run ./jailmanage.sh
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "   usage: ./jailmanage.sh [ jailname ]" ]
  [ "$BATS_RUN_COMMAND" = "./jailmanage.sh" ]
}

@test "usage lists each target" {
  run ./jailmanage.sh
  for _t in all audit vulnerable versions update clean send mergemaster selfupgrade; do
    [[ "$output" == *"$_t"* ]]
  done
}

@test "fix_jailname leaves a plain name unchanged" {
  source ./jailmanage.sh test
  run fix_jailname webmail
  [ "$status" -eq 0 ]
  [ "$output" = "webmail" ]
}

@test "fix_jailname rewrites - and . to _" {
  source ./jailmanage.sh test
  run fix_jailname web-mail.1
  [ "$status" -eq 0 ]
  [ "$output" = "web_mail_1" ]
}

@test "jail_root_path works" {
  source ./jailmanage.sh test
  run jail_root_path test
  [ "$status" -eq 0 ]
  [ "$output" = "/jails/test" ]
}

@test "jail_root_path honors ZFS_JAIL_MNT" {
  export ZFS_JAIL_MNT=/srv/jails
  source ./jailmanage.sh test
  run jail_root_path test
  [ "$status" -eq 0 ]
  [ "$output" = "/srv/jails/test" ]
}

@test "jail_audit_one reports a clean jail" {
  source ./jailmanage.sh test
  run jail_audit_one webmail true
  [ "$status" -eq 0 ]
  [[ "$output" == *webmail* ]]
}

@test "jail_audit_one reports a vulnerable jail" {
  source ./jailmanage.sh test
  run jail_audit_one webmail "printf 'libfoo-1.0 is vulnerable:\n'; false"
  [ "$status" -eq 1 ]
  [[ "$output" == *libfoo-1.0* ]]
  [[ "$output" != *"is vulnerable"* ]]
}
