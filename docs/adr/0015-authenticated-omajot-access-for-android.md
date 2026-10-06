# 0015: Authenticated Omajot access for Android

Status: Accepted, 2026-10-05.

The operator requested Android PWA access to the existing notebook and uses
only the TUI on the Mac. This replaces the deliberately desktop-only access
boundary in [0013](0013-retire-livesync-and-install-omajot-locally.md) and
[0014](0014-one-local-omajot-hub-for-all-desktop-clients.md), not their preserved
notes, shared-hub model, or completed one-time reset.

Use upstream Omajot's Tailscale identity check, a loopback listener on 8799,
and a private Tailscale Serve HTTPS endpoint on 8448. No Funnel grant, raw TCP
forward, secondary unauthenticated hub or compatibility alias is introduced.
An authenticated hub rejects direct local API requests too: the Mac's TUI
daemon therefore connects through the same HTTPS identity proxy as Android.
No desktop browser is required.

Generate the current hostname and allowed login from the live Tailscale
profile. They remain in private local configuration and the rendered
LaunchAgent, never Stow or tracked source. Refuse another explicitly configured
hub or identity rather than silently switching notebooks/accounts. Preserve
all other application configuration fields.

The installer owns only an exact root handler and HTTPS listener on 8448;
foreign handlers, alternate proxy paths and an existing Funnel grant are
conflicts, not permission to overwrite or widen access. Verify the actual
backend rejects unauthenticated API requests before publishing. Preserve all
unrelated Serve/Funnel configuration. A converged install neither republishes
the route nor restarts an active hub/TUI. Initial backend restarts and phone
installation require current human permission and a phone lease.

This trades direct loopback convenience for one identity-checked route on
every client. Notes stay in the original hub/CLI stores; adding a phone creates
another synchronized offline replica, never a destructive migration. Android
can work offline after loading, but synchronization still depends on the Mac
being awake, logged in and reachable over Tailscale.
