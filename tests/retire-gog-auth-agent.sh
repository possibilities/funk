#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/libexec/retire-gog-auth-agent"
fake_launchctl="$root/tests/fixtures/launchctl-install"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-retire-gog-auth-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
agent_dir="$test_home/agents"
log_dir="$test_home/logs"
state_dir="$test_home/state"
loaded="$test_home/loaded"
actions="$test_home/actions"
label=io.arthack.funk.ensure-gog-auth
mkdir "$agent_dir" "$log_dir" "$state_dir" "$loaded"
: >"$actions"

run_retire() {
    HOME="$test_home" \
        FUNK_LAUNCHAGENTS_DIR="$agent_dir" \
        FUNK_USER_LOG_DIR="$log_dir" \
        FUNK_STATE_DIR="$state_dir" \
        FUNK_LAUNCHCTL_BIN="$fake_launchctl" \
        FUNK_TEST_LAUNCHD_STATE="$loaded" \
        FUNK_TEST_LAUNCHD_LOG="$actions" \
        FUNK_TEST_PLIST_TOOL="$root/tests/lib/plist" \
        "$helper"
}

/usr/bin/plutil -create xml1 "$agent_dir/$label.plist"
/usr/bin/plutil -insert Label -string "$label" "$agent_dir/$label.plist"
/usr/bin/plutil -insert FunkInstallerOwner -string "$label.v1" "$agent_dir/$label.plist"
: >"$loaded/$label"
: >"$log_dir/gog-authed.log"
: >"$state_dir/gog-ensure-authed.alert"
run_retire >/dev/null
[ ! -e "$agent_dir/$label.plist" ] && [ ! -e "$loaded/$label" ] \
    || { printf 'retire-gog-auth-agent test: owned service survived\n' >&2; exit 1; }
[ ! -e "$log_dir/gog-authed.log" ] && [ ! -e "$state_dir/gog-ensure-authed.alert" ] \
    || { printf 'retire-gog-auth-agent test: retired state survived\n' >&2; exit 1; }

/usr/bin/plutil -create xml1 "$agent_dir/$label.plist"
/usr/bin/plutil -insert Label -string "$label" "$agent_dir/$label.plist"
if run_retire >/dev/null 2>&1; then
    printf 'retire-gog-auth-agent test: unowned plist was removed\n' >&2
    exit 1
fi
[ -f "$agent_dir/$label.plist" ] \
    || { printf 'retire-gog-auth-agent test: unowned plist disappeared\n' >&2; exit 1; }

printf 'retire-gog-auth-agent tests passed\n'
