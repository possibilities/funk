#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
pair_helper="$root/bin/.local/bin/adb-wireless-pair"
connect_helper="$root/bin/.local/bin/adb-wireless-connect"
adb_fixture="$root/tests/fixtures/adb"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-adb-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/adb.log"
state="$test_home/state/adb-target"

fail() {
    printf 'adb-wireless test: %s\n' "$*" >&2
    exit 1
}

run_pair() {
    HOME="$test_home" ADB="$adb_fixture" FUNK_TEST_ADB_LOG="$log" \
        "$pair_helper" "$@"
}

run_connect() {
    HOME="$test_home" ADB="$adb_fixture" FUNK_TEST_ADB_LOG="$log" \
        ADB_WIRELESS_STATE_FILE="$state" "$connect_helper" "$@"
}

: >"$log"
run_pair 37123 >/dev/null
grep -Fx $'pair\tsmallbird:37123' "$log" >/dev/null \
    || fail "pairing did not use Smallbird's Tailnet hostname and explicit port"
[ "$(awk -F '\t' '$1 == "pair" { print NF }' "$log")" -eq 2 ] \
    || fail "pairing code was passed on the command line"

: >"$log"
FUNK_TEST_ADB_DEVICES='smallbird:38555\tdevice' run_connect --print-serial 38555 \
    >"$test_home/serial" 2>/dev/null
[ "$(cat "$test_home/serial")" = "smallbird:38555" ] \
    || fail "connect did not print the exact Smallbird serial"
grep -Fx $'connect\tsmallbird:38555' "$log" >/dev/null \
    || fail "connect did not use Smallbird's Tailnet hostname and explicit port"
grep -Fx 'smallbird:38555' "$state" >/dev/null \
    || fail "successful explicit connection was not remembered"
[ "$(stat -f '%Lp' "$state")" = 600 ] \
    || fail "remembered connection does not have private permissions"

: >"$log"
FUNK_TEST_ADB_DEVICES='smallbird:38555\tdevice' run_connect --print-serial \
    >"$test_home/saved-serial"
[ "$(cat "$test_home/saved-serial")" = "smallbird:38555" ] \
    || fail "saved connection was not reusable by Raycast"
if grep -q '^connect' "$log"; then
    fail "already-connected saved target was needlessly reconnected"
fi

rm -f "$state"
: >"$log"
FUNK_TEST_ADB_DEVICES='smallbird:39999\tdevice' run_connect --print-serial \
    >"$test_home/existing-serial"
[ "$(cat "$test_home/existing-serial")" = "smallbird:39999" ] \
    || fail "existing Tailnet connection was not detected"

: >"$log"
run_pair --host smallbird.example-tailnet.ts.net 40111 >/dev/null
grep -Fx $'pair\tsmallbird.example-tailnet.ts.net:40111' "$log" >/dev/null \
    || fail "fully qualified Tailnet hostname override was not honored"

for rejected_host in 100.64.0.10 smallbird.local smallbird.example.com; do
    if run_pair --host "$rejected_host" 37123 >/dev/null 2>&1; then
        fail "non-Tailnet host was accepted: $rejected_host"
    fi
done

for rejected_port in 0 65536 abc '123:456'; do
    if run_connect "$rejected_port" >/dev/null 2>&1; then
        fail "invalid connection port was accepted: $rejected_port"
    fi
done

if grep -Eqi '(^|[^[:alnum:]_])mdns([^[:alnum:]_]|$)|_adb-tls' \
    "$pair_helper" "$connect_helper"; then
    fail "local discovery remains in a Tailnet-only helper"
fi
