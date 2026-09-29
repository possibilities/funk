# Decision log

| Record | Status | Scope |
| --- | --- | --- |
| [0002: Machine configuration and tool-owned state](0002-machine-configuration-and-tool-owned-state.md) | Retrospective | Local consequences of the existing Funk/AgentStart boundary. |
| [0003: Tracked theme with local picker override](0003-tracked-theme-with-local-picker-override.md) | Retrospective | One tracked named theme; accepted local override and symlink protection. |
| [0004: Kiosk persistence lifecycle and instance identity](0004-kiosk-persistence-lifecycle-and-instance-identity.md) | Superseded | Replaced by wrapper retirement in 0007; no Funk kiosk launchers remain. |
| [0005: Square kiosk windows](0005-square-kiosk-windows.md) | Superseded | Replaced by wrapper retirement in 0007; no Funk kiosk launchers remain. |
| [0006: Retire the AgentChats web launcher](0006-retire-agentchats-web-launcher.md) | Accepted | AgentVoice owns transcript UI; the AgentChats terminal picker and indexing remain. |
| [0007: Retire the agent-app kiosk wrappers](0007-retire-agent-app-kiosk-wrappers.md) | Accepted | Remove Funk-owned AgentHUD and AgentVoice WebKit wrappers; keep direct browser URLs. |

The initial records were captured on 2026-09-08 from existing constraints. Current
procedures live in [configuration guidance](../configuration.md).

Identifier `0001` already appears in Orca-update and boot-hardening records
in Git history. These new records use fresh identifiers; this index does not
assert that those earlier mechanisms remain current. Do not reuse a historical
identifier for an unrelated choice.
