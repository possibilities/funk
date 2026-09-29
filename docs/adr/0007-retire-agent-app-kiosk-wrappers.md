# 0007: Retire the agent-app kiosk wrappers

Accepted 2026-09-19.

Funk no longer owns WebKit or Chrome wrappers for agent-app surfaces. Direct
browser URLs remain the launch path for AgentHUD and AgentVoice transcripts;
native `AgentVoice.app` is outside this retirement. The obsolete Raycast
`localhost-8789-kiosk.sh` command is removed with the wrappers.

`./install` and the scheduled path therefore stop building or installing
`AgentHUD.app`, `AgentVoice Transcripts.app`, and `AgentVoice TEST Transcripts.app`.
A minimal exact-owner convergence helper deletes only those three bundles when
their identifiers are the verified `com.arthack.funk.kiosk.*` values, plus safe
known `.*.app.funk-transaction` remnants for the same owners. Foreign
applications at those names, native AgentVoice, unrelated apps, WebKit data, and
Chrome profile data are left untouched. No running application is terminated.

This supersedes [0004](0004-kiosk-persistence-lifecycle-and-instance-identity.md)
and [0005](0005-square-kiosk-windows.md), and completes the launcher retirement
begun in [0006](0006-retire-agentchats-web-launcher.md).
