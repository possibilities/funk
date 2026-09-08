#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-retire-gog.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
helper="$root/libexec/retire-gog"
mkdir -p "$test_home/agents" "$test_home/logs" "$test_home/state" \
    "$test_home/loaded" "$test_home/.local/bin" \
    "$test_home/Library/Application Support/gogcli"
printf 'private fixture\n' >"$test_home/Library/Application Support/gogcli/credentials.json"
link="$test_home/.local/bin/gog-ensure-authed"
expected="$test_home/code/funk/bin/.local/bin/gog-ensure-authed"

fail() { printf 'retire-gog test: %s\n' "$*" >&2; exit 1; }

cat >"$test_home/brew" <<'PYTHON'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['HOME'])
with (root / 'brew-calls').open('a') as file:
    file.write(json.dumps(sys.argv[1:]) + '\n')
if sys.argv[1:] == ['info', '--json=v2', '--installed']:
    state = (root / 'brew-state').read_text().strip()
    name = 'foreign/tap/gogcli' if state == 'foreign' else 'openclaw/tap/gogcli'
    if state == 'broken':
        print('{}')
    else:
        print(json.dumps({'formulae': [] if state == 'absent' else [
            {'name':'gogcli','full_name':name,'tap':name.rsplit('/',1)[0],
             'installed':[{'version':'0.39.1'}]}]}))
elif sys.argv[1:] == ['uninstall', '--formula', 'openclaw/tap/gogcli']:
    if os.environ.get('HOMEBREW_NO_AUTOREMOVE') != '1':
        sys.exit('package retirement must disable unrelated dependency cleanup')
    if (root / 'brew-state').read_text().strip() == 'fail-remove':
        sys.exit(1)
    (root / 'brew-state').write_text('absent')
else:
    sys.exit(2)
PYTHON
chmod 700 "$test_home/brew"

run_retire() {
    HOME="$test_home" FUNK_BREW_BIN="$test_home/brew" \
        FUNK_LAUNCHAGENTS_DIR="$test_home/agents" \
        FUNK_USER_LOG_DIR="$test_home/logs" FUNK_STATE_DIR="$test_home/state" \
        FUNK_LAUNCHCTL_BIN="$root/tests/fixtures/launchctl-install" \
        FUNK_TEST_LAUNCHD_STATE="$test_home/loaded" \
        FUNK_TEST_LAUNCHD_LOG="$test_home/launch-actions" \
        "$helper"
}

printf 'owned\n' >"$test_home/brew-state"
ln -s "$expected" "$link"
run_retire >/dev/null
[ ! -L "$link" ] || fail 'owned dangling helper survived'
[ "$(cat "$test_home/brew-state")" = absent ] || fail 'owned formula survived'
[ "$(cat "$test_home/Library/Application Support/gogcli/credentials.json")" = 'private fixture' ] \
    || fail 'credentials changed'
run_retire >/dev/null
[ "$(grep -c uninstall "$test_home/brew-calls")" = 1 ] || fail 'rerun repeated uninstall'

# Unowned paths and package provenance fail before any mutation.
for state in foreign broken; do
    printf '%s\n' "$state" >"$test_home/brew-state"
    : >"$test_home/brew-calls"
    ln -s "$expected" "$link"
    if run_retire >/dev/null 2>&1; then fail "accepted $state package metadata"; fi
    [ -L "$link" ] || fail 'failed preflight removed the helper'
    if grep -q uninstall "$test_home/brew-calls"; then fail 'failed preflight uninstalled'; fi
    rm "$link"
done
printf 'owned\n' >"$test_home/brew-state"
: >"$test_home/brew-calls"
printf 'foreign file\n' >"$link"
if run_retire >/dev/null 2>&1; then fail 'accepted foreign helper file'; fi
[ "$(cat "$link")" = 'foreign file' ] || fail 'foreign file changed'
[ ! -s "$test_home/brew-calls" ] || fail 'foreign helper reached Homebrew'
rm "$link"
ln -s "$test_home/elsewhere" "$link"
if run_retire >/dev/null 2>&1; then fail 'accepted foreign helper symlink'; fi
[ "$(readlink "$link")" = "$test_home/elsewhere" ] || fail 'foreign link changed'
rm "$link"

printf 'fail-remove\n' >"$test_home/brew-state"
ln -s "$expected" "$link"
if run_retire >/dev/null 2>&1; then fail 'hid package uninstall failure'; fi
[ -L "$link" ] || fail 'failed uninstall removed the helper'

printf 'retire-gog tests passed\n'
