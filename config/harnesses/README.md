# Personal harness preferences

`codex.toml` is the authored source for normal Codex launches through the fleet
shim. Edit it here; the next invocation uses the new settings. AgentStart owns
the wrapper and installs it through `scripts/install.sh --install`. This
directory is not a Stow package and has no installer of its own.

The wrapper copies preferences into a unique native profile under the existing
Codex home, adds trust for the invocation's effective cwd and project root,
runs Codex, and removes that copy after exit. Credentials, trust history,
generated skills/plugins, and sessions remain local. Never adopt the live
`~/.codex/config.toml` here or add `projects`, `profile`, or `profiles` to this
source. The initial preferences were selected from the existing config without
moving its machine state.

Precedence is base user config, this source, an explicitly selected native
profile, trusted project config, then CLI overrides. Relative file paths have
native profile semantics and resolve from `CODEX_HOME`, not this directory.
Native UI changes are not saved back here automatically.

AgentStart's `config/codex/README.md` documents supported commands, cleanup,
bypasses, and verification. Claude, Pi, and Fx can gain their own authored
sources when their invocation adapters are implemented.
