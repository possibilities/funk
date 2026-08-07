# Funk

Funk is Arthack's reproducible macOS setup and the successor to the old
dotfiles repository. It keeps Funk's narrower security model while carrying
forward the old repository's Stow-based, fix-forward configuration workflow.

## What it installs

The default installer applies the Brewfile plus the vendor-supported AI tool
installers:

- Tailscale, AltTab, Ghostty, Google Chrome, Chrome Canary, Brave, Firefox
- ChatGPT, Claude Desktop, Orca, Obsidian, Raycast
- GitHub CLI, Native SDK CLI (pinned to 0.7), Zig, Claude Code,
  Codex CLI, OpenCode, and Pi
- The AgentVoice desktop application, installed by AgentVoice's own
  `app:install` contract from `~/code/agentvoice`
- Orca CLI, orchestration, computer-use, skill-discovery, frontend design,
  web-design review, React engineering, Vercel AI SDK, AI Elements, shadcn,
  Native SDK discovery, and the Hack agent skill
- Yabai, skhd, and the narrowly justified Karabiner-Elements layer
- Git Delta, Neovim, tmux, Starship, btop, GNU Stow, and supporting
  shell/development tools, including `terminal-notifier`

`libexec/install-ai-tools` uses the official shell installers for
[Claude Code](https://code.claude.com/docs/en/terminal-guide),
[Codex CLI](https://github.com/openai/codex#installing-and-running-codex-cli),
[OpenCode](https://opencode.ai/docs/), and [Pi](https://pi.dev/docs/latest).
ChatGPT and Claude Desktop use their Homebrew casks because their normal
personal macOS downloads do not provide unattended installer commands. Orca
uses the cask documented by the [Orca project](https://github.com/stablyai/orca).
Run `libexec/install-ai-tools --check` to inspect the exact plan without making
changes.

### AgentVoice desktop application

`libexec/install-ai-tools` finishes by installing the AgentVoice desktop
application. Funk owns only the prerequisites and the call: it converges Zig
from the Brewfile, pins the Native SDK CLI to the `0.7` line AgentVoice
requires, verifies the installed Zig is 0.16 or newer, and then runs
`libexec/install-agentvoice-app`, which invokes `bun run --cwd
"$HOME/code/agentvoice" app:install`. AgentVoice owns packaging, transactional
bundle replacement into `~/Applications`, launching in production mode, and
readiness verification; Funk never reproduces that logic.

The step needs a local AgentVoice checkout at `~/code/agentvoice`. If it fails,
`./install` stops with the AgentVoice exit status and the setup is not reported
as successful. To recover, fix what the message names — a missing checkout
(`git clone` it), a missing or stale toolchain (`brew install zig` or
`brew upgrade zig`), a running application (see below), or an AgentVoice-side
build failure — then rerun either `./install` or
`libexec/install-agentvoice-app` alone.

Repeating the interactive setup is not a no-op on Funk's side: every run
delegates to AgentVoice again, and AgentVoice decides what happens. When the
installed application is not running it is safely replaced and relaunched. When
the installed copy **is** running, AgentVoice deliberately refuses rather than
swapping a live bundle, and its quit-and-rerun instruction and exit status
propagate straight through Funk, so the interactive run fails. Quit
AgentVoice.app and rerun.

The scheduled updater deliberately does not do this. `funk update` stays
skills-only through `libexec/install-agentvoice-skills`, so a background
LaunchAgent never rebuilds, replaces, or relaunches a running desktop app.

Homebrew formula and cask calls are install-or-upgrade operations. The
dedicated `libexec/install-orca` helper installs or greedily upgrades the Orca
cask, synchronizes `orca-cli`, `orchestration`, and `computer-use` globally for
Codex, Claude Code, OpenCode, and Pi, then verifies both the cask receipt and
the global skill records. Hermes is not part of this harness set.

After any Funk-managed cask pass, Funk reads Homebrew's cask metadata, requires
Gatekeeper's policy assessment to accept each app, and then removes only
`com.apple.quarantine`, recursively, from declared `.app` targets directly
under `/Applications` or the current user's `~/Applications`. It rejects
symlinks, non-app targets, path traversal, missing apps, assessment failures,
and targets in any other directory. It does not clear other extended
attributes, alter Gatekeeper policy, disable assessment, or touch arbitrary
downloads.

The AI installer also reproduces the globally managed agent skills with the
same `npx skills add` mechanism used by Orca's setup UI. For Codex, Claude Code,
OpenCode, and Pi, it installs:

- `orca-cli`, `orchestration`, and `computer-use` from Orca.
- `find-skills` from Vercel.
- `frontend-design` from Anthropic and `web-design-guidelines` from Vercel.
- `vercel-react-best-practices`, `ai-sdk`, and `ai-elements` from Vercel.
- The official `shadcn` skill, paired with shadcn's registry MCP server for
  Codex, Claude Code, and OpenCode.
- The `native-sdk` discovery skill from Vercel Labs Native. The globally
  installed Native CLI supplies its deeper, version-matched skills.

The shadcn skill provides Pi with its CLI workflow; Codex, Claude Code, and
OpenCode additionally get the official shadcn registry MCP server.

Finally, the installer synchronizes the locally authored `hack` skill from
`~/code/arthack` into the shared `~/.agents/skills` directory discovered by
Codex Desktop and the other agent skill locations. Funk's own agent guidance
lives in this repository's `AGENTS.md` instead of a priming skill. Funk is the
sole owner of AI-stack installation; Art Hack remains the source of Hack and
does not provide a second installer.

The installer also links the shared agent guidance file into each CLI's global
guidance location: `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` become
symlinks to the Stow-managed `~/AGENTS.md` (source: `agents/AGENTS.md`).
Claude Code reads only `CLAUDE.md`, and Codex skips empty guidance files, so
without these links the shared file is invisible to both CLIs outside sessions
started in the home directory itself. The installer refuses to replace an
independent non-symlink file at either location and verifies that each link
resolves to the shared file's content.

GitHub CLI is intentionally installed twice: once through the main Brewfile and
again by the AI tool installer. The latter preserves an existing login and can
adopt an old `/Users/mike/.config/gh/hosts.yml` only when no current host config
exists and the old file contains a portable token. Keyring-backed credentials
cannot be transferred by copying that file.

Karabiner owns Funk's low-level keyboard layer: global Cmd+1…8 becomes
F13…F20 and Cmd+9 becomes F12 for Yabai Space focus; Ctrl+1…9 becomes the
normal Cmd+number tab shortcut in Chrome, Chrome Canary, Brave, and Firefox;
Right Option+H/J/K/L becomes the arrow keys while preserving Shift; Caps Lock
becomes Escape; and left Command and left Option are swapped only on the
built-in keyboard.

skhd restores Ctrl+L as the address-bar shortcut in Funk's four browsers and
Cmd+Shift+V as a direct Raycast Clipboard History shortcut.

The default install also applies the personal macOS preferences retained from
the old dotfiles: dark mode, an empty auto-hidden Dock and menu bar, quiet UI,
hidden desktop items, column-view Finder, fast key repeat, Yabai-friendly
window and Space behavior, Raycast-friendly Spotlight shortcuts, Cmd+D as the
Raycast launcher with first-run onboarding dismissed, disabled AirPlay Receiver
and Handoff, disabled iCloud Desktop/Documents syncing, and the compact 12-hour
menu-bar clock. Run `funk configure-macos` to reapply them.

The old machine-wide settings are available through the explicit
`funk configure-system` command: it disables Spotlight indexing on all mounted
volumes, adds `serverperfmode=1` while preserving other NVRAM boot arguments,
disables SMB and removes the current user's Public Folder share, and sets AC
display sleep to five minutes. The obsolete Ctrl+F2/F3/F4 and screenshot
shortcut mutations remain omitted because Funk does not claim those keys.

## Stow-managed configuration

User-owned configuration is stored in GNU Stow packages and linked into the
target account. Funk owns the union of the useful packages from both projects:

| Package | Target | `--no-folding` |
| --- | --- | --- |
| `git` | `~/.config/git/` | no |
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
| `starship` | `~/.config/starship.toml` | no |
| `btop` | `~/.config/btop/` | no |
| `llm` | `~/Library/Application Support/io.datasette.llm/` | yes |
| `orca` | `~/.config/orca/settings.json` | no |
| `agents` | `~/AGENTS.md` | no |

Funk's current Yabai, skhd, and reviewed Karabiner configurations take
precedence where the two repositories overlapped. Privileged helpers,
LaunchAgents, generated application state, credentials, and remote Termux
configuration are intentionally not Stow-linked.

## Android device utilities

Funk installs `scrcpy` and Android Platform Tools. The `bin` package provides
Wireless ADB helpers for the phone named `Smolbird`. ADB traffic always uses
its fixed MagicDNS name `smolbird` by default. Local-LAN mDNS is used only to
read the rotating port advertised by the same already-paired Android device;
the discovered LAN address is never used as the ADB connection target.

macOS installs the Tailnet resolver as a resolver scoped to the Tailnet domain,
so it never answers a single-label query and `smolbird` alone does not resolve.
The helpers therefore complete a short name to its full MagicDNS name using the
suffix reported by `tailscale status --json` before handing it to `adb`.

Only the `android-platform-tools` cask puts `adb` on `PATH`. The Android
command line tools ship a second `adb` of a different version, and pointing
`PATH` at that one makes each client restart the other's server and drop every
wireless connection, so `ANDROID_HOME` names the SDK without adding its
`platform-tools` directory to `PATH`.

On the phone, open **Settings → Developer options → Wireless debugging**.
Choose **Pair device with pairing code**, ignore the displayed IP address, and
pass only its pairing port to `adb-wireless-pair PAIRING_PORT`. Enter the
temporary six-digit code at `adb`'s prompt so it is neither exposed in the
process list nor saved. Then return to the main Wireless debugging screen,
ignore its IP address, and run `adb-wireless-connect CONNECT_PORT` with that
screen's separate connection port.

A successful explicit connection remembers the non-secret Tailnet hostname,
Tailnet node identity, Android hardware identity, and connection port under
`~/.local/state/funk/`. Later calls keep both identities fixed and read a
passive Bonjour SRV snapshot for Android's rotating TLS-connect port. Service
records are filtered by the saved Android hardware serial before any port is
probed, and only matching ports are tested through the pinned Tailnet
hostname. Rotating-port selection never asks ADB to enumerate mDNS services.
Every connect, pair, and Raycast entry point exports the server-start policy
before invoking ADB: the isolated server on `tcp:localhost:5038` has mDNS
auto-connect disabled, so its multicast browser cannot connect to or query
unrelated paired devices, and `ADB_USB=0` prevents it from claiming macOS USB
interfaces from the user's normal ADB server on port 5037. Those settings are
inherited by `scrcpy`. Saved state is replaced only after ADB confirms both
identities. The Mac and phone must share a LAN for a rotated port to be
discovered; a still-current saved port remains usable elsewhere.

Pairing is never started by the connect helper. Existing state from an older
Funk version is upgraded only when its saved Tailnet port still reaches the
phone. If that legacy port has already rotated, run
`adb-wireless-connect CONNECT_PORT` once with Smolbird's current main Wireless
debugging port to bind both identities. Unbound or ambiguous services are
refused rather than guessed, and unrelated services are never selected as the
Tailnet target. An unexpected Android identity is disconnected without
changing saved state. If pairing was explicitly forgotten or revoked, use
`adb-wireless-pair` manually with the temporary pairing port and code.

Before ADB runs, `tailscale-ensure-online` verifies that this Mac and the named
phone peer are online. A `Stopped` local backend is reconnected with
`tailscale up`, its saved GUI-client settings, and a bounded readiness check.
`NeedsLogin`, invalid daemon responses, offline peers, unsupported states, and
MagicDNS failure remain distinct actionable errors; the helper does not change
authentication, DNS preferences, or pairing. Set `ADB_WIRELESS_HOST` or pass
`--host PHONE.TAILNET.ts.net` to use another Tailnet DNS hostname. IP literals,
`.local` names, and non-Tailnet domains are rejected.

The Raycast Script Commands in `~/.local/bin/raycast/` provide four `scrcpy`
launch modes: Android with or without audio, and flex-display Android with or
without audio. Add that directory to Raycast's Script Commands directories.
They use the same recovery and last successful connection; no phone address,
pairing code, or pairing state is stored in Funk. When Tailscale and the paired
phone are available, the preflight and rotating-port refresh keep these
launches one click. Raycast runs them without the interactive shell's
environment, so each one puts the Homebrew and Tailscale locations on `PATH`
itself and reports the helper's own error text instead of failing silently.

The current-user `com.arthack.funk.tailscale-online` LaunchAgent invokes the
same idempotent helper at login and every five minutes, appending only recovery
or error output to `~/Library/Logs/Funk/tailscale-online.log`. It does not
install a root daemon, a Homebrew `tailscaled` service, or an `/etc/resolver`
file.

A log file nobody reads is not a detector, so every health verdict also reaches
the operator through `terminal-notifier` under the
`com.arthack.funk.tailscale-online` group. A shared group keeps one entry in
Notification Center, but macOS re-displays the banner on every post, so posting
each run would put the same alert back on screen every five minutes. An
unchanged condition therefore posts nothing at all until it has stood for an
hour, then reminds once, silently — long enough that an outage is not a
recurring interruption, short enough that a dismissed alert still returns the
same day. Override the interval with
`FUNK_TAILSCALE_ALERT_REMINDER_SECONDS`. Only a change in the condition itself
is immediate and audible, and recovery clears the recorded history so a
recurrence is audible again. Usage errors stay silent — a mistyped flag is not
an outage.

A notifier that cannot notify is the same silent failure one level up, so
`funk verify-notifications` posts a probe and asks NotificationCenter what it
decided with it. macOS records that verdict only in the system log — the
delivery permission lives in a container `defaults` cannot read — so the probe
is the only honest test; anything cheaper reports a notifier emitting into a
void as healthy. `./install` runs it and reports the result without failing,
because the delivery toggle belongs to the operator and no installer can set
it. The check also re-registers the bundle with Launch Services, since macOS
will not surface notifications from an application it has not registered and a
Homebrew upgrade relocates it. Choose the Alerts style rather than Banners in
System Settings › Notifications › terminal-notifier so an outage stands on
screen until dismissed; the check reports which style is in effect.

The GUI client's daemon is a macOS network system extension, which fails in a
way that reopening the application cannot repair: when a replacement extension
cannot start because the outgoing one never finishes terminating, `sysextd`
parks both halves and never retries. No extension is active, so there is no
daemon to reach. The helper reads `systemextensionsctl list` and reports that
state by name, with the stuck and blocked versions, rather than advising a
restart that cannot work. Recovery is a reboot; if it survives one, the stale
staging directory under `/Library/SystemExtensions` is the thing to remove.

The helper also reports an upgrade that is merely *staged* while the tailnet is
still healthy. This is the trap worth closing early: a downloaded extension
upgrade is invisible until the next Tailscale restart, which may well be a
reboot that happens away from the machine. Applying it deliberately, with
physical access, keeps a failed swap from becoming an outage that cannot be
fixed remotely.

Homebrew is the only updater Funk lets touch this cask. Tailscale ships its own
Sparkle updater, and leaving it enabled is what staged the extension swap that
wedged; `configure-macos` turns off `SUEnableAutomaticChecks` and
`SUAutomaticallyUpdate` in `io.tailscale.ipn.macsys` so upgrades no longer land
on Tailscale's schedule. `tailscale-app` needs administrator authentication, so
the scheduled updater cannot converge it and does not try — it reports the cask
as `Needs ./install` in its notification, and `./install` performs the upgrade
interactively. The tradeoff is deliberate: Tailscale can now sit a release
behind until an install is run, which is the price of never having a network
extension swap itself while the machine is unattended.

The availability tradeoff is explicit: by default, a GUI disconnect or
`tailscale down` appears as `Stopped` and is reversed within five minutes. To
stay deliberately disconnected, persist the opt-out before disconnecting.
The marker always lives at
`~/.local/state/funk/tailscale-auto-recovery.disabled`; it deliberately ignores
`XDG_STATE_HOME` so interactive shells, Raycast, and launchd make the same
decision:

```sh
tailscale-ensure-online --disable
tailscale down
# Later, remove the opt-out and reconnect immediately:
tailscale-ensure-online --enable
```

The Screen Copy path respects the same opt-out.

Orca does not expose a standalone global preferences file: its settings share
`orca-data.json` with projects, worktrees, sessions, account metadata, and
other generated state, and Orca atomically replaces that file when saving.
Funk therefore stows a credential-free settings overlay at
`~/.config/orca/settings.json` and `funk configure-orca` reconciles only those
keys into the active profile. If Orca is open and the profile differs, the
command stops instead of racing Orca's writer; quit Orca and rerun it. It exits
`75` (`EX_TEMPFAIL`) in that case, which marks a step to repeat rather than a
broken installation. The default installer runs this reconciliation after
installing Orca, and treats `75` as deferred: it finishes every remaining step,
still succeeds, and closes by naming the one command left to run. Any other
non-zero status still fails the installation.

## Local kiosk launcher

`~/.local/bin/raycast/localhost-8789-kiosk.sh` is a Raycast Script Command,
titled `Localhost 8789 (kiosk)`, that opens `http://localhost:8789/` in a
full-screen Chrome kiosk window from the same directory as the `scrcpy`
commands.

It runs the Chrome binary directly with its own `--user-data-dir` under
`~/.local/state/funk/chrome-kiosk`. That is deliberate: launching through
`open` hands the URL to an already-running Chrome, which discards `--kiosk` and
leaves an ordinary tab. The dedicated profile keeps the kiosk window separate
from the everyday browser, so it carries no logins, extensions, or session
history from the main profile.

The launcher probes the port first and reports `nothing is listening` instead of
opening an error page in kiosk mode, where the address bar is out of reach. A
missing Chrome is reported the same way. Set `FUNK_KIOSK_URL` to point one-off
launches at another local address; `FUNK_CHROME` and `FUNK_KIOSK_PROFILE`
override the browser and profile locations.

Run `funk stow` after changing or adding a package. Existing target files are
never silently replaced: inspect a dry run with `funk stow --check`, then use
`funk stow --adopt <package>` only when you deliberately want to move the
existing target into Funk and review the resulting Git diff.

## Install

Run from the checked-out repository as the new account, never with `sudo`:

```sh
./install
```

This installs Homebrew when absent, explicitly upgrades every eligible
Brewfile dependency, stows every user configuration package, initializes
tmux-fzf, the pinned Node runtime, and shell-gpt, installs or upgrades the AI
tools listed above, links `funk` into the active Homebrew `bin` directory,
installs the scheduled updater, Tailscale recovery, and home-network
`home-awake` agents, starts the Yabai/skhd/Karabiner stack, and converges Yabai
Spaces 1–9. The `home-awake` step prompts for `sudo` once on a fresh machine to
install its root helper, then skips the privileged work on every later run.
Optional system layers and the window-stack opt-out are explicit:

```sh
./install --without-windows
./install --with-hardening
./install --with-system-settings
./install --all
```

The default window setup restows the Yabai, skhd, and Karabiner packages and
starts the app-provided user services. After the documented Recovery and
boot-argument prerequisites are complete, it installs Funk's guarded root
helper, loads the Yabai scripting addition, creates its digest-pinned sudo rule,
and waits for Spaces 1–9 to exist. It never changes SIP or boot arguments
itself, and exits unsuccessfully with recovery instructions if those
prerequisites are missing. Use `./install --without-windows` only when
deliberately installing on a machine that cannot use this window stack.

`--with-hardening` immediately loads the travel firewall posture.
`--with-system-settings` applies the privileged machine-wide settings described
above and prompts for administrator authentication. `--all` enables hardening
and system settings in addition to the default window stack.

Homebrew is single-prefix software. Funk refuses to operate if the detected
Homebrew prefix belongs to another macOS account; resolve that ownership choice
before installing from a new account.

### Applications left by a previous account

An application in `/Applications` that still belongs to a previous local
account cannot be replaced by this one, so Homebrew falls back to its own
`chown` on every upgrade. That prompt cannot be answered by the scheduled
updater, and cancelling it leaves the Caskroom in the aborted-upgrade state
described below.

`./install` therefore reclaims those bundles first. It reassigns installed cask
`.app` targets that do not belong to this account, in one scoped `chown`, and it
is a silent no-op once ownership is correct. Inspect the plan without changing
anything:

```sh
libexec/reclaim-app-ownership --check --brewfile Brewfile
```

Root ownership is judged against the cask's artifacts rather than assumed. When
the cask installs a pkg there is an installer that legitimately owns the bundle
and reassigning it would fight that installer, so it is left alone. When the
cask ships only an `.app` there is no such installer: root ownership means
something replaced the bundle as root, and Homebrew can no longer upgrade it
without a prompt the scheduled updater cannot answer. Treating those as
untouchable made the updater retry an upgrade that could only ever fail, so they
are reclaimed and, until they are, reported as needing `./install` rather than
attempted.

This is the only step of a default `./install` that can ask for a password, and
only until it has run once.

### Casks installed under a previous account

Homebrew records the user directories it will install into — `fontdir`,
`prefpanedir`, `servicedir` and the rest — in each cask's metadata at install
time. A cask installed under a previous account keeps that account's paths
forever, so every later upgrade moves artifacts through a home this account
usually cannot even read. Nothing about the failure names the cause: Homebrew
reports only that some source file `is not there`, and the scheduled updater
fails on it indefinitely.

`./install` repairs these before converging the Brewfile:

```sh
libexec/repair-cask-user-dirs --check --brewfile Brewfile
```

Only casks that actually install a user-directory artifact are selected — a cask
shipping binaries or an `.app` never touches one, so its recorded directories
are inert and reinstalling it would be churn. Repair is a reinstall rather than
a metadata rewrite, because corrected paths alone would leave Homebrew looking
for the previous version's files under a directory they were never in. Those
artifacts are user-level, so the repair stays unprivileged.

### Aborted cask upgrades

A completed cask install leaves a symlink at
`$(brew --prefix)/Caskroom/<token>/<version>/<App>.app` pointing at the
installed application. An upgrade interrupted after Homebrew's backup step
leaves a real directory there instead, and every later upgrade of that cask
fails with `It seems there is already an App at '<caskroom path>'`.

Both convergence paths repair that before asking Homebrew to move an
application, so the failure cannot persist across runs:

```sh
libexec/repair-cask-artifacts --check --brewfile Brewfile
```

The helper only replaces a stale backup whose application is still installed in
an approved Applications directory. When the application is gone the Caskroom
copy is the only one left, so it is reported and left for Homebrew.

## Scheduled updates

`funk update` converges the unattended-safe update set:

```sh
# repair any aborted-upgrade Caskroom state left by an interrupted run
# skip the casks that cannot converge without administrator authentication
brew bundle install --upgrade --file=/resolved/path/to/Funk/Brewfile
# release quarantine only from Brewfile casks' declared .app targets
# install or greedily upgrade Orca, release its app quarantine, and sync its skills
```

The LaunchAgent has no terminal, so a cask that needs administrator
authentication would fail the entire run rather than only itself. Before
converging, the updater names those casks for `HOMEBREW_BUNDLE_CASK_SKIP`:

```sh
libexec/list-unattendable-casks --brewfile Brewfile
```

A cask qualifies when it installs a pkg, when its removal steps run a
privileged script, or when its installed application still belongs to another
local account. `karabiner-elements` and `tailscale-app` are permanently in this
set because both install a pkg. Skipped casks are logged and named in the
notification as `Needs ./install: ...`, so an interactive `./install` still
upgrades them. The helper only reads Homebrew metadata and file ownership; the
scheduled path never elevates.

A cask installed under a previous account fails the same run for a different
reason, so its tokens join the same skip set:

```sh
libexec/repair-cask-user-dirs --list --brewfile Brewfile
```

Homebrew records the user directories it installs into — `fontdir`,
`prefpanedir` and the rest — in each cask's metadata at install time. A cask
installed by another account keeps that account's paths forever, so every later
upgrade looks for the previous version's artifacts in a home this account
usually cannot even read. Nothing in the failure names the cause: Homebrew
reports only that a source file `is not there`. One stale font cask failed every
scheduled run for a day that way, and because the Brewfile step aborts the run,
nothing after it ran either. Repairing one is a reinstall, which an unattended
run should not attempt, so the scheduled path skips and reports them and
`./install` repairs them.

The explicit `--upgrade` overrides `HOMEBREW_BUNDLE_NO_UPGRADE`; every Brewfile
cask is also marked `greedy: true`, so Homebrew considers casks that declare
their own updater or an unversioned latest release. Homebrew still honors a
deliberately pinned formula or cask, and an application that updates itself
outside Homebrew can have a version different from its Homebrew receipt.

The user LaunchAgent runs `funk update --notify` at 00:00, 06:00, 12:00, and
18:00 local time and appends stdout/stderr to
`~/Library/Logs/Funk/update.log`. The updater snapshots the Homebrew receipt
versions for the managed Brewfile entries, Orca's installed bundle version, plus
the three Orca skill revision hashes, before and after convergence. Orca's
version comes from `Orca.app/Contents/Info.plist` rather than its Homebrew
receipt, because the app updates itself and the receipt stops describing what is
installed the first time it does. A notification lists only
components whose recorded version or revision actually changed. A no-op says
`Installer ran; no updates.` Failures retain their exit status and send a short
failure notification when `terminal-notifier` is available.

Orca is installed on this path but never upgraded on it. The cask marks itself
`auto_updates true` precisely so Homebrew will not compete with the app's own
updater, and `--greedy` is the one flag that overrides that. Overriding it
replaced the bundle under a running Orca, whose renderer then resolved its
code-split chunks out of a bundle that was no longer the one it had started
from: opening Preferences produced a screen of unrelated source and a dead
window. Orca's updater stages a release and applies it on quit, when there is
nothing left to break, so `libexec/install-orca` converges the cask with
`--install-only` — installing a missing Orca, leaving an installed one alone.
See `docs/adr/0001-orca-updates-itself.md`.

Something replacing the bundle under a running Orca is still worth saying out
loud, whoever does it, so the run compares the installed bundle version across
convergence and prompts when it moved while Orca was running. The prompt goes to
its own `com.arthack.funk.orca-restart` group so it is not buried in the
`Updated: …` summary. A stopped Orca gets no prompt: it picks the new bundle up
on its next launch. The check compares the executable path exactly, because
`pgrep -x` does not match this bundle on macOS and the name alone would also
match the `Orca Helper` processes.

Other AI tools remain outside the scheduled path: their vendor installers,
application updaters, account-sensitive MCP setup, and local Hack skill source
are not all suitable for a background LaunchAgent. Re-running `./install`
reapplies their supported installation methods; Homebrew-backed Claude,
ChatGPT, GitHub CLI, Zig, and Orca are explicitly installed or
upgraded, and the Native SDK CLI is pinned to the `0.7` line. Re-running
`./install` is also what reinstalls the AgentVoice desktop application, which
requires AgentVoice.app to be quit if it is running; the scheduled path stays
skills-only precisely so a background job never has to make that call.

Funk never performs bundle cleanup, uninstalls, HEAD refreshes, or privileged
post-update hooks.

After a Yabai upgrade, run `funk yabai maintain` manually. This refreshes the
digest-pinned `yabai --load-sa` sudo rule, loads the current scripting addition,
regenerates Yabai's user service for the new Homebrew Cellar path, and waits for
Spaces 1–9 to converge.

## Travel hardening

`funk install-hardening` installs a root-owned helper and RunAtLoad
LaunchDaemon, validates both the full PF configuration and generated anchor
before loading, and applies a fixed travel posture:

- inbound traffic is denied on every `enN` physical interface;
- outbound/stateful traffic, DHCP, mDNS, and required IPv6 discovery remain;
- Tailscale's `utun` interface is outside the deny scope.

The only passwordless privilege is the root-owned helper with the exact
arguments `status` or `travel`; there is no wildcard or general shell access.

```sh
funk harden status
funk harden travel
```

There is no home-router detection, automatic relaxation, hostname logic,
notification integration, or service-specific opening. The firewall never learns
where it is. `home-awake` below does identify the home network, but only to
decide about sleep and the screen lock; the two never touch, and
`tests/validate.sh` asserts that the PF path contains no location detection and
no reference to `home-awake`.

## Home-network sleep and sign-in

`home-awake` keeps this Mac awake, and signed in, while it is wired into the
home network. It holds off idle sleep and turns the screen lock off, so coming
back to the machine needs no password. Leaving that network restores exactly the
screen lock delay that was in place before.

```sh
funk home-awake --status
funk home-awake --learn-network [NAME]
funk home-awake --set-password
```

The default installation sets this up. The `com.arthack.funk.home-awake`
LaunchAgent re-checks at login, on every SystemConfiguration change, and every
thirty seconds, appending only its own errors to
`~/Library/Logs/Funk/home-awake.log`.

Being plugged in is not by itself evidence of being home: any dock in any
building satisfies a link-status check, so a coworking desk or a hotel room
would turn the screen lock off. The gate is therefore a wired link *whose own
router answers with a recorded hardware address*. Wi-Fi does not qualify, even
on the same router.

Nothing is trusted until it is recorded on the machine itself, so a fresh
account relaxes nothing:

```sh
funk home-awake --learn-network study
```

That writes `~/.config/funk/home-awake.conf`, which is the only network that
counts:

```
router_label=study
router_mac=00:00:5e:00:53:0a
```

The router is read per interface with `ipconfig getoption`, not from the default
route, so a Tailscale exit node cannot change the answer to "which network is
this cable on". A hardware address that has aged out of the neighbour cache is
probed once before being believed, because *unknown* and *somewhere else* are
different answers and only the second one should re-lock the screen. Addresses
are compared after normalization, since `arp` prints octets without leading
zeros.

This is a convenience gate, not authentication. A router's hardware address is
public on its own segment and can be spoofed by anyone who knows it. It reliably
separates this house from a hotel dock; it does not stand up to somebody
targeting this machine.

Two things are privileged, and both go through the root-owned
`/usr/local/libexec/funk-home-awake` helper rather than a passwordless rule on
`pmset` or `sysadminctl` themselves. The granted invocations are exactly
`sleep 0`, `sleep 1`, `screenlock off`, `screenlock immediate`, and
`screenlock <seconds>`; the helper rejects any delay that is not a plain number
of seconds within a day. `tests/validate.sh` asserts that list.

Turning the screen lock off requires the login password that authorizes it.
`funk home-awake --set-password` stores it in the login keychain under
`funk-home-awake`, where `/usr/bin/security` reads it back; the password is
never passed as an argument, written to a file, or logged. Until it is stored,
home-awake manages sleep only and leaves the screen lock alone.

The tradeoff is deliberate and worth stating plainly: while this Mac is on the
home network, anyone with physical access to it is already signed in. FileVault
still protects the disk at rest, and none of this touches the travel firewall
posture above.

Idle-sleep suppression runs as its own `com.arthack.funk.home-awake-caffeinate`
job, installed to `~/.local/state/funk/` rather than `~/Library/LaunchAgents`.
Everything in the LaunchAgents directory loads at login; this job must run only
while home-awake has bootstrapped it, and launchd reaps the periodic check's
process group as soon as that check finishes, so a plain background
`caffeinate` would not survive.

## Full numbered-Space workflow

The approved nine-Space workflow uses Yabai features that still require its
scripting addition: creating Spaces and moving windows between them. Yabai's
current documentation requires a deliberate partial-SIP setup.

1. Follow Yabai's current
   [SIP instructions](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
   from macOS Recovery. For Apple Silicon on macOS 13 or newer, the documented
   Recovery command is:

   ```sh
   csrutil enable --without fs --without debug --without nvram
   ```

   Intel uses the different command documented on that page.

2. Reboot. On Apple Silicon, Yabai also requires
   `-arm64e_preview_abi`. Inspect existing boot arguments first and preserve any
   intentional values. If there are no others to preserve, Yabai documents:

   ```sh
   sudo nvram boot-args=-arm64e_preview_abi
   ```

   Reboot again.

3. Run `./install` (or `funk install-windows` when reapplying only this layer).
   It installs and invokes the guarded Yabai maintenance path, starts the
   `RunAtLoad` Yabai and skhd services, and waits for Spaces 1–9. Grant
   Accessibility to Yabai and skhd when prompted, restart the command after
   approval if necessary, approve Karabiner's requested
   permissions, keep Karabiner-Elements enabled under General > Login Items >
   Allow in Background, and keep Secure Keyboard Entry disabled while using
   skhd. Karabiner registers its own background services the first time it
   opens.

4. Verify the converged setup:

   ```sh
   funk yabai status
   ```

The maintenance helper is root-owned; normal maintenance accepts no arguments
(the root installer alone uses its read-only `--check`). It validates its
root-owned configuration and Yabai code signature, uses bounded commands,
writes only a SHA-256-pinned `yabai --load-sa` sudo rule, and rolls that rule
back if loading fails. It never changes SIP, modifies TCC directly, mints
certificates, or runs from the scheduled updater. See Yabai's current
[installation guide](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29).

## Validate

```sh
tests/validate.sh
```

The checks parse shell/config files, verify the exact Brewfile and approved
Karabiner rule set, exercise updater success/failure and change-aware
notifications with stub commands, verify scoped quarantine removal against
temporary app bundles, validate the macOS-preference command without applying
it, render the LaunchAgent, and dry-parse the PF rules. They do not install or
upgrade packages, load services, change preferences or firewall state, or
require accounts or secrets.
