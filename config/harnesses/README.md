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
bypasses, and verification.

Claude's authored settings live in `../../claude/.claude/preferences.json`.
`funk stow claude` links that file to `~/.claude/preferences.json`; managed
launches load it with native `--settings`. Edit the source for durable changes.
An explicit `--settings` replaces this overlay; native CLI flags and managed
policy keep their usual precedence. The overlay overrides user/project/local
settings, so put only global preferences here. Claude UI changes still write
local `settings.json` and must be promoted here deliberately.

The writable `~/.claude/settings.json` and `~/.claude.json` are not Stowed.
Hooks, statusline installation, generated classifier context, trust history,
credentials, and session state stay local. AgentStart's launch helper marks
the launched cwd and Git project/worktree roots trusted before starting Claude,
using its native config lock. This enables project instructions and hooks but
does not change the selected tool-permission mode. Set `AGENTSTART_CLAUDE_TRUST=0`
to keep normal trust prompts, or `AGENTLAUNCH_SHIM_BYPASS=1` for a native launch.
See AgentStart's `config/claude/README.md` for scope and verification.

Pi and Fx can gain their own authored sources when their adapters are implemented.
