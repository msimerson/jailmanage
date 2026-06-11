#!/bin/sh

if [ -n "$1" ]; then
    bats "$1"
    exit
fi

echo "shellcheck *.sh"
shellcheck *.sh

bats test/*.bats
