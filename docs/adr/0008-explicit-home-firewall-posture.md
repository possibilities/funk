# 0008: Explicit home firewall posture

- Status: Accepted
- Date: 2026-09-20

## Context

Funk's boot firewall applies a fail-closed travel posture to every physical
interface. That protects an unattended restart on an unknown network, but it
also prevents Greybird from receiving direct LAN traffic from trusted hosts at
home. Automatically recognizing the home network would let a mistaken or stale
signal relax the firewall without an operator decision.

## Decision

Boot continues to apply `travel`. `funk harden home` is the only way to select
the home posture, and it must be invoked manually. It permits inbound IPv4 on
`en6` from the fixed trusted subnet `192.168.50.0/24` before the interface's
quick block. It does not relax any other physical interface or change the
existing loopback, outbound-state, DHCP, mDNS, IPv6-neighbor, or Tailscale
behavior.

The privileged helper validates the fixed interface and subnet, parses the
rendered PF rules, and checks the expected allow-before-block shape before it
loads the anchor or records the posture. `funk harden status` compares the
marker with the effective rules. `funk harden travel` restores the exact boot
posture.

## Consequences

Direct home-LAN access requires one explicit action after boot. A restart always
returns to travel, so home access is unavailable until the operator selects it
again. Adding another trusted interface or subnet requires a reviewed source
change and updated policy tests; environment variables and network-location
detection cannot widen the exception.
