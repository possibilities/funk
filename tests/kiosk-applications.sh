#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-applications-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'kiosk applications test: %s\n' "$*" >&2
    exit 1
}

test_home="$test_dir/home"
applications="$test_home/Applications"
chrome_log="$test_dir/chrome.log"
mkdir -p "$test_home"

HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-kiosk-launchers >"$test_dir/install.out"

while IFS='|' read -r name identifier url; do
    bundle="$applications/$name.app"
    [ -d "$bundle" ] || fail "bundle was not installed: $name"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$bundle/Contents/Info.plist")" = "$identifier" ] \
        || fail "bundle identifier was incorrect: $name"
    [ "$(cat "$bundle/Contents/Resources/launcher-url")" = "$url" ] \
        || fail "bundle URL was incorrect: $name"
    [ ! -e "$bundle/Contents/Resources/profile-name" ] \
        || fail "bundle retained a dedicated Chrome profile: $name"
    /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 \
        || fail "bundle signature was invalid: $name"

    rm -f "$chrome_log"
    HOME="$test_home" NC="$root/tests/fixtures/nc" \
        FUNK_CHROME="$root/tests/fixtures/chrome" \
        FUNK_TEST_CHROME_LOG="$chrome_log" FUNK_TEST_REACHABLE_PORTS=443 \
        "$bundle/Contents/MacOS/FunkKioskLauncher" -psn_0_12345 \
        >"$test_dir/launch.out" 2>"$test_dir/launch.err"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$chrome_log" ] && break
        sleep 0.05
    done
    [ -s "$chrome_log" ] || fail "bundle did not start Chrome: $name"
    if grep -F 'arg=--user-data-dir=' "$chrome_log" >/dev/null; then
        fail "bundle started an isolated Chrome instance: $name"
    fi
    grep -Fx "arg=--app=$url" "$chrome_log" >/dev/null \
        || fail "bundle opened the wrong URL: $name"
    if grep -Fx 'arg=--kiosk' "$chrome_log" >/dev/null; then
        fail "bundle requested full-screen kiosk mode: $name"
    fi
done <<'EOF'
AgentVoice Transcripts|com.arthack.funk.kiosk.agentvoice|https://agentvoice.localhost/
AgentChats Transcripts|com.arthack.funk.kiosk.agentchats|https://agentchats.localhost/
EOF

HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-kiosk-launchers >"$test_dir/install-again.out"
[ "$(grep -c '^Already installed ' "$test_dir/install-again.out")" -eq 2 ] \
    || fail "repeated installation did not recognize both bundles"

# Recover a hard stop that happened after the installed bundle became backup.
recovery_transaction="$applications/.AgentChats Transcripts.app.funk-transaction"
mkdir -m 0700 "$recovery_transaction"
printf '%s\n' 'funk-kiosk-launcher-transaction-v1:com.arthack.funk.kiosk.agentchats' \
    >"$recovery_transaction/owner"
chmod 0600 "$recovery_transaction/owner"
mv "$applications/AgentChats Transcripts.app" "$recovery_transaction/backup.app"
HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-kiosk-launchers >"$test_dir/recover.out"
grep -F 'Recovered interrupted application backup' "$test_dir/recover.out" \
    >/dev/null || fail "installer did not report interrupted backup recovery"
[ -d "$applications/AgentChats Transcripts.app" ] \
    || fail "installer did not restore interrupted application backup"
[ ! -e "$recovery_transaction" ] \
    || fail "installer left the recovered transaction behind"

# A foreign bundle at an owned name is preserved rather than overwritten.
/usr/bin/plutil -replace CFBundleIdentifier -string com.example.foreign \
    "$applications/AgentVoice Transcripts.app/Contents/Info.plist"
if HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-kiosk-launchers \
    >"$test_dir/foreign.out" 2>"$test_dir/foreign.err"; then
    fail "installer replaced a foreign application"
fi
grep -F 'refusing to replace unrelated application' "$test_dir/foreign.err" \
    >/dev/null || fail "installer did not explain the foreign application"

printf 'Kiosk launcher application tests passed.\n'
