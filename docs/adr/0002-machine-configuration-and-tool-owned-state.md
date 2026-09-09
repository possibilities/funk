# 0002: Machine configuration and tool-owned state have separate owners

Status: Retrospective, recorded 2026-09-08 from the existing ownership contract.

Funk owns the machine's software, authored Stow configuration and guarded system
helpers. AgentStart owns the agent toolchain, generated integrations, installed
guidance and skill convergence; tool-owned writable state stays with its writer.
Funk calls that installer rather than growing another path. The alternative—
adopting whatever appears under a configuration directory—can publish stale
files, redirect another writer into Git, or track machine identity and secrets.

Keep target directories real where another writer needs them. Only proven,
authored preference sources are exceptions, as described in the
[current procedures](../configuration.md). This costs explicit owner checks and
some separately generated local files; a fresh installation still converges
through the owning helpers. Changes crossing the boundary must be delivered
with AgentStart rather than hidden in a live machine edit.

Evidence: [root ownership rules](../../AGENTS.md#ai-tooling-and-skills),
[Stow implementation](../../libexec/stow-config), and the existing
Funk boundary decision (`agentwiki get funk-boundary`).
The wiki decision is the boundary authority; this record captures its local
configuration consequences, not a new assignment of ownership.
