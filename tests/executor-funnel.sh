#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
installer="$root/libexec/install-executor-funnel"
tailscale_fixture="$root/tests/fixtures/tailscale-funnel"
jq_bin=$(command -v jq)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-executor-funnel-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
state="$test_dir/funnel.json"
log="$test_dir/tailscale.log"
host=greybird.example.test:443

fail() {
    printf 'executor-funnel test: %s\n' "$*" >&2
    exit 1
}

write_root_state() {
    "$jq_bin" -n --arg host "$host" '{
        TCP: {"443": {HTTPS: true}},
        Web: {($host): {Handlers: {
            "/": {Proxy: "http://127.0.0.1:8787"},
            "/another": {Proxy: "http://127.0.0.1:9999"}
        }}},
        AllowFunnel: {($host): true}
    }' >"$state"
}

run_installer() {
    TAILSCALE="$tailscale_fixture" \
        JQ="$jq_bin" \
        FUNK_TEST_FUNNEL_STATE="$state" \
        FUNK_TEST_TAILSCALE_LOG="$log" \
        "$installer" "$@"
}

write_root_state
: >"$log"
check_output=$(run_installer --check)
printf '%s\n' "$check_output" \
    | grep -F 'Would configure Executor Funnel' >/dev/null \
    || fail '--check did not report the missing route'
if grep -F 'funnel --yes' "$log" >/dev/null; then
    fail '--check changed Funnel state'
fi
"$jq_bin" -e --arg host "$host" '
    .Web[$host].Handlers["/"].Proxy == "http://127.0.0.1:8787"
    and (.Web[$host].Handlers | has("/mcp") | not)
' "$state" >/dev/null || fail '--check changed an existing handler'

run_installer >/dev/null
"$jq_bin" -e --arg host "$host" '
    .Web[$host].Handlers["/"].Proxy == "http://127.0.0.1:8787"
    and .Web[$host].Handlers["/another"].Proxy == "http://127.0.0.1:9999"
    and .Web[$host].Handlers["/mcp"].Proxy == "http://127.0.0.1:4789/mcp"
    and .AllowFunnel[$host] == true
' "$state" >/dev/null || fail 'convergence changed a sibling route or used the wrong backend'
[ "$(grep -Fc 'funnel --yes --bg --set-path=/mcp http://127.0.0.1:4789/mcp' "$log")" -eq 1 ] \
    || fail 'convergence did not use the exact additive Funnel command once'

idempotent_output=$(run_installer)
printf '%s\n' "$idempotent_output" \
    | grep -F 'Executor Funnel is configured' >/dev/null \
    || fail 'an existing route was not recognized as converged'
[ "$(grep -Fc 'funnel --yes --bg --set-path=/mcp http://127.0.0.1:4789/mcp' "$log")" -eq 1 ] \
    || fail 'idempotent convergence rewrote Funnel state'

write_root_state
"$jq_bin" --arg host "$host" '
    .Web[$host].Handlers["/mcp"] = {Proxy: "http://127.0.0.1:7777"}
' "$state" >"$state.conflict"
mv "$state.conflict" "$state"
: >"$log"
if run_installer >/dev/null 2>&1; then
    fail 'a conflicting /mcp handler was overwritten'
fi
"$jq_bin" -e --arg host "$host" '
    .Web[$host].Handlers["/mcp"].Proxy == "http://127.0.0.1:7777"
    and .Web[$host].Handlers["/"].Proxy == "http://127.0.0.1:8787"
' "$state" >/dev/null || fail 'conflict refusal changed Funnel state'
if grep -F 'funnel --yes' "$log" >/dev/null; then
    fail 'conflict refusal invoked a Funnel mutation'
fi

write_root_state
: >"$log"
set +e
FUNK_TEST_TAILSCALE_ONLINE=0 run_installer >/dev/null 2>&1
offline_status=$?
set -e
[ "$offline_status" -eq 75 ] || fail 'an offline node was not deferred'
if grep -F 'funnel --yes' "$log" >/dev/null; then
    fail 'offline convergence invoked a Funnel mutation'
fi

# A fresh Tailscale configuration has no Web or AllowFunnel objects yet. The
# same command must create only Executor's route without depending on the
# separately owned webhook handler already existing.
printf '{}\n' >"$state"
: >"$log"
run_installer >/dev/null
"$jq_bin" -e --arg host "$host" '
    .Web[$host].Handlers == {
        "/mcp": {Proxy: "http://127.0.0.1:4789/mcp"}
    }
    and .AllowFunnel[$host] == true
' "$state" >/dev/null || fail 'fresh convergence did not create only /mcp'
[ "$(grep -Fc 'funnel --yes --bg --set-path=/mcp http://127.0.0.1:4789/mcp' "$log")" -eq 1 ] \
    || fail 'fresh convergence did not use the additive Funnel command once'

printf 'executor-funnel tests passed\n'
