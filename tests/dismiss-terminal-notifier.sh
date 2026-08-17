#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/bin/.local/bin/dismiss-terminal-notifier"
notifier_fixture="$root/tests/fixtures/terminal-notifier-remove-limit"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-dismiss-notifier-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
state_file="$test_home/state"
log_file="$test_home/log"

fail() {
    printf 'dismiss-terminal-notifier test: %s\n' "$*" >&2
    exit 1
}

run() {
    FUNK_TERMINAL_NOTIFIER_BIN="$notifier_fixture" \
        FUNK_TEST_NOTIFIER_STATE="$state_file" \
        FUNK_TEST_NOTIFIER_LOG="$log_file" \
        "$helper"
}

printf '30\n' >"$state_file"
: >"$log_file"
run || fail "thirty notifications did not drain"
[ "$(<"$state_file")" -eq 0 ] || fail "notifications remain after the drain"
[ "$(grep -c '^-remove ALL$' "$log_file")" -eq 4 ] \
    || fail "the helper did not run four eight-notification removal passes"

printf '0\n' >"$state_file"
: >"$log_file"
run || fail "an empty notification set must succeed"
if grep -q '^-remove ALL$' "$log_file"; then
    fail "an empty notification set triggered a removal"
fi

FUNK_TERMINAL_NOTIFIER_BIN=/nonexistent "$helper" \
    || fail "a missing notifier must leave the hotkey process successful"

printf 'dismiss-terminal-notifier tests passed\n'
