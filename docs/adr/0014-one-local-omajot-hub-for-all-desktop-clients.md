# 0014: One local Omajot hub for all desktop clients

Status: Accepted, 2026-10-04.

The desktop-only access boundary and local client URL are superseded by
[0015: Authenticated Omajot access for Android](0015-authenticated-omajot-access-for-android.md).
The shared stores and one-time reset decision remain accepted.

The operator found that the TUI showed earlier local Omajot notes while the web
app did not, and requested that both show the same notebook, followed by an empty
fresh start. The first-stage installation in [0013](0013-retire-livesync-and-install-omajot-locally.md)
started a hub but did not connect the existing CLI replica to it.

Keep the upstream's separate hub and client storage formats. Overlay only the
desktop `hub` key in the actual configuration file read by the shared daemon/CLI
path resolver; preserve other fields and refuse foreign hubs or symlinks. This
is generated local configuration, not a new Stow package or adoption of writable
application state. A configuration change does not implicitly restart an active
TUI; explicit restart permission belongs to the repair/reset operation.

The requested one-time reset uses port 8799, a fresh browser origin, instead of
8797. Browser IndexedDB replicas retain their own cursor and queued operations;
erasing the hub alone neither resets those replicas nor prevents replay of old
notes. The old endpoint is not retained as an alias. Archive both native stores
before replacing them, close/reset the owned verification browser too, and
leave the new hub and client empty after proving bidirectional synchronization.
Normal installation must never repeat the destructive reset.

The loopback/no-auth desktop-only boundary, private recovery copies, and deferred
Obsidian migration/Android access remain unchanged.
