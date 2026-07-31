#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/bin/.local/bin/tailscale-ensure-online"
tailscale_fixture="$root/tests/fixtures/tailscale"
jq_bin=$(command -v jq)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-tailscale-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/tailscale.log"
state="$test_home/tailscale-state"
disabled="$test_home/.local/state/funk/tailscale-auto-recovery.disabled"
xdg_state="$test_home/custom-xdg-state"

fail() {
    printf 'tailscale-online test: %s\n' "$*" >&2
    exit 1
}

run_ensure() {
    HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
        TAILSCALE="$tailscale_fixture" JQ="$jq_bin" \
        FUNK_TEST_TAILSCALE_LOG="$log" \
        "$helper" "$@"
}

: >"$log"
run_ensure >"$test_home/running-output" 2>"$test_home/running-error"
[ ! -s "$test_home/running-output" ] && [ ! -s "$test_home/running-error" ] \
    || fail "already-running Tailscale was not a silent no-op"
[ "$(grep -c '^status --json$' "$log")" -eq 1 ] \
    || fail "already-running check did not read status exactly once"
if grep -Eq '^(up|wait)' "$log"; then
    fail "already-running check invoked a recovery command"
fi

printf 'Stopped\n' >"$state"
: >"$log"
FUNK_TEST_TAILSCALE_STATE_FILE="$state" run_ensure \
    >"$test_home/stopped-output" 2>"$test_home/stopped-error"
[ "$(cat "$state")" = Running ] || fail "Stopped backend was not restored"
grep -Fx up "$log" >/dev/null || fail "Stopped backend did not run tailscale up"
grep -Fx 'wait --timeout=15s' "$log" >/dev/null \
    || fail "Stopped recovery did not wait for bounded readiness"
grep -F 'reconnecting with saved settings' "$test_home/stopped-error" >/dev/null \
    || fail "Stopped recovery did not explain its state change"

: >"$log"
if FUNK_TEST_TAILSCALE_STATE=NeedsLogin run_ensure \
    >"$test_home/login-output" 2>"$test_home/login-error"; then
    fail "NeedsLogin was treated as recoverable"
fi
grep -F 'needs login' "$test_home/login-error" >/dev/null \
    || fail "NeedsLogin did not provide sign-in guidance"
if grep -q '^up$' "$log"; then
    fail "NeedsLogin invoked tailscale up"
fi

if FUNK_TEST_TAILSCALE_STATE=Starting run_ensure \
    >"$test_home/unsupported-output" 2>"$test_home/unsupported-error"; then
    fail "unsupported Tailscale state was changed automatically"
fi
grep -F 'unsupported state Starting' "$test_home/unsupported-error" >/dev/null \
    || fail "unsupported Tailscale state was not actionable"

if FUNK_TEST_TAILSCALE_STATUS_FAIL=1 run_ensure \
    >"$test_home/daemon-output" 2>"$test_home/daemon-error"; then
    fail "failed daemon status was accepted"
fi
grep -F 'could not reach a valid daemon' "$test_home/daemon-error" >/dev/null \
    || fail "failed daemon status was not distinguished"

if FUNK_TEST_TAILSCALE_INVALID_JSON=1 run_ensure \
    >"$test_home/json-output" 2>"$test_home/json-error"; then
    fail "invalid daemon JSON was accepted"
fi
grep -F 'returned invalid status' "$test_home/json-error" >/dev/null \
    || fail "invalid daemon JSON was not distinguished"

if FUNK_TEST_TAILSCALE_SELF_ONLINE=0 run_ensure \
    >"$test_home/self-output" 2>"$test_home/self-error"; then
    fail "Running-but-offline local node was accepted"
fi
grep -F 'local Tailscale node is Running but offline' "$test_home/self-error" >/dev/null \
    || fail "local offline state was not actionable"

if FUNK_TEST_TAILSCALE_PEER_STATE=Offline run_ensure --peer smolbird \
    >"$test_home/peer-output" 2>"$test_home/peer-error"; then
    fail "offline phone peer was accepted"
fi
grep -F 'peer smolbird.example-tailnet.ts.net is offline' "$test_home/peer-error" >/dev/null \
    || fail "offline phone peer was not distinguished"

if FUNK_TEST_TAILSCALE_PEER_STATE=Missing run_ensure --peer smolbird \
    >"$test_home/missing-output" 2>"$test_home/missing-error"; then
    fail "missing phone peer was accepted"
fi
grep -F 'peer smolbird.example-tailnet.ts.net is missing' "$test_home/missing-error" >/dev/null \
    || fail "missing phone peer was not distinguished"

peer_id=$(run_ensure --peer smolbird --print-peer-id)
[ "$peer_id" = n123-test-smolbird ] \
    || fail "online peer identity was not reported for state pinning"

printf 'Stopped\n' >"$state"
if FUNK_TEST_TAILSCALE_STATE_FILE="$state" FUNK_TEST_TAILSCALE_UP_FAIL=1 \
    run_ensure >"$test_home/up-output" 2>"$test_home/up-error"; then
    fail "tailscale up failure was accepted"
fi
grep -F 'tailscale up failed' "$test_home/up-error" >/dev/null \
    || fail "tailscale up failure was not actionable"

printf 'Stopped\n' >"$state"
if FUNK_TEST_TAILSCALE_STATE_FILE="$state" FUNK_TEST_TAILSCALE_WAIT_FAIL=1 \
    run_ensure >"$test_home/wait-output" 2>"$test_home/wait-error"; then
    fail "tailscale wait failure was accepted"
fi
grep -F 'readiness check failed' "$test_home/wait-error" >/dev/null \
    || fail "tailscale wait failure was not actionable"

run_ensure --disable >"$test_home/disable-output"
[ -f "$disabled" ] || fail "intentional-disconnect opt-out was not persisted"
[ ! -e "$xdg_state/funk/tailscale-auto-recovery.disabled" ] \
    || fail "intentional-disconnect marker followed XDG_STATE_HOME"
printf 'Stopped\n' >"$state"
: >"$log"
if env -u XDG_STATE_HOME HOME="$test_home" TAILSCALE="$tailscale_fixture" \
    JQ="$jq_bin" FUNK_TEST_TAILSCALE_LOG="$log" \
    FUNK_TEST_TAILSCALE_STATE_FILE="$state" "$helper" \
    >"$test_home/disabled-output" 2>"$test_home/disabled-error"; then
    fail "launchd-style environment ignored the interactive opt-out"
fi
grep -F 'automatic recovery is disabled' "$test_home/disabled-error" >/dev/null \
    || fail "canonical opt-out did not survive the launchd environment"
if grep -q '^up$' "$log"; then
    fail "disabled automatic recovery invoked tailscale up"
fi

: >"$log"
FUNK_TEST_TAILSCALE_STATE_FILE="$state" run_ensure --enable \
    >"$test_home/enable-output" 2>"$test_home/enable-error"
[ ! -e "$disabled" ] && [ "$(cat "$state")" = Running ] \
    || fail "re-enabling recovery did not remove the opt-out and reconnect"
grep -Fx up "$log" >/dev/null \
    || fail "re-enabling recovery did not restore a Stopped backend"
