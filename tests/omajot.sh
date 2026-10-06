#!/bin/bash

# The public installer boundary owns identity, private-route preservation,
# no-auth publication refusal, and writable client-config convergence.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/funk-omajot-test.XXXXXXXX")
scratch=$(cd "$scratch" && pwd -P)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home" "$scratch/prefix/opt/omajot/bin"
ln -s /usr/bin/true "$scratch/prefix/opt/omajot/bin/omajot"
cat >"$scratch/bin/tailscale" <<'STUB'
#!/bin/bash
set -euo pipefail
case "$*" in
    'status --json') cat "$FUNK_TEST_TAILNET_JSON" ;;
    'serve status --json')
        [ "${FUNK_TEST_SERVE_FAILURE:-0}" = 0 ] || exit 1
        cat "$FUNK_TEST_SERVE_JSON" ;;
    'serve --bg --https=8448 http://127.0.0.1:8799')
        printf '%s\n' "$*" >>"$FUNK_TEST_SERVE_CALLS"
        /usr/bin/python3 - "$FUNK_TEST_SERVE_JSON" <<'PYTHON'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
state = json.loads(p.read_text())
state.setdefault('TCP', {})['8448'] = {'HTTPS': True}
state.setdefault('Web', {})['machine.example-tailnet.ts.net:8448'] = {
    'Handlers': {'/': {'Proxy': 'http://127.0.0.1:8799'}},
}
p.write_text(json.dumps(state))
PYTHON
        ;;
    *) exit 2 ;;
esac
STUB
cat >"$scratch/bin/launchctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$FUNK_TEST_LAUNCH_CALLS"
case "$1" in
    print) [ "${FUNK_TEST_LAUNCH_RUNNING:-0}" = 1 ] ;;
    bootout) exit 1 ;;
    bootstrap) exit 0 ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$scratch/bin/tailscale" "$scratch/bin/launchctl"
export FUNK_ROOT="$root" HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/home/.config"
export FUNK_TEST_BREW_PREFIX="$scratch/prefix"
export FUNK_TEST_SERVE_JSON="$scratch/serve.json" FUNK_TEST_TAILNET_JSON="$scratch/tailnet.json"
export FUNK_TEST_SERVE_CALLS="$scratch/serve-calls" FUNK_TEST_LAUNCH_CALLS="$scratch/launch-calls"
export FUNK_LAUNCHCTL_BIN="$scratch/bin/launchctl"
export PATH="$scratch/bin:$root/tests/fixtures:$PATH"
cat >"$FUNK_TEST_TAILNET_JSON" <<'JSON'
{"BackendState":"Running","Self":{"Online":true,"DNSName":"machine.example-tailnet.ts.net.","UserID":1},"User":{"1":{"LoginName":"person@example.invalid"}}}
JSON
printf '%s\n' '{}' >"$FUNK_TEST_SERVE_JSON"
"$root/bin/funk" install-omajot --check >/dev/null
[ ! -e "$HOME/.config/omajot" ] && [ ! -e "$HOME/Library/LaunchAgents" ]
[ ! -e "$FUNK_TEST_SERVE_CALLS" ]

# Unlike the retired local-only installer, convergence accepts this exact
# authenticated route but never a different handler, raw TCP or Funnel grant.
owned='{"TCP":{"8448":{"HTTPS":true}},"Web":{"machine.example-tailnet.ts.net:8448":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8799"}}}}}'
printf '%s\n' "$owned" >"$FUNK_TEST_SERVE_JSON"
"$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1 || {
    cat "$scratch/output" >&2
    printf 'Omajot rejected its authenticated private endpoint\n' >&2; exit 1
}
for status in \
    '{"TCP":{"8448":{"HTTPS":true}},"Web":{"machine.example-tailnet.ts.net:8448":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9999"}}}}}' \
    '{"TCP":{"8448":{"HTTPS":true}},"Web":{"machine.example-tailnet.ts.net:8448":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8799"},"/other":{"Text":"keep me"}}}}}' \
    '{"TCP":{"8448":{"TCPForward":"127.0.0.1:8799"}}}' \
    '{"Web":{"machine.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://localhost:8799/"}}}}}' \
    '{"Web":{"machine.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://[::1]:8799"}}}}}' \
    '{"TCP":{"8448":{"HTTPS":true}},"AllowFunnel":{"machine.example-tailnet.ts.net:8448":true}}'; do
    printf '%s\n' "$status" >"$FUNK_TEST_SERVE_JSON"
    if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
        printf 'Omajot accepted a conflicting or public route\n' >&2; exit 1
    fi
done
if FUNK_TEST_SERVE_FAILURE=1 "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot accepted unknown Tailscale routes\n' >&2; exit 1
fi
grep -F 'cannot read Tailscale route status' "$scratch/output" >/dev/null
printf '%s\n' 'not-json' >"$FUNK_TEST_SERVE_JSON"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot accepted malformed Tailscale routes\n' >&2; exit 1
fi
grep -F 'invalid Tailscale route status' "$scratch/output" >/dev/null

# Run the production entry point with only the HTTP transport substituted.
# Its public installer still renders/installs real files and calls fixture
# executables. A 200 input must prevent publication; a 403 input permits it.
runtime_install() {
    /usr/bin/python3 - "$root" "$scratch/prefix/opt/omajot/bin/omajot" "$1" <<'PYTHON'
import runpy
import sys
from unittest.mock import patch
from urllib.error import HTTPError
root, binary, code = sys.argv[1:]
class Response:
    status = int(code)
    def __enter__(self): return self
    def __exit__(self, *args): pass
def request(url, **kwargs):
    assert url == 'http://127.0.0.1:8799/api/whoami'
    if code == '403':
        raise HTTPError(url, 403, 'Forbidden', {}, None)
    return Response()
sys.argv = [root + '/libexec/install-omajot.py', root, binary]
with patch('urllib.request.urlopen', request):
    runpy.run_path(sys.argv[0], run_name='__main__')
PYTHON
}
printf '%s\n' '{}' >"$FUNK_TEST_SERVE_JSON"
if runtime_install 200 >"$scratch/output" 2>&1; then
    printf 'Omajot published an unauthenticated runtime\n' >&2; exit 1
fi
grep -F 'refusing to proxy an unauthenticated hub' "$scratch/output" >/dev/null || {
    cat "$scratch/output" >&2; exit 1;
}
[ ! -e "$FUNK_TEST_SERVE_CALLS" ]
cat >"$FUNK_TEST_SERVE_JSON" <<'JSON'
{"TCP":{"443":{"HTTPS":true}},"Web":{"machine.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8787"}}}},"AllowFunnel":{"machine.example-tailnet.ts.net:443":true}}
JSON
cp "$FUNK_TEST_SERVE_JSON" "$scratch/unrelated-before.json"
runtime_install 403 >/dev/null
/usr/bin/python3 - "$scratch" <<'PYTHON'
import json
from pathlib import Path
import plistlib
import sys
root = Path(sys.argv[1])
config = json.loads((root / 'home/.config/omajot/config.json').read_text())
assert config == {'hub': 'https://machine.example-tailnet.ts.net:8448', 'hub_login': 'person@example.invalid'}
before = json.loads((root / 'unrelated-before.json').read_text())
after = json.loads((root / 'serve.json').read_text())
assert after['TCP'].pop('8448') == {'HTTPS': True}
assert after['Web'].pop('machine.example-tailnet.ts.net:8448') == {'Handlers': {'/': {'Proxy': 'http://127.0.0.1:8799'}}}
assert after == before, 'Omajot changed unrelated Serve or Funnel state'
with (root / 'home/Library/LaunchAgents/io.arthack.funk.omajot-hub.plist').open('rb') as f:
    args = plistlib.load(f)['ProgramArguments']
assert '--no-auth' not in args and args[args.index('--login') + 1] == config['hub_login']
assert args[args.index('--url') + 1] == config['hub']
assert args[args.index('--bind') + 1] == '127.0.0.1'
assert len((root / 'serve-calls').read_text().splitlines()) == 1
PYTHON
export FUNK_TEST_LAUNCH_RUNNING=1
cp "$FUNK_TEST_LAUNCH_CALLS" "$scratch/launch-before"
runtime_install 403 >/dev/null
[ "$(wc -l <"$FUNK_TEST_SERVE_CALLS")" -eq 1 ]
# A matching active LaunchAgent must not be booted out or bootstrapped again.
tail -n 1 "$FUNK_TEST_LAUNCH_CALLS" | grep -F 'print gui/' >/dev/null
[ "$(wc -l <"$FUNK_TEST_LAUNCH_CALLS")" -eq "$(( $(wc -l <"$scratch/launch-before") + 1 ))" ]

printf '%s\n' '{"hub":"http://127.0.0.1:8799","data":"~/other-notes","extension_setting":42}' \
    >"$XDG_CONFIG_HOME/omajot/config.json"
runtime_install 403 >/dev/null
/usr/bin/python3 - "$XDG_CONFIG_HOME/omajot/config.json" <<'PYTHON'
import json
from pathlib import Path
import sys
p = Path(sys.argv[1])
assert json.loads(p.read_text()) == {
    'hub': 'https://machine.example-tailnet.ts.net:8448', 'hub_login': 'person@example.invalid',
    'data': '~/other-notes', 'extension_setting': 42,
}
assert p.stat().st_mode & 0o777 == 0o600
PYTHON
before=$(stat -f '%m:%i' "$XDG_CONFIG_HOME/omajot/config.json")
runtime_install 403 >/dev/null
[ "$(stat -f '%m:%i' "$XDG_CONFIG_HOME/omajot/config.json")" = "$before" ]
for config in '{"hub":"https://another-hub.invalid"}' '{"hub_login":"another-person@example.invalid"}' '[1]' 'not-json'; do
    printf '%s\n' "$config" >"$XDG_CONFIG_HOME/omajot/config.json"
    if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
        printf 'Omajot replaced foreign or invalid application config\n' >&2; exit 1
    fi
done
mv "$XDG_CONFIG_HOME/omajot/config.json" "$scratch/foreign.json"
ln -s "$scratch/foreign.json" "$XDG_CONFIG_HOME/omajot/config.json"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot followed a configuration symlink\n' >&2; exit 1
fi
grep -F 'refusing symlinked Omajot configuration' "$scratch/output" >/dev/null
rm "$XDG_CONFIG_HOME/omajot/config.json"
printf '%s\n' '{"BackendState":"Stopped"}' >"$FUNK_TEST_TAILNET_JSON"
if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
    printf 'Omajot fell back to unauthenticated access without Tailscale\n' >&2; exit 1
fi
grep -F 'no unauthenticated fallback' "$scratch/output" >/dev/null
printf 'Omajot authenticated installer tests passed.\n'
