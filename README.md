# Funk

Funk is Arthack's reproducible macOS setup and the successor to the old
dotfiles repository. It keeps Funk's narrower security model while carrying
forward the old repository's Stow-based, fix-forward configuration workflow.

## What it installs

The default installer applies the Brewfile plus the vendor-supported AI tool
installers:

- Tailscale, Ghostty, Google Chrome, Chrome Canary, Brave, Firefox
- ChatGPT, Claude Desktop, Orca, Obsidian, Raycast
- GitHub CLI, Claude Code, Codex CLI, OpenCode, and Pi
- Yabai, skhd, and the narrowly justified Karabiner-Elements layer
- Git Delta, Neovim, tmux, Tinty, Starship, btop, GNU Stow, and supporting
  shell/development tools

`libexec/install-ai-tools` uses the official shell installers for
[Claude Code](https://code.claude.com/docs/en/terminal-guide),
[Codex CLI](https://github.com/openai/codex#installing-and-running-codex-cli),
[OpenCode](https://opencode.ai/docs/), and [Pi](https://pi.dev/docs/latest).
ChatGPT and Claude Desktop use their Homebrew casks because their normal
personal macOS downloads do not provide unattended installer commands. Orca
uses the cask documented by the [Orca project](https://github.com/stablyai/orca).
Run `libexec/install-ai-tools --check` to inspect the exact plan without making
changes.

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
the old dotfiles: dark mode and a black wallpaper, an empty auto-hidden Dock and
menu bar, quiet UI, hidden desktop items, column-view Finder, fast key repeat,
Yabai-friendly window and Space behavior, Raycast-friendly Spotlight shortcuts,
Cmd+D as the Raycast launcher with first-run onboarding dismissed, disabled
AirPlay Receiver and Handoff, disabled iCloud Desktop/Documents syncing, and the
compact 12-hour menu-bar clock. Run `funk configure-macos` to reapply them.

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
| `tinty` | `~/.config/tinted-theming/tinty/` | no |
| `zsh` | `~/.zshenv`, `~/.zshrc`, `~/.zsh/` | yes |
| `yabai` | `~/.config/yabai/` | no |
| `karabiner` | `~/.config/karabiner/` | yes |
| `tmuxctl` | `~/.config/tmuxctl/` | yes |
| `bin` | `~/.local/bin/` | yes |
| `starship` | `~/.config/starship.toml` | no |
| `btop` | `~/.config/btop/` | no |
| `llm` | `~/Library/Application Support/io.datasette.llm/` | yes |
| `orca` | `~/.config/orca/settings.json` | no |

Funk's current Yabai, skhd, and reviewed Karabiner configurations take
precedence where the two repositories overlapped. Privileged helpers,
LaunchAgents, generated application state, credentials, and remote Termux
configuration are intentionally not Stow-linked.

Orca does not expose a standalone global preferences file: its settings share
`orca-data.json` with projects, worktrees, sessions, account metadata, and
other generated state, and Orca atomically replaces that file when saving.
Funk therefore stows a credential-free settings overlay at
`~/.config/orca/settings.json` and `funk configure-orca` reconciles only those
keys into the active profile. If Orca is open and the profile differs, the
command stops instead of racing Orca's writer; quit Orca and rerun it. The
default installer runs this reconciliation after installing Orca.

Run `funk stow` after changing or adding a package. Existing target files are
never silently replaced: inspect a dry run with `funk stow --check`, then use
`funk stow --adopt <package>` only when you deliberately want to move the
existing target into Funk and review the resulting Git diff.

## Install

Run from the checked-out repository as the new account, never with `sudo`:

```sh
./install
```

This installs Homebrew when absent, runs `brew bundle install`, stows every user
configuration package, initializes Tinty, tmux-fzf, the pinned Node runtime, and
shell-gpt, installs the AI tools listed above, links `funk` into the active
Homebrew `bin` directory, installs the daily updater, starts the Yabai/skhd/
Karabiner stack, and converges Yabai Spaces 1–9.
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

## Daily updates

`funk update` runs only:

```sh
brew bundle install --file=/resolved/path/to/Funk/Brewfile
```

The user LaunchAgent runs it daily at 10:00 local time and appends stdout/stderr
to `~/Library/Logs/Funk/update.log`. Failures retain their exit status. Funk
never performs bundle cleanup, uninstalls, quarantine removal, HEAD refreshes,
notifications, or privileged post-update hooks.

AI tools are intentionally outside the daily Brewfile update: their vendor
installers and application updaters own upgrades. Re-running `./install` also
reapplies their supported installation methods.

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
notification integration, or service-specific opening.

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
certificates, or runs from the daily updater. See Yabai's current
[installation guide](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29).

## Validate

```sh
tests/validate.sh
```

The checks parse shell/config files, verify the exact Brewfile and approved
Karabiner rule set, exercise updater success/failure with a stub Homebrew
command, validate the macOS-preference command without applying it, render the
LaunchAgent, and dry-parse the PF rules. They do not install packages, load
services, change preferences or firewall state, or require accounts or secrets.
