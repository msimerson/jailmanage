# https://bats-core.readthedocs.io/en/stable/writing-tests.html

#setup() {
#  load ../jailmanage.sh
#}

@test "test arg exits 0" {
  run ./jailmanage.sh test
  [ "$status" -eq 0 ]
}

@test "no arg prompts for usage" {
  run ./jailmanage.sh
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "   usage: ./jailmanage.sh [ jailname ]" ]
  [ "$BATS_RUN_COMMAND" = "./jailmanage.sh" ]
}

@test "jail_root_path works" {
  source ./jailmanage.sh test
  run jail_root_path test
  [ "$status" -eq 0 ]
  [ "$output" = "/jails/test" ]
}
