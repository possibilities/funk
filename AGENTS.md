# Project context

- `/Users/mike/code/dotfiles` (written by the user as `~mike/code/dotfiles`) is
  the long-lived dotfiles and system-setup repository from the old `mike` user
  account.
- Treat that repository and the old account as valuable reference material when
  developing Funk. Reuse useful ideas selectively rather than assuming the old
  setup should be copied wholesale into the new account.
- Credentials and authenticated CLI configuration from the old account may be
  migrated into the new account when needed. Copy only the required files,
  retain restrictive permissions, and never print, inspect unnecessarily, or
  commit secret values.
- Preserve Funk's current goals and safety constraints when adapting anything
  from the old setup.

## Fix-forward configuration

Every durable system change belongs in this repository. A fresh account should
converge by running `./install`; avoid one-off configuration that disappears on
the next machine.

- Add software to `Brewfile` and install it through Funk.
- Put user configuration in the appropriate Stow package and run `funk stow`
  so the live path links back here.
- Add macOS preferences to the appropriate configuration helper.
- Do not edit a Stow-managed file through its path in `$HOME`; edit the source
  in this repository.
- Use `funk stow --adopt <package>` only to migrate an intentional existing
  config, then review the Git diff because `--adopt` changes repository files.
- When a new package is added, register it in `libexec/stow-config`, document
  its target and folding mode in `README.md`, and test the forward path.
- Preserve common Emacs/readline movement, history, cutting, and yanking
  bindings when changing shell or terminal input behavior.
- Reload an affected application after changing its live config when possible:
  source tmux's config, restart Yabai/skhd services, and reapply Tinty themes.
  Karabiner reloads its configuration automatically.

Packages using `--no-folding` are `ssh`, `ghostty`, `tmux`, `zsh`, `karabiner`,
`tmuxctl`, `bin`, and `llm`. This keeps their target directories available for
application-generated or unmanaged files. Other user config packages may use
Stow's normal directory folding.

Root-owned helpers, LaunchDaemons, rendered LaunchAgents, credentials, generated
state, and remote-device configuration are not Stow packages. Continue to use
Funk's guarded installers for privileged files; a symlink from a root execution
path into this user-writable checkout would be a privilege-escalation hazard.
