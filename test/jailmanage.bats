
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
  #[ "$output" = "usage: ./jailmanage.sh [ jailname ]" ]
  [ "$BATS_RUN_COMMAND" = "./jailmanage.sh" ]
}

#@test "jail_root_path works" {
#  source ./jailmanage.sh test
#  run jail_root_path matt
#  [ "$status" -eq 0 ]
#  [ "$output" = "usage: ./jailmanage.sh [ jailname ]" ]
#}

