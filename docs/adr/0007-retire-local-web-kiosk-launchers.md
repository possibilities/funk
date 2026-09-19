# 0007: Retire local web kiosk launchers

- Status: Accepted
- Date: 2026-09-18

## Context

Funk previously rendered three native WebKit wrappers for AgentHUD and the
production and TEST AgentVoice web services. A separate Raycast command opened
an unrelated local page in Chrome kiosk mode. The services themselves remain
available through their direct HTTPS localhost URLs, while the wrappers add a
second browser runtime and a maintenance surface with no remaining ownership
need.

## Decision

Funk no longer builds, installs, documents, or exposes the local web-wrapper
applications or the Chrome kiosk Raycast command. Fresh `./install` and
scheduled convergence do not recreate them.

The private retirement helper cleans up existing installs only at these exact
paths, and only after the matching `CFBundleIdentifier` proves ownership:

- `~/Applications/AgentHUD.app` — `com.arthack.funk.kiosk.agenthud`
- `~/Applications/AgentVoice Transcripts.app` — `com.arthack.funk.kiosk.agentvoice`
- `~/Applications/AgentVoice TEST Transcripts.app` — `com.arthack.funk.kiosk.agentvoice-test`

It unregisters a proved owned bundle when Launch Services is available and
removes only old transaction directories that carry the exact former Funk owner
marker and contain no unrecognized artifacts. It never removes
`~/Applications/AgentVoice.app`, WebKit storage, the Chrome kiosk profile, or a
foreign bundle at a former path. The direct services remain
`https://agenthud.localhost/`, `https://agentvoice.localhost/`, and
`https://agentvoice-test.localhost`.

## Consequences

The kiosk persistence and square-window contracts in [0004](0004-kiosk-persistence-lifecycle-and-instance-identity.md)
and [0005](0005-square-kiosk-windows.md) no longer have an implementation.
This decision also supersedes [0006](0006-retire-agentchats-web-launcher.md):
there is no remaining Funk-owned web kiosk. Historical records remain for the
ownership and safety rationale behind the exact cleanup boundary.
