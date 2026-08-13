#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-ghostty-terminfo-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
resources="$test_home/Ghostty.app/Contents/Resources"
target="$test_home/home/.terminfo"

fail() {
    printf 'ghostty-terminfo test: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$resources/terminfo/67" "$resources/terminfo/78" "$target/78"
printf 'ghostty alias entry\n' >"$resources/terminfo/67/ghostty"
printf 'xterm-ghostty entry with extended capabilities\n' \
    >"$resources/terminfo/78/xterm-ghostty"
printf 'unrelated entry\n' >"$target/78/xterm-unrelated"

run_helper() {
    HOME="$test_home/home" \
        FUNK_GHOSTTY_RESOURCES="$resources" \
        "$root/bin/funk" install-ghostty-terminfo
}

run_helper >"$test_home/first.out"
cmp -s "$resources/terminfo/67/ghostty" "$target/67/ghostty" \
    || fail "ghostty alias entry was not installed verbatim"
cmp -s "$resources/terminfo/78/xterm-ghostty" "$target/78/xterm-ghostty" \
    || fail "xterm-ghostty entry was not installed verbatim"
[ "$(cat "$target/78/xterm-unrelated")" = 'unrelated entry' ] \
    || fail "installer changed an unrelated terminfo entry"

run_helper >"$test_home/second.out"
grep -F 'Ghostty terminfo is current' "$test_home/second.out" >/dev/null \
    || fail "a converged second run was not reported as current"

printf 'stale\n' >"$target/78/xterm-ghostty"
run_helper >/dev/null
cmp -s "$resources/terminfo/78/xterm-ghostty" "$target/78/xterm-ghostty" \
    || fail "a stale entry was not refreshed"

rm "$resources/terminfo/78/xterm-ghostty"
if run_helper >"$test_home/missing.out" 2>"$test_home/missing.err"; then
    fail "installer accepted an incomplete Ghostty terminfo database"
fi
grep -F 'Ghostty terminfo entry is missing' "$test_home/missing.err" >/dev/null \
    || fail "missing-entry failure was not actionable"
cmp -s "$resources/terminfo/67/ghostty" "$target/67/ghostty" \
    || fail "a failed run changed an already installed entry"

printf 'ghostty-terminfo test: ok\n'
