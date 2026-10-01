# shellcheck shell=bash
# Assertions shared by the bash test scripts. Source it, run checks, then
# `exit $fail`.
fail=0
check() { # <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
contains() { # <description> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n        [%s] not in [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
