#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-find-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'kiosk find test: %s\n' "$*" >&2
    exit 1
}

/usr/bin/clang \
    -std=c11 -Os -Wall -Wextra -Werror -fobjc-arc \
    -mmacosx-version-min=13.0 \
    -I "$root/libexec" \
    -framework AppKit -framework Foundation -framework WebKit \
    "$root/tests/fixtures/kiosk-find-harness.m" \
    -o "$test_dir/kiosk-find-harness"

"$test_dir/kiosk-find-harness" >"$test_dir/output"
grep -Fx 'Kiosk native Find panel searches WKWebView content and dismisses successfully.' \
    "$test_dir/output" >/dev/null || fail "find harness did not report success"

printf 'Kiosk native Find behavior test passed.\n'
