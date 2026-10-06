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

The OBS Virtual Camera approval follows the same report-without-forcing rule.
OBS ships its signed camera system extension inside the cask, while macOS owns
the enabled state in its protected system-extension database. The approval is
durable across launches and same-identity upgrades, keyed by OBS's Team ID and
extension bundle ID, but neither Stow nor `defaults` can set it and
`systemextensionsctl` exposes no enable operation. `funk verify-obs-camera`
checks that the expected signed identity is activated and enabled. `./install`
and the scheduled update path report the exact operator-owned Settings step
when it is absent or waiting; they never open Settings or modify the protected
database unattended.

Repair state that makes Homebrew elevate instead of letting it recur:
`libexec/reclaim-app-ownership` for applications left by a previous account,
and `libexec/repair-cask-artifacts` for Caskroom state left by an aborted
upgrade.

## Firewall postures

`funk install-hardening` installs the root-owned helper and boot service. Boot
always applies `travel`, which blocks unsolicited inbound traffic on every
physical interface while preserving loopback, outbound state, and Tailscale.

At home, the operator may explicitly run `funk harden home`. That posture adds
one IPv4 exception on `en6` for `192.168.50.0/24`, immediately before `en6`'s
quick inbound block; every unrelated physical interface keeps the travel
rules. The helper does not identify the network or switch posture on its own,
and it refuses `home` if the trusted interface is unavailable or the fixed
policy fails validation.

`funk harden status` reports the selected posture, trusted interface and
subnet, and the effective rule shape for every physical interface. Run
`funk harden travel` to restore the exact boot posture.

## Harness preferences and guidance

Personal Codex preferences are an authored-source exception, tracked in
`config/harnesses/codex.toml`. AgentStart's optional Codex invocation helper copies that file into a
private native profile for each invocation and adds temporary cwd/project
trust; it owns the helper and its installation. Bare permission shims do not
load these preferences. The source is never Stowed
over the live config, and trust, credentials, generated integrations, and
session state never belong in it. See `config/harnesses/README.md`.

Personal Claude preferences are the corresponding Stow exception:
`claude/.claude/preferences.json` links to `~/.claude/preferences.json`.
AgentStart's optional Claude invocation helper loads it with native `--settings` and records
workspace trust in local Claude state under Claude's config lock. Never adopt
`settings.json` or `.claude.json`: generated integrations, classifier state,
credentials, and project history stay local. The package uses `--no-folding`
so Claude's config directory remains outside this checkout.

Every operator guidance file the harnesses read is AgentStart's, linked by its
installer rather than stowed here. AgentStart's `scripts/install.sh`
owns the canonical empty guidance in its fixed resource set and the
`~/.claude/AGENTS.md` / `~/.codex/AGENTS.md` links, plus the extension prompts
at `~/.config/agentguidance/`. Follow that installer contract for destinations. The retired operator-guidance and
AI-tool Stow packages must not be recreated beyond the authored Claude
preferences exception above — edit `~/code/agentstart/prompts/`
or `~/code/agentstart/config/` instead.

## Configuration with another writer

Configuration another program writes is overlaid, never adopted. The llm CLI
and its model configuration are AgentStart's (`config/llm/`, and the formula
left the Brewfile with them). Adopt a file only when Funk is its sole writer.

## Omajot TUI and Android PWA

The `Brewfile` installs `renerocksai/tap/omajot`. Run `omajot tui` on the Mac;
Android uses the same hub's installable web app (PWA). A desktop browser is
optional, not a separate setup requirement. `./install` runs
`funk install-omajot`, which renders the owned `io.arthack.funk.omajot-hub`
LaunchAgent and starts the hub at login. `funk install-omajot --check` validates
the identity, client configuration and route plan without changing anything.
Converged runs preserve the running hub and do not restart an active TUI.

The hub listens only on `127.0.0.1:8799` and checks `Tailscale-User-Login` on
every API request. Tailscale Serve supplies that identity and HTTPS on dedicated
port **8448**; this endpoint must never have Funnel enabled. The installer
derives the machine's DNS name and user login from the signed-in Tailscale
profile, never tracked account/hostname values. It refuses a foreign listener,
extra handler, raw TCP forward, alternate proxy to the hub, or Funnel grant
rather than replacing it. Unrelated routes and their Funnel settings remain
unchanged. There is no `--no-auth` fallback if identity or routes are unavailable.
Before publishing, the installer verifies that the actual loopback API rejects
unauthenticated requests with 403.

On Android, connect Tailscale to the same account, open the generated HTTPS URL
(`omajot qr` prints it), then install Omajot from Chrome's menu. Keep Chrome's
site storage: it contains the offline replica. Reading and editing can work
offline after the initial load; changes synchronize when the app is running
and the Mac hub is reachable. The Mac must be awake and logged in to sync.
Use one Omajot window per phone; close its ordinary browser tab after installing
the PWA. If a leftover window owns the replica, the app offers **Use here**.
Phone installation is an explicitly leased operation, not an ADB side effect
of `./install`. Never create another hub or reset notes to add a phone.

The hub keeps `batches.jsonl` and `blobs/` in `~/omajot-data`, and its log is
`~/Library/Logs/Funk/omajot-hub.log`. The CLI's separate replica is in
`~/.local/share/omajot`. These are intentionally different storage formats, not
two independent notebooks: `funk install-omajot` overlays the generated HTTPS
`hub` URL and `hub_login` in `${XDG_CONFIG_HOME:-~/.config}/omajot/config.json`,
so the CLI/TUI replica and every web replica synchronize through the same hub.
The upstream reader is
`src/daemon/paths.zig` (`configPath`, `readConfig`, `resolve`), shared by the
daemon and note commands. Other configuration fields are preserved; symlinked
configuration, a different hub URL or a different configured identity are
refused rather than adopted or overwritten. Only Funk's retired local URLs
may migrate automatically. Quit the TUI and explicitly stop its background
daemon and owned hub before the first authenticated installation; preserve
both stores and reconnect the existing replica afterward. Direct loopback
API requests then fail by design, so the TUI's daemon must use the HTTPS URL.
Do not retain an unauthenticated desktop alias.

Both data directories are Restic roots. Normal installation preserves content;
the operator-requested fresh start is not repeated on convergence. Before a
reset, close every TUI/web client, stop the exact owned hub and background
daemon, and retain a verified private recovery copy of both stores. Reset both
stores together, never point the hub at the CLI's different-format directory.
A browser also owns an IndexedDB replica: either clear only Omajot's old origin
or use a genuinely fresh local origin. Otherwise old queued changes can return,
or a cursor ahead of the reset hub can leave it in conflict. Verify a CLI-created
note in the web app and a web edit in the CLI, then leave the requested empty
workspace after removing verification content and resetting all test replicas.
These are application-owned state, not Stow packages;
any future Tailscale login or hostname configuration must remain machine-local.

## Retired Obsidian LiveSync and on-demand GitHub snapshots

LiveSync was retired in favour of Omajot. Neither
`./install` nor the scheduled path installs its plugin, CouchDB, or a sync
endpoint. The desktop Obsidian application and `~/obsidian/work` remain available
as source material until migration is separately requested.

For an existing installation, close Obsidian and stop the user CouchDB service
before taking a verified private backup of the entire vault (including hidden
files and Git history), Obsidian application state, CouchDB data, generated
configuration and local credentials. Only then remove the `obsidian-livesync`
entry from `community-plugins.json` and its manifest-verified plugin directory.
Remove only the HTTPS 8448 Serve route whose `/` handler is
`http://127.0.0.1:5984`, never reset Serve or alter unrelated routes. Remove the
generated override only when its first line is
`; Funk Obsidian LiveSync (generated; do not commit)`, uninstall the dedicated
CouchDB formula, and remove its backed-up data and
`~/Library/Application Support/Funk/obsidian-livesync`. Preserve notes, the
private GitHub repository, and unrelated Obsidian plugins/application state.

Android removal targets the verified `md.obsidian` package through an explicitly
selected ADB serial. Uninstall without `-k` so app-private data is removed;
shared-storage documents are not a reason to delete arbitrary phone directories.

GitHub snapshots are **never scheduled**. Initialise Git in the vault and set
`origin` to the dedicated private `possibilities/obsidian-work` repository,
then run `funk obsidian-push` whenever a snapshot is wanted. It stages only
Markdown, canvas files, common media and `.gitignore`; it refuses a non-private
destination, hidden paths, unexpected tracked files, or symlinks. Obsidian's
`.obsidian` and plugin state are not published. Review the prospective tracked
files before the first push. The vault and its Git history are app/user-owned,
not Stow packages; the Funk helper is the durable policy.

## Retired local web wrappers

AgentChats' search CLI and terminal resume picker remain available, but Funk
now installs no local WebKit or Chrome kiosk launcher. Use the direct services
in a normal browser: `https://agenthud.localhost/`,
`https://agentvoice.localhost/`, and `https://agentvoice-test.localhost`.

`./install` and the scheduled path run a private retirement helper for existing
installations. It removes only `~/Applications/AgentHUD.app`,
`~/Applications/AgentVoice Transcripts.app`, and
`~/Applications/AgentVoice TEST Transcripts.app` when their exact
`CFBundleIdentifier` values prove they are Funk's former bundles. It unregisters
those bundles when possible and reconciles only a matching old Funk transaction
remnant. A foreign bundle, symlink, malformed transaction, native
`~/Applications/AgentVoice.app`, all WebKit data, and the dedicated Chrome
profile are preserved. The retired Raycast launcher is removed only when its
Stow symlink resolves to the exact former script path in the running Funk
checkout.


## Comprehensive backup resource bounds

The hourly `io.arthack.funk.backup-onsite` LaunchAgent sets `GOMAXPROCS=2` for
its process tree. Restic otherwise uses every CPU core available to the Go
runtime; it also sizes tree-saving, blob-upload and index-loading worker pools
from that value. Two cores keep the comprehensive 48-root traversal, hashing,
compression, encryption, repository locking and verification behavior intact
while bounding its CPU concurrency. The existing `ProcessType=Background` and
`LowPriorityIO=true` settings continue to lower scheduling and I/O priority.

This is a concurrency bound rather than a hard memory limit. Restic documents
that a lower `GOMAXPROCS` can reduce memory use, but repository indexes and
buffers still determine the resident set. A hard memory ceiling could kill a
valid backup before it publishes a complete snapshot, so the LaunchAgent does
not set one. The daily offsite job is unchanged because this bound responds to
the high-frequency, broad onsite workload.

After changing the bound, run `funk install-backups`; the guarded installer
renders and reloads the owned LaunchAgent. Confirm the live value with:

```sh
launchctl print gui/$(id -u)/io.arthack.funk.backup-onsite
```

The wrapper's per-tier lock still rejects a concurrent manual invocation, and
launchd never starts a second instance of an already-running job. Long SQLite
staging before the `starting onsite Restic backup` log line is separate from
Restic resource use; the largest current staged database can dominate total
wall time even when the Restic phase remains bounded.

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
