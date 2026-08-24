#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/libexec/yaos-recovery"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/funk-yaos-recovery.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT

fail() {
    printf 'yaos-recovery test: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    printf '%s\n' "$1" | grep -F "$2" >/dev/null \
        || fail "output is missing: $2"
}

assert_not_contains() {
    if printf '%s\n' "$1" | grep -F "$2" >/dev/null; then
        fail "output disclosed forbidden text: $2"
    fi
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

vault="$test_tmp/vault"
plugin_dir="$vault/.obsidian/plugins/yaos"
checkout="$test_tmp/checkout"
fake_curl="$test_tmp/curl"
sentinel_token=test-sync-token-never-print-this-4f7d89a1
mkdir -p "$plugin_dir" "$checkout"

cat >"$plugin_dir/manifest.json" <<'EOF'
{"id":"yaos","version":"2.1.0"}
EOF
: >"$plugin_dir/main.js"
cat >"$plugin_dir/data.json" <<EOF
{
  "host": "https://yaos.notimpossiblemike.workers.dev",
  "token": "$sentinel_token",
  "vaultId": "test-vault-id-never-print",
  "deviceName": "greybird",
  "enableAttachmentSync": true
}
EOF
chmod 600 "$plugin_dir/data.json"

cat >"$fake_curl" <<'EOF'
#!/bin/bash
case "${FUNK_YAOS_CURL_MODE:-ready}" in
    ready)
        printf '%s\n' '{"claimed":true,"attachments":true,"snapshots":true,"socketTicketAuth":true,"serverVersion":"0.3.0","schemaVersion":3,"maxBlobUploadBytes":10485760}'
        ;;
    wrong)
        printf '%s\n' '{"claimed":true,"attachments":false,"snapshots":false,"socketTicketAuth":true,"serverVersion":"0.3.0","schemaVersion":3,"maxBlobUploadBytes":10485760}'
        ;;
    offline) exit 7 ;;
esac
EOF
chmod +x "$fake_curl"

run_guide() {
    FUNK_YAOS_MAC_VAULT="$vault" \
    FUNK_YAOS_CHECKOUT="$checkout" \
    FUNK_YAOS_CURL_BIN="$fake_curl" \
        "$helper" "$@"
}

output=$(run_guide --check) || fail "complete configuration did not pass --check"
assert_contains "$output" "ready: YAOS plugin 2.1.0 is installed"
assert_contains "$output" "ready: plugin has a recovery-capable setup token (value withheld)"
assert_contains "$output" "ready: Worker is claimed"
assert_not_contains "$output" "$sentinel_token"
assert_not_contains "$output" "test-vault-id-never-print"

mv "$plugin_dir/data.json" "$plugin_dir/data.json.backup"
output=$(run_guide) || fail "default guide failed for missing plugin data"
assert_contains "$output" "plugin data.json is missing"
assert_contains "$output" "backup or a surviving device"
mv "$plugin_dir/data.json.backup" "$plugin_dir/data.json"

cat >"$plugin_dir/data.json" <<EOF
{
  "host": "https://wrong.invalid",
  "token": "$sentinel_token",
  "vaultId": "test-vault-id-never-print",
  "deviceName": "smolbird",
  "enableAttachmentSync": false
}
EOF
chmod 600 "$plugin_dir/data.json"
output=$(run_guide) || fail "default guide failed for wrong local state"
assert_contains "$output" "plugin host does not match"
assert_contains "$output" "plugin device identity is not greybird"
assert_contains "$output" "attachment sync is disabled or absent"
assert_not_contains "$output" "$sentinel_token"
assert_not_contains "$output" "test-vault-id-never-print"

if run_guide --check >/dev/null 2>&1; then
    fail "--check passed incomplete local state"
fi

output=$(FUNK_YAOS_CURL_MODE=offline run_guide) \
    || fail "default guide failed while Worker was unavailable"
assert_contains "$output" "Worker capabilities could not be verified"
if FUNK_YAOS_CURL_MODE=offline run_guide --check >/dev/null 2>&1; then
    fail "--check passed while Worker was unavailable"
fi

# shellcheck disable=SC2088 # The guide intentionally prints a portable ~/ path.
for fact in \
    "https://yaos.notimpossiblemike.workers.dev" \
    "bucket yaos bound as YAOS_BUCKET" \
    "~/obsidian/work" \
    "/sdcard/Documents/obsidian/work" \
    "1b56897b4d72a51307c4c6e38d621128f4e69cf6" \
    "exact line /work" \
    "Recovery order:"; do
    assert_contains "$output" "$fact"
done
assert_contains "$output" "Create bucket 'yaos' only if the list proves it is absent"
assert_contains "$output" "Deploy only after confirming the account, existing state, pinned commit"
assert_contains "$output" "does not run automatically"

printf 'yaos-recovery tests passed\n'
