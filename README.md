# Funk

[![CI](https://github.com/possibilities/funk/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/possibilities/funk/actions/workflows/ci.yml)

Funky dotfiles.

The machine half of one macOS setup: Homebrew, GNU Stow packages, launchd
agents, and system settings. The AI toolchain is the other half and lives in
[AgentStart](https://github.com/possibilities/agentstart), which `./install`
requires as a sibling checkout at `~/code/agentstart`.

This converges one operator's machine, and the defaults are that operator's.
Read it, fork it, take what you want — but `./install` is not a starting point
for someone else's Mac.

## Install

```sh
git clone git@github.com:possibilities/funk.git ~/code/funk
cd ~/code/funk
./install
```

Flags: `--with-hardening`, `--without-windows`, `--with-system-settings`,
`--all`.

The first run on a new account asks for a git commit name and address, and
writes `~/.ssh/config.d` from whatever tailnet Tailscale is reporting. Neither
is stored here.

Browser runtimes and their dependencies are installed by AgentBrowse's
`scripts/install-host`; Funk no longer installs Docker or Apple container. Full installation retires
the old Docker CLI packages after checking existing profile migration receipts.
Apple package removal is an explicit administrator step, preserving its data.

## Executor Funnel

`./install` converges one additive Tailscale Funnel handler:
`https://<Tailscale DNS name>/mcp` proxies to Executor at
`http://127.0.0.1:4789/mcp`. Funk owns only `/mcp`; the existing `/` handler for
the AgentSource GitHub webhook daemon and every other Funnel handler remain
untouched. Use `funk install-executor-funnel --check` for a read-only verdict or
`funk install-executor-funnel` to converge the route directly.

Executor owns authentication and its generated token; Funk never reads or
stores it. In a private terminal, run `executor server rotate-token`, save the
returned value directly in a password manager, and enter it in the remote MCP
client's bearer-token field. The client sends that value as the
`Authorization: Bearer …` header. Do not paste the token into this repository,
shell commands, issue trackers, or chat logs.

An unauthenticated request to `https://<Tailscale DNS name>/mcp` should return
HTTP 401 with `WWW-Authenticate: Bearer`. That check exercises the public route
without exposing the token.

## Backups

Funk installs two encrypted Restic jobs:

- `io.arthack.funk.backup-onsite` runs hourly and at login against Silverbird.
  It is the comprehensive recovery copy: agent sessions and configuration,
  repositories including Git objects, authored home directories, selected app
  state, local worktrees and source mirrors, browser profiles, media, and the
  additive transcript archive on Scratch when it is mounted.
- `io.arthack.funk.backup-offsite` runs daily at 04:00 against Backblaze B2.
  It keeps the smaller irreplaceable core—including Claude sessions, Codex
  configuration, source repositories, keys, configuration, and authored
  stores—but omits bulky reproducible or locally mirrored data such as the
  high-volume Codex session/history corpus, Scratch archives, worktrees,
  source mirrors, downloads, media, browser profiles, VM images, package
  caches, and derived search indexes.

Credentials stay machine-local at `~/.config/restic/silverbird.env` and
`~/.config/restic/b2.env`, mode `0600`. Their secret values and the Silverbird
SSH bootstrap must also exist in an independent password-manager or offline
recovery record: a repository cannot provide the password needed to unlock
itself. A repository without credentials is reported as deferred during
installation rather than breaking convergence of the rest of the account.

The selected `Library` roots, including the raw login Keychain databases, are
best-effort recovery material. macOS privacy controls may deny an unattended
LaunchAgent access, and a raw Keychain copy is not a portable secret export;
independent credential escrow remains the authoritative disaster-recovery path.

Before Restic reads the filesystem, `funk backup` refreshes verified recovery
copies of live SQLite data under `~/.local/state/funk/backup-staging`. A failed
application snapshot is reported after the remaining home data is backed up;
it never blocks unrelated data as the retired backup pipeline did.

There is deliberately no automatic `forget` or `prune` yet. Inspect real
growth first, then add a separately reviewed, repository- and tag-scoped
retention policy. For a restore drill, source the selected repository's env
file and use `restic snapshots --tag funk-home-onsite` (or
`funk-home-offsite`), then `restic restore <snapshot> --target <empty-dir>`.

## Use

```sh
funk update          # converge Homebrew and the scheduled agents
funk stow --check    # preview config links
funk stow            # link config packages into $HOME
funk chuchu-theme    # build and push Signal Room to Chuchu Lab
funk install-android-launchers
                     # converge the four Screen Copy applications
funk install-ghostty-terminfo
                     # expose Ghostty capabilities to remote shells
funk install-noizey  # build and install the global terminal sound mixer
noizey               # launch from any directory
funk backup onsite --check
                     # validate Silverbird backup prerequisites
funk help            # everything else
```

The Android applications use an authorized USB phone directly when exactly
one is attached. With none attached they recover the existing wireless ADB
connection; emulators are ignored and multiple authorized USB devices are
rejected as ambiguous. If neither USB nor wireless is available, the launcher
posts a macOS notification instead of failing invisibly.

Noizey's native terminal executable is built from the clean `~/code/noizey`
checkout into `~/.local/lib/noizey/noizey`. Funk's `bin` Stow package exposes
`~/.local/bin/noizey` on PATH. Both `./install` and `funk update` refresh it;
`funk install-noizey` runs just that installation. Go is declared in the
Brewfile, and building also requires the Xcode command-line tools.

Clone Noizey before the first installation. Funk builds the checked-out
revision without pulling or moving its branch, refuses dirty source, and
keeps the previous executable if a build fails. Existing presets/settings
and running playback are preserved. `FUNK_NOIZEY_ROOT` can select another
clean checkout; `FUNK_NOIZEY_DIR` changes the native installation directory
and must also be set when launching through the wrapper.

## Test

```sh
tests/validate.sh
```

Runs anywhere. The checks that need macOS skip themselves off Darwin and print
what they skipped; on the machine the skip list is empty.

Contributor notes, including the Stow package table and the rules this
repository holds itself to, are in [AGENTS.md](AGENTS.md).
