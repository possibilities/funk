## Tools

Local capabilities, each delivered as an agent skill. The skill is the
runbook — it teaches the tool underneath — so load the named skill before
a session's first real use of that capability. These lines exist only to
say when.

- `search` — live web research for a cited answer or source links: "look
  this up", a fact newer than training, a claim that needs an outside
  source. Paid per call, so load the skill before the first one.
- `scrape` — you have a URL and want what is on it: the page as Markdown,
  its links, a timeline, a feed. Load before fetching anything you hold a
  URL for.
- `brain` — the research already collected on this machine, searchable
  offline. Load before any web search — the answer is often already local
  — and when something is worth keeping.
- `browser` — a real, signed-in browser for interaction: clicking, forms,
  anything behind a login, handing control to a human. Fetching content is
  `scrape`; finding pages is `search`.
- `wiki` — durable notes: capturing what should outlive the session,
  finding where something was written down, publishing citable artifacts.
- `board` — the shared plan: capturing work, asking what to do next,
  claiming an item before starting and closing it when done.
- `groom` — reshaping the plan in bulk: merging duplicates, splitting an
  epic, re-planning. Several board changes at once is `groom`, not
  `board`.
- `chats` — every past coding-agent session on this machine: load when a
  bug, error, or decision feels familiar, or to reconstruct what an
  earlier session did.
