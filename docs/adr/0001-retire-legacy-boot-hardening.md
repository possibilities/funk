# 0001: Funk's hardening installer retires the pre-Funk boot daemon

The machine booted under `harden.boot`, a root LaunchDaemon from the retired
dotfiles that applied a fail-closed `travel` anchor and relied on a login agent,
already gone, to relax it, so every reboot left the physical LAN inbound-denied
with nothing to change that. `system/install-hardening-root` now applies Funk's
own posture synchronously and then boots that daemon out, removes its plist and
helper, drops its anchor traversal from `/etc/pf.conf`, and flushes its rules,
so the two postures never coexist and the LAN is never briefly unguarded. The
pre-Funk tailnet service fences under `/etc/pf.anchors/` stay untouched: they
restrict ssh, VNC, OBS, and dev ports to the tailnet in every posture, Funk has
no equivalent yet, and removing them would widen exposure.
