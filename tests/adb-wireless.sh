#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
pair_helper="$root/bin/.local/bin/adb-wireless-pair"
connect_helper="$root/bin/.local/bin/adb-wireless-connect"
ensure_helper="$root/bin/.local/bin/tailscale-ensure-online"
adb_fixture="$root/tests/fixtures/adb"
tailscale_fixture="$root/tests/fixtures/tailscale"
resolver_fixture="$root/tests/fixtures/dscacheutil"
dns_sd_fixture="$root/tests/fixtures/dns-sd"
nc_fixture="$root/tests/fixtures/nc"
# Exported for every child, not passed per invocation: this suite drives the
# connect helper through paths that reach tailscale-ensure-online, and an
# unpinned notifier posts the fixture's fictional tailnet into the operator's
# real Notification Center. Losing one test to a missed variable is cheap;
# teaching someone to distrust these alerts is not.
export FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier"
jq_bin=$(command -v jq)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-adb-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/adb.log"
adb_env_log="$test_home/adb-env.log"
state="$test_home/state/adb-target"
tailscale_log="$test_home/tailscale.log"
tailscale_state="$test_home/tailscale-state"
connected_file="$test_home/connected-target"
dnssd_log="$test_home/dnssd.log"
dnssd_term_log="$test_home/dnssd-term.log"
nc_log="$test_home/nc.log"
xdg_state="$test_home/custom-xdg-state"

phone=smolbird.example-tailnet.ts.net
phone_id=R5CT91TW4RP
tailnet_node=n123-test-smolbird
adb_server_socket=tcp:localhost:5038

fail() {
    printf 'adb-wireless test: %s\n' "$*" >&2
    exit 1
}

reset_adb() {
    rm -f "$connected_file"
    : >"$log"
    : >"$adb_env_log"
    : >"$dnssd_log"
    : >"$dnssd_term_log"
    : >"$nc_log"
}

write_bound_state() {
    mkdir -p "$(dirname "$state")"
    printf '%s\nserial=%s\ntailnet_node=%s\n' \
        "$1" "$phone_id" "$tailnet_node" >"$state"
}

assert_isolated_adb() {
    [ -s "$adb_env_log" ] || fail "ADB fixture did not record its environment"
    if awk -F '\t' \
        -v socket="$adb_server_socket" \
        '$2 != "auto=0" || $3 != "socket=" socket || $4 != "usb=0" {
            bad=1
        }
        END { exit bad }' \
        "$adb_env_log"; then
        :
    else
        fail "ADB command escaped the isolated wireless-only server"
    fi
    if grep -q '^auto-connect' "$log"; then
        fail "ADB auto-connected an unrelated paired device"
    fi
    if grep -q '^usb-claim' "$log"; then
        fail "isolated ADB server contended for a USB interface"
    fi
}

run_pair() {
    HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
        ADB_USB=1 ADB_MDNS_AUTO_CONNECT=adb-tls-connect \
        ADB_SERVER_SOCKET=tcp:localhost:5037 \
        ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" \
        FUNK_TEST_ADB_LOG="$log" FUNK_TEST_ADB_ENV_LOG="$adb_env_log" \
        FUNK_TEST_ADB_SIMULATE_MDNS_AUTOCONNECT=1 \
        FUNK_TEST_ADB_SIMULATE_USB_CONTENTION=1 \
        "$pair_helper" "$@"
}

run_connect() {
    HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
        ADB_USB=1 ADB_MDNS_AUTO_CONNECT=adb-tls-connect \
        ADB_SERVER_SOCKET=tcp:localhost:5037 \
        ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" \
        TAILSCALE_ENSURE_ONLINE="$ensure_helper" JQ="$jq_bin" \
        DSCACHEUTIL="$resolver_fixture" DNS_SD="$dns_sd_fixture" NC="$nc_fixture" \
        SHLOCK=/usr/bin/shlock \
        ADB_WIRELESS_DISCOVERY_SECONDS="${ADB_WIRELESS_DISCOVERY_SECONDS:-1}" \
        FUNK_TEST_ADB_LOG="$log" FUNK_TEST_ADB_ENV_LOG="$adb_env_log" \
        FUNK_TEST_ADB_SIMULATE_MDNS_AUTOCONNECT=1 \
        FUNK_TEST_ADB_SIMULATE_USB_CONTENTION=1 \
        FUNK_TEST_TAILSCALE_LOG="$tailscale_log" \
        FUNK_TEST_ADB_CONNECTED_FILE="$connected_file" \
        FUNK_TEST_DNSSD_LOG="$dnssd_log" \
        FUNK_TEST_DNSSD_TERM_LOG="$dnssd_term_log" \
        FUNK_TEST_NC_LOG="$nc_log" \
        ADB_WIRELESS_STATE_FILE="$state" "$connect_helper" "$@"
}

reset_adb
run_pair 37123 >/dev/null
grep -Fx "$(printf 'pair\t%s:37123' "$phone")" "$log" >/dev/null \
    || fail "pairing did not use the phone's qualified MagicDNS name and port"
[ "$(awk -F '\t' '$1 == "pair" { print NF }' "$log")" -eq 2 ] \
    || fail "pairing code was passed on the command line"
assert_isolated_adb

reset_adb
run_connect --print-serial 38555 >"$test_home/serial" 2>"$test_home/explicit-error"
[ "$(cat "$test_home/serial")" = "$phone:38555" ] \
    || fail "--print-serial stdout was not exactly the explicit target"
grep -Fx "$(printf 'connect\t%s:38555' "$phone")" "$log" >/dev/null \
    || fail "explicit connect did not use the qualified Tailnet target"
grep -Fx "$phone:38555" "$state" >/dev/null \
    || fail "successful explicit connection was not remembered"
grep -Fx "serial=$phone_id" "$state" >/dev/null \
    || fail "successful connection did not bind the Android identity"
grep -Fx "tailnet_node=$tailnet_node" "$state" >/dev/null \
    || fail "successful connection did not bind the Tailnet node"
[ "$(stat -f '%Lp' "$state")" = 600 ] \
    || fail "remembered connection does not have private permissions"
assert_isolated_adb

reset_adb
FUNK_TEST_ADB_DEVICES="$phone:38555\tdevice" run_connect --print-serial \
    >"$test_home/saved-serial"
[ "$(cat "$test_home/saved-serial")" = "$phone:38555" ] \
    || fail "saved connection was not reusable by Screen Copy"
if grep -q '^connect' "$log"; then
    fail "already-connected saved target was needlessly reconnected"
fi
assert_isolated_adb

# A reachable saved port needs no discovery and remains fixed to the pinned
# Tailnet host and Android identity.
reset_adb
FUNK_TEST_REACHABLE_PORTS=38555 \
FUNK_TEST_ADB_IDENTITIES="$phone:38555\t$phone_id" \
    run_connect --print-serial >"$test_home/fallback-serial" 2>/dev/null
[ "$(cat "$test_home/fallback-serial")" = "$phone:38555" ] \
    || fail "reachable saved port did not reconnect"
grep -Fx "$(printf 'connect\t%s:38555' "$phone")" "$log" >/dev/null \
    || fail "saved port did not use the Tailnet hostname"
[ ! -s "$dnssd_log" ] || fail "reachable saved port needlessly browsed mDNS"
assert_isolated_adb

# A changed Tailnet node is rejected before ADB, port probing, or discovery.
printf '%s\nserial=%s\ntailnet_node=n999-former-phone\n' \
    "$phone:38555" "$phone_id" >"$state"
reset_adb
if run_connect --print-serial \
    >"$test_home/node-output" 2>"$test_home/node-error"; then
    fail "changed Tailnet node was accepted"
fi
grep -F 'Tailnet identity mismatch' "$test_home/node-error" >/dev/null \
    || fail "changed Tailnet node was not explained"
[ ! -s "$log" ] && [ ! -s "$nc_log" ] && [ ! -s "$dnssd_log" ] \
    || fail "changed Tailnet node reached discovery or ADB"

# Legacy state is migrated only by verifying its saved stable-host port. It
# cannot use passive discovery before an Android identity is bound.
printf '%s\n' "$phone:38555" >"$state"
reset_adb
FUNK_TEST_REACHABLE_PORTS=38555 run_connect --print-serial \
    >"$test_home/legacy-serial" 2>/dev/null
[ "$(cat "$test_home/legacy-serial")" = "$phone:38555" ] \
    || fail "reachable legacy target was not verified"
grep -Fx "serial=$phone_id" "$state" >/dev/null \
    || fail "legacy migration did not bind the Android identity"
grep -Fx "tailnet_node=$tailnet_node" "$state" >/dev/null \
    || fail "legacy migration did not bind the Tailnet node"
[ ! -s "$dnssd_log" ] || fail "legacy migration browsed before identity binding"

printf '%s\n' "$phone:38555" >"$state"
reset_adb
if FUNK_TEST_DNSSD_ZONE="adb-OTHER-noise._adb-tls-connect._tcp SRV 0 0 42000 Android.local. ; Replace with unicast FQDN of target host" \
    FUNK_TEST_REACHABLE_PORTS=42000 run_connect --print-serial \
        >"$test_home/legacy-stale-output" 2>"$test_home/legacy-stale-error"; then
    fail "stale legacy target was rebound from unrelated mDNS"
fi
grep -F 'unbound saved target' "$test_home/legacy-stale-error" >/dev/null \
    || fail "stale legacy target did not request explicit bootstrap"
[ ! -s "$dnssd_log" ] || fail "stale legacy state consulted mDNS"
[ "$(cat "$state")" = "$phone:38555" ] \
    || fail "failed legacy verification changed durable state"

rm -f "$state"
reset_adb
if FUNK_TEST_DNSSD_ZONE="adb-STRANGER-one._adb-tls-connect._tcp SRV 0 0 44000 Android.local. ; Replace with unicast FQDN of target host" \
    FUNK_TEST_REACHABLE_PORTS=44000 run_connect --print-serial \
        >"$test_home/unbound-output" 2>"$test_home/unbound-error"; then
    fail "unbound helper adopted a nearby paired phone"
fi
grep -F 'supply Smolbird' "$test_home/unbound-error" >/dev/null \
    || fail "unbound helper did not request the explicit connection port"
[ ! -s "$dnssd_log" ] || fail "unbound helper performed passive discovery"
if grep -Eq '^(connect|-s)' "$log"; then
    fail "unbound helper connected to or queried a device"
fi
assert_isolated_adb

# An existing connection on the isolated server remains a safe migration path.
rm -f "$state"
reset_adb
FUNK_TEST_ADB_DEVICES="$phone:39999\tdevice" run_connect --print-serial \
    >"$test_home/existing-serial"
[ "$(cat "$test_home/existing-serial")" = "$phone:39999" ] \
    || fail "existing Tailnet connection was not detected"
grep -Fx "serial=$phone_id" "$state" >/dev/null \
    || fail "existing connection did not initialize identity state"
assert_isolated_adb

# Passive DNS-SD sees two instances for the saved phone, as macOS does in
# practice. Only the one reachable through the pinned Tailnet host is selected.
write_bound_state "$phone:39999"
reset_adb
FUNK_TEST_DNSSD_ZONE="adb-$phone_id-live._adb-tls-connect._tcp SRV 0 0 44129 Android.local. ; Replace with unicast FQDN of target host\nadb-$phone_id-live\\\\032(2)._adb-tls-connect._tcp SRV 0 0 41222 Android.local. ; Replace with unicast FQDN of target host" \
FUNK_TEST_REACHABLE_PORTS=41222 \
FUNK_TEST_ADB_IDENTITIES="$phone:41222\t$phone_id" \
    run_connect --print-serial >"$test_home/discovered-serial" 2>/dev/null
[ "$(cat "$test_home/discovered-serial")" = "$phone:41222" ] \
    || fail "passive rotating-port discovery did not select the reachable port"
grep -Fx "$(printf 'connect\t%s:41222' "$phone")" "$log" >/dev/null \
    || fail "rotating-port connection did not stay on the Tailnet host"
grep -Fx -- '-Z _adb-tls-connect._tcp local.' "$dnssd_log" >/dev/null \
    || fail "rotating-port recovery did not use passive DNS-SD"
grep -Fx terminated "$dnssd_term_log" >/dev/null \
    || fail "bounded discovery did not terminate the persistent DNS-SD browser"
[ "$(head -n 1 "$state")" = "$phone:41222" ] \
    || fail "confirmed rotating port was not persisted"
assert_isolated_adb

# Zero can only appear safe with a test fixture that exits by itself. Real
# Darwin dns-sd browsing is persistent, so reject zero before starting it.
write_bound_state "$phone:41000"
reset_adb
if ADB_WIRELESS_DISCOVERY_SECONDS=0 run_connect --print-serial \
    >"$test_home/zero-duration-output" 2>"$test_home/zero-duration-error"; then
    fail "zero-second persistent DNS-SD discovery was accepted"
fi
grep -F 'ADB_WIRELESS_DISCOVERY_SECONDS must be an integer from 1 to 10' \
    "$test_home/zero-duration-error" >/dev/null \
    || fail "zero-second discovery rejection was not actionable"
[ ! -s "$dnssd_log" ] \
    || fail "zero-second discovery started a persistent DNS-SD browser"

# Unrelated paired services are visible in the passive snapshot, but are
# filtered by instance identity before any port probe or ADB command.
write_bound_state "$phone:41000"
reset_adb
FUNK_TEST_DNSSD_ZONE="adb-OTHERPHONE-noise._adb-tls-connect._tcp SRV 0 0 42000 Other.local. ; Replace with unicast FQDN of target host\nadb-$phone_id-next._adb-tls-connect._tcp SRV 0 0 41333 Android.local. ; Replace with unicast FQDN of target host" \
FUNK_TEST_REACHABLE_PORTS="42000 41333" \
FUNK_TEST_ADB_IDENTITIES="$phone:41333\t$phone_id" \
    run_connect --print-serial >"$test_home/selected-serial" 2>/dev/null
[ "$(cat "$test_home/selected-serial")" = "$phone:41333" ] \
    || fail "saved identity did not select its passive DNS-SD port"
grep -Fx "$(printf 'connect\t%s:41333' "$phone")" "$log" >/dev/null \
    || fail "identity-selected service used the wrong target"
if grep -F '42000' "$nc_log" >/dev/null \
    || grep -F 'OTHERPHONE' "$log" >/dev/null \
    || grep -q '^auto-connect' "$log"; then
    fail "unrelated paired service was probed, queried, or auto-connected"
fi
assert_isolated_adb

# Two identity-matching ports that both answer on the pinned phone are truly
# ambiguous. Refuse before an ADB connect or device property query.
write_bound_state "$phone:41000"
reset_adb
if FUNK_TEST_DNSSD_ZONE="adb-$phone_id-same._adb-tls-connect._tcp SRV 0 0 43001 Android.local. ; Replace with unicast FQDN of target host\nadb-$phone_id-same\\\\032(2)._adb-tls-connect._tcp SRV 0 0 43002 Android.local. ; Replace with unicast FQDN of target host" \
    FUNK_TEST_REACHABLE_PORTS="43001 43002" run_connect --print-serial \
        >"$test_home/ambiguous-output" 2>"$test_home/ambiguous-error"; then
    fail "ambiguous reachable ports were accepted"
fi
grep -F 'multiple reachable mDNS ports match the saved phone identity' \
    "$test_home/ambiguous-error" >/dev/null \
    || fail "realistic ambiguity was not explained"
if grep -Eq '^(connect|-s)' "$log"; then
    fail "ambiguous discovery connected to or queried a device"
fi
assert_isolated_adb

# A reachable unrelated service cannot displace the saved target when no
# identity-matching candidate answers.
write_bound_state "$phone:41000"
reset_adb
if FUNK_TEST_DNSSD_ZONE="adb-STRANGER-one._adb-tls-connect._tcp SRV 0 0 44000 Stranger.local. ; Replace with unicast FQDN of target host\nadb-$phone_id-stale._adb-tls-connect._tcp SRV 0 0 45000 Android.local. ; Replace with unicast FQDN of target host" \
    FUNK_TEST_REACHABLE_PORTS=44000 run_connect --print-serial \
        >"$test_home/unrelated-output" 2>"$test_home/unrelated-error"; then
    fail "reachable unrelated service was accepted"
fi
grep -F 'no reachable mDNS port matches the saved phone identity' \
    "$test_home/unrelated-error" >/dev/null \
    || fail "missing identity-matching port was not actionable"
if grep -F '44000' "$nc_log" >/dev/null \
    || grep -Eq '^(connect|-s)' "$log"; then
    fail "unrelated service was probed, connected, or queried"
fi

# A just-connected unexpected identity is disconnected and durable state stays
# pinned to the intended phone.
write_bound_state "$phone:41222"
reset_adb
if FUNK_TEST_REACHABLE_PORTS=41222 \
    FUNK_TEST_ADB_IDENTITIES="$phone:41222\tOTHERPHONE" \
    run_connect --print-serial >"$test_home/mismatch-output" \
        2>"$test_home/mismatch-error"; then
    fail "saved Tailnet target accepted another Android identity"
fi
grep -F 'disconnected the unexpected device' "$test_home/mismatch-error" >/dev/null \
    || fail "unexpected Android identity was not disconnected"
grep -Fx "$(printf 'disconnect\t%s:41222' "$phone")" "$log" >/dev/null \
    || fail "unexpected Android identity remained connected"
[ ! -e "$connected_file" ] \
    || fail "unexpected Android identity remained in the fixture device list"
[ "$(head -n 1 "$state")" = "$phone:41222" ] \
    || fail "Android identity mismatch changed saved state"

# Recovery diagnostics remain on stderr while --print-serial stdout stays
# exactly machine-readable.
printf 'Stopped\n' >"$tailscale_state"
: >"$tailscale_log"
reset_adb
FUNK_TEST_TAILSCALE_STATE_FILE="$tailscale_state" run_connect --print-serial 41111 \
    >"$test_home/stopped-serial" 2>"$test_home/stopped-error"
[ "$(cat "$test_home/stopped-serial")" = "$phone:41111" ] \
    || fail "recovery diagnostics contaminated --print-serial stdout"
grep -F 'Tailscale is stopped' "$test_home/stopped-error" >/dev/null \
    || fail "Stopped recovery diagnostics were not preserved on stderr"
grep -F "connected to $phone:41111" "$test_home/stopped-error" >/dev/null \
    || fail "ADB connection diagnostics were not preserved on stderr"
grep -Fx up "$tailscale_log" >/dev/null \
    || fail "Screen Copy path did not use shared Stopped recovery"

# DNS and peer failures remain distinct and never reach ADB.
reset_adb
if FUNK_TEST_MAGICDNS_FAIL=1 run_connect --print-serial \
    >"$test_home/dns-output" 2>"$test_home/dns-error"; then
    fail "unresolvable MagicDNS host was accepted"
fi
grep -F 'MagicDNS cannot resolve' "$test_home/dns-error" >/dev/null \
    || fail "MagicDNS failure was not identified"
[ ! -s "$log" ] || fail "MagicDNS failure reached ADB"

reset_adb
if FUNK_TEST_TAILSCALE_PEER_STATE=Offline run_connect --print-serial \
    >"$test_home/offline-output" 2>"$test_home/offline-error"; then
    fail "offline phone peer reached ADB"
fi
grep -F "peer $phone is offline" "$test_home/offline-error" >/dev/null \
    || fail "offline phone peer was not distinguished"
[ ! -s "$log" ] || fail "offline phone peer reached ADB"

# Authentication failure is pairing-specific and never invokes pairing.
write_bound_state "$phone:38555"
reset_adb
if FUNK_TEST_REACHABLE_PORTS=38555 \
    FUNK_TEST_ADB_CONNECT_ERROR="failed to authenticate to $phone:38555" \
    run_connect --print-serial >"$test_home/auth-output" 2>"$test_home/auth-error"; then
    fail "ADB authentication failure was accepted"
fi
grep -F 'pairing may have been revoked' "$test_home/auth-error" >/dev/null \
    || fail "ADB authentication failure was not distinguished"
grep -F 'pair manually with adb-wireless-pair' "$test_home/auth-error" >/dev/null \
    || fail "ADB authentication failure did not preserve manual pairing"
if grep -q '^pair' "$log"; then
    fail "authentication recovery invoked pairing automatically"
fi

# Passive discovery and ADB command failures preserve known-good state.
write_bound_state "$phone:41222"
reset_adb
if FUNK_TEST_DNSSD_FAIL=1 run_connect --print-serial \
    >"$test_home/dnssd-fail-output" 2>"$test_home/dnssd-fail-error"; then
    fail "DNS-SD command failure was accepted"
fi
grep -F 'passive DNS-SD discovery failed' "$test_home/dnssd-fail-error" >/dev/null \
    || fail "DNS-SD command failure was not actionable"
[ "$(head -n 1 "$state")" = "$phone:41222" ] \
    || fail "DNS-SD command failure changed saved state"

reset_adb
if FUNK_TEST_REACHABLE_PORTS=41222 \
    FUNK_TEST_ADB_CONNECT_ERROR='connection refused' run_connect --print-serial \
    >"$test_home/connect-fail-output" 2>"$test_home/connect-fail-error"; then
    fail "ADB connect command failure was accepted"
fi
grep -F 'pairing was not changed' "$test_home/connect-fail-error" >/dev/null \
    || fail "ADB connect command failure was not actionable"
[ "$(head -n 1 "$state")" = "$phone:41222" ] \
    || fail "ADB connect command failure changed saved state"

# State serialization prevents concurrent launchers from overwriting identity.
/usr/bin/shlock -f "${state}.lock" -p "$$"
reset_adb
if run_connect --print-serial >"$test_home/lock-output" 2>"$test_home/lock-error"; then
    fail "concurrent state writer was accepted"
fi
grep -F 'another adb-wireless-connect process' "$test_home/lock-error" >/dev/null \
    || fail "state lock contention was not explained"
rm -f "${state}.lock"
[ ! -s "$log" ] || fail "state lock contention reached ADB"

# Tab-anchored parsing ignores unrelated serials containing spaces.
rm -f "$state"
reset_adb
FUNK_TEST_ADB_DEVICES="adb-$phone_id-random (2)._x._tcp\tdevice\n$phone:40222\tdevice" \
    run_connect --print-serial >"$test_home/spaced-serial"
[ "$(cat "$test_home/spaced-serial")" = "$phone:40222" ] \
    || fail "a serial containing spaces hid the Tailnet device"

# Qualified hosts work verbatim; unsafe hosts and ports remain rejected.
reset_adb
run_pair --host "$phone" 40111 >/dev/null
grep -Fx "$(printf 'pair\t%s:40111' "$phone")" "$log" >/dev/null \
    || fail "fully qualified Tailnet hostname override was not honored"
assert_isolated_adb

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
