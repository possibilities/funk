#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-retirement-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'kiosk retirement test: %s\n' "$*" >&2
    exit 1
}

test_home="$test_dir/home"
applications="$test_home/Applications"
mkdir -p "$test_home"

write_plist() {
    local destination=$1 identifier=$2
    mkdir -p "$destination/Contents"
    cat >"$destination/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
</dict>
</plist>
EOF
}

make_bundle() {
    local destination=$1 identifier=$2 sentinel=${3:-owned}
    write_plist "$destination" "$identifier"
    printf '%s\n' "$sentinel" >"$destination/sentinel"
}

run_retire() {
    local output=$1
    shift
    HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
        "$root/bin/funk" retire-kiosk-launchers "$@" >"$output"
}

make_bundle "$applications/AgentVoice Transcripts.app" \
    com.arthack.funk.kiosk.agentvoice owned-voice
make_bundle "$applications/AgentVoice TEST Transcripts.app" \
    com.arthack.funk.kiosk.agentvoice-test owned-voice-test
make_bundle "$applications/AgentHUD.app" \
    com.arthack.funk.kiosk.agenthud owned-hud

# Native AgentVoice, a foreign app at an owned name after the first pass, and
# unrelated applications must survive exact-owner retirement.
make_bundle "$applications/AgentVoice.app" com.arthack.agentvoice native-agentvoice
make_bundle "$applications/Unrelated.app" com.example.unrelated unrelated-app
mkdir -p "$applications/Other App.app"
printf 'other\n' >"$applications/Other App.app/sentinel"

retired_chats="$applications/AgentChats Transcripts.app"
make_bundle "$retired_chats" com.arthack.funk.kiosk.agentchats retained-chats

webkit_voice="$test_home/Library/WebKit/com.arthack.funk.kiosk.agentvoice"
webkit_hud="$test_home/Library/WebKit/com.arthack.funk.kiosk.agenthud"
webkit_chats="$test_home/Library/WebKit/com.arthack.funk.kiosk.agentchats"
chrome_profile="$test_home/.local/state/funk/chrome-kiosk"
mkdir -p "$webkit_voice" "$webkit_hud" "$webkit_chats" "$chrome_profile"
printf 'voice-history\n' >"$webkit_voice/sentinel"
printf 'hud-history\n' >"$webkit_hud/sentinel"
printf 'chats-history\n' >"$webkit_chats/sentinel"
printf 'chrome-profile\n' >"$chrome_profile/sentinel"

owned_transaction="$applications/.AgentVoice TEST Transcripts.app.funk-transaction"
mkdir -m 0700 "$owned_transaction"
printf '%s\n' 'funk-kiosk-launcher-transaction-v1:com.arthack.funk.kiosk.agentvoice-test' \
    >"$owned_transaction/owner"
chmod 0600 "$owned_transaction/owner"
make_bundle "$owned_transaction/backup.app" \
    com.arthack.funk.kiosk.agentvoice-test transaction-backup
make_bundle "$owned_transaction/incoming.app" \
    com.arthack.funk.kiosk.agentvoice-test transaction-incoming

empty_transaction="$applications/.AgentHUD.app.funk-transaction"
mkdir -m 0700 "$empty_transaction"

run_retire "$test_dir/check.out" --check
grep -F "Would remove $applications/AgentVoice Transcripts.app" "$test_dir/check.out" \
    >/dev/null || fail "--check did not report the owned AgentVoice bundle"
grep -F "Would remove $applications/AgentHUD.app" "$test_dir/check.out" \
    >/dev/null || fail "--check did not report the owned AgentHUD bundle"
grep -F "Would remove application transaction $owned_transaction" "$test_dir/check.out" \
    >/dev/null || fail "--check did not report the owned transaction remnant"
[ -d "$applications/AgentVoice Transcripts.app" ] \
    || fail "--check removed an owned bundle"
[ -d "$owned_transaction" ] || fail "--check removed a transaction remnant"

run_retire "$test_dir/retire.out"
grep -F "Removed $applications/AgentVoice Transcripts.app" "$test_dir/retire.out" \
    >/dev/null || fail "owned AgentVoice wrapper was not removed"
grep -F "Removed $applications/AgentVoice TEST Transcripts.app" "$test_dir/retire.out" \
    >/dev/null || fail "owned AgentVoice TEST wrapper was not removed"
grep -F "Removed $applications/AgentHUD.app" "$test_dir/retire.out" \
    >/dev/null || fail "owned AgentHUD wrapper was not removed"
grep -F "Removed application transaction $owned_transaction" "$test_dir/retire.out" \
    >/dev/null || fail "owned transaction remnant was not removed"
grep -F "Removed incomplete application transaction $empty_transaction" \
    "$test_dir/retire.out" >/dev/null \
    || fail "empty transaction remnant was not removed"

[ ! -e "$applications/AgentVoice Transcripts.app" ] \
    || fail "owned AgentVoice wrapper remains"
[ ! -e "$applications/AgentVoice TEST Transcripts.app" ] \
    || fail "owned AgentVoice TEST wrapper remains"
[ ! -e "$applications/AgentHUD.app" ] \
    || fail "owned AgentHUD wrapper remains"
[ ! -e "$owned_transaction" ] || fail "owned transaction remnant remains"
[ ! -e "$empty_transaction" ] || fail "empty transaction remnant remains"
[ ! -e "$applications/.com.arthack.funk.kiosk-launchers.lock" ] \
    || fail "retirement left the installer lock behind"

[ "$(cat "$applications/AgentVoice.app/sentinel")" = native-agentvoice ] \
    || fail "native AgentVoice.app was changed"
[ "$(cat "$applications/Unrelated.app/sentinel")" = unrelated-app ] \
    || fail "unrelated application was changed"
[ "$(cat "$applications/Other App.app/sentinel")" = other ] \
    || fail "unrelated application directory was changed"
[ "$(cat "$retired_chats/sentinel")" = retained-chats ] \
    || fail "retired AgentChats bundle was changed"
[ "$(cat "$webkit_voice/sentinel")" = voice-history ] \
    || fail "AgentVoice WebKit data was changed"
[ "$(cat "$webkit_hud/sentinel")" = hud-history ] \
    || fail "AgentHUD WebKit data was changed"
[ "$(cat "$webkit_chats/sentinel")" = chats-history ] \
    || fail "AgentChats WebKit data was changed"
[ "$(cat "$chrome_profile/sentinel")" = chrome-profile ] \
    || fail "Chrome kiosk profile data was changed"

run_retire "$test_dir/retire-again.out"
[ "$(grep -c '^Already retired ' "$test_dir/retire-again.out")" -eq 3 ] \
    || fail "repeated retirement was not idempotent"
if grep -E '^(Removed|Would remove) ' "$test_dir/retire-again.out" >/dev/null; then
    fail "idempotent retirement reported a removal"
fi

make_bundle "$applications/AgentHUD.app" com.example.foreign foreign-hud
run_retire "$test_dir/foreign.out"
grep -F "Preserved unrelated application: $applications/AgentHUD.app" \
    "$test_dir/foreign.out" >/dev/null \
    || fail "foreign application at an owned name was not preserved"
[ "$(cat "$applications/AgentHUD.app/sentinel")" = foreign-hud ] \
    || fail "foreign application at an owned name was changed"

foreign_transaction="$applications/.AgentVoice Transcripts.app.funk-transaction"
mkdir -m 0700 "$foreign_transaction"
printf 'foreign-owner\n' >"$foreign_transaction/owner"
chmod 0600 "$foreign_transaction/owner"
if HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    "$root/bin/funk" retire-kiosk-launchers \
    >"$test_dir/foreign-transaction.out" 2>"$test_dir/foreign-transaction.err"; then
    fail "retirement removed a foreign transaction"
fi
grep -F 'refusing foreign application transaction' "$test_dir/foreign-transaction.err" \
    >/dev/null || fail "retirement did not explain the foreign transaction"
[ -f "$foreign_transaction/owner" ] \
    || fail "foreign transaction remnant was removed"
rm -rf "$foreign_transaction"

unexpected_transaction="$applications/.AgentVoice TEST Transcripts.app.funk-transaction"
mkdir -m 0700 "$unexpected_transaction"
printf '%s\n' 'funk-kiosk-launcher-transaction-v1:com.arthack.funk.kiosk.agentvoice-test' \
    >"$unexpected_transaction/owner"
printf 'surprise\n' >"$unexpected_transaction/extra"
if HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    "$root/bin/funk" retire-kiosk-launchers \
    >"$test_dir/unexpected.out" 2>"$test_dir/unexpected.err"; then
    fail "retirement deleted a transaction with unexpected artifacts"
fi
grep -F 'application transaction has an unexpected artifact' "$test_dir/unexpected.err" \
    >/dev/null || fail "retirement did not explain unexpected transaction artifacts"
[ -f "$unexpected_transaction/extra" ] \
    || fail "unexpected transaction artifact was removed"

printf 'Kiosk launcher retirement tests passed.\n'
