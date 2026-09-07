#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
status_command="$root/libexec/launchd-status"
fake_launchctl="$root/tests/fixtures/launchctl-install"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-launchd-status-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
agent_dir="$test_home/agents"
state_dir="$test_home/state"
logs="$test_home/logs"
system_agents="$test_home/daemons"
system_logs="$test_home/system-logs"
loaded="$test_home/loaded"
mkdir "$agent_dir" "$state_dir" "$logs" "$system_agents" "$system_logs" "$loaded"
: >"$test_home/actions"

labels='io.arthack.funk.update
io.arthack.funk.ensure-tailscale-online
io.arthack.funk.ensure-gog-auth
io.arthack.funk.keep-home-awake
io.arthack.funk.preserve-transcripts'
for label in $labels; do
    cp "$root/launchd/$label.plist.in" "$agent_dir/$label.plist"
    : >"$loaded/$label"
done
cp "$root/launchd/io.arthack.funk.caffeinate.plist" \
    "$state_dir/io.arthack.funk.caffeinate.plist"

run_status() {
    HOME="$test_home" \
        FUNK_LAUNCHCTL_BIN="$fake_launchctl" \
        FUNK_TEST_LAUNCHD_STATE="$loaded" \
        FUNK_TEST_LAUNCHD_LOG="$test_home/actions" \
        FUNK_TEST_PLIST_TOOL="$root/tests/lib/plist" \
        FUNK_LAUNCHAGENTS_DIR="$agent_dir" \
        FUNK_STATE_DIR="$state_dir" \
        FUNK_USER_LOG_DIR="$logs" \
        FUNK_SYSTEM_LAUNCHDAEMONS_DIR="$system_agents" \
        FUNK_SYSTEM_LOG_DIR="$system_logs" \
        FUNK_TEST_NEVER_EXITED_LABEL=io.arthack.funk.update \
        "$status_command"
}

run_status >"$test_home/status"
grep -F 'exit=(never exited)' "$test_home/status" >/dev/null \
    || { printf 'launchd-status test: never-exited state was not reported\n' >&2; exit 1; }

rm "$loaded/io.arthack.funk.ensure-tailscale-online"
if run_status >/dev/null 2>&1; then
    printf 'launchd-status test: unloaded periodic job was accepted\n' >&2
    exit 1
fi

printf 'launchd-status tests passed\n'
