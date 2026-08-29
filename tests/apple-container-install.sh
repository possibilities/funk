#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/libexec/install-apple-container"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/funk-apple-container-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'apple-container install test: %s\n' "$*" >&2
    exit 1
}

fixtures="$test_root/fixtures"
mkdir -p "$fixtures"

cat >"$fixtures/pkgutil" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$1" in
    --pkg-info)
        [ -f "$FUNK_TEST_RECEIPT" ] || exit 1
        printf 'package-id: com.apple.container-installer\n'
        if [ "$(cat "$FUNK_TEST_RECEIPT")" != malformed ]; then
            printf 'version: %s\n' "$(cat "$FUNK_TEST_RECEIPT")"
        fi
        ;;
    --check-signature)
        [ "${FUNK_TEST_SIGNATURE:-good}" = good ] || exit 1
        printf 'Status: signed by a certificate trusted by Mac OS X\n'
        printf '1. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)\n'
        ;;
    *) exit 64 ;;
esac
EOF

cat >"$fixtures/codesign" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${FUNK_TEST_TEAM:-good}" = good ] || {
    [ "$1" != --verify ] && printf 'TeamIdentifier=FOREIGN\n' >&2
    exit 1
}
if [ "$1" = --verify ]; then
    exit 0
fi
printf 'TeamIdentifier=UPBK2H6LZM\n' >&2
EOF

cat >"$fixtures/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = --output ]; then
        output=$2
        shift 2
    else
        shift
    fi
done
[ -n "$output" ] || exit 64
printf 'signed package fixture\n' >"$output"
EOF

cat >"$fixtures/shasum" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${FUNK_TEST_CHECKSUM:-good}" = good ]; then
    printf '6603d430d20f6f799215f729a4350bcf79cba371d96cb9d66fcefae46f05472f  %s\n' "${@: -1}"
else
    printf 'badbadbad  %s\n' "${@: -1}"
fi
EOF

cat >"$fixtures/container-template" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$1 $2" = 'system status' ] || exit 64
printf 'apiserver is not running and not registered with launchd\n'
EOF

cat >"$fixtures/installer" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '0.8.0\n' >"$FUNK_TEST_RECEIPT"
cp "$FUNK_TEST_CONTAINER_TEMPLATE" "$FUNK_CONTAINER_BIN"
chmod +x "$FUNK_CONTAINER_BIN"
printf 'installer\n' >>"$FUNK_TEST_INSTALL_LOG"
EOF

cat >"$fixtures/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'sudo\n' >>"$FUNK_TEST_INSTALL_LOG"
exec "$@"
EOF
chmod +x "$fixtures"/*

run_case() {
    local case_root=$1
    shift
    mkdir -p "$case_root"
    FUNK_TEST_RECEIPT="$case_root/receipt" \
    FUNK_TEST_INSTALL_LOG="$case_root/install.log" \
    FUNK_TEST_CONTAINER_TEMPLATE="$fixtures/container-template" \
    FUNK_CONTAINER_BIN="$case_root/container" \
    FUNK_CONTAINER_PKGUTIL_BIN="$fixtures/pkgutil" \
    FUNK_CONTAINER_CODESIGN_BIN="$fixtures/codesign" \
    FUNK_CONTAINER_CURL_BIN="$fixtures/curl" \
    FUNK_CONTAINER_SHASUM_BIN="$fixtures/shasum" \
    FUNK_CONTAINER_SUDO_BIN="$fixtures/sudo" \
    FUNK_CONTAINER_INSTALLER_BIN="$fixtures/installer" \
    TMPDIR="$case_root" \
        "$@" "$helper"
}

# Missing state installs once, verifies the result, and repeated convergence is
# a no-op that leaves the stopped service unchanged.
success_root="$test_root/success"
run_case "$success_root" env >/dev/null
[ "$(cat "$success_root/receipt")" = 0.8.0 ] || fail "successful install omitted its receipt"
[ "$(grep -c '^installer$' "$success_root/install.log")" -eq 1 ] \
    || fail "successful install did not invoke the package installer exactly once"
run_case "$success_root" env >/dev/null
[ "$(grep -c '^installer$' "$success_root/install.log")" -eq 1 ] \
    || fail "repeated convergence reinstalled Apple container"

# An already-installed newer package is valid install-only convergence, not an
# automatic downgrade to the helper's acquisition version.
installed_root="$test_root/installed"
mkdir -p "$installed_root"
printf '0.9.0\n' >"$installed_root/receipt"
cp "$fixtures/container-template" "$installed_root/container"
chmod +x "$installed_root/container"
run_case "$installed_root" env >/dev/null
[ ! -e "$installed_root/install.log" ] || fail "installed package was replaced"

malformed_root="$test_root/malformed"
mkdir -p "$malformed_root"
printf 'malformed\n' >"$malformed_root/receipt"
cp "$fixtures/container-template" "$malformed_root/container"
chmod +x "$malformed_root/container"
if run_case "$malformed_root" env >/dev/null 2>&1; then
    fail "malformed package receipt was accepted"
fi

checksum_root="$test_root/checksum"
if run_case "$checksum_root" env FUNK_TEST_CHECKSUM=bad >/dev/null 2>&1; then
    fail "bad package checksum was accepted"
fi
[ ! -e "$checksum_root/install.log" ] || fail "bad checksum reached the installer"

signature_root="$test_root/signature"
if run_case "$signature_root" env FUNK_TEST_SIGNATURE=bad >/dev/null 2>&1; then
    fail "bad package signature was accepted"
fi
[ ! -e "$signature_root/install.log" ] || fail "bad signature reached the installer"

foreign_root="$test_root/foreign"
mkdir -p "$foreign_root"
cp "$fixtures/container-template" "$foreign_root/container"
chmod +x "$foreign_root/container"
if run_case "$foreign_root" env >/dev/null 2>&1; then
    fail "command without a package receipt was overwritten"
fi
[ ! -e "$foreign_root/install.log" ] || fail "foreign command reached the installer"

foreign_signature_root="$test_root/foreign-signature"
mkdir -p "$foreign_signature_root"
printf '0.8.0\n' >"$foreign_signature_root/receipt"
cp "$fixtures/container-template" "$foreign_signature_root/container"
chmod +x "$foreign_signature_root/container"
if run_case "$foreign_signature_root" env FUNK_TEST_TEAM=foreign >/dev/null 2>&1; then
    fail "foreign installed binary was accepted"
fi
[ ! -e "$foreign_signature_root/install.log" ] || fail "foreign binary was replaced"

printf 'apple-container install tests passed\n'
