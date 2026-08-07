#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/bin/.local/bin/gog-ensure-authed"
gog_fixture="$root/tests/fixtures/gog"
notifier_fixture="$root/tests/fixtures/terminal-notifier"
jq_bin=$(command -v jq)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-gog-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
notifications="$test_home/notifications"
accounts_file="$test_home/accounts"
probe_file="$test_home/probe"
clients_file="$test_home/clients"
alert_file="$test_home/.local/state/funk/gog-ensure-authed.alert"
gog_calls="$test_home/gog-calls"

fail() {
    printf 'gog-authed test: %s\n' "$*" >&2
    exit 1
}

# Pinning gog to the fixture is load-bearing, not tidiness: unpinned, the helper
# would read this machine's real credential and the suite's verdicts would change
# with whether someone happens to be signed in.
run_check() {
    HOME="$test_home" \
        GOG="$gog_fixture" JQ="$jq_bin" \
        FUNK_TEST_GOG_ACCOUNTS_FILE="$accounts_file" \
        FUNK_TEST_GOG_PROBE_FILE="$probe_file" \
        FUNK_TEST_GOG_CLIENTS_FILE="$clients_file" \
        FUNK_TERMINAL_NOTIFIER_BIN="$notifier_fixture" \
        FUNK_TEST_NOTIFIER_LOG="$notifications" \
        FUNK_TEST_GOG_LOG="$gog_calls" \
        "$helper" "$@"
}

notification_count() {
    [ -s "$notifications" ] || {
        printf '0'
        return 0
    }
    grep -c . "$notifications"
}

last_notification() {
    [ -s "$notifications" ] || return 0
    tail -n 1 "$notifications"
}

# clients defaults to 1: most cases exercise stages past client setup.
set_state() {
    printf '%s' "$1" >"$accounts_file"
    printf '%s' "$2" >"$probe_file"
    printf '%s' "${3:-1}" >"$clients_file"
}

# ── a working credential is silent ───────────────────────────────────────────
set_state 1 ok
: >"$notifications"
run_check || fail "a working credential must exit zero"
[ "$(notification_count)" -eq 0 ] || fail "a working credential must not notify"
[ ! -e "$alert_file" ] || fail "a working credential must not record an alert"

# ── losing the credential alerts once, audibly, with a click action ──────────
set_state 0 ok
: >"$notifications"
run_check && fail "a missing credential must exit nonzero"
[ "$(notification_count)" -eq 1 ] || fail "losing the credential must notify exactly once"
case "$(last_notification)" in
    *"no account authorized yet"*) ;;
    *) fail "the alert must name the stage: $(last_notification)" ;;
esac
case "$(last_notification)" in
    *"<-sound> <default>"*) ;;
    *) fail "a new fault must play a sound: $(last_notification)" ;;
esac
case "$(last_notification)" in
    *"<-execute> <osascript"*"Terminal"*) ;;
    *) fail "the alert must open a terminal for its remedy: $(last_notification)" ;;
esac
[ -e "$alert_file" ] || fail "losing the credential must record an alert"

# ── an unchanged fault stays quiet: this is the anti-spam guarantee ──────────
: >"$notifications"
run_check && fail "a standing fault must keep exiting nonzero"
[ "$(notification_count)" -eq 0 ] \
    || fail "an unchanged fault must not notify again: $(last_notification)"

# ── the reminder eventually re-posts, silently ───────────────────────────────
: >"$notifications"
FUNK_GOG_ALERT_REMINDER_SECONDS=0 run_check && fail "a standing fault stays nonzero"
[ "$(notification_count)" -eq 1 ] || fail "the reminder must re-post once"
case "$(last_notification)" in
    *"<-sound>"*) fail "a reminder must be silent: $(last_notification)" ;;
esac

# ── recovery announces itself once and clears the history ────────────────────
set_state 1 ok
: >"$notifications"
run_check || fail "a restored credential must exit zero"
[ "$(notification_count)" -eq 1 ] || fail "recovery must notify exactly once"
case "$(last_notification)" in
    *"recovered"*) ;;
    *) fail "recovery must say so: $(last_notification)" ;;
esac
[ ! -e "$alert_file" ] || fail "recovery must clear the alert history"

: >"$notifications"
run_check || fail "a still-working credential must exit zero"
[ "$(notification_count)" -eq 0 ] || fail "recovery must not repeat"

# ── a stored credential Google no longer honors is a fault ───────────────────
set_state 1 expired
: >"$notifications"
run_check && fail "an expired credential must exit nonzero"
case "$(last_notification)" in
    *"expired or revoked"*) ;;
    *) fail "an expired credential must be named as such: $(last_notification)" ;;
esac

# ── a network failure is not a credential failure ────────────────────────────
# The whole point of discriminating: alerting on every flaky connection would
# train the reader to ignore the alert that matters.
rm -f "$alert_file"
set_state 1 network
: >"$notifications"
run_check || fail "a network failure must not be reported as a credential fault"
[ "$(notification_count)" -eq 0 ] || fail "a network failure must not alert"
[ ! -e "$alert_file" ] || fail "a network failure must not record an alert"

# ── --check reports without alerting ─────────────────────────────────────────
set_state 0 ok
: >"$notifications"
run_check --check && fail "--check must carry the verdict in its exit status"
[ "$(notification_count)" -eq 0 ] || fail "--check must not notify"
[ ! -e "$alert_file" ] || fail "--check must not record an alert"

# ── the probe names its account ──────────────────────────────────────────────
# With several credentials stored and no default chosen, gog refuses a call it
# cannot attribute, so an unnamed probe would prove nothing about any of them.
set_state 1 ok
: >"$gog_calls"
run_check || fail "a working credential must exit zero"
grep -q -- '--account mike@example.com gmail search' "$gog_calls" \
    || fail "the probe must name the account it is validating: $(cat "$gog_calls")"

# ── each setup stage names itself and its own remedy ─────────────────────────
rm -f "$alert_file"
set_state 0 ok 0
: >"$notifications"
run_check && fail "a missing OAuth client must exit nonzero"
case "$(last_notification)" in
    *"no OAuth client configured"*) ;;
    *) fail "a missing client must be named: $(last_notification)" ;;
esac
case "$(last_notification)" in
    *"auth setup"*) ;;
    *) fail "a missing client must point at setup: $(last_notification)" ;;
esac

# ── finishing a stage announces the next one, unprompted ─────────────────────
# This is the guidance: the alert is edge-triggered on the message, so a changed
# stage is a change, and the reader is told what to do next without asking.
set_state 0 ok 1
: >"$notifications"
run_check && fail "no authorized account must exit nonzero"
[ "$(notification_count)" -eq 1 ] || fail "advancing a stage must notify once"
case "$(last_notification)" in
    *"no account authorized yet"*) ;;
    *) fail "the next stage must be named: $(last_notification)" ;;
esac
case "$(last_notification)" in
    *"<-sound> <default>"*) ;;
    *) fail "a stage change must be audible: $(last_notification)" ;;
esac

# ── a named account is offered directly rather than the guided flow ──────────
: >"$notifications"
rm -f "$alert_file"
FUNK_GOG_ACCOUNT=someone@example.com run_check && fail "still nonzero"
case "$(last_notification)" in
    *"auth add someone@example.com --services gmail"*) ;;
    *) fail "a configured account must be offered directly: $(last_notification)" ;;
esac

# ── an expired credential offers re-authorization, not first-time setup ──────
rm -f "$alert_file"
set_state 1 expired 1
: >"$notifications"
run_check && fail "an expired credential must exit nonzero"
case "$(last_notification)" in
    *"auth login"*) ;;
    *) fail "an expired credential must offer re-authorization: $(last_notification)" ;;
esac

printf 'gog-authed tests passed\n'
