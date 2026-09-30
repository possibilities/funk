# 0012: Transient internal backup workspaces

Accepted 2026-09-30.

The external Scratch NVMe controller repeatedly disappeared during the hourly
onsite backup's database snapshot/Restic read bursts. A captured failure peaked
near 55°C at the SSD sensor, below its warning threshold; it did not establish
SSD over-temperature shutdown. Moving the correlated I/O is a mitigation, not
proof that the enclosure or SSD is healthy.

Persistent staging also kept older database copies while writing replacements,
and failed/interrupted runs could leave temporary files. Merely relocating that
layout would move its space spikes and leftovers onto the smaller internal SSD.

Both backup tiers now share a kernel lock and use one marked internal workspace
per run. Capacity admission, incremental SQLite checks, producer file limits and
aggregate supervision replace unbounded temporary generation. Completion and
interruption stop producers before removing the workspace; parent-loss handling
and next-run marked recovery cover a killed supervisor without PID-file races.
These controls are deliberately documented as a supervised budget, not a strict
filesystem quota. Defaults target 8 GiB of working storage and preserve 20 GiB
free. Agentbrain restore verification precedes the larger snapshots so its
isolated restore does not overlap the entire application staging generation.

The operator chose explicit Restic `--no-cache` rather than another potentially
growing persistent internal cache. Existing staging and caches are not copied
or automatically erased: migration identifies only disposable generated data.
Consistent SQLite backup and verification, tier coverage, unrelated-data backup
on degraded application snapshots, and independent transcript preservation from
[0009](0009-preserve-transcripts-independently-of-search-freshness.md) remain.

This supersedes the former Scratch-first persistent staging/cache behavior
described in the README, not the transcript preservation decision. Operations
and exact capacity limitations live in [backup-storage](../backup-storage.md).
