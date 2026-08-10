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
funk help            # everything else
```

## Test

```sh
tests/validate.sh
```

Runs anywhere. The checks that need macOS skip themselves off Darwin and print
what they skipped; on the machine the skip list is empty.

Contributor notes, including the Stow package table and the rules this
repository holds itself to, are in [AGENTS.md](AGENTS.md).
