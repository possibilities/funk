#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
script="$root/bin/.local/bin/home-awake"
fixtures="$root/tests/fixtures/home-awake"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-home-awake-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT

state_dir="$test_home/.local/state/funk"
config_file="$test_home/.config/funk/home-awake.conf"
screenlock_state_file="$state_dir/home-awake-screenlock"
caffeinate_plist="$state_dir/io.arthack.funk.caffeinate.plist"
mkdir -p "$state_dir" "$test_home/.config/funk"
cp "$root/launchd/io.arthack.funk.caffeinate.plist" "$caffeinate_plist"

log="$test_home/actions.log"
# Keep the sleep-transition notifications inside the fixture.
notifier_log="$test_home/notifier.log"
sleep_file="$test_home/sleep-disabled"
caffeinate_marker="$test_home/caffeinate-loaded"
arp_cold_file="$test_home/arp-warm"
helper_path=/usr/local/libexec/funk-home-awake
# Both addresses come from the range IEEE reserves for documentation, so no
# fixture ever carries a real piece of anyone's network.
home_router=00:00:5e:00:53:0a
other_router=00:00:5e:00:53:0b

fail() {
    printf 'home-awake test: %s\n' "$*" >&2
    exit 1
}

record_home_router() {
    printf 'router_label=%s\nrouter_mac=%s\n' "${2:-home}" "$1" >"$config_file"
}

run_ha() {
    HOME="$test_home" \
        FUNK_HOME_AWAKE_PATH="$fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_HOME_AWAKE_HELPER="$helper_path" \
        FUNK_TEST_HA_LOG="$log" \
        FUNK_TEST_HA_SLEEP_FILE="$sleep_file" \
        FUNK_TEST_HA_CAFFEINATE_FILE="$caffeinate_marker" \
        FUNK_TEST_HA_ARP_COLD_FILE="$arp_cold_file" \
        FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
        FUNK_TEST_NOTIFIER_LOG="$notifier_log" \
        "$script" "$@"
}

reset_state() {
    : >"$log"
    : >"$notifier_log"
    printf '0\n' >"$sleep_file"
    rm -f "$caffeinate_marker" "$screenlock_state_file"
    : >"$arp_cold_file"
    record_home_router "$home_router"
}

# Joining the home network changes sleep behavior without changing the user's
# password policy or accessing credentials.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "the home network did not start the idle-sleep job"
[ "$(cat "$sleep_file")" = 1 ] || fail "the home network on AC power did not suppress sleep"

# Converged state must be silent: no second bootstrap, no repeated privileged
# call, because the thirty-second agent runs this constantly.
: >"$log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
if grep -F 'sudo-stub' "$log" >/dev/null; then
    fail "an already-converged run repeated a privileged change"
fi
if grep -F 'launchctl-stub <bootstrap>' "$log" >/dev/null; then
    fail "an already-converged run bootstrapped the idle-sleep job again"
fi

# Unplugging restores normal sleep while leaving the password policy alone.
: >"$log"
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] || fail "unplugging kept the idle-sleep job"
[ "$(cat "$sleep_file")" = 0 ] || fail "unplugging kept sleep suppressed"
[ ! -e "$screenlock_state_file" ] \
    || fail "a sleep transition wrote a saved password policy"
grep -F 'launchctl-stub <bootout>' "$log" >/dev/null \
    || fail "the idle-sleep job was not booted out"

# The whole point of matching the router: a live cable in some other building
# is not home. This is the case a bare link-status check gets wrong.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_ROUTER_MAC="$other_router" run_ha
[ ! -e "$caffeinate_marker" ] || fail "a foreign wired network was treated as home"

# With no recorded router nothing is home, so a fresh account relaxes nothing.
reset_state
rm -f "$config_file"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] || fail "an unconfigured machine treated a cable as home"

# A router that answers but is unreachable by name must not match either.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_ROUTER_MAC='' run_ha
[ ! -e "$caffeinate_marker" ] || fail "an unanswered router was treated as home"

# Wi-Fi is excluded by interface, so the same router over the air is not enough.
reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] \
    || fail "the home router over Wi-Fi was treated as a wired connection"

# Hardware addresses are compared after normalization, so case and dropped
# leading zeros on either side still describe the same router.
reset_state
record_home_router '00:00:5E:00:53:0A'
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "an upper-case recorded address did not match"

reset_state
record_home_router '08:00:27:00:00:01'
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_ROUTER_MAC='8:0:27:0:0:1' run_ha
[ -e "$caffeinate_marker" ] \
    || fail "an address printed without leading zeros did not match"

# A cold neighbour cache is not the same answer as a different router: one probe
# repopulates it, and the match then succeeds.
reset_state
rm -f "$arp_cold_file"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "a cold neighbour cache was treated as a foreign network"
grep -F 'ping-stub' "$log" >/dev/null \
    || fail "a cold neighbour cache was not probed before being believed"

# Wired at home on battery still holds off idle sleep, but must not take the
# system-wide disablesleep flag that would also override the clamshell.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=0 run_ha
[ -e "$caffeinate_marker" ] || fail "battery power did not start the idle-sleep job"
[ "$(cat "$sleep_file")" = 0 ] || fail "battery power suppressed system sleep"

# A legacy saved delay is no longer owned by sleep management. Exercise the
# complete network/power lifecycle and assert at the OS-command boundary that
# neither password controls nor the keychain were accessed.
reset_state
printf '300\n' >"$screenlock_state_file"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=0 run_ha
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
run_ha --status >/dev/null
[ "$(cat "$screenlock_state_file")" = 300 ] \
    || fail "sleep transitions rewrote a legacy saved password policy"
if grep -E 'security-stub|sysadminctl-stub|<screenlock>' "$log" >/dev/null; then
    fail "sleep management accessed credentials or screen-lock controls"
fi

# Retired credential entry points must not prompt or access stored credentials.
for option in --set-password --authorize; do
    reset_state
    if run_ha "$option" >/dev/null 2>&1; then
        fail "a retired credential option was accepted: $option"
    fi
    if [ -s "$log" ]; then
        fail "a retired credential option performed an action: $option"
    fi
done

reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
status_output=$(FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha --status)
printf '%s\n' "$status_output" | grep -F 'network: wired to home on en5' >/dev/null \
    || fail "--status did not report the home network"
printf '%s\n' "$status_output" | grep -Fx 'caffeinate: yes' >/dev/null \
    || fail "--status did not report the idle-sleep job"
printf '%s\n' "$status_output" | grep -Fx 'sleepdisabled: yes' >/dev/null \
    || fail "--status did not report suppressed sleep"
printf '%s\n' "$status_output" | grep -F "$home_router" >/dev/null \
    || fail "--status did not report the recorded router"

away_output=$(FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha --status)
printf '%s\n' "$away_output" | grep -Fx 'network: away' >/dev/null \
    || fail "--status did not distinguish being away from home"

rm -f "$config_file"
unconfigured_output=$(FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha --status)
printf '%s\n' "$unconfigured_output" | grep -F 'not recorded' >/dev/null \
    || fail "--status did not say that no router has been recorded"

# --learn-network records whatever this Mac is currently wired to, and that
# recording is what subsequently counts as home.
reset_state
rm -f "$config_file"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_ROUTER_MAC="$other_router" \
    run_ha --learn-network >/dev/null
grep -Fx "router_mac=$other_router" "$config_file" >/dev/null \
    || fail "--learn-network did not record the connected router"
grep -Fx 'router_label=192.168.50.1' "$config_file" >/dev/null \
    || fail "--learn-network did not fall back to the router address as a name"

reset_state
rm -f "$config_file"
FUNK_TEST_HA_ETHERNET=1 run_ha --learn-network study >/dev/null
grep -Fx 'router_label=study' "$config_file" >/dev/null \
    || fail "--learn-network did not accept a name"

: >"$log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "the learned router was not treated as home"

# Learning requires being on the network, rather than recording nothing.
rm -f "$config_file"
if FUNK_TEST_HA_ETHERNET=0 run_ha --learn-network >/dev/null 2>&1; then
    fail "--learn-network succeeded with no wired interface"
fi
[ ! -e "$config_file" ] || fail "--learn-network wrote a configuration it could not fill"

if run_ha --nonsense >/dev/null 2>&1; then
    fail "an unknown option was accepted"
fi
# The root helper exposes only the two sleep operations. Argument guards run
# before the root check so these tests never need elevated access.
root_helper="$root/system/funk-home-awake"

# The helper always exits non-zero on these unprivileged runs, so its output is
# captured rather than piped: under pipefail a pipeline would report the
# helper's status instead of the grep's, and every check below would be
# answering the wrong question.
helper_says() {
    bash "$root_helper" "$@" 2>&1 || true
}

# Reaching the root check is how an argument reports that it survived
# validation, since that is the only other place these runs can stop.
reached_root_check() {
    printf '%s\n' "$1" | grep -q 'must run as root'
}

for rejected in off immediate 300; do
    if reached_root_check "$(helper_says screenlock "$rejected")"; then
        fail "the root helper accepted a retired screen-lock operation: $rejected"
    fi
done

for rejected in 2 '' 'x' '-a'; do
    if reached_root_check "$(helper_says sleep "$rejected")"; then
        fail "the root helper accepted sleep argument: $rejected"
    fi
done

for accepted in 0 1; do
    if ! reached_root_check "$(helper_says sleep "$accepted")"; then
        fail "the root helper rejected valid sleep argument: $accepted"
    fi
done

if reached_root_check "$(helper_says sleep 0 extra)"; then
    fail "the root helper accepted an extra argument"
fi
if reached_root_check "$(helper_says pmset)"; then
    fail "the root helper accepted an unknown action"
fi
printf '%s\n' "$(helper_says validate)" | grep -q 'is installable' \
    || fail "the root helper did not report itself installable"
