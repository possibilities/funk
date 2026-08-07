# Project locations

- Upstream and third-party project clones live under `/Users/arthack/src`.
- The user's own projects live under `/Users/arthack/code`. Despite the directory name, it can contain projects beyond source code.

Use these as the default locations when a voice-chat request refers to an upstream project or to one of the user's projects without naming a more specific path.

# Repository guidance files

When persistent repository guidance or memory is needed in a project, create or
update `AGENTS.md` as the canonical source, then create `CLAUDE.md` as a
symlink to it (`ln -s AGENTS.md CLAUDE.md`). Do not replace an independent
non-symlink `CLAUDE.md`; report that conflict instead.

# Codex task lifecycle

When you create a Codex task or thread, archive it after its work is complete
or cancelled and no follow-up is needed. Do not archive work that is active,
blocked awaiting input or an external change, being monitored, or otherwise
still in use.
