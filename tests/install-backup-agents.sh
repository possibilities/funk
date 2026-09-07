#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
installer="$root/libexec/install-backup-agents"
fake_launchctl="$root/tests/fixtures/launchctl-install"
plist_tool="$root/tests/lib/plist"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-backup-install-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
agent_dir="$test_home/Library/LaunchAgents"
log_dir="$test_home/Library/Logs/Funk"
state="$test_home/loaded"
actions="$test_home/actions"
mkdir -p "$agent_dir" "$log_dir" "$state" \
    "$test_home/.local/state/funk" "$test_home/.config/restic"
chmod 700 "$agent_dir" "$log_dir" "$state" "$test_home/.local" \
    "$test_home/.local/state" "$test_home/.local/state/funk" \
    "$test_home/.config" "$test_home/.config/restic"

fail() {
    printf 'install-backup-agents test: %s\n' "$*" >&2
    exit 1
}

run_installer() {
    HOME="$test_home" \
        FUNK_ROOT="$root" \
        FUNK_RESTIC_BIN=/usr/bin/true \
        FUNK_LAUNCHAGENTS_DIR="$agent_dir" \
        FUNK_USER_LOG_DIR="$log_dir" \
        FUNK_LAUNCHCTL_BIN="$fake_launchctl" \
        FUNK_TEST_LAUNCHD_STATE="$state" \
        FUNK_TEST_LAUNCHD_LOG="$actions" \
        FUNK_TEST_PLIST_TOOL="$plist_tool" \
        "$installer" "$@"
}

make_historical() {
    local label="$1" command_name="$2" interval="$3" timeout="$4" log_name="$5"
    /usr/bin/python3 - "$agent_dir/$label.plist" "$label" "$command_name" \
        "$interval" "$timeout" "$log_name" "$test_home" <<'PYTHON'
import plistlib
import sys

path, label, command, interval, timeout, log_name, home = sys.argv[1:]
data = {
    "Label": label,
    "ProgramArguments": [home + "/.local/bin/" + command],
    "HardResourceLimits": {"NumberOfFiles": 65536},
    "SoftResourceLimits": {"NumberOfFiles": 65536},
    "StandardErrorPath": home + "/Backups/restic/" + log_name,
    "StandardOutPath": home + "/Backups/restic/" + log_name,
    "StartInterval": int(interval),
    "TimeOut": int(timeout),
}
with open(path, "wb") as handle:
    plistlib.dump(data, handle)
PYTHON
}

# An unconfigured repository is deferred without making account convergence
# fail or publishing a job that would fail every time launchd runs it.
output=$(run_installer --check)
printf '%s\n' "$output" | grep -F 'Deferred onsite backup' >/dev/null \
    || fail 'missing onsite credentials were not deferred'
printf '%s\n' "$output" | grep -F 'Deferred offsite backup' >/dev/null \
    || fail 'missing offsite credentials were not deferred'

printf 'RESTIC_REPOSITORY=test\nRESTIC_PASSWORD=test\n' \
    >"$test_home/.config/restic/silverbird.env"
printf 'RESTIC_REPOSITORY=test\nRESTIC_PASSWORD=test\n' \
    >"$test_home/.config/restic/b2.env"
chmod 600 "$test_home/.config/restic/"*.env

# Exact historical definitions can be stopped and removed once the canonical
# replacement is installed.
make_historical backup.snapshot-silverbird restic-backup-silverbird \
    3600 3300 launchd-silverbird.log
make_historical backup.snapshot restic-backup 86400 28800 launchd.log
: >"$state/backup.snapshot-silverbird"
: >"$state/backup.snapshot"
run_installer >/dev/null
for label in io.arthack.funk.backup-onsite io.arthack.funk.backup-offsite; do
    [ -f "$agent_dir/$label.plist" ] && [ -f "$state/$label" ] \
        || fail "canonical job was not installed and loaded: $label"
done
[ ! -e "$agent_dir/backup.snapshot-silverbird.plist" ] \
    && [ ! -e "$agent_dir/backup.snapshot.plist" ] \
    || fail 'recognized historical definitions survived migration'

# A historical label with even one changed field is foreign and remains
# untouched.
rm -f "$agent_dir/io.arthack.funk.backup-onsite.plist" "$state/io.arthack.funk.backup-onsite"
make_historical backup.snapshot-silverbird restic-backup-silverbird \
    3600 3300 launchd-silverbird.log
/usr/bin/plutil -replace TimeOut -integer 3299 \
    "$agent_dir/backup.snapshot-silverbird.plist"
: >"$state/backup.snapshot-silverbird"
if run_installer >/dev/null 2>&1; then
    fail 'changed historical definition was claimed by label'
fi
[ -f "$agent_dir/backup.snapshot-silverbird.plist" ] \
    && [ -f "$state/backup.snapshot-silverbird" ] \
    || fail 'foreign historical definition was modified'

# The narrower transcript job keeps its owned plist when launchd cannot stop
# it, so a retry can recover rather than leaving an orphaned in-memory job.
rm -f "$agent_dir/backup.snapshot-silverbird.plist" "$state/backup.snapshot-silverbird"
retired_label=io.arthack.funk.preserve-transcripts
/usr/bin/python3 - "$agent_dir/$retired_label.plist" "$retired_label" <<'PYTHON'
import plistlib
import sys

path, label = sys.argv[1:]
with open(path, "wb") as handle:
    plistlib.dump({"Label": label, "FunkInstallerOwner": label + ".v1"}, handle)
PYTHON
: >"$state/$retired_label"
if FUNK_TEST_FAIL_BOOTOUT="$retired_label" run_installer >/dev/null 2>&1; then
    fail 'failed transcript-agent bootout was accepted'
fi
[ -f "$agent_dir/$retired_label.plist" ] && [ -f "$state/$retired_label" ] \
    || fail 'failed transcript-agent bootout removed recovery state'

printf 'install-backup-agents tests passed\n'
