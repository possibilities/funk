#!/bin/bash

# Exercise the installer boundary: a no-auth hub cannot start behind a proxy,
# or when the current Tailscale routes cannot be established.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/funk-omajot-test.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home" "$scratch/prefix/opt/omajot/bin"
ln -s /usr/bin/true "$scratch/prefix/opt/omajot/bin/omajot"
cat >"$scratch/bin/tailscale" <<'STUB'
#!/bin/bash
[ "$*" = 'serve status --json' ] || exit 2
[ "${FUNK_TEST_SERVE_FAILURE:-0}" = 0 ] || exit 1
cat "$FUNK_TEST_SERVE_JSON"
STUB
chmod +x "$scratch/bin/tailscale"
export FUNK_ROOT="$root" HOME="$scratch/home"
export XDG_CONFIG_HOME="$HOME/.config"
export FUNK_TEST_BREW_PREFIX="$scratch/prefix"
export FUNK_TEST_SERVE_JSON="$scratch/serve.json"
# Keep the real jq available, while using the existing Homebrew fixture.
export PATH="$scratch/bin:$root/tests/fixtures:$PATH"

printf '%s\n' '{}' >"$FUNK_TEST_SERVE_JSON"
"$root/bin/funk" install-omajot --check >/dev/null
[ ! -e "$HOME/Library/LaunchAgents" ] || {
    printf 'Omajot --check installed a live service\n' >&2; exit 1;
}
for status in \
    '{"Web":{"machine.invalid:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8799"}}}}}' \
    '{"Web":{"machine.invalid:443":{"Handlers":{"/":{"Proxy":"http://localhost:8799/"}}}}}' \
    '{"TCP":{"443":{"TCPForward":"[::1]:8799"}}}'; do
    printf '%s\n' "$status" >"$FUNK_TEST_SERVE_JSON"
    if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
        printf 'Omajot accepted a proxied no-auth port\n' >&2; exit 1
    fi
    grep -F 'port 8799 is proxied by Tailscale' "$scratch/output" >/dev/null
done
if FUNK_TEST_SERVE_FAILURE=1 "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot accepted unknown Tailscale routes\n' >&2; exit 1
fi
grep -F 'cannot verify Tailscale routes' "$scratch/output" >/dev/null
printf '%s\n' 'not-json' >"$FUNK_TEST_SERVE_JSON"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot accepted malformed Tailscale routes\n' >&2; exit 1
fi
grep -F 'invalid Tailscale route status' "$scratch/output" >/dev/null
printf '%s\n' '{}' >"$FUNK_TEST_SERVE_JSON"
cat >"$scratch/bin/launchctl" <<'STUB'
#!/bin/bash
case "$1" in
    print|bootout) exit 1 ;;
    bootstrap) exit 0 ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$scratch/bin/launchctl"
export FUNK_LAUNCHCTL_BIN="$scratch/bin/launchctl"
"$root/bin/funk" install-omajot >/dev/null
/usr/bin/python3 - "$XDG_CONFIG_HOME/omajot/config.json" <<'PYTHON'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
assert p.exists(), 'Omajot installer did not connect the CLI/TUI to its hub'
assert json.loads(p.read_text())['hub'] == 'http://127.0.0.1:8799'
PYTHON
# Omajot owns every other field; convergence must preserve them and avoid a
# write when already correct, rather than replacing a writable app config.
printf '%s\n' '{"hub":"http://127.0.0.1:8797","data":"~/other-notes","extension_setting":42}' \
    >"$XDG_CONFIG_HOME/omajot/config.json"
"$root/bin/funk" install-omajot >/dev/null
/usr/bin/python3 - "$XDG_CONFIG_HOME/omajot/config.json" <<'PYTHON'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
assert json.loads(p.read_text()) == {
    'hub': 'http://127.0.0.1:8799', 'data': '~/other-notes', 'extension_setting': 42,
}
assert p.stat().st_mode & 0o777 == 0o600
PYTHON
/usr/bin/python3 - "$XDG_CONFIG_HOME/omajot/config.json" "$root/bin/funk" <<'PYTHON'
import pathlib
import subprocess
import sys
p = pathlib.Path(sys.argv[1])
before = p.stat().st_mtime_ns
subprocess.run([sys.argv[2], 'install-omajot'], check=True, stdout=subprocess.DEVNULL)
assert p.stat().st_mtime_ns == before, 'Converged Omajot config was rewritten'
PYTHON
printf '%s\n' '{"hub":"https://another-hub.invalid"}' >"$XDG_CONFIG_HOME/omajot/config.json"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot replaced a different hub configuration\n' >&2; exit 1
fi
grep -F 'already targets another hub' "$scratch/output" >/dev/null
mv "$XDG_CONFIG_HOME/omajot/config.json" "$scratch/foreign.json"
ln -s "$scratch/foreign.json" "$XDG_CONFIG_HOME/omajot/config.json"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot followed a configuration symlink\n' >&2; exit 1
fi
grep -F 'refusing symlinked Omajot configuration' "$scratch/output" >/dev/null
printf 'Omajot desktop-only installer tests passed.\n'
