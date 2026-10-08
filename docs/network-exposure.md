# Network exposure and retirement checks

The application boundary is loopback first: a web/API backend listens on
`127.0.0.1` or `::1`, and an explicitly owned private Tailscale Serve route
provides remote access. Serve does not replace the application's authorization.
Public Funnel is a separate exposure decision, never an incidental consequence
of moving a backend to loopback.

## Preserve the client contract

Omajot keeps its identity-checked loopback hub on 8799 and private HTTPS route on
8448. Its TUI and Android PWA use the same authenticated endpoint and the same
existing notebook. Network hardening must not reset or relocate either store,
change its allowed identity, or interrupt an active notes session.

AgentStart owns Agentbrain's share ingress and its networking. Its native
Chrome/Android clients already use port 8787 and bearer authentication. A
loopback cutover must preserve that client contract through a private TCP Serve
forward, or explicitly coordinate a client migration. Before the cutover,
inspect every Serve/Funnel proxy to the backend: an unrelated public route can
otherwise become live as soon as a previously tailnet-bound server starts
accepting localhost connections.

## Native service exceptions

SSH and Screen Sharing are macOS socket-activated services. Their wildcard
listeners are not equivalent to wildcard application web servers, and neither
should be disabled or moved behind an HTTP proxy just to empty a socket table.
Keep their Tailscale access and enforce the physical-network boundary through
the guarded PF policy. Apple authentication, discovery and VPN transport also
need separate treatment; a UDP socket is not necessarily an inbound server.

AirPlay and Rapport's existing disabled preferences remain authored in
`libexec/configure-macos`. An explicitly permitted reload can apply those
preferences, but repeated process killing is not a durable network policy.

## One-time retirements, 2026-10-07

The operator explicitly authorized remediation after the listener audit.
Private recovery copies of configuration and route state were retained under
`~/.local/state/funk/network-hardening-<timestamp>`; they are generated local
state, never tracked or Stowed.

- The removed CouchDB installation had left its independently spawned Erlang
  port mapper on wildcard TCP 4369. Before stopping the exact process, verify
  that it belongs to the target account, its executable points into the removed
  CouchDB installation, and the mapper reports no registered Erlang nodes.
  Never kill all Erlang processes by name.
- The exact-marker-owned `io.arthack.agentstart.serve-mcp` LaunchAgent still
  attempted the retired command. Stop and remove only that owned service
  description; preserve native credentials and private configuration.
- The archived Source webhook's public HTTPS 443 root handler forwarded to an
  absent loopback backend on 8787. Its retirement is bounded to that exact
  handler/listener/Funnel grant. A different proxy, additional handler or active
  backend is a conflict requiring reassessment, not permission to reset Serve.
  All unrelated routes, including Omajot's, must remain unchanged.

These are completed maintenance operations, not new recurring installer phases
or compatibility services. Active-source installers no longer recreate their
retired owners.

## Acceptance

- `funk harden status` must validate the selected posture on every current
  physical interface, including interfaces appearing after boot. Reconciliation
  must not infer a trusted home network or repeatedly reload unchanged rules.
- Recheck both IPv4 and IPv6 TCP listeners with `netstat -anv -p tcp`; use
  `lsof` to attribute user-owned processes. Kernel inspection is necessary
  because unprivileged `lsof` omits some system-owned listeners.
- Application backends must be loopback-only, intentional private frontends
  must remain tailnet-only, and no retired public Funnel grant may return.
- Agentbrain's unauthenticated health request must be rejected and its
  authenticated `agentbrain doctor --json` share-ingress check must pass.
- Omajot must remain online with no pending changes, without a hub/TUI restart
  or alteration to its existing stores.
- A socket inventory or a probe from the Mac itself does not prove remote LAN
  reachability. Distinguish saved configuration, effective privileged PF rules,
  and an independently authorized external-device test when reporting results.
