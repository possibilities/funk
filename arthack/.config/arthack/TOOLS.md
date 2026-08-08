## Tools

Bespoke local CLIs, all on PATH, built for agents — plus one adopted
third-party tool, flagged below. Every tool's runbook is its agent skill:
load the named skill before a session's first real use of that tool.
`--help` stays the reference for exact flags, and `--agent-help` remains as
the in-binary fallback when a skill is unavailable. All emit structured
output (`--json` or an envelope).

- `agentsearch` — paid, grounded web research: `ask` for synthesized, cited
  answers, `find` for links. Skill: `search`.
- `agentscrape` — turn a specific URL into Markdown, link lists, or feed
  entries; prefer it over curl whenever a page's content is the goal.
  Skill: `scrape`.
- `agentbrain` — durable local research index; check it before reaching for
  the web — the answer is often already here. Skill: `brain`.
- `agentweb` — the browser control plane for authorized, signed-in browser
  work; sessions are established by a human (`agentweb signin`).
  Skill: `browser`.
- `agentwiki` — the document vault: durable markdown, links, immutable
  published artifacts. Skill: `wiki`.
- `agentboard` — the shared planning board: `ready`, `claim`, `done`; speak
  labels, never ids. Skills: `board`, and `groom` for bulk reshaping.
- `cass` (third-party) — search every past coding-agent session on this
  machine; reach for it when a bug, error, or decision feels familiar.
  Never run bare `cass` (blocking TUI) — subcommand + `--robot`.
  Skill: `chats`.
