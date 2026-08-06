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
caffeinate_plist="$state_dir/com.arthack.funk.home-awake-caffeinate.plist"
mkdir -p "$state_dir"
cp "$root/launchd/com.arthack.funk.home-awake-caffeinate.plist" "$caffeinate_plist"

log="$test_home/actions.log"
sleep_file="$test_home/sleep-disabled"
screenlock_file="$test_home/screenlock"
caffeinate_marker="$test_home/caffeinate-loaded"
helper_path=/usr/local/libexec/funk-home-awake
trusted_profile=210e869a3589eca555c48a923f93d34cbb9ff957e163c9a4d7c9ba8fb18c14b2

fail() {
    printf 'home-awake test: %s\n' "$*" >&2
    exit 1
}

run_ha() {
    HOME="$test_home" \
        FUNK_HOME_AWAKE_PATH="$fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_HOME_AWAKE_HELPER="$helper_path" \
        FUNK_TEST_HA_LOG="$log" \
        FUNK_TEST_HA_SLEEP_FILE="$sleep_file" \
        FUNK_TEST_HA_SCREENLOCK_FILE="$screenlock_file" \
        FUNK_TEST_HA_CAFFEINATE_FILE="$caffeinate_marker" \
        "$script" "$@"
}

reset_state() {
    : >"$log"
    printf '0\n' >"$sleep_file"
    printf '300\n' >"$screenlock_file"
    rm -f "$caffeinate_marker" "$screenlock_state_file"
}

# Ethernet on AC power: awake, sleep suppressed, and the screen lock turned off
# after its previous delay is recorded.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "Ethernet did not start the idle-sleep job"
[ "$(cat "$sleep_file")" = 1 ] || fail "Ethernet on AC power did not suppress sleep"
[ "$(cat "$screenlock_file")" = off ] || fail "Ethernet did not turn the screen lock off"
[ "$(cat "$screenlock_state_file")" = 300 ] \
    || fail "the previous screen lock delay was not recorded"
grep -F "sudo-stub <$helper_path> <screenlock> <off>" "$log" >/dev/null \
    || fail "the screen lock change did not go through the root helper"
grep -F 'launchctl-stub <bootstrap>' "$log" >/dev/null \
    || fail "the idle-sleep job was not bootstrapped"

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

# Leaving the trusted network restores exactly the recorded delay.
: >"$log"
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] || fail "leaving the network kept the idle-sleep job"
[ "$(cat "$sleep_file")" = 0 ] || fail "leaving the network kept sleep suppressed"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "leaving the network did not restore the previous screen lock delay"
[ ! -e "$screenlock_state_file" ] \
    || fail "the recorded screen lock delay outlived its restore"
grep -F 'launchctl-stub <bootout>' "$log" >/dev/null \
    || fail "the idle-sleep job was not booted out"

# An untrusted network is left completely alone.
reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 \
    FUNK_TEST_HA_WIFI_PROFILE=0000000000000000000000000000000000000000000000000000000000000000 \
    run_ha
[ ! -e "$caffeinate_marker" ] || fail "an untrusted Wi-Fi network started the idle-sleep job"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "an untrusted Wi-Fi network changed the screen lock"

# The trusted Wi-Fi network qualifies only while plugged in.
reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 \
    FUNK_TEST_HA_WIFI_PROFILE="$trusted_profile" run_ha
[ -e "$caffeinate_marker" ] || fail "trusted Wi-Fi on AC power did not stay awake"
[ "$(cat "$screenlock_file")" = off ] \
    || fail "trusted Wi-Fi on AC power did not turn the screen lock off"

reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=0 \
    FUNK_TEST_HA_WIFI_PROFILE="$trusted_profile" run_ha
[ ! -e "$caffeinate_marker" ] || fail "trusted Wi-Fi on battery stayed awake"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "trusted Wi-Fi on battery changed the screen lock"

# Ethernet on battery still holds off idle sleep, but must not take the
# system-wide disablesleep flag that would also override the clamshell.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=0 run_ha
[ -e "$caffeinate_marker" ] || fail "Ethernet on battery did not start the idle-sleep job"
[ "$(cat "$sleep_file")" = 0 ] \
    || fail "Ethernet on battery suppressed system sleep"

# Without the stored password the screen lock is left untouched, the run
# reports failure, and no stale delay is recorded for a later restore.
reset_state
status=0
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_PASSWORD_MISSING=1 \
    run_ha || status=$?
[ "$status" -ne 0 ] || fail "a missing keychain password was reported as success"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "the screen lock changed without the authorizing password"
[ ! -e "$screenlock_state_file" ] \
    || fail "a delay was recorded even though the screen lock never changed"
[ "$(cat "$sleep_file")" = 1 ] \
    || fail "a missing password prevented the unrelated sleep change"

# A restore with no recorded delay must re-lock immediately rather than guess.
reset_state
printf 'off\n' >"$screenlock_file"
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ "$(cat "$screenlock_file")" = immediate ] \
    || fail "an unrecorded screen lock did not fall back to immediate"

reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
status_output=$(FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha --status)
printf '%s\n' "$status_output" | grep -Fx 'network: Ethernet' >/dev/null \
    || fail "--status did not report the trusted network"
printf '%s\n' "$status_output" | grep -Fx 'caffeinate: yes' >/dev/null \
    || fail "--status did not report the idle-sleep job"
printf '%s\n' "$status_output" | grep -Fx 'sleepdisabled: yes' >/dev/null \
    || fail "--status did not report suppressed sleep"
printf '%s\n' "$status_output" | grep -Fx 'screenlock: off' >/dev/null \
    || fail "--status did not report the screen lock"
printf '%s\n' "$status_output" | grep -F "$trusted_profile" >/dev/null \
    || fail "--status did not report the trusted Wi-Fi network"

# --learn-network replaces the shipped default, and the recorded network is the
# one that then counts as trusted.
reset_state
learned=1111111111111111111111111111111111111111111111111111111111111111
FUNK_TEST_HA_WIFI_PROFILE="$learned" FUNK_TEST_HA_WIFI_LABEL=somewhere-else \
    run_ha --learn-network >/dev/null
grep -Fx "wifi_profile_id=$learned" "$config_file" >/dev/null \
    || fail "--learn-network did not record the joined network"
grep -Fx 'wifi_label=somewhere-else' "$config_file" >/dev/null \
    || fail "--learn-network did not record the network name"

reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_WIFI_PROFILE="$learned" run_ha
[ -e "$caffeinate_marker" ] || fail "the learned network was not treated as trusted"

reset_state
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 \
    FUNK_TEST_HA_WIFI_PROFILE="$trusted_profile" run_ha
[ ! -e "$caffeinate_marker" ] \
    || fail "the superseded default network was still treated as trusted"

if run_ha --nonsense >/dev/null 2>&1; then
    fail "an unknown option was accepted"
fi
