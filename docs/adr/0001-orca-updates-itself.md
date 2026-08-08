# 1. Orca updates itself; Funk only installs it

Funk installs the Orca cask when it is missing and never upgrades it. Orca ships
an updater that stages a release and applies it on quit, and its cask sets
`auto_updates true` so Homebrew defers to that; `brew upgrade --greedy` is the
one flag that overrides the deference, and using it replaced the bundle under a
running app, whose renderer could then no longer resolve the code-split chunks
it had started from.

This is a deliberate exception to Funk's rule that everything converges through
this repository: convergence that corrupts a running application is worse than
letting the application converge itself. The cost is that Funk no longer pins
Orca's version, so `funk update` reports the installed bundle's version rather
than driving it.
