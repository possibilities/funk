# Decision log

| Record | Status | Scope |
| --- | --- | --- |
| [0002: Machine configuration and tool-owned state](0002-machine-configuration-and-tool-owned-state.md) | Retrospective | Local consequences of the existing Funk/AgentStart boundary. |
| [0003: Tracked theme with local picker override](0003-tracked-theme-with-local-picker-override.md) | Retrospective | One tracked named theme; accepted local override and symlink protection. |
| [0004: Kiosk persistence lifecycle and instance identity](0004-kiosk-persistence-lifecycle-and-instance-identity.md) | Superseded by 0007 | Historical WebKit launcher persistence contract. |
| [0005: Square kiosk windows](0005-square-kiosk-windows.md) | Superseded by 0007 | Historical native kiosk-window behavior. |
| [0006: Retire the AgentChats web launcher](0006-retire-agentchats-web-launcher.md) | Superseded by 0007 | Historical partial kiosk retirement. |
| [0007: Retire local web kiosk launchers](0007-retire-local-web-kiosk-launchers.md) | Accepted | Retire the remaining wrappers with exact-owner cleanup. |
| [0008: Explicit home firewall posture](0008-explicit-home-firewall-posture.md) | Accepted | Keep travel as the boot default and allow trusted LAN traffic only after a manual action. |
| [0009: Preserve transcripts independently of search freshness](0009-preserve-transcripts-independently-of-search-freshness.md) | Accepted | Keep archive copying and Restic independent from derived AgentChats indexing. |

The initial records were captured on 2026-09-08 from existing constraints. Current
procedures live in [configuration guidance](../configuration.md).

Identifier `0001` already appears in Orca-update and boot-hardening records
in Git history. These new records use fresh identifiers; this index does not
assert that those earlier mechanisms remain current. Do not reuse a historical
identifier for an unrelated choice.
