#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
backup="$root/bin/.local/bin/funk-backup"
fake_restic="$root/tests/fixtures/restic"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-backup-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
credentials="$test_home/restic.env"
mkdir "$test_home/.config" "$test_home/.codex" "$test_home/code" \
    "$test_home/Documents" "$test_home/Downloads"
mkdir "$test_home/code/jobsearch"
/usr/bin/sqlite3 "$test_home/code/jobsearch/jobsearch.db" \
    'CREATE TABLE durable (value TEXT); INSERT INTO durable VALUES ("kept");'
printf 'RESTIC_REPOSITORY=test\nRESTIC_PASSWORD=test\n' >"$credentials"
chmod 600 "$credentials"

if HOME="$test_home" FUNK_RESTIC_BIN=/usr/bin/true \
    FUNK_BACKUP_CREDENTIALS="$test_home/missing.env" \
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
: >"$restic_log"
if HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
    FUNK_TRANSCRIPT_VAULT_BIN=/usr/bin/true \
    FUNK_TEST_RESTIC_LOG="$restic_log" \
    "$backup" onsite >/dev/null 2>&1; then
    printf 'funk-backup test: degraded application snapshots were accepted\n' >&2
    exit 1
fi
grep -F -- '--tag funk-home-onsite' "$restic_log" >/dev/null \
    || { printf 'funk-backup test: preflight failure blocked Restic\n' >&2; exit 1; }
find "$test_home/.local/state/funk/backup-staging" \
    -type f \( -name '.*-wal' -o -name '.*-shm' \) | grep . >/dev/null \
    && { printf 'funk-backup test: SQLite verification left temp sidecars\n' >&2; exit 1; }
[ -f "$test_home/.local/state/funk/backup-staging/onsite/jobsearch.sqlite3" ] \
    || { printf 'funk-backup test: Jobsearch snapshot was not staged\n' >&2; exit 1; }

: >"$restic_log"
if HOME="$test_home" \
    FUNK_RESTIC_BIN="$fake_restic" \
    FUNK_BACKUP_CREDENTIALS="$credentials" \
    FUNK_BACKUP_LOG="$test_home/backup.log" \
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

printf 'funk-backup tests passed\n'
