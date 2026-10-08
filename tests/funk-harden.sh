#!/bin/bash

set -euo pipefail
root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-harden-lifecycle.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
export FUNK_TEST_HARDEN_DIR="$test_dir"

fail() {
    printf 'funk-harden lifecycle test: %s\n' "$*" >&2
    exit 1
}

# Relocate OS boundaries in a disposable copy, not through root-helper flags
# or environment overrides that an unprivileged caller could use in production.
python3 - "$root" "$test_dir" <<'PYTHON'
from pathlib import Path
import re
import sys

root, target = map(Path, sys.argv[1:])
source = (root / "system/funk-harden").read_text()
for command in ("pfctl", "ifconfig", "sysctl", "shlock", "install", "chown", "chmod"):
    source = re.sub(r"/(?:usr/)?s?bin/" + command + r"\b", str(target / command), source)
    (target / command).symlink_to(root / "tests/fixtures/hardening/command")
for command in ("id", "stat"):
    source = source.replace(command + " -", str(target / command) + " -")
    (target / command).symlink_to(root / "tests/fixtures/hardening/command")
for path in ("/var/db/funk", "/var/run/funk-harden.lock", "/etc/pf.conf"):
    source = source.replace(path, str(target / Path(path).name))
(target / "helper").write_text(source)
PYTHON

run_helper() {
    /bin/bash "$test_dir/helper" "$@"
}

printf 'anchor "com.arthack.funk.travel"\n' > "$test_dir/pf.conf"
printf 'lo0 en0 utun0\n' > "$test_dir/interfaces"
run_helper boot >/dev/null
grep -Fx 'block drop in quick on en6 all' "$test_dir/anchor-rules" >/dev/null \
    || fail 'the known Ethernet adapter is not fenced before it attaches'
# The selected posture's reconciliation entry point is the same one launchd
# invokes repeatedly. The pre-fix helper has no such owning lifecycle at all.
printf 'lo0 en0 en6 en9 utun0\n' > "$test_dir/interfaces"
run_helper reconcile >/dev/null 2>&1 \
    || fail 'an interface appearing after boot cannot be reconciled'
run_helper status >/dev/null || fail 'hot-plugged physical interfaces are not fenced'
grep -Fx 'block drop in quick on en9 all' "$test_dir/anchor-rules" >/dev/null \
    || fail 'a new physical interface was omitted'
[ "$(cat "$test_dir/funk/hardening-posture")" = travel ] \
    || fail 'hot-plug selected home without an operator action'
if grep -F '192.168.50.0/24' "$test_dir/anchor-rules" >/dev/null; then
    fail 'travel gained a trusted LAN exception'
fi

assert_no_change() {
    local output
    cp "$test_dir/changes" "$test_dir/changes-before"
    output=$(run_helper "$1" 2>&1)
    [ -z "$output" ] || fail "converged $1 appended idle log output"
    cmp -s "$test_dir/changes" "$test_dir/changes-before" \
        || fail "converged $1 rewrote state or changed PF"
}
assert_no_change reconcile
assert_no_change travel
main_loads=$(grep -c '^pfctl -f ' "$test_dir/changes")
[ "$main_loads" -eq 1 ] || fail 'interface reconciliation reloaded the main PF rules'

run_helper home >/dev/null
printf 'lo0 en0 en6 en9 en10 utun0\n' > "$test_dir/interfaces"
run_helper reconcile >/dev/null
[ "$(cat "$test_dir/funk/hardening-posture")" = home ] \
    || fail 'reconciliation lost the manual same-boot home selection'
grep -Fx 'pass in quick on en6 inet from 192.168.50.0/24 to any' \
    "$test_dir/anchor-rules" >/dev/null || fail 'the fixed home exception was lost'
grep -Fx 'block drop in quick on en10 all' "$test_dir/anchor-rules" >/dev/null \
    || fail 'home stopped fencing an unrelated new physical interface'
[ "$(grep -c '192.168.50.0/24' "$test_dir/anchor-rules")" -eq 1 ] \
    || fail 'home broadened the trusted interface/subnet policy'
assert_no_change reconcile
assert_no_change home

# Removing the home adapter must not stop fencing other hot-plugged interfaces
# or silently select a different posture. Reattachment uses the retained rule.
printf 'lo0 en0 en9 en10 en11 utun0\n' > "$test_dir/interfaces"
run_helper reconcile >/dev/null
run_helper status >/dev/null || fail 'detached home adapter disabled reconciliation'
cp "$test_dir/changes" "$test_dir/changes-before"
if run_helper home >/dev/null 2>&1; then
    fail 'manual home selection succeeded without its trusted interface'
fi
cmp -s "$test_dir/changes" "$test_dir/changes-before" \
    || fail 'rejected home selection changed PF or state'
printf 'lo0 en0 en6 en9 en10 en11 utun0\n' > "$test_dir/interfaces"
assert_no_change reconcile

printf 'boot-two\n' > "$test_dir/boot"
run_helper reconcile >/dev/null
[ "$(cat "$test_dir/funk/hardening-posture")" = travel ] \
    || fail 'a new boot reused the previous home selection'
if grep -F '192.168.50.0/24' "$test_dir/anchor-rules" >/dev/null; then
    fail 'a new boot retained home permission'
fi
assert_no_change reconcile
run_helper status >/dev/null

# A failed posture write during a new boot must not stamp that new session on
# the old home marker. Otherwise a retry could resurrect prior-boot permission.
run_helper home >/dev/null
printf 'boot-three\n' > "$test_dir/boot"
if FUNK_TEST_HARDEN_INSTALL_FAIL=hardening-posture run_helper reconcile >/dev/null 2>&1; then
    fail 'a failed posture write was reported as success'
fi
[ "$(cat "$test_dir/funk/hardening-boot-session")" = boot-two ] \
    || fail 'a failed posture write stamped a new session on the previous home permission'
run_helper reconcile >/dev/null
[ "$(cat "$test_dir/funk/hardening-posture")" = travel ] \
    || fail 'retry after a failed state write resurrected home'

# Readiness must check the effective ordering, not just the presence of an
# anchor name: a preceding foreign quick pass can bypass our fence.
printf 'pass in quick all\nanchor "com.arthack.funk.travel" all\n' > "$test_dir/main-rules"
if run_helper status >/dev/null 2>&1; then
    fail 'status accepted an anchor shadowed by an earlier foreign quick pass'
fi
run_helper reconcile >/dev/null
run_helper status >/dev/null || fail 'the root traversal was not repaired'

printf 'pass in quick on en0 all\n' >> "$test_dir/anchor-rules"
if run_helper status >/dev/null 2>&1; then
    fail 'status accepted unexpected effective anchor rules'
fi
run_helper reconcile >/dev/null
run_helper status >/dev/null

cp "$test_dir/changes" "$test_dir/changes-before"
mv "$test_dir/funk/hardening-posture" "$test_dir/saved-posture"
ln -s "$test_dir/saved-posture" "$test_dir/funk/hardening-posture"
if run_helper reconcile >/dev/null 2>&1; then
    fail 'reconciliation accepted a state symlink'
fi
cmp -s "$test_dir/changes" "$test_dir/changes-before" \
    || fail 'unsafe state changed PF before being rejected'
rm "$test_dir/funk/hardening-posture"
mv "$test_dir/saved-posture" "$test_dir/funk/hardening-posture"

python3 - "$root/system/io.arthack.funk.harden-boot.plist" <<'PYTHON'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    job = plistlib.load(handle)
assert job["ProgramArguments"] == ["/usr/local/libexec/funk-harden", "reconcile"]
assert job["RunAtLoad"] is True
assert 1 <= job["StartInterval"] <= 10
assert job["FunkInstallerOwner"] == "io.arthack.funk.harden-boot.v1"
PYTHON

# Exercise installation with only OS/process boundaries relocated. This is the
# owner of PF bytes, root-copy safety and the sudoers enumeration, not a replay
# of the installer's private matcher.
python3 - "$root" "$test_dir" <<'PYTHON'
from pathlib import Path
import re
import sys

root, target = map(Path, sys.argv[1:])
(target / "source/system").mkdir(parents=True)
(target / "source/libexec").mkdir()
(target / "source/system/funk-harden").write_bytes((target / "helper").read_bytes())
(target / "source/system/funk-harden").chmod(0o755)
job = "io.arthack.funk.harden-boot.plist"
(target / "source/system" / job).write_bytes((root / "system" / job).read_bytes())
for script, relative in (("system/install-hardening-root", "installer"),
                         ("libexec/install-hardening", "source/libexec/install-hardening")):
    source = (root / script).read_text()
    for command in ("install", "shlock", "pfctl", "launchctl", "plutil", "visudo", "chmod", "sudo"):
        source = re.sub(r"/(?:usr/)?s?bin/" + command + r"\b", str(target / command), source)
        if not (target / command).exists():
            (target / command).symlink_to(root / "tests/fixtures/hardening/command")
    source = source.replace("/usr/libexec/PlistBuddy", str(target / "PlistBuddy"))
    for command in ("id", "stat", "uname"):
        source = source.replace(command + " -", str(target / command) + " -")
        if not (target / command).exists():
            (target / command).symlink_to(root / "tests/fixtures/hardening/command")
    for path, local in (("/usr/local/libexec", "libexec"),
                        ("/Library/LaunchDaemons", "LaunchDaemons"),
                        ("/Library/Logs/Funk", "logs"),
                        ("/etc/sudoers.d", "sudoers.d"),
                        ("/etc/pf.conf", "pf.conf"),
                        ("/var/run/funk-hardening-install.lock", "installer.lock")):
        source = source.replace(path, str(target / local))
    (target / relative).write_text(source)
    (target / relative).chmod(0o755)
(target / "source/system/install-hardening-root").write_bytes((target / "installer").read_bytes())
(target / "source/system/install-hardening-root").chmod(0o755)
(target / "PlistBuddy").symlink_to(root / "tests/fixtures/hardening/command")
for directory in ("LaunchDaemons", "sudoers.d"):
    (target / directory).mkdir()
PYTHON

cat > "$test_dir/pf.conf" <<'PF'
# Foreign options and translation anchors stay byte-for-byte untouched.
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
anchor "legacy.travel"
pass in quick on en0 proto tcp to any port 22
# Existing owned duplicate traversals.
anchor "com.arthack.funk.travel"
  anchor "com.arthack.funk.travel" # duplicate
PF
cp "$test_dir/pf.conf" "$test_dir/pf-before"
run_helper home >/dev/null
/bin/bash "$test_dir/installer" --user operator --source-root "$test_dir/source" >/dev/null
[ "$(cat "$test_dir/funk/hardening-posture")" = home ] \
    || fail 'installation lost the manual same-boot posture'
python3 - "$test_dir" <<'PYTHON'
from pathlib import Path
import sys

root = Path(sys.argv[1])
before = (root / "pf-before").read_bytes().splitlines(keepends=True)
after = (root / "pf.conf").read_bytes().splitlines(keepends=True)
owned = lambda line: b'anchor "com.arthack.funk.travel"' in line
assert [line for line in before if not owned(line)] == [line for line in after if not owned(line)]
assert sum(owned(line) for line in after) == 1
assert after.index(b'anchor "com.arthack.funk.travel"\n') < after.index(b'anchor "legacy.travel"\n')
expected = "".join(f"operator ALL=(root) NOPASSWD: {root}/libexec/funk-harden {action}\n"
                   for action in ("status", "travel", "home"))
assert (root / "sudoers.d/funk-harden-501").read_text() == expected
PYTHON
cp "$test_dir/changes" "$test_dir/changes-before"
/bin/bash "$test_dir/installer" --user operator --source-root "$test_dir/source" >/dev/null
cmp -s "$test_dir/changes" "$test_dir/changes-before" \
    || fail 'repeat root installation rewrote files, reloaded PF or restarted launchd'
FUNK_ROOT="$test_dir/source" FUNK_TEST_HARDEN_USER=1 \
    /bin/bash "$test_dir/source/libexec/install-hardening" >/dev/null
cmp -s "$test_dir/changes" "$test_dir/changes-before" \
    || fail 'converged user installation attempted elevation or a privileged change'

# A source-matching plist on disk is not proof that launchd imported it. A stale
# boot-only cached job must be replaced, then subsequent convergence is silent.
python3 - "$test_dir/loaded-io.arthack.funk.harden-boot" <<'PYTHON'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
job = json.loads(path.read_text())
job.pop("StartInterval")
job["ProgramArguments"][-1] = "boot"
path.write_text(json.dumps(job))
PYTHON
/bin/bash "$test_dir/installer" --user operator --source-root "$test_dir/source" >/dev/null
python3 - "$test_dir/loaded-io.arthack.funk.harden-boot" <<'PYTHON'
import json
from pathlib import Path
import sys

job = json.loads(Path(sys.argv[1]).read_text())
assert job["StartInterval"] == 10
assert job["ProgramArguments"][-1] == "reconcile"
PYTHON
cp "$test_dir/changes" "$test_dir/changes-before"
/bin/bash "$test_dir/installer" --user operator --source-root "$test_dir/source" >/dev/null
cmp -s "$test_dir/changes" "$test_dir/changes-before" \
    || fail 'repaired launchd import did not converge'

mv "$test_dir/libexec/funk-harden" "$test_dir/saved-helper"
ln -s "$test_dir/saved-helper" "$test_dir/libexec/funk-harden"
if /bin/bash "$test_dir/installer" --user operator --source-root "$test_dir/source" >/dev/null 2>&1; then
    fail 'installer followed a root-helper target symlink'
fi

printf 'funk-harden tests passed\n'
