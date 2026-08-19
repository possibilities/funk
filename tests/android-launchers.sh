#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/libexec/android-screen-copy"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-android-launchers-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'android-launchers test: %s\n' "$*" >&2
    exit 1
}

devices="$test_dir/devices"
adb_env="$test_dir/adb.env"
connect_log="$test_dir/connect.log"
scrcpy_log="$test_dir/scrcpy.log"
scrcpy_env="$test_dir/scrcpy.env"
test_home="$test_dir/home"
mkdir -p "$test_home"

run_helper() {
    rm -f "$connect_log" "$scrcpy_log" "$scrcpy_env"
    HOME="$test_home" \
        ADB="$root/tests/fixtures/adb-launcher" \
        ADB_WIRELESS_CONNECT="$root/tests/fixtures/android-wireless-connect" \
        SCRCPY="$root/tests/fixtures/scrcpy-launcher" \
        FUNK_TEST_ADB_DEVICES_FILE="$devices" \
        FUNK_TEST_ADB_ENV_LOG="$adb_env" \
        FUNK_TEST_CONNECT_LOG="$connect_log" \
        FUNK_TEST_SCRCPY_LOG="$scrcpy_log" \
        FUNK_TEST_SCRCPY_ENV_LOG="$scrcpy_env" \
        "$helper" "$1"
}

assert_args() {
    local serial=$1
    shift
    {
        printf '%s\n' -s "$serial" --stay-awake --keep-active --keyboard=uhid
        printf '%s\n' "$@"
    } >"$test_dir/expected.args"
    /usr/bin/cmp -s "$test_dir/expected.args" "$scrcpy_log" \
        || fail "scrcpy arguments did not match for $serial"
}

cat >"$devices" <<'EOF'
List of devices attached
USB123 device product:phone
wireless-phone:5555 device product:phone
EOF
run_helper audio
assert_args USB123 --audio-source=playback
[ ! -e "$connect_log" ] || fail "single USB phone called wireless recovery"
grep -Fx 'ADB_SERVER_SOCKET=<unset>' "$adb_env" >/dev/null \
    || fail "USB discovery inherited the wireless ADB server"
grep -Fx 'ADB_SERVER_SOCKET=<unset>' "$scrcpy_env" >/dev/null \
    || fail "USB scrcpy inherited the wireless ADB server"

cat >"$devices" <<'EOF'
List of devices attached
wireless-phone:5555 device product:phone
EOF
run_helper no-audio
assert_args wireless-phone:5555 --no-audio
grep -Fx 'ADB_SERVER_SOCKET=tcp:localhost:5038' "$connect_log" >/dev/null \
    || fail "wireless recovery did not use Funk's isolated ADB server"
grep -Fx 'ADB_USB=0' "$scrcpy_env" >/dev/null \
    || fail "wireless scrcpy did not retain USB isolation"

cat >"$devices" <<'EOF'
List of devices attached
USB-DENIED unauthorized
USB-OFFLINE offline
EOF
run_helper flex-audio
assert_args wireless-phone:5555 --audio-source=playback --new-display --flex-display
[ -e "$connect_log" ] || fail "unavailable USB entries suppressed wireless recovery"

cat >"$devices" <<'EOF'
List of devices attached
USB123 device
USB456 device
EOF
rm -f "$connect_log" "$scrcpy_log"
status=0
run_helper audio >"$test_dir/multiple.out" 2>"$test_dir/multiple.err" || status=$?
[ "$status" -ne 0 ] || fail "multiple USB phones were guessed instead of rejected"
[ ! -e "$connect_log" ] || fail "multiple USB phones fell back to wireless"
[ ! -e "$scrcpy_log" ] || fail "multiple USB phones started scrcpy"
grep -F 'more than one authorized USB device' "$test_dir/multiple.err" >/dev/null \
    || fail "multiple USB failure was not actionable"

cat >"$devices" <<'EOF'
List of devices attached
USB123 device
EOF
for mode in audio no-audio flex-audio flex-no-audio; do
    run_helper "$mode"
    case "$mode" in
        audio) assert_args USB123 --audio-source=playback ;;
        no-audio) assert_args USB123 --no-audio ;;
        flex-audio)
            assert_args USB123 --audio-source=playback --new-display --flex-display
            ;;
        flex-no-audio)
            assert_args USB123 --no-audio --new-display --flex-display
            ;;
    esac
done

applications="$test_home/Applications"
HOME="$test_home" FUNK_ANDROID_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-android-launchers >"$test_dir/install.out"

while IFS='|' read -r name identifier mode; do
    bundle="$applications/$name.app"
    [ -d "$bundle" ] || fail "bundle was not installed: $name"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$bundle/Contents/Info.plist")" = "$identifier" ] \
        || fail "bundle identifier was incorrect: $name"
    [ "$(cat "$bundle/Contents/Resources/launcher-mode")" = "$mode" ] \
        || fail "bundle mode was incorrect: $name"
    /usr/bin/cmp -s "$helper" "$bundle/Contents/Resources/android-screen-copy" \
        || fail "bundle did not embed the current helper: $name"
    /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 \
        || fail "bundle signature was invalid: $name"
done <<'EOF'
Android (audio)|com.arthack.funk.android.audio|audio
Android (no audio)|com.arthack.funk.android.noaudio|no-audio
Android flex (audio)|com.arthack.funk.android.flex.audio|flex-audio
Android flex (no audio)|com.arthack.funk.android.flex.noaudio|flex-no-audio
EOF

HOME="$test_home" FUNK_ANDROID_APPLICATIONS_DIR="$applications" \
    FUNK_SKIP_LAUNCHSERVICES_REGISTRATION=1 \
    "$root/bin/funk" install-android-launchers >"$test_dir/install-again.out"
[ "$(grep -c '^Already installed ' "$test_dir/install-again.out")" -eq 4 ] \
    || fail "repeated installation did not recognize all four bundles"

printf 'Android launcher application tests passed.\n'
