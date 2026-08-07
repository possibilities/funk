## Tools

Bespoke local CLIs, all on PATH, built for agents. Run `<tool> --agent-help`
before a session's first real use of one — it is the agent runbook: when to
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
