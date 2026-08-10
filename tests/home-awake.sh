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
keychain_state_file="$state_dir/home-awake-keychain"
caffeinate_plist="$state_dir/com.arthack.funk.home-awake-caffeinate.plist"
mkdir -p "$state_dir" "$test_home/.config/funk"
cp "$root/launchd/com.arthack.funk.home-awake-caffeinate.plist" "$caffeinate_plist"

log="$test_home/actions.log"
# The keychain states below are announced through terminal-notifier, so the
# notifier is pinned at a stub: the fixture PATH alone would only make the
# assertions unreachable, and a PATH that ever grows the real binary would post
# this suite's fictional verdicts into the operator's Notification Center.
notifier_log="$test_home/notifier.log"
sleep_file="$test_home/sleep-disabled"
screenlock_file="$test_home/screenlock"
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
        FUNK_TEST_HA_SCREENLOCK_FILE="$screenlock_file" \
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
    printf '300\n' >"$screenlock_file"
    rm -f "$caffeinate_marker" "$screenlock_state_file" "$keychain_state_file"
    : >"$arp_cold_file"
    record_home_router "$home_router"
}

# Wired to the recorded router on AC power: awake, sleep suppressed, and the
# screen lock turned off after its previous delay is recorded.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ -e "$caffeinate_marker" ] || fail "the home network did not start the idle-sleep job"
[ "$(cat "$sleep_file")" = 1 ] || fail "the home network on AC power did not suppress sleep"
[ "$(cat "$screenlock_file")" = off ] \
    || fail "the home network did not turn the screen lock off"
[ "$(cat "$screenlock_state_file")" = 300 ] \
    || fail "the previous screen lock delay was not recorded"
grep -F "sudo-stub <$helper_path> <screenlock> <off>" "$log" >/dev/null \
    || fail "the screen lock change did not go through the root helper"

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

# Unplugging restores exactly the recorded delay.
: >"$log"
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] || fail "unplugging kept the idle-sleep job"
[ "$(cat "$sleep_file")" = 0 ] || fail "unplugging kept sleep suppressed"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "unplugging did not restore the previous screen lock delay"
[ ! -e "$screenlock_state_file" ] \
    || fail "the recorded screen lock delay outlived its restore"
grep -F 'launchctl-stub <bootout>' "$log" >/dev/null \
    || fail "the idle-sleep job was not booted out"

# The whole point of matching the router: a live cable in some other building
# is not home. This is the case a bare link-status check gets wrong.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_ROUTER_MAC="$other_router" run_ha
[ ! -e "$caffeinate_marker" ] || fail "a foreign wired network was treated as home"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "a foreign wired network turned the screen lock off"

# With no recorded router nothing is home, so a fresh account relaxes nothing.
reset_state
rm -f "$config_file"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ ! -e "$caffeinate_marker" ] || fail "an unconfigured machine treated a cable as home"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "an unconfigured machine turned the screen lock off"

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
grep -F '<-message> <Screen lock unmanaged: run home-awake --set-password>' \
    "$notifier_log" >/dev/null \
    || fail "a missing keychain item did not say how to store one"

# Nothing is stored, so this state re-checks itself on every tick -- which makes
# it the one where a banner per tick would actually reach the operator.
: >"$notifier_log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_PASSWORD_MISSING=1 \
    run_ha || true
[ ! -s "$notifier_log" ] \
    || fail "the standing missing-password notice was posted again on the next tick"

# A refused read is a different answer from a missing item, and it is the one
# that must not repeat: this agent runs every thirty seconds inside the GUI
# session, so a read nobody has approved is a keychain dialog every thirty
# seconds. One attempt, one notification, then nothing until --authorize.
reset_state
status=0
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_PASSWORD_DENIED=128 \
    run_ha || status=$?
[ "$status" -ne 0 ] || fail "a refused keychain read was reported as success"
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "the screen lock changed without an approved password"
[ ! -e "$screenlock_state_file" ] \
    || fail "a refused read recorded a delay the screen lock never left"
grep -F 'security-stub <find-generic-password>' "$log" >/dev/null \
    || fail "the first run after a refusal did not attempt the keychain read"
grep -F '<-message> <Screen lock unmanaged: run home-awake --authorize>' \
    "$notifier_log" >/dev/null \
    || fail "a refused keychain read did not say how to approve it"

: >"$log"
: >"$notifier_log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_PASSWORD_DENIED=128 \
    run_ha || true
if grep -F 'security-stub <find-generic-password>' "$log" >/dev/null; then
    fail "a refused keychain read was retried on the next tick"
fi
[ ! -s "$notifier_log" ] \
    || fail "the standing approval notice was posted again on the next tick"

# Which code a refusal carries is not something this suite can pin: a declined
# prompt, a locked keychain and an ACL that does not list the reader all report
# different ones. home-awake keys on the single code that means absence, so
# every other refusal has to reach the same held state.
for refusal in 1 36 51 128; do
    reset_state
    FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 \
        FUNK_TEST_HA_PASSWORD_DENIED="$refusal" run_ha || true
    [ "$(cat "$screenlock_file")" = 300 ] \
        || fail "refusal $refusal changed the screen lock"
    : >"$log"
    FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 \
        FUNK_TEST_HA_PASSWORD_DENIED="$refusal" run_ha || true
    if grep -F 'security-stub <find-generic-password>' "$log" >/dev/null; then
        fail "refusal $refusal was retried instead of held"
    fi
done

# --authorize is the way out of the held state, and the read it performs exists
# only to make the prompt happen here, so the password may not come back out.
reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 FUNK_TEST_HA_PASSWORD_DENIED=128 \
    run_ha || true
authorize_output=$(run_ha --authorize)
if printf '%s\n' "$authorize_output" | grep -F 'test-login-password' >/dev/null; then
    fail "--authorize printed the password it read"
fi
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
[ "$(cat "$screenlock_file")" = off ] \
    || fail "--authorize did not restore unattended screen-lock management"

# Approving what is not stored, and approving a read that is refused anyway, are
# both failures: neither may leave the agent believing it has consent.
reset_state
status=0
FUNK_TEST_HA_PASSWORD_MISSING=1 run_ha --authorize >/dev/null 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "--authorize approved a keychain item that is missing"
status=0
FUNK_TEST_HA_PASSWORD_DENIED=128 run_ha --authorize >/dev/null 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "--authorize reported a refused read as approved"
: >"$log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha || true
if grep -F 'security-stub <find-generic-password>' "$log" >/dev/null; then
    fail "a refusal declined at the terminal did not hold the unattended read"
fi
keychain_status=$(run_ha --status)
printf '%s\n' "$keychain_status" | grep -Fx 'screenlock password: unapproved' >/dev/null \
    || fail "--status did not report the recorded keychain verdict"

# Re-storing must replace the item's access list rather than merge into it, so
# the old copy is deleted first and the new one is added trusting nothing. -T ""
# is the only way to say that: security trusts the creating application, which
# here is security itself, unless the empty path revokes it.
reset_state
run_ha --set-password >/dev/null
grep -F 'security-stub <delete-generic-password>' "$log" >/dev/null \
    || fail "--set-password wrote over the existing item instead of replacing it"
delete_line=$(awk '/security-stub <delete-generic-password>/ { print NR; exit }' "$log")
add_line=$(awk '/security-stub <add-generic-password>/ { print NR; exit }' "$log")
[ -n "$add_line" ] || fail "--set-password did not store the item"
[ "$delete_line" -lt "$add_line" ] \
    || fail "--set-password stored the new item before removing the old one"
grep -F '<-T> <>' "$log" >/dev/null \
    || fail "--set-password stored an item that trusts its creating application"
if grep -F '<-T> </usr/bin/security>' "$log" >/dev/null; then
    fail "--set-password granted /usr/bin/security unattended access again"
fi
if grep -F '<-U>' "$log" >/dev/null; then
    fail "--set-password relied on an update to revoke an existing grant"
fi

# A first run has nothing to delete, and that is not a failure.
reset_state
FUNK_TEST_HA_DELETE_STATUS=44 run_ha --set-password >/dev/null \
    || fail "--set-password failed on the missing item a first run deletes"
grep -F 'security-stub <add-generic-password>' "$log" >/dev/null \
    || fail "--set-password did not store the item after a first-run delete"

# Any other delete failure means the old access list may still stand, so nothing
# is stored on top of it.
reset_state
status=0
FUNK_TEST_HA_DELETE_STATUS=1 run_ha --set-password >/dev/null 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "a failed delete was reported as a stored password"
if grep -F 'security-stub <add-generic-password>' "$log" >/dev/null; then
    fail "the item was re-added after its old copy could not be removed"
fi

# A freshly stored item trusts nothing, so the agent must wait to be told it may
# read rather than finding out through a dialog.
reset_state
run_ha --set-password >/dev/null
: >"$log"
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha || true
if grep -F 'security-stub <find-generic-password>' "$log" >/dev/null; then
    fail "--set-password left the agent reading an item nobody had approved"
fi
[ "$(cat "$screenlock_file")" = 300 ] \
    || fail "an unapproved item still turned the screen lock off"

# A restore with no recorded delay must re-lock immediately rather than guess.
reset_state
printf 'off\n' >"$screenlock_file"
FUNK_TEST_HA_ETHERNET=0 FUNK_TEST_HA_AC=1 run_ha
[ "$(cat "$screenlock_file")" = immediate ] \
    || fail "an unrecorded screen lock did not fall back to immediate"

reset_state
FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha
status_output=$(FUNK_TEST_HA_ETHERNET=1 FUNK_TEST_HA_AC=1 run_ha --status)
printf '%s\n' "$status_output" | grep -F 'network: wired to home on en5' >/dev/null \
    || fail "--status did not report the home network"
printf '%s\n' "$status_output" | grep -Fx 'caffeinate: yes' >/dev/null \
    || fail "--status did not report the idle-sleep job"
printf '%s\n' "$status_output" | grep -Fx 'sleepdisabled: yes' >/dev/null \
    || fail "--status did not report suppressed sleep"
printf '%s\n' "$status_output" | grep -Fx 'screenlock: off' >/dev/null \
    || fail "--status did not report the screen lock"
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
# The root helper is the whole privileged surface, and sudoers has to accept a
# numeric argument for the delay form, so these guards are the real bound on
# what the unattended agent can ask root to do. They run before the root check
# precisely so they can be asserted here.
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

for rejected in '999999' 'off; rm -rf /' '-1' 'abc' '0' '1e3' ' 300' 'off extra'; do
    if reached_root_check "$(helper_says screenlock "$rejected")"; then
        fail "the root helper accepted screen lock specification: $rejected"
    fi
done

for rejected in 2 '' 'x' '-a'; do
    if reached_root_check "$(helper_says sleep "$rejected")"; then
        fail "the root helper accepted sleep argument: $rejected"
    fi
done

for accepted in off immediate 1 300 86400; do
    if ! reached_root_check "$(helper_says screenlock "$accepted")"; then
        fail "the root helper rejected valid screen lock specification: $accepted"
    fi
done

for accepted in 0 1; do
    if ! reached_root_check "$(helper_says sleep "$accepted")"; then
        fail "the root helper rejected valid sleep argument: $accepted"
    fi
done

if reached_root_check "$(helper_says screenlock off extra)"; then
    fail "the root helper accepted an extra argument"
fi
if reached_root_check "$(helper_says pmset)"; then
    fail "the root helper accepted an unknown action"
fi
printf '%s\n' "$(helper_says validate)" | grep -q 'is installable' \
    || fail "the root helper did not report itself installable"
