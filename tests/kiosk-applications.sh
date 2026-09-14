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
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' \
        "$bundle/Contents/Info.plist")" = AppIcon ] \
        || fail "bundle icon declaration was incorrect: $name"
    [ -s "$bundle/Contents/Resources/AppIcon.icns" ] \
        || fail "bundle icon was missing: $name"
    [ ! -e "$bundle/Contents/Resources/profile-name" ] \
        || fail "bundle retained a dedicated Chrome profile: $name"
    /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 \
        || fail "bundle signature was invalid: $name"

    "$bundle/Contents/MacOS/FunkKioskLauncher" --check \
        >"$test_dir/launch-check.out"
    expected=$(printf '%s\n' \
        "url=$url" \
        'window=chromeless' \
        'fullscreen=disabled' \
        'engine=WKWebView' \
        'edit=Undo|selector=undo:|key=z|modifiers=command|target=responder-chain' \
        'edit=Redo|selector=redo:|key=z|modifiers=command+shift|target=responder-chain' \
        'edit=Cut|selector=cut:|key=x|modifiers=command|target=responder-chain' \
        'edit=Copy|selector=copy:|key=c|modifiers=command|target=responder-chain' \
        'edit=Paste|selector=paste:|key=v|modifiers=command|target=responder-chain' \
        'edit=Select All|selector=selectAll:|key=a|modifiers=command|target=responder-chain')
    [ "$(cat "$test_dir/launch-check.out")" = "$expected" ] \
        || fail "bundle reported the wrong native window configuration: $name"
    /usr/bin/otool -L "$bundle/Contents/MacOS/FunkKioskLauncher" \
        | grep -F '/WebKit.framework/' >/dev/null \
        || fail "bundle did not link the system WebKit framework: $name"
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
