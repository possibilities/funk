# 0013: Retire LiveSync and install Omajot locally

Status: Accepted, 2026-10-04.

The initial independent CLI replica and port 8797 are corrected by
[0014: One local Omajot hub for all desktop clients](0014-one-local-omajot-hub-for-all-desktop-clients.md).
The desktop-only access boundary is superseded by
[0015: Authenticated Omajot access for Android](0015-authenticated-omajot-access-for-android.md).
The LiveSync retirement remains accepted.

The operator explicitly retired Obsidian LiveSync and requested a desktop
backup, removal of the Android Obsidian application, and installation of
Omajot. Content migration and Android access are separate later work.
This supersedes the LiveSync transport/installation portions of
[0011](0011-private-livesync-and-manual-vault-snapshots.md), not its private,
on-demand GitHub snapshot policy.

Remove the CouchDB dependency and both plugin/remote installers, including
their normal and scheduled convergence hooks. Removing live files alone would
allow the next `./install` to undo the operator's decision. Existing teardown
requires a verified backup first, exact plugin/config ownership checks, and
removal of only the LiveSync Serve endpoint. Notes and other applications'
configuration are outside the deletion scope.

Omajot already has an upstream Homebrew formula. Use that released binary and
its embedded web app, with an owned login LaunchAgent, explicit loopback binding
and no authentication only for this desktop-local stage. Use port 8797 rather
than the upstream default 8787, which already has other service/Serve uses on
the target machine. Refuse a Tailscale proxy to this unauthenticated port.
Do not repurpose an existing endpoint or choose a Tailscale identity now.

Retain existing Omajot state and include both its hub and CLI replica in Restic
roots. The alternative—configuring a remote hub immediately—would silently
expand this installation into the explicitly deferred phone/access stage.

See [the current installation procedure](../configuration.md#omajot-tui-and-android-pwa).
