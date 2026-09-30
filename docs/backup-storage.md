# Backup working storage

`funk backup onsite|offsite --check` validates credentials and reports the
estimated temporary peak, staging budget, available internal space, and reserve.
It creates neither staging nor a lock. An unsafe estimate returns deferred
status 75 instead of advertising the run as ready.

## Lifecycle and capacity

- Both tiers use private, run-local staging under
  `~/.local/state/funk/backup-work/run-<id>/snapshots`. No staging or Restic cache
  is written to Scratch. The onsite transcript archive remains on Scratch;
  moving staging does not remove that separate archive workload.
- A shared kernel file lock serializes the tiers. Only one staging generation
  exists for active backup work; the previous run is not retained alongside new
  SQLite copies. Agentbrain restore verification runs first, before the larger
  application snapshots, to avoid overlapping its temporary restore with them.
- Default controls are `FUNK_BACKUP_STAGING_BUDGET_BYTES=8589934592` (8 GiB) and
  `FUNK_BACKUP_FREE_RESERVE_BYTES=21474836480` (20 GiB). An estimate that exceeds
  the budget or would consume the reserve defers before large writes.
- SQLite backups check capacity every 64 pages (at most 4 MiB). Producers also
  have per-file write limits. A supervisor samples aggregate staging, helper
  temporary data, and filesystem free space every 100 ms, stopping work at a
  64 MiB safety margin inside the budget/reserve. Helper and SQLite temporary
  directories are inside the supervised workspace.
- **This is a supervised budget, not a filesystem quota.** A fast multi-file
  producer, an unlinked temporary file, or scheduler delays can overshoot between
  observations. Free-space monitoring covers unlinked allocations, but the
  64 MiB margin is not a mathematical upper bound on overshoot. A strict quota
  would need a separate filesystem mechanism. The main practical reduction is
  one generation with no retained replacement copies or disk cache, not a claim
  of byte-exact enforcement. Each run logs its observed peak.
- Restic receives `--no-cache` explicitly, even if the credential environment
  defines `RESTIC_CACHE_DIR`. The tradeoff is additional network I/O.

Successful, failed, degraded, and caught interrupted runs remove their owned
workspace after stopping their entire producer/transport process group. If the
supervisor is killed, its group leader detects the lost parent and shuts down
the group; the next run recovers the marked abandoned workspace under the lock.
Unmarked directories and legacy recovery staging are never deleted automatically.
Filesystem errors that prevent safe teardown or removal are reported rather
than hidden. No cleanup mechanism can run while the machine is powered off.

An individual application snapshot failure remains visible while Restic backs
up unrelated roots. A global capacity violation defers the run. Live SQLite
stores remain excluded in favor of consistent, checked staged copies.

## Migration and pause/resume

Do not copy existing staging or caches into the new workspace. Legacy generated
copies live under `~/.local/state/funk/backup-staging` and
`/Volumes/Scratch/cache/funk/backup-staging`; Restic cache may exist under
`/Volumes/Scratch/cache/restic` or `~/Library/Caches/restic`. Inspect exact files,
confirm their original databases still exist and prior backups completed, and
remove only confirmed generated copies after installation. Keep unrelated files,
original databases, transcript archives, and actual Restic repositories intact.
Restic's `cache --cleanup --max-age 0 --cache-dir <confirmed-cache>` cleans local
repository cache entries without contacting or pruning the backup repository.

To pause a tier, disable and unload its exact Launch service label:

```sh
launchctl disable "gui/$(id -u)/io.arthack.funk.backup-onsite"
launchctl bootout "gui/$(id -u)/io.arthack.funk.backup-onsite"
```

Repeat for `backup-offsite`. To resume intentionally, enable the selected exact
label, then bootstrap its plist from `~/Library/LaunchAgents`. Onsite has
`RunAtLoad`, so bootstrap starts a backup immediately. Do not use installation
as a pause-preserving operation: `funk install-backups` loads configured jobs.
Test storage/restore behavior with `tests/funk-backup.sh` and a disposable local
repository before resuming real schedules.
