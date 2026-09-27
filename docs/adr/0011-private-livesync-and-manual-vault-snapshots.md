# 0011: Private LiveSync remote and manual vault snapshots

Status: Accepted, 2026-09-27.

The work vault synchronises between greybird and smolbird through a CouchDB
instance on greybird, exposed only through Tailscale Serve HTTPS. Android needs
valid HTTPS; loopback-only CouchDB avoids a second LAN/public listener. This
avoids a hosted account and keeps the data in the operator's backup domain,
but greybird must be online for changes to reach the other device. Peer-to-peer
sync was not chosen because it requires both Obsidian apps to be online and
connected at the same time. Never enable Funnel on the database port.

The separate private `possibilities/obsidian-work` GitHub repository receives
only on-demand snapshots of notes and common attachments. GitHub is not the
LiveSync transport and no watcher, hook, or scheduled path pushes vault changes.
The push helper rejects a public destination, hidden/plugin state, unexpected
tracked files, and symlinks. This prevents a future credential-bearing plugin
configuration from entering Git history through an overbroad `git add`.

The CouchDB credential and Obsidian's writable plugin state remain local, not
Stowed or tracked by Funk. The installer converges the generated CouchDB config
after Homebrew upgrades; Obsidian owns plugin updates and enablement. The
operator must verify recovery from the separate Restic roots for the vault and
database, since Git snapshots are neither a remote database nor a full
application-state backup.

See [the installation and recovery procedure](../configuration.md#obsidian-livesync-and-on-demand-github-snapshots).
