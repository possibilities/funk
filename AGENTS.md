# Funk agent guidance

## Repository context

- `/Users/arthack/code/funk` is the canonical Funk repository and
  `/Users/arthack` is the target account's home. In a worktree, treat that
  worktree's root as the repository path.
- `/Users/mike/code/dotfiles` is the long-lived setup repository from the old
  account. Use it as reference material and migrate useful ideas selectively;
  preserve Funk's narrower goals and safety constraints.
- Migrate credentials or authenticated CLI configuration only when needed.
  Copy the minimum required files, preserve restrictive permissions, and never
  print, inspect unnecessarily, or commit secret values.

## Fix-forward configuration

Every durable system change belongs in this repository. A fresh account should
converge by running `./install`; do not rely on one-off live configuration.

- Add software to `Brewfile` and install it through Funk.
- Add user configuration to the appropriate GNU Stow package, edit the source
  here rather than its live path under `$HOME`, and run `funk stow`.
- Use `funk stow --check` before risky changes. Use
  `funk stow --adopt <package>` only to migrate an intentional existing config,
  then review the Git diff because adoption changes repository files.
- For a new package, register it in `libexec/stow-config`, document its target
  and folding mode in `README.md`, and test the forward installation path.
- Add user-level macOS preferences to `libexec/configure-macos`; route
  privileged machine settings through the guarded system helpers.
- Preserve common Emacs/readline movement, history, cutting, and yanking
  bindings when changing shell or terminal input behavior.
- Reload affected applications after changing live configuration when
  possible: source tmux's config and restart Yabai/skhd services. Karabiner
  reloads its configuration automatically.

The `ssh`, `ghostty`, `tmux`, `zsh`, `karabiner`, `tmuxctl`, `bin`, and `llm`
packages use `--no-folding` so their target directories remain available for
generated or unmanaged files. Other packages may use normal Stow folding.

Never Stow credentials, secrets, generated application state, remote-device
configuration, root-owned helpers, LaunchDaemons, or rendered LaunchAgents.
Install privileged files through Funk's guarded helpers; never link a root
execution path into this user-writable checkout.

An unattended agent that needs root gets a purpose-built helper, not a
passwordless rule on a general-purpose system binary. `system/funk-home-awake`
is the model: sudoers names that helper with an enumerated argument list, and
the helper validates every argument before touching `pmset` or `sysadminctl`.
`tests/validate.sh` pins the granted list, so widening it is a deliberate,
reviewable change rather than a side effect.

## Unprivileged convergence

A default `./install` must not ask for a password once the machine has
converged. Two rules keep that true, and both are asserted by
`tests/validate.sh`:

- The scheduled `funk update` path never elevates. Anything needing
  administrator authentication is identified by `libexec/list-unattendable-casks`
  and skipped through `HOMEBREW_BUNDLE_CASK_SKIP`, then reported, rather than
  attempted and failed.
- A privileged step runs only when it would actually change something. Compare
  the installed state first, as `libexec/install-window-manager` does before
  invoking `system/install-yabai-root`, and skip the step when it already
  matches.

`funk install-home-awake` follows the same rule. It compares the installed root
helper's digest and its granted sudo invocations first, and elevates only when
they differ from this checkout.

Repair state that makes Homebrew elevate instead of letting it recur:
`libexec/reclaim-app-ownership` for applications left by a previous account,
and `libexec/repair-cask-artifacts` for Caskroom state left by an aborted
upgrade.

## AI tooling and skills

Funk is the sole owner of AI-stack installation. Keep desktop applications,
command-line agents, and globally managed skills on the single
`libexec/install-ai-tools` path; do not create another installer or
synchronization path in `~/code/arthack`.

The Stow-linked home guidance (`agents/AGENTS.md`, at `~/AGENTS.md`) stays
deliberately empty: global advice belongs in the Art Hack extension prompts,
rendered into the `hack` skill, not in a file loaded into every session.
`libexec/install-ai-tools` still links `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md` at that file so future guidance has a delivery path, and
refuses to replace an independent non-symlink file at either location.

Funk's repository guidance lives in this `AGENTS.md`, not in a priming skill.
Do not install or synchronize a separate `funk` skill. `~/code/arthack`
remains the source of truth for the personal `hack`, `resource-create`, and
`resource-update` skills, each of which the Funk installer must refresh
completely, including `agents/openai.yaml`, in all configured global agent skill
locations.

The extension prompts those skills render against are Funk's, not Art Hack's:
the `arthack` package owns `~/.config/arthack/`. Edit
`arthack/.config/arthack/` here and run `funk stow`, so a fresh account renders
the same skills this one does. Their recognized names — `SYSTEM.md`,
`GUIDELINES.md`, `TOOLS.md` — are Art Hack's contract; an unrecognized file
renders to nothing.

Configuration another program writes is overlaid, never adopted. Orca rewrites
every agent CLI's hook configuration on launch, so those files stay out of Stow
and `funk configure-orca` reconciles only the keys Funk owns. Adopt a file only
when Funk is its sole writer.

Prove a configuration file is read before adopting it. A directory under
`~/.config` named for a program is not evidence that the program loads it —
programs move their configuration into the checkout and leave the old files
behind. Find the code path that reads the file, or leave it where it is;
adopting a retired file publishes dead configuration as live.

After changing AI tooling or skill installation, run:

```sh
libexec/install-ai-tools
```

Then compare the installed `hack` manifest with its Art Hack source manifest.
Do not substitute a manual copy or a second helper for this convergence check.
