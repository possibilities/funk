# Configuration procedures

Read the relevant section before changing its Stow package, application or
convergence helper. Root [ownership constraints](../AGENTS.md) apply throughout;
the [decision log](adr/README.md) explains configuration and theme ownership.
Paths below are relative to the repository root unless explicitly absolute.

## Terminal theme and local picker

- Managed configuration carries no raw palette: no hard-coded named color or
  hex literal, and no generated palette. Colors are named once, by
  `theme = ` in `ghostty/.config/ghostty/config`, and every other layer
  follows the terminal that results. Tmux's
  `tmux/.config/tmux/conf.d/theme.conf` styles the status bar against that
  palette using only ANSI indices (`colour0-15`) plus `default`.
  `tests/validate.sh` pins that theme line's presence, the named-color and hex
  bans, the tmux file's existence, and its confinement to the ANSI range, so a
  future theme cleanup cannot sweep the status bar away again the way `24663c1`
  did. Theme *files* still never live here: the Ghostty cask installs all of
  them under the application's Resources, and Funk names one by string.
- Picking a theme and tracking one are separate steps, and the seam between
  them is deliberate. `ghostty-themes` — upstream's picker, cloned to
  `~/source/flyerAI2025--ghostty-themes` by `funk install-ghostty-themes` and reached through
  Funk's wrapper at `bin/.local/bin/ghostty-themes`, bound to
  `ctrl+cmd+shift-t` in skhd — browses the cask's themes and writes the pick
  into Ghostty's macOS Application Support config rather than the XDG one.
  Ghostty loads that file second, so a pick outranks the tracked line until
  someone promotes it by editing `theme = ` here and deleting the
  machine-local file. That override is a known footgun, accepted to keep the
  picker: nothing warns when the machine drifts from the checkout. The wrapper
  still exists to pin `GHOSTTY_CONFIG` at the machine-local path, because the
  picker rewrites its target with `mktemp` + `mv` — aimed at
  `~/.config/ghostty/config` it would replace that Stow link with a real file.
  `tests/validate.sh` pins the wrapper's pin.

## Stow packages and generated identity

| Package | Target | `--no-folding` |
| --- | --- | --- |
| `git` | `~/.config/git/` | yes |
| `ssh` | `~/.ssh/` | yes |
| `ghostty` | `~/.config/ghostty/` | yes |
| `nvim` | `~/.config/nvim/` | no |
| `skhd` | `~/.config/skhd/` | no |
| `tmux` | `~/.config/tmux/` | yes |
| `zsh` | `~/.zshenv`, `~/.zshrc`, `~/.zsh/` | yes |
| `yabai` | `~/.config/yabai/` | no |
| `karabiner` | `~/.config/karabiner/` | yes |
| `tmuxctl` | `~/.config/tmuxctl/` | yes |
| `bin` | `~/.local/bin/` | yes |
| `btop` | `~/.config/btop/` | no |
| `herdr` | `~/.config/herdr/` | yes |
| `claude` | `~/.claude/preferences.json` | yes |

A `--no-folding` package's target directory stays a real directory, so it can
hold files Funk does not track. That is the whole reason those rows are marked:
`~/.ssh/config.d` is written by `funk ssh-tailnet-config` and
`~/.config/git/config.local` by `funk git-identity`, and under normal folding
both generators would be writing straight back into this checkout.

Machine-identifying data is generated onto the machine at converge time, never
tracked and never adopted back. `home-awake --learn-network` records the home
router that way, `funk ssh-tailnet-config` records the tailnet that way, and
`funk git-identity` records the commit name and address that way; all three
write outside this repository, and none may be pulled back in with
`funk stow --adopt`.

The identity case is the one where getting the folding wrong is worst, and it
is worth understanding before touching the `git` package. A relative
`include.path` resolves against the directory of the *link* git opened, not the
file behind it — so a real `~/.config/git` puts `config.local` on the machine,
while a folded one puts the operator's name and address inside this working
tree. `tests/validate.sh` asserts both halves: no identity in the tracked file,
and a real directory to hold the untracked one.

## Unprivileged convergence helpers

`funk install-home-awake` follows the same rule. It compares the installed root
helper's digest and its granted sudo invocations first, and elevates only when
they differ from this checkout. It extends the rule to the login keychain by
probing the stored item attribute-only, without `-w`, so the lookup never
reaches the item's data and never raises a dialog, and by reporting the verdict
`home-awake` last recorded instead of reading the secret. The prompt belongs to
`home-awake --authorize`, which a human runs on purpose.

A step that cannot converge is reported rather than failed.
`funk ssh-tailnet-config` exits `EX_TEMPFAIL` when Tailscale cannot answer,
having written and removed nothing, and `./install` prints a Deferred note and
finishes.

Repair state that makes Homebrew elevate instead of letting it recur:
`libexec/reclaim-app-ownership` for applications left by a previous account,
and `libexec/repair-cask-artifacts` for Caskroom state left by an aborted
upgrade.

## Harness preferences and guidance

Personal Codex preferences are an authored-source exception, tracked in
`config/harnesses/codex.toml`. AgentStart's Codex shim copies that file into a
private native profile for each invocation and adds temporary cwd/project
trust; it owns the wrapper and its installation. The source is never Stowed
over the live config, and trust, credentials, generated integrations, and
session state never belong in it. See `config/harnesses/README.md`.

Personal Claude preferences are the corresponding Stow exception:
`claude/.claude/preferences.json` links to `~/.claude/preferences.json`.
AgentStart's managed Claude shim loads it with native `--settings` and records
workspace trust in local Claude state under Claude's config lock. Never adopt
`settings.json` or `.claude.json`: generated integrations, classifier state,
credentials, and project history stay local. The package uses `--no-folding`
so Claude's config directory remains outside this checkout.

Every operator guidance file the harnesses read is AgentStart's, linked by its
installer rather than stowed here. AgentStart's `scripts/install.sh`
owns the canonical empty guidance in its fixed resource set and the
`~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` links, plus the extension prompts
at `~/.config/agentguidance/`. Follow that installer contract for destinations. The retired operator-guidance and
AI-tool Stow packages must not be recreated beyond the authored Claude
preferences exception above — edit `~/code/agentstart/prompts/`
or `~/code/agentstart/config/` instead.

## Configuration with another writer

Configuration another program writes is overlaid, never adopted. The llm CLI
and its model configuration are AgentStart's (`config/llm/`, and the formula
left the Brewfile with them). Herdr's live `config.toml` is also AgentStart's:
`scripts/herdr-config` renders it from that checkout's tracked source, while
Funk's `herdr` package retains only the machine-owned `agent-mem.sh` helper.
Adopt a file only when Funk is its sole writer.

## Kiosk launcher applications

`funk install-kiosk-launchers` renders the AgentVoice and AgentChats transcript
applications into `~/Applications`. Their URLs are fixed resources inside the
ad-hoc-signed bundles. Chrome's windowed app mode removes browser chrome without
creating a full-screen macOS Space and reuses the normal Chrome process and
profile rather than cold-starting an isolated browser for each application. The
installer refuses to replace a bundle unless its identifier proves Funk owns
it, and both `./install` and the scheduled path converge the applications
without elevation.


## Process headroom warnings

`funk install-process-warning` installs `io.arthack.funk.warn-process-headroom`,
a login and five-minute launchd check. Normal `./install` converges it too.
The short-lived `/usr/bin/python3` checker calls macOS libproc and sysctl
directly; it has no subprocesses, inference, process termination or service
restart actions. It counts both user and system capacity and records the ten
largest parent groups without command arguments or environment variables.

Warnings begin at 300 free slots, become critical at 150, and repeat at most
every 30 minutes unless severity increases. Recovery at 400 slots rearms the
warning. These thresholds apply to whichever of the user and system limits has
less room. Five-minute sampling cannot catch every burst or guarantee launchd
can spawn the checker when the process table is already full.

Alerts use AgentNotify's documented local Unix socket, without launching the app
or a CLI. The app must already be running. If delivery fails, the exact request
is saved and retried on the next scheduled check; a healthy sample cancels an
unsent warning. Errors go to `~/Library/Logs/Funk/process-headroom.log`.
No notification is sent on healthy checks.

Private state is in `~/.local/state/funk/process-headroom/`: `latest.json` holds
the latest sample, `state.json` holds throttling/delivery state, and `resume.md`
is the notification's clickable handoff. Supply nonsecret investigation metadata
with `funk install-process-warning --context /absolute/context.json`; include
`cwd`, `session_id`, `resume_command`, evidence paths and any relevant pane IDs.
That file is copied to local `context.json` and preserved by later installations.
Never commit machine/session metadata. Optional `notify_socket` overrides the
default `~/.local/state/agentnotify/notify.sock` for accounts with custom state.
Opening the handoff does not execute its resume command. `--check` renders and
validates without loading a job or changing local state.

`python3 tests/process-headroom.py` exercises synthetic pressure, throttling,
escalation, recovery, delivery failure/idempotency, the socket wire format and
the five-minute plist, without spawning tool inventories or sending real alerts.
