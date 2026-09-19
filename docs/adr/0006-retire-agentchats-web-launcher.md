# 0006: Retire the AgentChats web launcher

Superseded by [0007](0007-retire-local-web-kiosk-launchers.md), accepted 2026-09-15.

AgentVoice now owns the transcript UI implementation. AgentChats retires its
web reader while retaining its CLI, MCP, archive/index/search, and OpenTUI resume
picker. The fixed AgentChats web kiosk would point to a retired endpoint.

Funk therefore stops building and installing `AgentChats Transcripts.app` and
removes its dedicated icon. The AgentVoice production/TEST and AgentHUD launchers
remain unchanged. This partially supersedes [0004](0004-kiosk-persistence-lifecycle-and-instance-identity.md)
and [0005](0005-square-kiosk-windows.md) only for the AgentChats launcher;
generic WebKit persistence and square-window behavior remain supported.

Existing installed bundles and WebKit storage are not silently removed, and no
running application is terminated. Removing an already installed AgentChats kiosk
is an explicit operator cleanup after closing it. The transcript-vault archive
and AgentChats index refresh remain untouched.
