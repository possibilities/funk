#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
installer="$root/libexec/install-yaos"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/funk-install-yaos.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

fail() {
    printf 'install-yaos test: %s\n' "$*" >&2
    exit 1
}

source_repo="$test_tmp/source"
checkout="$test_tmp/checkout"
vault="$test_tmp/vault"
plugin_dir="$vault/.obsidian/plugins/yaos"
fake_npm="$test_tmp/npm"
mkdir -p "$source_repo/scripts" "$plugin_dir"

git -C "$source_repo" init -q
git -C "$source_repo" config user.name 'Funk test'
git -C "$source_repo" config user.email 'funk-test@example.invalid'
printf '%s\n' 'forked source' >"$source_repo/marker.txt"
printf '%s\n' '{"id":"yaos","version":"2.1.0"}' >"$source_repo/manifest.json"
printf '%s\n' 'styles' >"$source_repo/styles.css"
printf '%s\n' '{}' >"$source_repo/package-lock.json"
printf '%s\n' 'main.js' 'node_modules/' >"$source_repo/.gitignore"
printf '%s\n' 'process.exit(0);' >"$source_repo/scripts/guard-production-bundles.mjs"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'fork base'
pinned_commit=$(git -C "$source_repo" rev-parse HEAD)
git -C "$source_repo" branch integration

cat >"$fake_npm" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-}" = --prefix ] || exit 64
prefix=$2
shift 2
case "${1:-}:${2:-}" in
    ci:)
        mkdir -p "$prefix/node_modules"
        ;;
    run:build)
        printf '%s\n' 'built YAOS plugin' >"$prefix/main.js"
        ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$fake_npm"

printf '%s\n' 'old bundle' >"$plugin_dir/main.js"
printf '%s\n' 'old manifest' >"$plugin_dir/manifest.json"
printf '%s\n' 'old styles' >"$plugin_dir/styles.css"
printf '%s\n' 'secret state remains opaque' >"$plugin_dir/data.json"
chmod 600 "$plugin_dir/data.json"
data_fingerprint=$(stat -f '%d:%i:%z:%m:%Lp' "$plugin_dir/data.json")

run_installer() {
    HOME="$test_tmp/home" \
    FUNK_YAOS_FORK_URL="$source_repo" \
    FUNK_YAOS_CARRIED_BRANCH=integration \
    FUNK_YAOS_PINNED_COMMIT="$pinned_commit" \
    FUNK_YAOS_CHECKOUT="$checkout" \
    FUNK_YAOS_MAC_VAULT="$vault" \
    FUNK_YAOS_NPM_BIN="$fake_npm" \
        "$installer" "$@"
}
mkdir -p "$test_tmp/home"

output=$(run_installer) || fail "initial convergence failed"
printf '%s\n' "$output" | grep -F 'linked YAOS 2.1.0' >/dev/null \
    || fail "installer did not report the linked version"
[ "$(cat "$checkout/marker.txt")" = 'forked source' ] \
    || fail "pinned fork source was not selected"
for artifact in main.js manifest.json styles.css; do
    [ -L "$plugin_dir/$artifact" ] || fail "$artifact is not a link"
    [ "$plugin_dir/$artifact" -ef "$checkout/$artifact" ] \
        || fail "$artifact does not target the managed checkout"
done
[ "$(stat -f '%d:%i:%z:%m:%Lp' "$plugin_dir/data.json")" = "$data_fingerprint" ] \
    || fail "data.json changed during convergence"

run_installer --check >/dev/null || fail "converged installation did not pass --check"

printf '%s\n' 'unexpected local edit' >>"$checkout/manifest.json"
if run_installer --check >/dev/null 2>&1; then
    fail "--check accepted an unrelated tracked checkout edit"
fi
git -C "$checkout" checkout -q -- manifest.json
run_installer --check >/dev/null || fail "restored installation did not pass --check"

git -C "$source_repo" switch -q integration
printf '%s\n' 'advanced fork source' >"$source_repo/marker.txt"
git -C "$source_repo" add marker.txt
git -C "$source_repo" commit -qm 'advance carried branch'
pinned_commit=$(git -C "$source_repo" rev-parse HEAD)
if run_installer --check >/dev/null 2>&1; then
    fail "--check accepted a stale fork commit"
fi
run_installer >/dev/null || fail "installer did not converge a clean checkout to the new pin"
[ "$(cat "$checkout/marker.txt")" = 'advanced fork source' ] \
    || fail "installer did not select the advanced fork source"
run_installer --check >/dev/null || fail "advanced fork installation did not pass --check"

printf 'install-yaos tests passed\n'
