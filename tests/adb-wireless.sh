#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
pair_helper="$root/bin/.local/bin/adb-wireless-pair"
connect_helper="$root/bin/.local/bin/adb-wireless-connect"
adb_fixture="$root/tests/fixtures/adb"
tailscale_fixture="$root/tests/fixtures/tailscale"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-adb-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/adb.log"
state="$test_home/state/adb-target"

# The helpers complete a single-label MagicDNS name with the Tailnet's suffix,
# so the fixture Tailnet decides the qualified name these assertions expect.
phone="smolbird.example-tailnet.ts.net"

fail() {
    printf 'adb-wireless test: %s\n' "$*" >&2
    exit 1
}

run_pair() {
    HOME="$test_home" ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" \
        FUNK_TEST_ADB_LOG="$log" "$pair_helper" "$@"
}

run_connect() {
    HOME="$test_home" ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" \
        FUNK_TEST_ADB_LOG="$log" ADB_WIRELESS_STATE_FILE="$state" \
        "$connect_helper" "$@"
}

: >"$log"
run_pair 37123 >/dev/null
grep -Fx "$(printf 'pair\t%s:37123' "$phone")" "$log" >/dev/null \
    || fail "pairing did not use the phone's qualified MagicDNS name and port"
[ "$(awk -F '\t' '$1 == "pair" { print NF }' "$log")" -eq 2 ] \
    || fail "pairing code was passed on the command line"

: >"$log"
FUNK_TEST_ADB_DEVICES="$phone:38555\tdevice" run_connect --print-serial 38555 \
    >"$test_home/serial" 2>/dev/null
[ "$(cat "$test_home/serial")" = "$phone:38555" ] \
    || fail "connect did not print the exact phone serial"
grep -Fx "$(printf 'connect\t%s:38555' "$phone")" "$log" >/dev/null \
    || fail "connect did not use the phone's qualified MagicDNS name and port"
grep -Fx "$phone:38555" "$state" >/dev/null \
    || fail "successful explicit connection was not remembered"
[ "$(stat -f '%Lp' "$state")" = 600 ] \
    || fail "remembered connection does not have private permissions"

: >"$log"
FUNK_TEST_ADB_DEVICES="$phone:38555\tdevice" run_connect --print-serial \
    >"$test_home/saved-serial"
[ "$(cat "$test_home/saved-serial")" = "$phone:38555" ] \
    || fail "saved connection was not reusable by Raycast"
if grep -q '^connect' "$log"; then
    fail "already-connected saved target was needlessly reconnected"
fi

rm -f "$state"
: >"$log"
FUNK_TEST_ADB_DEVICES="$phone:39999\tdevice" run_connect --print-serial \
    >"$test_home/existing-serial"
[ "$(cat "$test_home/existing-serial")" = "$phone:39999" ] \
    || fail "existing Tailnet connection was not detected"

# adb separates a serial from its state with a single tab, and a locally
# discovered serial can contain spaces. Selection must stay anchored to the
# Tailnet device no matter what else is attached.
rm -f "$state"
: >"$log"
FUNK_TEST_ADB_DEVICES="adb-R5CT91TW4RP-3gO2Fq (2)._x._tcp\tdevice\n$phone:40222\tdevice" \
    run_connect --print-serial >"$test_home/spaced-serial"
[ "$(cat "$test_home/spaced-serial")" = "$phone:40222" ] \
    || fail "a serial containing spaces hid the Tailnet device"

rm -f "$state"
: >"$log"
FUNK_TEST_ADB_DEVICES="adb-R5CT91TW4RP-3gO2Fq (2)._x._tcp\tdevice\n$phone:40333\tdevice" \
    run_connect --print-serial 40333 >"$test_home/spaced-explicit" 2>/dev/null
[ "$(cat "$test_home/spaced-explicit")" = "$phone:40333" ] \
    || fail "explicit connect did not confirm the qualified target"

# An already qualified name must be used verbatim, not qualified twice.
: >"$log"
run_pair --host "$phone" 40111 >/dev/null
grep -Fx "$(printf 'pair\t%s:40111' "$phone")" "$log" >/dev/null \
    || fail "fully qualified Tailnet hostname override was not honored"

: >"$log"
run_pair --host other.example-tailnet.ts.net 40444 >/dev/null
grep -Fx $'pair\tother.example-tailnet.ts.net:40444' "$log" >/dev/null \
    || fail "another Tailnet host was not honored verbatim"

for rejected_host in 100.64.0.10 smolbird.local smolbird.example.com; do
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
