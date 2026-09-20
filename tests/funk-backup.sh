#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
backup="$root/bin/.local/bin/funk-backup"
vault="$root/bin/.local/bin/transcript-vault"
fake_restic="$root/tests/fixtures/restic"
fake_agentchats="$root/tests/fixtures/agentchats-fail"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-backup-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
credentials="$test_home/restic.env"
scratch_cache="$test_home/scratch-cache"
scratch_stage="$scratch_cache/funk/backup-staging/onsite"
backup_lock="$test_home/backup.lock"
mkdir "$test_home/.config" "$test_home/.codex" "$test_home/code" \
    "$test_home/Documents" "$test_home/Downloads" "$scratch_cache"
mkdir "$test_home/code/jobsearch"
mkdir -p "$test_home/.claude/projects/project" "$test_home/.local/bin"
printf '%s\n' 'preserved conversation' >"$test_home/.claude/projects/project/transcript.jsonl"
printf '%s\n' 'preserved history' >"$test_home/.claude/history.jsonl"
install -m 755 "$fake_agentchats" "$test_home/.local/bin/agentchats"
/usr/bin/sqlite3 "$test_home/code/jobsearch/jobsearch.db" \
    'CREATE TABLE durable (value TEXT); INSERT INTO durable VALUES ("kept");'
printf 'RESTIC_REPOSITORY=test\nRESTIC_PASSWORD=test\n' >"$credentials"
chmod 600 "$credentials"

if HOME="$test_home" FUNK_RESTIC_BIN=/usr/bin/true \
    FUNK_BACKUP_CREDENTIALS="$test_home/missing.env" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
    "$backup" onsite --check >/dev/null 2>&1; then
    printf 'funk-backup test: missing credentials were reported ready\n' >&2
    exit 1
else
    [ "$?" -eq 75 ] \
        || { printf 'funk-backup test: missing credentials were not deferred\n' >&2; exit 1; }
fi

check() {
    HOME="$test_home" \
        FUNK_RESTIC_BIN=/usr/bin/true \
        FUNK_BACKUP_CREDENTIALS="$credentials" \
        FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
        "$backup" "$1" --check
}

onsite=$(check onsite)
offsite=$(check offsite)
onsite_roots=$(printf '%s\n' "$onsite" | sed -n 's/.*ready: \([0-9][0-9]*\) roots.*/\1/p')
offsite_roots=$(printf '%s\n' "$offsite" | sed -n 's/.*ready: \([0-9][0-9]*\) roots.*/\1/p')
[ "$onsite_roots" -gt "$offsite_roots" ] \
    || { printf 'funk-backup test: onsite tier lacks its extended roots\n' >&2; exit 1; }

chmod 644 "$credentials"
if check onsite >/dev/null 2>&1; then
    printf 'funk-backup test: permissive credentials were accepted\n' >&2
    exit 1
fi

# A failed application preflight must be visible, but must not prevent Restic
# from protecting the unrelated roots that are available.
chmod 600 "$credentials"
restic_log="$test_home/restic.log"
agentchats_log="$test_home/agentchats.log"
archive_root="$test_home/transcript-archive"
vault_lock="$test_home/transcript-vault.lock"
mkdir -p "$archive_root"
legacy_stage="$test_home/.local/state/funk/backup-staging/onsite"
mkdir -p "$legacy_stage"
touch "$legacy_stage/legacy-marker"
: >"$restic_log"
if HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_BACKUP_LOCK_DIR="$backup_lock" \
    FUNK_TRANSCRIPT_VAULT_BIN="$vault" \
    TRANSCRIPT_VAULT_ARCHIVE_ROOT="$archive_root" \
    TRANSCRIPT_VAULT_LOCK_DIR="$vault_lock" \
    FUNK_TEST_AGENTCHATS_LOG="$agentchats_log" \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    "$backup" onsite >"$test_home/onsite-output" 2>&1; then
    printf 'funk-backup test: degraded application snapshots were accepted\n' >&2
    exit 1
fi
grep -F -- '--tag funk-home-onsite' "$restic_log" >/dev/null \
    || { printf 'funk-backup test: preflight failure blocked Restic\n' >&2; exit 1; }
! [ -e "$agentchats_log" ] \
    || { printf 'funk-backup test: backup invoked the disabled AgentChats indexer\n' >&2; exit 1; }
[ -f "$archive_root/home/.claude/projects/project/transcript.jsonl" ] \
    || { printf 'funk-backup test: disabled indexing blocked transcript archiving\n' >&2; exit 1; }
cmp "$test_home/.claude/projects/project/transcript.jsonl" \
    "$archive_root/home/.claude/projects/project/transcript.jsonl" \
    || { printf 'funk-backup test: archived transcript differs from live source\n' >&2; exit 1; }
grep -F 'index deferred: legacy ingest disabled pending bounded runner' \
    "$test_home/onsite-output" >/dev/null \
    || { printf 'funk-backup test: backup did not disclose deferred search freshness\n' >&2; exit 1; }
grep -F -- "$scratch_stage" "$restic_log" >/dev/null \
    || { printf 'funk-backup test: external staging was not passed to Restic\n' >&2; exit 1; }
find "$scratch_cache/funk/backup-staging" "$test_home/.local/state/funk/backup-staging" \
    -type f \( -name '.*-wal' -o -name '.*-shm' \) | grep . >/dev/null \
    && { printf 'funk-backup test: SQLite verification left temp sidecars\n' >&2; exit 1; }
[ -f "$scratch_stage/jobsearch.sqlite3" ] \
    || { printf 'funk-backup test: Jobsearch snapshot was not staged\n' >&2; exit 1; }
[ -f "$legacy_stage/legacy-marker" ] \
    || { printf 'funk-backup test: degraded preflight removed legacy staging\n' >&2; exit 1; }

: >"$restic_log"
if HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_BACKUP_LOCK_DIR="$backup_lock" \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    "$backup" offsite >/dev/null 2>&1; then
    printf 'funk-backup test: degraded offsite snapshots were accepted\n' >&2
    exit 1
fi
grep -F -- "--exclude $test_home/.codex/sessions" "$restic_log" >/dev/null \
    || { printf 'funk-backup test: B2 includes large Codex sessions\n' >&2; exit 1; }
if grep -F -- "$test_home/Downloads" "$restic_log" >/dev/null; then
    printf 'funk-backup test: B2 includes bulky onsite-only roots\n' >&2
    exit 1
fi
grep -F -- "--exclude $test_home/.local/state/agentweb/control.sqlite3" "$restic_log" >/dev/null \
    || { printf 'funk-backup test: live Agentweb database is not excluded\n' >&2; exit 1; }
[ -f "$test_home/.local/state/funk/backup-staging/offsite/jobsearch.sqlite3" ] \
    || { printf 'funk-backup test: offsite snapshot was not staged internally\n' >&2; exit 1; }

# Legacy internal onsite staging is retired only after both the application
# preflight and Restic succeed with the external staging root protected.
mkdir -p "$test_home/.local/bin"
install -m 755 "$root/tests/fixtures/agentbrain" "$test_home/.local/bin/agentbrain"
install -m 755 "$root/tests/fixtures/agentboard" "$test_home/.local/bin/agentboard"
if HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_BACKUP_LOCK_DIR="$backup_lock" \
    FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    FUNK_TEST_RESTIC_EXIT=9 \
    "$backup" onsite >/dev/null 2>&1; then
    printf 'funk-backup test: failed Restic run was accepted\n' >&2
    exit 1
fi
[ -f "$legacy_stage/legacy-marker" ] \
    || { printf 'funk-backup test: failed Restic run removed legacy staging\n' >&2; exit 1; }

HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$scratch_cache" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_BACKUP_LOCK_DIR="$backup_lock" \
    FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    "$backup" onsite >/dev/null
[ ! -e "$legacy_stage" ] \
    || { printf 'funk-backup test: successful external backup retained legacy staging\n' >&2; exit 1; }

# An absent cache directory represents an unmounted Scratch volume. The onsite
# job must fall back internally without creating the configured external path.
missing_scratch_cache="$test_home/unmounted-scratch/cache"
HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_SCRATCH_CACHE_ROOT="$missing_scratch_cache" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_BACKUP_LOCK_DIR="$backup_lock" \
    FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    "$backup" onsite >/dev/null
[ -f "$legacy_stage/jobsearch.sqlite3" ] \
    || { printf 'funk-backup test: onsite fallback did not stage internally\n' >&2; exit 1; }
[ ! -e "$missing_scratch_cache" ] \
    || { printf 'funk-backup test: onsite fallback created an unmounted cache root\n' >&2; exit 1; }

printf 'funk-backup tests passed\n'
