# Context

Funk's own vocabulary. Use these terms in code, commits, and documentation.

**Scheduled path** — the work `funk update --notify` does when the
`com.arthack.funk.update` LaunchAgent runs it, four times a day, with no
terminal and no way to answer a password prompt. Anything that cannot converge
under those conditions is triaged out and reported rather than attempted.
_Avoid_: cron job, background update, unattended run.

**Bundle swap** — replacing an application's bundle on disk while the
application is running. The process keeps resolving paths into a bundle that is
no longer the one it launched from, so lazily loaded code fails against
content it was never built against. Distinct from an upgrade, which is a bundle
swap only when nothing is running.
_Avoid_: in-place upgrade, hot update.

**Install-only convergence** — installing a package when it is missing while
leaving an installed copy at whatever version it is on. What Funk does for a
component that ships its own updater, so the two updaters do not compete.
_Avoid_: pinning, freezing, skipping.

**Unattendable cask** — a Homebrew cask the scheduled path cannot converge:
it installs a pkg, its removal steps run a privileged script, its application
belongs to another local account, or its recorded install directories point
into another account's home. Named for `HOMEBREW_BUNDLE_CASK_SKIP` and reported
as `Needs ./install: …`.
_Avoid_: broken cask, failed cask.

**Generated host file** — a file under `~/.ssh/config.d/` whose first line is
`funk ssh-tailnet-config`'s marker. The marker is the only proof of ownership
the generator has, so it is also the only thing it may overwrite or prune;
everything else in that directory belongs to the operator.
_Avoid_: managed host, stowed host, tailnet config, hardcoded hosts.

**Keychain hold** — the recorded verdict that stops the unattended path
re-reading an item whose access no human has approved, so a refusal costs one
dialog rather than one every thirty seconds. Cleared by
`home-awake --authorize`.
_Avoid_: locked out, denied, blocked.

**Chuchu Lab theme deployment** — The explicit `funk chuchu-theme` action that
copies Funk's canonical Signal Room asset into the Chuchu checkout, rebuilds
and reinstalls the debuggable Lab package with its data retained, selects the
theme, and relaunches it. Its application-ID check runs before ADB so the
official package is outside the command's authority.
_Avoid_: Chuchu update, official theme install, stable replacement.

**Android launcher application** — One of the per-user macOS application
bundles under `~/Applications` that starts a Screen Copy mode and is indexed as
an application by launchers such as Raycast. It replaces the retired Raycast
script commands and is the only supported Android launch surface.
_Avoid_: Raycast Android launcher, script command.

**Fork-and-adapt** — what this repository offers a reader who is not the account
it converges. `./install` is written for one machine and its recorded facts, so
the useful thing to take is a part of it, not a run of it.
_Avoid_: bootstrap, dotfiles framework, general-purpose installer.
