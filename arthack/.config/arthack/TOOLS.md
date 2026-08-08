## Tools

Bespoke local CLIs, all on PATH, built for agents — plus one adopted
third-party tool, flagged below. Run `<tool> --agent-help` before a
session's first real use of a bespoke one — it is the agent runbook: when to
reach for the tool and how to use it well. `--help` stays the reference for
exact flags. All emit structured output (`--json` or an envelope).

- `agentsearch` — paid, grounded web research: `ask` when you want the answer
  (hand it the whole dense question; it decomposes internally), `find` when
  you want the links (short keywords, one concept per call).
- `agentscrape` — the fetch-a-specific-URL tool: turns pages into Markdown,
  link lists, and feed inventories, auto-attaching a signed-in session when
  one exists; prefer it over curl whenever a page's content is the goal.
- `agentbrain` — Durable local research index: `context` or `search`
  before reaching for the web — the answer is often already here — and
  `submit` anything worth keeping (indexing is async, not instant).
- `agentweb` — the browser control plane for authorized, signed-in browser
  work: it holds origin rules and the sessions a human established; attach a
  session or ask the human to run `agentweb signin`.
- `agentwiki` — the document vault: capture snippets and full documents as
  plain markdown, search and link them, publish immutable versioned artifacts.
  Take `path <ref>` and edit the file directly rather than round-tripping
  content through the CLI; refs accept spoken phrases, and `resolve` ranks
  the candidates when a phrase is ambiguous.
- `agentboard` — the planning board: capture work at any granularity, `ready`
  for what is unblocked, `claim` before starting, `done` when finished. Speak
  labels, never ids; bulk reshaping goes through `groom export`/`apply`, and
  `render --publish` snapshots the board into agentwiki.
- `cass` (third-party) — search every past coding-agent session on this
  machine: Claude Code, Codex, Pi, and twenty more. Reach for it whenever a
  bug, error message, or decision feels familiar — the answer is often in an
  old session. No `--agent-help`: load the `chats` skill before first use —
  it is the runbook — and never run bare `cass` (it opens a blocking TUI);
  always pass `--robot`.
