#!/bin/bash
set -euo pipefail
root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-window-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
/usr/bin/clang -std=c11 -Os -Wall -Wextra -Werror -fobjc-arc \
    -mmacosx-version-min=13.0 -I "$root/libexec" \
    -framework AppKit -framework Foundation \
    "$root/tests/fixtures/kiosk-window-harness.m" -o "$test_dir/kiosk-window-harness"
"$test_dir/kiosk-window-harness"
