#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/funk-obs-camera-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

extension="$test_root/com.obsproject.obs-studio.mac-camera-extension.systemextension"
mkdir -p "$extension"

fixture="$test_root/systemextensionsctl"
cat >"$fixture" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = list ] \
    && [ "$2" = com.apple.system_extension.cmio ] || exit 64
printf 'enabled\tactive\tteamID\tbundleID (version)\tname\t[state]\n'
case "${FUNK_TEST_OBS_CAMERA_STATE:-enabled}" in
    enabled)
        printf '*\t*\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/1)\tOBS Virtual Camera\t[activated enabled]\n'
        ;;
    waiting)
        printf '\t*\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/1)\tOBS Virtual Camera\t[activated waiting for user]\n'
        ;;
    staged)
        printf '*\t*\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.1/1)\tOBS Virtual Camera\t[activated enabled]\n'
        printf '\t\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/1)\tOBS Virtual Camera\t[activated waiting to upgrade]\n'
        ;;
    absent)
        ;;
    *)
        exit 64
        ;;
esac
EOF
chmod +x "$fixture"

run_check() {
    FUNK_SYSTEMEXTENSIONSCTL_BIN="$fixture" \
        FUNK_OBS_CAMERA_EXTENSION="$extension" \
        FUNK_TEST_OBS_CAMERA_STATE="$1" \
        "$root/libexec/verify-obs-camera"
}

run_check enabled >"$test_root/enabled-output"
grep -F 'activated and enabled' "$test_root/enabled-output" >/dev/null

if run_check waiting >"$test_root/waiting-output" 2>&1; then
    printf 'verify-obs-camera test: waiting approval was accepted\n' >&2
    exit 1
fi
grep -F 'needs operator approval' "$test_root/waiting-output" >/dev/null
grep -F 'activated waiting for user' "$test_root/waiting-output" >/dev/null
grep -F 'System Settings > General > Login Items & Extensions > OBS > Media Extension' \
    "$test_root/waiting-output" >/dev/null

if run_check staged >"$test_root/staged-output" 2>&1; then
    printf 'verify-obs-camera test: pending extension upgrade was accepted\n' >&2
    exit 1
fi
grep -F 'activated enabled], [activated waiting to upgrade' \
    "$test_root/staged-output" >/dev/null

if run_check absent >"$test_root/absent-output" 2>&1; then
    printf 'verify-obs-camera test: absent extension registration was accepted\n' >&2
    exit 1
fi
grep -F 'is not registered with macOS' "$test_root/absent-output" >/dev/null

if FUNK_SYSTEMEXTENSIONSCTL_BIN="$fixture" \
    FUNK_OBS_CAMERA_EXTENSION="$test_root/missing.systemextension" \
    "$root/libexec/verify-obs-camera" >"$test_root/missing-output" 2>&1; then
    printf 'verify-obs-camera test: missing extension bundle was accepted\n' >&2
    exit 1
fi
grep -F 'camera extension is missing' "$test_root/missing-output" >/dev/null

printf 'OBS camera extension approval diagnosis passed.\n'
