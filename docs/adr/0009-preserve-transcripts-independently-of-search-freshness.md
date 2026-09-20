# 0009: Preserve transcripts independently of search freshness

Accepted 2026-09-20.

`transcript-vault` preserves Claude transcripts by copying the live store into
the additive Scratch archive. The hourly onsite Restic backup invokes that
helper before taking its comprehensive snapshot. It formerly also ran the
legacy `agentchats index --json` command synchronously. A changed large active
transcript could make that derived-index pass expensive enough to delay archive
copying and the Restic run, even though neither operation depends on search.

Funk now performs no AgentChats indexing from `transcript-vault`. Each vault
run reports `index deferred: legacy ingest disabled pending bounded runner` and
states that preservation does not establish search freshness. Archive copying
remains additive, and an archive or application-snapshot warning remains
independent from the Restic attempt as before.

AgentChats owns its bounded ingest runner and freshness reporting. A future
automated trigger must have one generated owner, resource budgets and an
explicit cross-repository decision; Funk must not restore a synchronous legacy
indexing path to make a successful backup look like a fresh search index.
