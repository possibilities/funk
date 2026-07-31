#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
connect_helper="$root/bin/.local/bin/adb-wireless-connect"
ensure_helper="$root/bin/.local/bin/tailscale-ensure-online"
adb_fixture="$root/tests/fixtures/adb"
tailscale_fixture="$root/tests/fixtures/tailscale"
resolver_fixture="$root/tests/fixtures/dscacheutil"
dns_sd_fixture="$root/tests/fixtures/dns-sd"
nc_fixture="$root/tests/fixtures/nc"
scrcpy_fixture="$root/tests/fixtures/scrcpy"
jq_bin=$(command -v jq)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-scrcpy-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
state="$test_home/adb-target"
tailscale_state="$test_home/tailscale-state"
tailscale_log="$test_home/tailscale.log"
adb_log="$test_home/adb.log"
connected_file="$test_home/connected-target"
scrcpy_log="$test_home/scrcpy.log"
dnssd_term_log="$test_home/dnssd-term.log"
xdg_state="$test_home/custom-xdg-state"
disabled="$test_home/.local/state/funk/tailscale-auto-recovery.disabled"

phone=smolbird.example-tailnet.ts.net
phone_id=R5CT91TW4RP
tailnet_node=n123-test-smolbird
zone="adb-$phone_id-live._adb-tls-connect._tcp SRV 0 0 44129 Android.local. ; Replace with unicast FQDN of target host\nadb-$phone_id-live\\\\032(2)._adb-tls-connect._tcp SRV 0 0 41222 Android.local. ; Replace with unicast FQDN of target host"

fail() {
    printf 'scrcpy launcher test: %s\n' "$*" >&2
    exit 1
}

write_state() {
    printf '%s\nserial=%s\ntailnet_node=%s\n' \
        "$phone:39999" "$phone_id" "$tailnet_node" >"$state"
}

run_launcher() {
    HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
        ADB_USB=1 ADB_MDNS_AUTO_CONNECT=adb-tls-connect \
        ADB_SERVER_SOCKET=tcp:localhost:5037 \
        ADB_WIRELESS_CONNECT="$connect_helper" SCRCPY="$scrcpy_fixture" \
        ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" \
        TAILSCALE_ENSURE_ONLINE="$ensure_helper" JQ="$jq_bin" \
        DSCACHEUTIL="$resolver_fixture" DNS_SD="$dns_sd_fixture" NC="$nc_fixture" \
        SHLOCK=/usr/bin/shlock ADB_WIRELESS_DISCOVERY_SECONDS=1 \
        ADB_WIRELESS_STATE_FILE="$state" \
        FUNK_TEST_TAILSCALE_STATE_FILE="$tailscale_state" \
        FUNK_TEST_TAILSCALE_LOG="$tailscale_log" \
        FUNK_TEST_ADB_LOG="$adb_log" \
        FUNK_TEST_ADB_CONNECTED_FILE="$connected_file" \
        FUNK_TEST_DNSSD_ZONE="$zone" \
        FUNK_TEST_DNSSD_TERM_LOG="$dnssd_term_log" \
        FUNK_TEST_REACHABLE_PORTS=41222 \
        FUNK_TEST_ADB_IDENTITIES="$phone:41222\t$phone_id" \
        FUNK_TEST_SCRCPY_LOG="$scrcpy_log" \
        "$1"
}

wait_for_scrcpy() {
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$scrcpy_log" ] && return 0
        sleep 0.05
    done
    return 1
}

for launcher in \
    scrcpy.sh \
    scrcpy-no-audio.sh \
    scrcpy-flex.sh \
    scrcpy-no-audio-flex.sh; do
    write_state
    printf 'Stopped\n' >"$tailscale_state"
    rm -f "$connected_file" "$scrcpy_log"
    : >"$dnssd_term_log"
    : >"$tailscale_log"
    : >"$adb_log"

    run_launcher "$root/bin/.local/bin/raycast/$launcher" \
        >"$test_home/$launcher.out" 2>"$test_home/$launcher.err"
    [ ! -s "$test_home/$launcher.out" ] \
        || fail "$launcher wrote diagnostics to stdout"
    grep -F 'Tailscale is stopped' "$test_home/$launcher.err" >/dev/null \
        || fail "$launcher lost Tailscale recovery diagnostics"
    grep -F "connected to $phone:41222" "$test_home/$launcher.err" >/dev/null \
        || fail "$launcher lost ADB recovery diagnostics"
    wait_for_scrcpy || fail "$launcher did not execute scrcpy"
    grep -Fx terminated "$dnssd_term_log" >/dev/null \
        || fail "$launcher did not terminate the persistent DNS-SD browser"

    extra_args=
    case "$launcher" in
        scrcpy-no-audio.sh) extra_args='arg=--no-audio' ;;
        scrcpy-flex.sh)
            extra_args=$(printf '%s\n' 'arg=--new-display' 'arg=--flex-display')
            ;;
        scrcpy-no-audio-flex.sh)
            extra_args=$(
                printf '%s\n' \
                    'arg=--no-audio' 'arg=--new-display' 'arg=--flex-display'
            )
            ;;
    esac
    expected=$(
        printf '%s\n' \
            'server_socket=tcp:localhost:5038' \
            'mdns_auto_connect=0' \
            'usb=0' \
            'arg=-s' \
            "arg=$phone:41222" \
            'arg=--stay-awake' \
            'arg=--keep-active' \
            'arg=--keyboard=uhid'
        [ -z "$extra_args" ] || printf '%s\n' "$extra_args"
    )
    [ "$(cat "$scrcpy_log")" = "$expected" ] \
        || fail "$launcher passed a contaminated serial or wrong arguments to scrcpy"
done

# Exercise the supported install path and the files it actually places in HOME,
# then preserve one-click recovery if a newly added sibling has not yet been
# re-stowed. Both launches omit the source-path overrides used above.
installed_home="$test_home/installed-home"
installed_adb_env_log="$test_home/installed-adb-env.log"
mkdir -p "$installed_home"
HOME="$installed_home" "$root/bin/funk" stow bin
[ -L "$installed_home/.local/bin/adb-wireless-connect" ] \
    || fail "Funk install did not stow the connection helper"
[ -x "$installed_home/.local/bin/tailscale-ensure-online" ] \
    || fail "Funk install did not stow the recovery helper"
[ -L "$installed_home/.local/bin/raycast/scrcpy.sh" ] \
    || fail "Funk install did not stow the Raycast launcher"

run_installed_launcher() {
    (
        unset ADB_WIRELESS_CONNECT TAILSCALE_ENSURE_ONLINE
        HOME="$installed_home" XDG_STATE_HOME="$xdg_state" \
            PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            ADB_USB=1 ADB_MDNS_AUTO_CONNECT=adb-tls-connect \
            ADB_SERVER_SOCKET=tcp:localhost:5037 \
            ADB="$adb_fixture" TAILSCALE="$tailscale_fixture" JQ="$jq_bin" \
            DSCACHEUTIL="$resolver_fixture" DNS_SD="$dns_sd_fixture" \
            NC="$nc_fixture" SHLOCK=/usr/bin/shlock \
            ADB_WIRELESS_DISCOVERY_SECONDS=1 \
            ADB_WIRELESS_STATE_FILE="$state" \
            FUNK_TEST_TAILSCALE_STATE_FILE="$tailscale_state" \
            FUNK_TEST_TAILSCALE_LOG="$tailscale_log" \
            FUNK_TEST_ADB_LOG="$adb_log" \
            FUNK_TEST_ADB_ENV_LOG="$installed_adb_env_log" \
            FUNK_TEST_ADB_SIMULATE_MDNS_AUTOCONNECT=1 \
            FUNK_TEST_ADB_SIMULATE_USB_CONTENTION=1 \
            FUNK_TEST_ADB_CONNECTED_FILE="$connected_file" \
            FUNK_TEST_REACHABLE_PORTS=39999 \
            FUNK_TEST_ADB_IDENTITIES="$phone:39999\t$phone_id" \
            SCRCPY="$scrcpy_fixture" FUNK_TEST_SCRCPY_LOG="$scrcpy_log" \
            "$installed_home/.local/bin/raycast/scrcpy.sh"
    )
}

assert_installed_launch() {
    local label=$1

    [ ! -s "$test_home/$label.out" ] \
        || fail "$label launcher wrote diagnostics to stdout"
    wait_for_scrcpy || fail "$label launcher did not execute scrcpy"
    grep -Fx "arg=$phone:39999" "$scrcpy_log" >/dev/null \
        || fail "$label launcher did not select the saved phone"
    [ -s "$installed_adb_env_log" ] \
        || fail "$label ADB fixture did not record its environment"
    awk -F '\t' \
        '$2 != "auto=0" || $3 != "socket=tcp:localhost:5038" || $4 != "usb=0" {
            bad=1
        }
        END { exit bad }' "$installed_adb_env_log" \
        || fail "$label launcher escaped the isolated ADB server"
    if grep -Eq '^(auto-connect|usb-claim|pair)' "$adb_log"; then
        fail "$label launcher touched an unrelated device or paired"
    fi
    grep -Fx 'status --json' "$tailscale_log" >/dev/null \
        || fail "$label launcher did not find the recovery helper"
}

for installed_case in installed-fresh installed-without-helper-link; do
    if [ "$installed_case" = installed-without-helper-link ]; then
        rm "$installed_home/.local/bin/tailscale-ensure-online"
        [ ! -e "$installed_home/.local/bin/tailscale-ensure-online" ] \
            || fail "temporary recovery-helper link was not removed"
    fi
    write_state
    printf 'Running\n' >"$tailscale_state"
    rm -f "$connected_file" "$scrcpy_log"
    : >"$tailscale_log"
    : >"$adb_log"
    : >"$installed_adb_env_log"
    run_installed_launcher >"$test_home/$installed_case.out" \
        2>"$test_home/$installed_case.err"
    assert_installed_launch "$installed_case"
done

# An opt-out created with custom XDG state must also stop the Raycast path,
# whose helper uses the same canonical HOME-relative marker as launchd.
HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
    TAILSCALE="$tailscale_fixture" JQ="$jq_bin" \
    "$ensure_helper" --disable >/dev/null
[ -f "$disabled" ] || fail "interactive opt-out did not use the canonical path"
[ ! -e "$xdg_state/funk/tailscale-auto-recovery.disabled" ] \
    || fail "interactive opt-out followed XDG_STATE_HOME"

write_state
printf 'Stopped\n' >"$tailscale_state"
rm -f "$connected_file" "$scrcpy_log"
: >"$tailscale_log"
if run_launcher "$root/bin/.local/bin/raycast/scrcpy.sh" \
    >"$test_home/disabled.out" 2>"$test_home/disabled.err"; then
    fail "Raycast ignored the canonical deliberate-disconnect marker"
fi
grep -F 'automatic recovery is disabled' "$test_home/disabled.err" >/dev/null \
    || fail "Raycast did not report the deliberate-disconnect opt-out"
[ ! -e "$scrcpy_log" ] || fail "Raycast launched scrcpy while recovery was disabled"
if grep -q '^up$' "$tailscale_log"; then
    fail "Raycast reconnected Tailscale despite the opt-out"
fi
