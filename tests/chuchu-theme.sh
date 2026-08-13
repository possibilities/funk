#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
funk="$root/bin/funk"
# The production connection helper can route a Tailscale failure through
# funk-notify. Keep fixture failures inside the test instead of posting them to
# the operator's real Notification Center.
export FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-chuchu-theme-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
checkout="$test_home/src/chuchu"
theme_target="$checkout/android/app/src/main/assets/themes/Signal Room"
preferences="$test_home/chuchu_settings.xml"
remote_preferences="$test_home/remote-settings.xml"
adb_log="$test_home/adb.log"
gradle_log="$test_home/gradle.log"

fail() {
    printf 'chuchu-theme test: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$(dirname -- "$theme_target")"
ln -s "$root/tests/fixtures/gradlew-chuchu" "$checkout/android/gradlew"
cat >"$preferences" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <float name="terminal_font_size_sp" value="17.0" />
    <string name="theme_name">12-bit Rainbow</string>
    <string name="theme_mode">System</string>
</map>
EOF

run_helper() {
    FUNK_ROOT="$root" FUNK_CHUCHU_ROOT="$checkout" \
        ADB="$root/tests/fixtures/adb-chuchu" \
        ADB_WIRELESS_CONNECT="$root/tests/fixtures/adb-wireless-connect-chuchu" \
        APKANALYZER="$root/tests/fixtures/apkanalyzer-chuchu" \
        UNZIP="$root/tests/fixtures/unzip-chuchu" \
        FUNK_TEST_CHUCHU_PREFS="$preferences" \
        FUNK_TEST_CHUCHU_REMOTE_PREFS="$remote_preferences" \
        FUNK_TEST_CHUCHU_ADB_LOG="$adb_log" \
        FUNK_TEST_CHUCHU_GRADLE_LOG="$gradle_log" \
        FUNK_TEST_CHUCHU_BUILT_THEME="$theme_target" \
        "$funk" chuchu-theme
}

run_helper >"$test_home/run.out"
cmp -s "$root/assets/chuchu/Signal Room" "$theme_target" \
    || fail "canonical Signal Room asset was not synced into Chuchu"
[ "$(cat "$gradle_log")" = :app:assembleDebug ] \
    || fail "Chuchu debug APK was not built"
grep -F '<float name="terminal_font_size_sp" value="17.0"' "$preferences" \
    >/dev/null || fail "existing Lab preferences were replaced"
grep -F '<string name="theme_name">Signal Room</string>' "$preferences" \
    >/dev/null || fail "Signal Room was not selected"
grep -F '<string name="theme_mode">Dark</string>' "$preferences" \
    >/dev/null || fail "dark mode was not selected"
grep -F $'\tinstall\t-r\t' "$adb_log" >/dev/null \
    || fail "Lab APK was not reinstalled with data retention"
grep -F $'\tshell\tam\tstart\t-n\tcom.arthack.chuchu.lab/' "$adb_log" \
    >/dev/null || fail "Lab was not relaunched"
if grep -E $'\tcom\.jossephus\.chuchu($|\t)' "$adb_log" >/dev/null; then
    fail "official Chuchu package entered the ADB command path"
fi
if grep -F $'\tuninstall\t' "$adb_log" >/dev/null; then
    fail "installer used a destructive APK replacement"
fi
awk -F '\t' '$1 != "auto=0" || $2 != "socket=tcp:localhost:5038" ||
    $3 != "usb=0" { bad=1 } END { exit bad }' "$adb_log" \
    || fail "installer escaped Funk's isolated ADB server"
grep -F 'official package was untouched' "$test_home/run.out" >/dev/null \
    || fail "success output does not state the package boundary"

# The application-ID proof runs before ADB. A checkout accidentally producing
# the official package must stop without sending even one command to the phone.
: >"$adb_log"
if FUNK_TEST_CHUCHU_APPLICATION_ID=com.jossephus.chuchu \
    run_helper >"$test_home/rejected.out" 2>"$test_home/rejected.err"; then
    fail "installer accepted an APK for official Chuchu"
fi
[ ! -s "$adb_log" ] || fail "rejected official APK reached ADB"
grep -F 'refusing to install APK for com.jossephus.chuchu' \
    "$test_home/rejected.err" >/dev/null \
    || fail "official-package refusal was not actionable"

printf 'chuchu-theme test: ok\n'
