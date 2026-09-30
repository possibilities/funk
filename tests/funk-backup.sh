#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
backup="${FUNK_BACKUP_UNDER_TEST:-$root/bin/.local/bin/funk-backup}"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-backup-test.XXXXXX")
# Resolve macOS /var's symlink before testing the real-directory safety policy.
test_home=$(cd -P "$test_home" && pwd)
runner=
cleanup() {
    if [ -n "$runner" ]; then
        kill -TERM "$runner" 2>/dev/null || true
        wait "$runner" 2>/dev/null || true
    fi
    if [ -f "$test_home/ready" ]; then
        local fixture_pid fixture_group
        fixture_pid=$(cat "$test_home/ready")
        if ps -o command= -p "$fixture_pid" | grep -F "$root/tests/fixtures/restic" >/dev/null; then
            fixture_group=$(ps -o pgid= -p "$fixture_pid" | tr -d ' ')
            kill -KILL -- "-$fixture_group" 2>/dev/null || true
        fi
    fi
    rm -rf "$test_home"
}
trap cleanup EXIT
credentials="$test_home/restic.env"
scratch_cache="$test_home/scratch-cache"
workspace="$test_home/.local/state/funk/backup-work"
legacy_stage="$test_home/.local/state/funk/backup-staging/onsite"
restic_log="$test_home/restic.log"
mkdir -p "$test_home/.config" "$test_home/.codex" "$test_home/code" \
    "$test_home/Documents" "$test_home/Downloads" "$scratch_cache" \
    "$test_home/personal/jobsearch" "$test_home/.local/bin" "$legacy_stage"
printf 'legacy recovery\n' >"$legacy_stage/keep"
/usr/bin/sqlite3 "$test_home/personal/jobsearch/jobsearch.db" \
    'CREATE TABLE durable (value TEXT); INSERT INTO durable VALUES ("kept");'
printf 'RESTIC_REPOSITORY=test\nRESTIC_PASSWORD=test\nRESTIC_CACHE_DIR=%s\n' \
    "$scratch_cache/restic" >"$credentials"
chmod 600 "$credentials"
install -m 755 "$root/tests/fixtures/agentbrain" "$test_home/.local/bin/agentbrain"
install -m 755 "$root/tests/fixtures/agentboard" "$test_home/.local/bin/agentboard"

fail() { printf 'funk-backup test: %s\n' "$*" >&2; exit 1; }
run() {
    HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" \
        FUNK_BACKUP_FREE_RESERVE_BYTES=0 FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true \
        FUNK_TEST_RESTIC_LOG="$restic_log" "$backup" "$@"
}
expect_status() {
    local expected=$1 status=0
    shift
    "$@" >"$test_home/output" 2>&1 || status=$?
    [ "$status" -eq "$expected" ] || fail "expected exit $expected, got $status: $(cat "$test_home/output")"
}
no_runs() {
    [ ! -f "$legacy_stage/jobsearch.sqlite3" ] \
        && [ ! -d "$scratch_cache/funk/backup-staging" ] || fail 'run-local staging was retained'
    if [ -d "$workspace" ]; then
        ! find "$workspace" -maxdepth 1 -name 'run-*' | grep . >/dev/null \
            || fail 'run-local staging was retained'
    fi
}
wait_ready() {
    local count
    for count in $(seq 1 160); do
        [ ! -f "$test_home/ready" ] || return 0
        sleep 0.05
    done
    fail 'fixture never entered the Restic phase'
}

check_case() {
    expect_status 75 env FUNK_BACKUP_CREDENTIALS="$test_home/missing.env" \
        HOME="$test_home" FUNK_RESTIC_BIN=/usr/bin/true "$backup" onsite --check
    local onsite offsite onsite_roots offsite_roots
    onsite=$(run onsite --check)
    offsite=$(run offsite --check)
    onsite_roots=$(printf '%s\n' "$onsite" | sed -n 's/.*ready: \([0-9][0-9]*\) roots.*/\1/p')
    offsite_roots=$(printf '%s\n' "$offsite" | sed -n 's/.*ready: \([0-9][0-9]*\) roots.*/\1/p')
    [ "$onsite_roots" -gt "$offsite_roots" ] || fail 'onsite lacks extended roots'
    [ ! -e "$workspace" ] && [ ! -e "$test_home/backup.lock" ] || fail '--check wrote staging or lock'
    chmod 644 "$credentials"
    expect_status 1 run onsite --check
    chmod 600 "$credentials"
}

storage_case() {
    FUNK_TEST_RESTIC_COPY="$test_home/restored.sqlite3" expect_status 0 run onsite
    [ -f "$test_home/restored.sqlite3" ] || fail 'consistent Jobsearch snapshot was not offered to Restic'
    [ "$(/usr/bin/sqlite3 "$test_home/restored.sqlite3" 'SELECT value FROM durable;')" = kept ] \
        || fail 'staged SQLite data cannot be restored'
    grep -F -- '--no-cache' "$restic_log" >/dev/null || fail 'Restic cache was not disabled explicitly'
    [ -z "$(find "$scratch_cache" -mindepth 1 -print)" ] || fail 'backup wrote external staging/cache'
    [ -f "$legacy_stage/keep" ] || fail 'backup removed legacy recovery material'
    no_runs
    : >"$restic_log"
    run offsite >/dev/null
    grep -F -- "--exclude $test_home/.codex/sessions" "$restic_log" >/dev/null || fail 'B2 includes Codex sessions'
    ! grep -F -- "$test_home/Downloads" "$restic_log" >/dev/null || fail 'B2 includes onsite-only roots'
    grep -F -- "--exclude $test_home/.local/state/agentweb/control.sqlite3" "$restic_log" >/dev/null \
        || fail 'live Agentweb SQLite store was not excluded'
    no_runs
}

failure_case() {
    expect_status 9 env FUNK_TEST_RESTIC_EXIT=9 \
        HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" FUNK_BACKUP_FREE_RESERVE_BYTES=0 \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true FUNK_TEST_RESTIC_LOG="$restic_log" "$backup" onsite
    no_runs
    [ -f "$legacy_stage/keep" ] || fail 'failed backup removed legacy recovery material'
    rm "$test_home/.local/bin/agentbrain"
    : >"$restic_log"
    expect_status 1 run onsite
    grep -F -- '--tag funk-home-onsite' "$restic_log" >/dev/null || fail 'degraded snapshot blocked unrelated roots'
    no_runs
    install -m 755 "$root/tests/fixtures/agentbrain" "$test_home/.local/bin/agentbrain"
}

restore_case() {
    local real_restic restored
    real_restic=$(command -v restic || true)
    if [ -z "$real_restic" ]; then
        printf 'funk-backup: local Restic restore check skipped (restic unavailable)\n'
        return 0
    fi
    cp "$credentials" "$test_home/original.env"
    printf 'RESTIC_REPOSITORY=%s\nRESTIC_PASSWORD=test\nRESTIC_CACHE_DIR=%s\n' \
        "$test_home/repository" "$scratch_cache/restic" >"$credentials"
    HOME="$test_home" RESTIC_REPOSITORY="$test_home/repository" RESTIC_PASSWORD=test \
        "$real_restic" --no-cache init --quiet
    FUNK_TEST_REAL_RESTIC="$real_restic" expect_status 0 run offsite
    no_runs
    HOME="$test_home" RESTIC_REPOSITORY="$test_home/repository" RESTIC_PASSWORD=test \
        "$real_restic" --no-cache restore latest --target "$test_home/restored" --quiet
    restored=$(find "$test_home/restored" -name jobsearch.sqlite3 -type f | head -n 1)
    [ -n "$restored" ] && [ "$(/usr/bin/sqlite3 "$restored" 'SELECT value FROM durable;')" = kept ] \
        || fail 'local Restic restore lost the consistent database snapshot'
    ! find "$test_home/restored" -name jobsearch.db | grep . >/dev/null || fail 'Restic included the live database'
    [ -z "$(find "$scratch_cache" -mindepth 1 -print)" ] || fail 'local Restic enabled external cache'
    mv "$test_home/original.env" "$credentials"
}

archive_case() {
    mkdir -p "$test_home/.claude/projects/project" "$test_home/archive"
    printf 'conversation\n' >"$test_home/.claude/projects/project/transcript.jsonl"
    install -m 755 "$root/tests/fixtures/agentchats-fail" "$test_home/.local/bin/agentchats"
    HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" \
        FUNK_BACKUP_FREE_RESERVE_BYTES=0 FUNK_TRANSCRIPT_VAULT_BIN="$root/bin/.local/bin/transcript-vault" \
        TRANSCRIPT_VAULT_ARCHIVE_ROOT="$test_home/archive" TRANSCRIPT_VAULT_LOCK_DIR="$test_home/vault.lock" \
        FUNK_TEST_AGENTCHATS_LOG="$test_home/agentchats.log" FUNK_TEST_RESTIC_LOG="$restic_log" \
        "$backup" onsite >"$test_home/output"
    cmp "$test_home/.claude/projects/project/transcript.jsonl" \
        "$test_home/archive/home/.claude/projects/project/transcript.jsonl" || fail 'transcript preservation failed'
    [ ! -e "$test_home/agentchats.log" ] || fail 'backup invoked the retired indexer'
    grep -F 'index deferred: legacy ingest disabled pending bounded runner' "$test_home/output" >/dev/null \
        || fail 'backup did not disclose deferred search freshness'
    no_runs
}

concurrency_case() {
    # exec the entrypoint so runner is the supervisor, not a background shell.
    HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" FUNK_BACKUP_FREE_RESERVE_BYTES=0 \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true FUNK_TEST_RESTIC_LOG="$restic_log" \
        FUNK_TEST_RESTIC_READY="$test_home/ready" "$backup" onsite >"$test_home/active-output" 2>&1 &
    runner=$!
    wait_ready
    expect_status 75 run offsite
    grep -F 'shared workspace lock' "$test_home/output" >/dev/null || fail 'second tier did not defer on shared lock'
    kill -TERM "$runner"
    local status=0
    wait "$runner" || status=$?
    runner=
    [ "$status" -eq 143 ] || fail "TERM returned $status rather than 143"
    no_runs
    local before
    before=$(wc -c <"$test_home/ready.writes")
    sleep 0.2
    [ "$(wc -c <"$test_home/ready.writes")" -eq "$before" ] || fail 'transport kept writing after cleanup'
    run offsite >/dev/null
    no_runs
}

stale_case() {
    # A SIGKILLed supervisor leaves staging. The group leader must shut down
    # its producers before the next run can recover that owned workspace.
    HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" FUNK_BACKUP_FREE_RESERVE_BYTES=0 \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true FUNK_TEST_RESTIC_LOG="$restic_log" \
        FUNK_TEST_RESTIC_READY="$test_home/ready" "$backup" onsite >"$test_home/active-output" 2>&1 &
    runner=$!
    wait_ready
    local group
    group=$(ps -o pgid= -p "$(cat "$test_home/ready")" | tr -d ' ')
    kill -KILL "$runner"
    wait "$runner" 2>/dev/null || true
    runner=
    local count stopped=0
    for ((count=0; count<60; count++)); do
        if ! ps -axo pgid=,stat= | awk -v group="$group" \
            '$1 == group && $2 !~ /^Z/ { found=1 } END { exit !found }'; then
            stopped=1
            break
        fi
        sleep 0.1
    done
    [ "$stopped" -eq 1 ] || fail 'lost supervisor left live producers holding the lock'
    mkdir -p "$workspace/unrelated" "$workspace/run-00000000000000000000000000000000"
    printf 'not ours\n' >"$workspace/unrelated/keep"
    printf 'malformed\n' >"$workspace/run-00000000000000000000000000000000/.owner"
    run offsite >"$test_home/output"
    grep -F 'recovered owned stale staging' "$test_home/output" >/dev/null || fail 'owned stale run was not recovered'
    [ -f "$workspace/unrelated/keep" ] && [ -f "$legacy_stage/keep" ] \
        && [ -f "$workspace/run-00000000000000000000000000000000/.owner" ] || fail 'recovery deleted unowned data'
    [ "$(find "$workspace" -maxdepth 1 -name 'run-*' | wc -l | tr -d ' ')" -eq 1 ] || fail 'owned run survived stale recovery'
    rm -rf "$workspace/run-00000000000000000000000000000000"
}

capacity_case() {
    # Sparse source metadata rejects before reading/copying 100 MiB.
    /usr/bin/python3 -c 'import sys; open(sys.argv[1], "wb").truncate(100 * 1024 ** 2)' "$test_home/.codex/thread_history_1.sqlite"
    FUNK_BACKUP_STAGING_BUDGET_BYTES=100663296 expect_status 75 run onsite --check
    grep -F 'staging estimate exceeds budget' "$test_home/output" >/dev/null || fail '--check advertised an unsafe generation as ready'
    FUNK_BACKUP_STAGING_BUDGET_BYTES=100663296 expect_status 75 run onsite
    grep -F 'staging estimate exceeds budget' "$test_home/output" >/dev/null || fail 'large source was not rejected in preflight'
    [ ! -e "$restic_log" ] || fail 'capacity rejection reached Restic'
    no_runs
    rm "$test_home/.codex/thread_history_1.sqlite"
    FUNK_BACKUP_FREE_RESERVE_BYTES=9223372036854775807 expect_status 75 \
        env HOME="$test_home" FUNK_RESTIC_BIN="$root/tests/fixtures/restic" \
        FUNK_BACKUP_CREDENTIALS="$credentials" FUNK_BACKUP_LOG="$test_home/backup.log" \
        FUNK_BACKUP_LOCK_DIR="$test_home/backup.lock" FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        FUNK_TEST_RESTIC_LOG="$restic_log" "$backup" onsite
    grep -F 'free-space reserve' "$test_home/output" >/dev/null || fail 'reserve rejection was not reported'
    no_runs
}

growth_case() {
    FUNK_TEST_BRAIN_GROW=1 FUNK_BACKUP_STAGING_BUDGET_BYTES=100663296 expect_status 75 run onsite
    grep -F 'staging budget/free-space guard tripped' "$test_home/output" >/dev/null \
        || fail 'growing helper bypassed producer-time capacity guard'
    [ ! -e "$restic_log" ] || fail 'unsafe growing generation reached Restic'
    no_runs
}

safety_case() {
    mkdir "$test_home/external"
    # Do not silently follow even an internal symlink: the same route can point
    # at Scratch tomorrow. --check must detect it without writing either side.
    rm -rf "$test_home/.local/state/funk"
    ln -s "$test_home/external" "$test_home/.local/state/funk"
    expect_status 1 run onsite --check
    grep -F 'real internal directories' "$test_home/output" >/dev/null || fail 'symlink rejection was not location safety'
    [ -z "$(find "$test_home/external" -mindepth 1 -print)" ] || fail 'unsafe staging symlink was followed'
}

for test_case in ${1:-check storage failure restore archive concurrency stale capacity growth safety}; do
    # Each selected case gets fresh observable receipts, while HOME stays tiny.
    rm -f "$restic_log" "$test_home/ready" "$test_home/ready.writes"
    "${test_case}_case"
done
printf 'funk-backup tests passed\n'
