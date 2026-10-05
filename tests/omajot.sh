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
    '{"Web":{"machine.invalid:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8797"}}}}}' \
    '{"Web":{"machine.invalid:443":{"Handlers":{"/":{"Proxy":"http://localhost:8797/"}}}}}' \
    '{"TCP":{"443":{"TCPForward":"[::1]:8797"}}}'; do
    printf '%s\n' "$status" >"$FUNK_TEST_SERVE_JSON"
    if "$root/bin/funk" install-omajot --check >"$scratch/output" 2>&1; then
        printf 'Omajot accepted a proxied no-auth port\n' >&2; exit 1
    fi
    grep -F 'port 8797 is proxied by Tailscale' "$scratch/output" >/dev/null
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
printf 'Omajot desktop-only installer tests passed.\n'
