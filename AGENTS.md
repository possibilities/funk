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

The `ssh`, `ghostty`, `tmux`, `zsh`, `karabiner`, `tmuxctl`, and `bin`
packages use `--no-folding` so their target directories remain available
for generated or unmanaged files. Other packages may use normal Stow
folding.

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

## Validation

`tests/validate.sh` is the whole suite and runs anywhere, but it does not run
*everything* everywhere. The checks that need macOS to mean anything — the
`pfctl` parse of the travel firewall, Gatekeeper quarantine xattrs, the
Homebrew cask helpers that read ownership with BSD `stat -f`, the `funk update`
path through the Darwin-gated `libexec/install-orca`, and the home-awake and
Android launcher suites — skip themselves off Darwin and print what they
skipped, and the summary line repeats the list. Everything else is portable:
the policy greps, `bash -n` over every shell file, shellcheck, and the launchd
plist assertions, which read through `tests/lib/plist` (stdlib `plistlib`)
rather than PlistBuddy and plutil.

CI runs the portable half on Ubuntu, so a green run there is not a claim that
the macOS-only checks passed — only that nothing portable regressed. **Run
`tests/validate.sh` on the machine before landing anything that touches the
guarded halves**; that run is the one where the skip list is empty.

shellcheck runs at `--severity=warning`, and that floor is deliberate rather
than lazy. The style tier disagrees between releases — 0.9.0 raises SC2015 on
assertions 0.11.0 will not emit even when asked for SC2015 by name — so
enforcing it means pinning a version, and the pinned release binary needs
roughly 3.7GB of RSS whether it is handed all 76 files or one five-line
fixture. That was tried and reverted. Fix what errors and warnings find; do not
raise the floor back to style without solving the memory cost first.

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

Funk no longer owns AI-toolchain installation; `~/code/agentdots` does. The
boundary rubric lives in the wiki (`agentwiki get funk-boundary`):
anything depended on by or deeply related to the agent* fleet — harness CLIs,
pinned npm globals, MCP registration, guidance links, extension prompts, and
every globally managed skill — belongs in Agentdots, and the machine itself —
Homebrew, Stow, launchd, macOS settings, account migration — stays here.

Concretely, Funk keeps the AI *desktop applications* (the claude and chatgpt
casks, converged from `./install`, and the Orca cask, installed once by
`libexec/install-orca` and then left to its own updater) plus the `gh`
credential migration. `./install` then calls
`~/code/agentdots/scripts/install.sh --install` and refuses to finish if that
checkout is missing; the scheduled updater calls
`~/code/agentdots/scripts/sync-skills` the same way. Do not grow a second
installer or skill-synchronization path in this repository — a new AI tool,
skill, or harness configuration belongs in Agentdots.

Every operator guidance file the harnesses and the voice orchestrator read
is Agentdots', linked by its installer rather than stowed here: the
deliberately empty `~/AGENTS.md` (with `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md` linked at it), the extension prompts at
`~/.config/agentguidance/`, and the AgentVoice doctrine at
`~/.config/agentvoice/`. The `agents`, `arthack`, `agentvoice`, `llm`, and
`orca` Stow packages are all gone; do not recreate one — edit
`~/code/agentdots/prompts/` or `~/code/agentdots/config/` instead.

Funk's repository guidance lives in this `AGENTS.md`, not in a priming skill.
Do not install or synchronize a separate `funk` skill.

Configuration another program writes is overlaid, never adopted. Orca rewrites
every agent CLI's hook configuration on launch, so those files stay out of
Stow entirely; `funk configure-orca` — now a delegation to Agentdots'
`scripts/configure-orca`, which owns the overlay at `config/orca/` — merges
only the keys the overlay names. The llm CLI and its model configuration are
likewise Agentdots' (`config/llm/`, and the formula left the Brewfile with
them). Adopt a file only when Funk is its sole writer.

Prove a configuration file is read before adopting it. A directory under
`~/.config` named for a program is not evidence that the program loads it —
programs move their configuration into the checkout and leave the old files
behind. Find the code path that reads the file, or leave it where it is;
adopting a retired file publishes dead configuration as live.

After changing the AI application or migration steps here, or anything in the
Agentdots-owned toolchain, run:

```sh
~/code/agentdots/scripts/install.sh --install
```

Then compare the installed `collab` manifest with its agentguidance source
template.
Do not substitute a manual copy or a second helper for this convergence check.
