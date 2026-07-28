# Funk

Funk is Arthack's deliberately small macOS setup. It is a new configuration
project, not a port of the old dotfiles repository.

## What it installs

The Brewfile declares only:

- Tailscale, Ghostty, Google Chrome, Chrome Canary, Brave
- ChatGPT, Claude, Obsidian, Raycast
- Yabai, skhd, and the narrowly justified Karabiner-Elements layer

Karabiner has exactly two paired rules: global Cmd+1…9 becomes F13…F21 for
Yabai Space focus, while Ctrl+1…9 becomes the normal Cmd+number tab shortcut in
Chrome, Chrome Canary, and Brave. No modifier swaps or Option-hjkl rules survive.

The default install also applies the personal macOS preferences retained from
the old dotfiles: dark mode and a black wallpaper, an empty auto-hidden Dock and
menu bar, quiet UI, hidden desktop items, column-view Finder, fast key repeat,
Yabai-friendly window and Space behavior, Raycast-friendly Spotlight shortcuts,
disabled AirPlay Receiver and Handoff, disabled iCloud Desktop/Documents syncing,
and the compact 12-hour menu-bar clock. Run `funk configure-macos` to reapply
them.

The old machine-wide settings are available through the explicit
`funk configure-system` command: it disables Spotlight indexing on all mounted
volumes, adds `serverperfmode=1` while preserving other NVRAM boot arguments,
disables SMB and removes the current user's Public Folder share, and sets AC
display sleep to five minutes. The obsolete Ctrl+F2/F3/F4 and screenshot
shortcut mutations remain omitted because Funk does not claim those keys.

## Install

Run from the checked-out repository as the new account, never with `sudo`:

```sh
./install
```

This installs Homebrew when absent, runs `brew bundle install`, links `funk`
into the active Homebrew `bin` directory, and installs the daily updater.
Optional system layers are explicit:

```sh
./install --with-hardening
./install --with-windows
./install --with-system-settings
./install --all
```

`--with-hardening` immediately loads the travel firewall posture.
`--with-windows` installs user configs and starts the app-provided user services,
but it does not change SIP or create the scripting-addition sudo rule.
`--with-system-settings` applies the privileged machine-wide settings described
above and prompts for administrator authentication. `--all` enables all three
optional layers.

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

After a Yabai upgrade, run `funk yabai maintain` manually. This refreshes the
digest-pinned `yabai --load-sa` sudo rule, loads the current scripting addition,
and regenerates Yabai's user service for the new Homebrew Cellar path.

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

3. Run `funk install-windows`. Grant Accessibility to Yabai and skhd when
   prompted, restart each service after approval, approve Karabiner's requested
   permissions, and keep Secure Keyboard Entry disabled while using skhd.

4. Configure and verify the scripting addition:

   ```sh
   funk yabai maintain
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

The checks parse shell/config files, verify the exact Brewfile and minimal
Karabiner rule set, exercise updater success/failure with a stub Homebrew
command, validate the macOS-preference command without applying it, render the
LaunchAgent, and dry-parse the PF rules. They do not install packages, load
services, change preferences or firewall state, or require accounts or secrets.
