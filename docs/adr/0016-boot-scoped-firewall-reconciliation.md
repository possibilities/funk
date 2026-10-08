# 0016: Boot-scoped firewall reconciliation

- Status: Accepted
- Date: 2026-10-07
- Extends: [0008: Explicit home firewall posture](0008-explicit-home-firewall-posture.md)

## Context

The boot-only renderer fenced interfaces present at startup. Ethernet `en6`
appeared later and remained exposed until manual reapplication. Reapplying also
reloaded the entire main PF ruleset unnecessarily. Repeating the old `boot`
action would fix interface drift but silently revoke an explicit home selection.
An earlier foreign quick pass can bypass a later Funk anchor, while duplicate
Funk traversals add no protection.

## Decision

The existing guarded root LaunchDaemon invokes `reconcile` at load and every ten
seconds. A kernel boot-session UUID binds the root-owned posture marker to this
boot: missing, stale or invalid selection falls back to travel. Only the manual
`home` action can select the existing fixed `en6` IPv4 exception. Reconciliation,
adapter detachment and same-boot installation retain that selection; a new boot
does not. Root actions serialize with a bounded `shlock` wait. Sudoers remains
enumerated to `status`, `travel` and `home`, without a new account grant.

Render `en6` even when absent and remember observed physical names in guarded
generated state. PF binds retained named-interface rules when those interfaces
attach, so known adapters have no hot-plug polling gap. Apple PF matches exact
interface identities, not an `en*` group (see `pfi_kif_match` and
`pfi_attach_ifnet` in [XNU's PF interface implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/pf_if.c)).
For genuinely unseen names, choose periodic convergence over a new event-driven
root program or an inbound blanket that would change virtual-interface policy.
The nominal ten-second interval is not a hard real-time security guarantee.

Compare PF's canonical parsed rules with the complete effective owned anchor.
Reload only that anchor when different; write markers only when changed. Do not
flush states or touch Tailscale. The installer removes only exact owned traversal
lines and inserts one before foreign filter rules, preserving every foreign byte
and relative order. Reload the main ruleset only when its effective owned
traversal is missing, duplicated or misordered. Retain foreign anchors rather
than guessing ownership of historical rules.

## Consequences

The reported `en6` startup hole is closed by prebound rules, while unfamiliar
hardware still has a polling window until a successful reconciliation. Sleep,
load or helper failure can lengthen it. Status checks complete anchor equality
and traversal as well as interface blocks. A first upgrade safely selects travel
because the old installation has no boot-session marker.

Converged source/installed comparisons avoid authentication, PF reloads and
LaunchDaemon restarts. A traversal repair may replace transient main-ruleset
additions with `/etc/pf.conf`; those additions need their own durable owner.
Existing connection states survive posture tightening deliberately, preserving
active applications and remote sessions. Legacy anchor removal remains a
separate ownership decision.
