# 0010: Install OpenCode 2 Desktop with a local cask

Status: Accepted, 2026-09-24.

Funk owns desktop applications; AgentStart's side-by-side `opencode2` CLI
installation does not install a macOS app. Homebrew's `opencode-desktop` cask
still ships OpenCode 1, and the OpenCode 2 tap has no desktop cask. Funk's
Brewfile therefore taps this checkout locally and installs its own
`opencode2-desktop` cask from the official Apple silicon DMG. The initial
2.0.16 download is checksum-pinned and its bundle was checked for notarized
Developer ID signature, bundle version and Gatekeeper acceptance.

The cask declares its own updater and is not `greedy`, avoiding a scheduled
Homebrew bundle swap while the desktop app runs. This is an install-only
bootstrap independent of AgentStart's CLI cutover, not a configuration/session migration. Replace the
local cask with a suitable upstream V2 cask when one exists; never substitute
the V1 cask just because it has the same `OpenCode.app` artifact name.
