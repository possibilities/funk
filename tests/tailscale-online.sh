#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/bin/.local/bin/tailscale-ensure-online"
tailscale_fixture="$root/tests/fixtures/tailscale"
sysext_fixture="$root/tests/fixtures/systemextensionsctl"
notifier_fixture="$root/tests/fixtures/terminal-notifier"
jq_bin=$(command -v jq)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-tailscale-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/tailscale.log"
state="$test_home/tailscale-state"
disabled="$test_home/.local/state/funk/tailscale-auto-recovery.disabled"
alert_state="$test_home/.local/state/funk/tailscale-ensure-online.alert"
notifications="$test_home/notifications"
xdg_state="$test_home/custom-xdg-state"

fail() {
    printf 'tailscale-online test: %s\n' "$*" >&2
    exit 1
}

# Pinning systemextensionsctl to the fixture is load-bearing, not tidiness:
# unpinned, the helper would read this machine's real extension state and the
# suite's verdicts would change with it.
run_ensure() {
    HOME="$test_home" XDG_STATE_HOME="$xdg_state" \
        TAILSCALE="$tailscale_fixture" JQ="$jq_bin" \
        SYSTEMEXTENSIONSCTL="$sysext_fixture" \
        FUNK_TERMINAL_NOTIFIER_BIN="$notifier_fixture" \
        FUNK_TEST_NOTIFIER_LOG="$notifications" \
        FUNK_TEST_TAILSCALE_LOG="$log" \
        "$helper" "$@"
}

last_notification() {
    [ -s "$notifications" ] || return 0
    tail -n 1 "$notifications"
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
    JQ="$jq_bin" SYSTEMEXTENSIONSCTL="$sysext_fixture" \
    FUNK_TERMINAL_NOTIFIER_BIN="$notifier_fixture" \
    FUNK_TEST_NOTIFIER_LOG="$notifications" FUNK_TEST_TAILSCALE_LOG="$log" \
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

# A wedged system-extension upgrade leaves no daemon to reach. Reporting the
# generic "reopen the app" advice for it sends the operator down a path that
# cannot work, so the diagnosis has to name the extension and the reboot.
: >"$notifications"
rm -f "$alert_state"
if FUNK_TEST_SYSEXT_STATE=wedged FUNK_TEST_TAILSCALE_STATUS_FAIL=1 run_ensure \
    >"$test_home/wedged-output" 2>"$test_home/wedged-error"; then
    fail "wedged system extension was accepted"
fi
grep -F 'could not reach a valid daemon' "$test_home/wedged-error" >/dev/null \
    || fail "wedged extension lost the unreachable-daemon distinction"
grep -F 'system extension upgrade is wedged' "$test_home/wedged-error" >/dev/null \
    || fail "wedged extension was not identified as the cause"
grep -F '1.98.10 stuck terminating' "$test_home/wedged-error" >/dev/null \
    || fail "wedged extension did not report the stuck outgoing version"
grep -F '1.102.2 waiting' "$test_home/wedged-error" >/dev/null \
    || fail "wedged extension did not report the blocked incoming version"
grep -F 'Reboot' "$test_home/wedged-error" >/dev/null \
    || fail "wedged extension did not name the recovery action"
if grep -F 'open or restart the Tailscale app' "$test_home/wedged-error" >/dev/null; then
    fail "wedged extension still offered advice that cannot work"
fi
last_notification | grep -F 'system extension upgrade is wedged' >/dev/null \
    || fail "wedged extension did not reach the operator as a notification"
last_notification | grep -F '<-sound> <default>' >/dev/null \
    || fail "a newly detected outage was not audible"
last_notification | grep -F '<-group> <com.arthack.funk.tailscale-online>' >/dev/null \
    || fail "outage notification was not grouped for replacement"

# The five-minute LaunchAgent must not re-alert 288 times a day for one
# unresolved outage; the standing notification refreshes silently instead.
: >"$notifications"
if FUNK_TEST_SYSEXT_STATE=wedged FUNK_TEST_TAILSCALE_STATUS_FAIL=1 run_ensure \
    >/dev/null 2>&1; then
    fail "repeated wedged extension was accepted"
fi
last_notification | grep -F 'system extension upgrade is wedged' >/dev/null \
    || fail "unresolved outage stopped refreshing its notification"
if last_notification | grep -F '<-sound>' >/dev/null; then
    fail "an unchanged outage re-alerted audibly"
fi

# An invalid daemon response has the same cause and deserves the same answer.
: >"$notifications"
if FUNK_TEST_SYSEXT_STATE=wedged FUNK_TEST_TAILSCALE_INVALID_JSON=1 run_ensure \
    >/dev/null 2>"$test_home/wedged-json-error"; then
    fail "wedged extension with invalid JSON was accepted"
fi
grep -F 'returned invalid status' "$test_home/wedged-json-error" >/dev/null \
    || fail "invalid JSON lost its distinction when an extension was wedged"
grep -F 'system extension upgrade is wedged' "$test_home/wedged-json-error" >/dev/null \
    || fail "invalid JSON did not report the wedged extension cause"

# Without a wedge there is nothing extension-specific to say, and the original
# advice is the correct advice.
: >"$notifications"
rm -f "$alert_state"
if FUNK_TEST_SYSEXT_STATE=healthy FUNK_TEST_TAILSCALE_STATUS_FAIL=1 run_ensure \
    >/dev/null 2>"$test_home/plain-error"; then
    fail "unreachable daemon was accepted"
fi
grep -F 'open or restart the Tailscale app' "$test_home/plain-error" >/dev/null \
    || fail "an unreachable daemon without a wedge lost its original guidance"

# A machine with no systemextensionsctl at all must degrade, not crash.
: >"$notifications"
rm -f "$alert_state"
if SYSTEMEXTENSIONSCTL=/nonexistent/systemextensionsctl \
    FUNK_TEST_TAILSCALE_STATUS_FAIL=1 run_ensure \
    >/dev/null 2>"$test_home/noctl-error"; then
    fail "unreachable daemon was accepted without systemextensionsctl"
fi
grep -F 'open or restart the Tailscale app' "$test_home/noctl-error" >/dev/null \
    || fail "a missing systemextensionsctl did not degrade to the plain message"

# The trap this closes: a staged upgrade is invisible while Tailscale works, and
# applies on the next restart -- which may happen while away from the machine.
: >"$notifications"
rm -f "$alert_state"
FUNK_TEST_SYSEXT_STATE=staged run_ensure \
    >"$test_home/staged-output" 2>"$test_home/staged-error" \
    || fail "a staged upgrade was treated as an outage on a healthy tailnet"
grep -F 'upgrade to 1.102.2 is staged' "$test_home/staged-error" >/dev/null \
    || fail "staged upgrade was not surfaced before the next restart"
grep -F 'physical access' "$test_home/staged-error" >/dev/null \
    || fail "staged upgrade did not explain when to apply it"
last_notification | grep -F 'is staged' >/dev/null \
    || fail "staged upgrade did not reach the operator as a notification"

# Recovery has to reset the alert history, or a recurrence would refresh
# silently and never be heard again.
: >"$notifications"
FUNK_TEST_SYSEXT_STATE=healthy run_ensure \
    >"$test_home/recovered-output" 2>"$test_home/recovered-error" \
    || fail "a healthy tailnet with a healthy extension was not accepted"
[ ! -s "$test_home/recovered-output" ] && [ ! -s "$test_home/recovered-error" ] \
    || fail "a fully healthy run was not a silent no-op"
[ ! -e "$alert_state" ] || fail "recovery did not clear the alert history"
[ ! -s "$notifications" ] || fail "a healthy run notified the operator"

: >"$notifications"
FUNK_TEST_SYSEXT_STATE=staged run_ensure >/dev/null 2>&1 \
    || fail "staged upgrade was not re-detected after recovery"
last_notification | grep -F '<-sound> <default>' >/dev/null \
    || fail "a condition returning after recovery was not audible again"

# A deliberate disconnect is not an outage and must not leave one standing.
: >"$notifications"
run_ensure --disable >/dev/null
[ ! -e "$alert_state" ] \
    || fail "an intentional disconnect left a standing outage alert"
run_ensure --enable >/dev/null 2>&1 || true

# A mistyped flag is a usage error, not something to wake the operator for.
: >"$notifications"
rm -f "$alert_state"
if run_ensure --nonsense >/dev/null 2>&1; then
    fail "an unknown option was accepted"
fi
[ ! -s "$notifications" ] || fail "a usage error notified the operator"
[ ! -e "$alert_state" ] || fail "a usage error recorded an alert"
