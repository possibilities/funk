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
funk yaos-recovery   # inspect YAOS readiness and print resurrection steps
funk help            # everything else
```

Every install ends with the same YAOS resurrection handoff. It records the
deployed Worker, pinned upstream source, R2 binding, vault roles, and recovery
order without storing the sync token, vault ID, plugin state, Cloudflare
identity, or Android configuration. Use `funk yaos-recovery --check` when a
machine-readable readiness exit code matters.

The Android applications use an authorized USB phone directly when exactly
one is attached. With none attached they recover the existing wireless ADB
connection; emulators are ignored and multiple authorized USB devices are
rejected as ambiguous. If neither USB nor wireless is available, the launcher
posts a macOS notification instead of failing invisibly.

## Test

```sh
tests/validate.sh
```

Runs anywhere. The checks that need macOS skip themselves off Darwin and print
what they skipped; on the machine the skip list is empty.

Contributor notes, including the Stow package table and the rules this
repository holds itself to, are in [AGENTS.md](AGENTS.md).
