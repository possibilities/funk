#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/libexec/install-user-launchagent"
fake_launchctl="$root/tests/fixtures/launchctl-install"
plist_tool="$root/tests/lib/plist"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-launchagent-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
agent_dir="$test_home/agents"
log_dir="$test_home/logs"
state="$test_home/loaded"
actions="$test_home/actions"
rendered="$root/launchd/io.arthack.funk.caffeinate.plist"
new_label=io.arthack.funk.caffeinate
old_label=com.arthack.funk.home-awake-caffeinate
mkdir -m 0700 "$agent_dir" "$log_dir" "$state" "$test_home/.local" "$test_home/.local/state" "$test_home/.local/state/funk"

fail() {
    printf 'install-user-launchagent test: %s\n' "$*" >&2
    exit 1
}

run_installer() {
    HOME="$test_home" \
        FUNK_LAUNCHCTL_BIN="$fake_launchctl" \
        FUNK_TEST_LAUNCHD_STATE="$state" \
        FUNK_TEST_LAUNCHD_LOG="$actions" \
        FUNK_TEST_PLIST_TOOL="$plist_tool" \
        "$helper" "$new_label" "$old_label" "$rendered" "$log_dir" "$agent_dir" preserve
}

make_legacy() {
    cp "$rendered" "$agent_dir/$old_label.plist"
    /usr/bin/plutil -replace Label -string "$old_label" "$agent_dir/$old_label.plist"
    /usr/bin/plutil -remove FunkInstallerOwner "$agent_dir/$old_label.plist"
}

reset_case() {
    rm -f "$agent_dir"/* "$state"/* "$actions"
}

# Real installers render templates with plutil, which discards XML comments.
# The ownership key must survive that path and remain acceptable to the shared
# installer.
reset_case
rendered_template="$test_home/rendered-template.plist"
cp "$root/launchd/io.arthack.funk.update.plist.in" "$rendered_template"
/usr/bin/plutil -replace ProgramArguments.1 -string "$root/bin/funk" "$rendered_template"
/usr/bin/plutil -replace StandardOutPath -string "$log_dir/update.log" "$rendered_template"
rendered="$rendered_template"
new_label=io.arthack.funk.update
old_label=com.arthack.funk.update
run_installer
[ "$(/usr/libexec/PlistBuddy -c 'Print :FunkInstallerOwner' "$agent_dir/$new_label.plist")" = "$new_label.v1" ] \
    || fail "plutil-rendered plist lost its ownership marker"
rendered="$root/launchd/io.arthack.funk.caffeinate.plist"
new_label=io.arthack.funk.caffeinate
old_label=com.arthack.funk.home-awake-caffeinate
reset_case

# A running exact predecessor is replaced, reloaded under the new label, and
# removed only after the new bootstrap succeeds.
make_legacy
: >"$state/$old_label"
run_installer
[ -f "$agent_dir/$new_label.plist" ] || fail "new plist was not published"
[ ! -e "$agent_dir/$old_label.plist" ] || fail "legacy plist survived successful migration"
[ -f "$state/$new_label" ] && [ ! -e "$state/$old_label" ] \
    || fail "running legacy job did not move to the new label"

# Preserve mode installs an idle on-demand definition without starting it.
reset_case
run_installer
[ -f "$agent_dir/$new_label.plist" ] && [ ! -e "$state/$new_label" ] \
    || fail "preserve mode started an idle on-demand job"

# A changed predecessor is foreign even though it uses the historical label.
reset_case
make_legacy
/usr/bin/plutil -replace ProgramArguments.0 -string /bin/false "$agent_dir/$old_label.plist"
if run_installer >/dev/null 2>&1; then
    fail "foreign legacy plist was replaced"
fi
[ ! -e "$agent_dir/$new_label.plist" ] || fail "foreign refusal published the new plist"

# A cached legacy job without its exact on-disk definition cannot be claimed.
reset_case
: >"$state/$old_label"
if run_installer >/dev/null 2>&1; then
    fail "loaded legacy job without a plist was replaced"
fi
[ -f "$state/$old_label" ] || fail "loaded foreign legacy job was stopped"

# A rejected replacement restores the old definition and running state.
reset_case
make_legacy
: >"$state/$old_label"
if FUNK_TEST_FAIL_BOOTSTRAP="$new_label" run_installer >/dev/null 2>&1; then
    fail "failed bootstrap was accepted"
fi
[ -f "$agent_dir/$old_label.plist" ] && [ ! -e "$agent_dir/$new_label.plist" ] \
    || fail "failed bootstrap did not restore plist state"
[ -f "$state/$old_label" ] && [ ! -e "$state/$new_label" ] \
    || fail "failed bootstrap did not restore the legacy job"

# A failed legacy bootout restores the published file and leaves the job alone.
reset_case
make_legacy
: >"$state/$old_label"
if FUNK_TEST_FAIL_BOOTOUT="$old_label" run_installer >/dev/null 2>&1; then
    fail "failed bootout was accepted"
fi
[ -f "$agent_dir/$old_label.plist" ] && [ ! -e "$agent_dir/$new_label.plist" ] \
    || fail "failed bootout did not restore plist state"
[ -f "$state/$old_label" ] || fail "failed bootout stopped the legacy job"

# Final destination directories and the cross-installer lock are fail-closed.
reset_case
real_agent_dir="$test_home/real-agents"
mkdir -m 0700 "$real_agent_dir"
rmdir "$agent_dir"
ln -s "$real_agent_dir" "$agent_dir"
if run_installer >/dev/null 2>&1; then
    fail "symlink destination directory was accepted"
fi
rm "$agent_dir"
mkdir -m 0700 "$agent_dir"
saved_agent_dir="$agent_dir"
mkdir -m 0700 "$test_home/redirect-target"
ln -s "$test_home/redirect-target" "$test_home/linked-parent"
agent_dir="$test_home/linked-parent/agents"
if run_installer >/dev/null 2>&1; then
    fail "symlink ancestor directory was accepted"
fi
[ ! -e "$test_home/redirect-target/agents" ] \
    || fail "symlink ancestor was traversed before refusal"
agent_dir="$saved_agent_dir"
lock_file="$test_home/.local/state/funk/launchd-install.lock"
/usr/bin/shlock -p "$$" -f "$lock_file" || fail "could not establish test lock"
if run_installer >/dev/null 2>&1; then
    fail "concurrent installation lock was ignored"
fi
[ -f "$lock_file" ] || fail "contending installer removed another process's lock"
rm "$lock_file"

printf 'install-user-launchagent tests passed\n'
