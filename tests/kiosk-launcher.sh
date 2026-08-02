#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
launcher="$root/bin/.local/bin/raycast/localhost-8789-kiosk.sh"
chrome_fixture="$root/tests/fixtures/chrome"
nc_fixture="$root/tests/fixtures/nc"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
chrome_log="$test_home/chrome.log"
profile="$test_home/.local/state/funk/chrome-kiosk"

fail() {
    printf 'kiosk launcher test: %s\n' "$*" >&2
    exit 1
}

run_launcher() {
    HOME="$test_home" NC="$nc_fixture" FUNK_CHROME="$chrome_fixture" \
        FUNK_TEST_CHROME_LOG="$chrome_log" \
        FUNK_TEST_REACHABLE_PORTS="$1" \
        "${2:-$launcher}"
}

wait_for_chrome() {
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$chrome_log" ] && return 0
        sleep 0.05
    done
    return 1
}

# The default target is reachable: Chrome runs in kiosk mode against its own
# profile, which is what keeps --kiosk from being dropped by a running Chrome.
rm -f "$chrome_log"
run_launcher 8789 >"$test_home/reachable.out" 2>"$test_home/reachable.err"
[ ! -s "$test_home/reachable.out" ] \
    || fail "launcher wrote diagnostics to stdout"
[ ! -s "$test_home/reachable.err" ] \
    || fail "launcher reported an error for a reachable port"
wait_for_chrome || fail "launcher did not execute Chrome"
expected=$(
    printf '%s\n' \
        "arg=--user-data-dir=$profile" \
        'arg=--no-first-run' \
        'arg=--no-default-browser-check' \
        'arg=--kiosk' \
        'arg=--app=http://localhost:8789/'
)
[ "$(cat "$chrome_log")" = "$expected" ] \
    || fail "launcher passed the wrong arguments to Chrome"
[ -d "$profile" ] || fail "launcher did not create its dedicated profile"

# Nothing listening: report it instead of opening an error page in kiosk mode,
# where the user cannot reach the address bar to recover.
rm -f "$chrome_log"
if run_launcher 9999 >"$test_home/closed.out" 2>"$test_home/closed.err"; then
    fail "launcher succeeded while nothing was listening"
fi
grep -F 'nothing is listening on localhost:8789' "$test_home/closed.err" \
    >/dev/null || fail "launcher did not report the closed port"
[ ! -e "$chrome_log" ] || fail "launcher started Chrome without a server"

# A missing Chrome is reported as itself rather than as a shell error.
rm -f "$chrome_log"
if HOME="$test_home" NC="$nc_fixture" \
    FUNK_CHROME="$test_home/absent-chrome" \
    FUNK_TEST_CHROME_LOG="$chrome_log" FUNK_TEST_REACHABLE_PORTS=8789 \
    "$launcher" >"$test_home/nochrome.out" 2>"$test_home/nochrome.err"; then
    fail "launcher succeeded without Chrome"
fi
grep -F 'Google Chrome is not installed' "$test_home/nochrome.err" >/dev/null \
    || fail "launcher did not report the missing browser"

# An overridden URL keeps the same one-click behavior, including its own port.
rm -f "$chrome_log"
HOME="$test_home" NC="$nc_fixture" FUNK_CHROME="$chrome_fixture" \
    FUNK_TEST_CHROME_LOG="$chrome_log" FUNK_TEST_REACHABLE_PORTS=3000 \
    FUNK_KIOSK_URL=http://127.0.0.1:3000/dash \
    "$launcher" >"$test_home/override.out" 2>"$test_home/override.err"
[ ! -s "$test_home/override.err" ] \
    || fail "overridden URL reported an error for a reachable port"
wait_for_chrome || fail "overridden URL did not execute Chrome"
grep -Fx 'arg=--app=http://127.0.0.1:3000/dash' "$chrome_log" >/dev/null \
    || fail "overridden URL did not reach Chrome"

# Exercise the supported install path and the file it actually places in HOME.
installed_home="$test_home/installed-home"
mkdir -p "$installed_home"
HOME="$installed_home" "$root/bin/funk" stow bin
installed_launcher="$installed_home/.local/bin/raycast/localhost-8789-kiosk.sh"
[ -L "$installed_launcher" ] \
    || fail "Funk install did not stow the kiosk launcher"
rm -f "$chrome_log"
HOME="$installed_home" NC="$nc_fixture" FUNK_CHROME="$chrome_fixture" \
    FUNK_TEST_CHROME_LOG="$chrome_log" FUNK_TEST_REACHABLE_PORTS=8789 \
    "$installed_launcher" \
    >"$test_home/installed.out" 2>"$test_home/installed.err"
[ ! -s "$test_home/installed.err" ] \
    || fail "installed launcher reported an error for a reachable port"
wait_for_chrome || fail "installed launcher did not execute Chrome"
grep -Fx "arg=--user-data-dir=$installed_home/.local/state/funk/chrome-kiosk" \
    "$chrome_log" >/dev/null \
    || fail "installed launcher did not use the current HOME for its profile"
