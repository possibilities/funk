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
