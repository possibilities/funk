# 0004: Kiosk persistence lifecycle and instance identity

- Status: Accepted
- Date: 2026-09-14

## Context

The kiosk launcher uses `WKWebsiteDataStore.defaultDataStore`. An isolated
native process test established that this store preserves `localStorage` across
process termination and a same-identifier bundle replacement, while
`sessionStorage` correctly receives a new identity in a new process.

That browser-style session boundary is insufficient for a single-window kiosk.
A web application cannot otherwise distinguish a restarted kiosk window from a
new ordinary browser tab. AppKit termination also did not dispatch `pagehide`
soon enough for the loaded page to flush a same-tick edit.

## Decision

The launcher injects a read-only main-frame
`window.funkKiosk.persistenceInstanceId` at document start. Its value is the
application's stable bundle identifier followed by `:main`. This contract is
valid because every kiosk launcher application owns exactly one main window.
Web applications may use the optional value to keep the same persistence owner
across kiosk process restarts. Ordinary browsers omit it and retain their own
per-tab ownership.

When AppKit asks the launcher to terminate, the launcher returns
`NSTerminateLater`, dispatches a standard nonpersisted `pagehide` event into the
main page, and replies as soon as that JavaScript finishes. A 500 ms fallback
allows termination if the web process does not respond. The launcher neither
reads nor interprets page state.

## Consequences

Production AgentVoice, TEST AgentVoice, and AgentChats remain isolated because
their bundle identifiers are different. A future launcher that creates multiple
windows must give each window a distinct stable identity before it can use this
bridge.

The page owns its persistence format and synchronous lifecycle handler. Abrupt
process death remains outside the termination hook, so pages that need
same-keystroke crash recovery must journal that state as the input changes.
The native storage harness tests process restart, bundle replacement,
termination dispatch, and bundle-identifier isolation without opening a visible
window or using either installed kiosk profile.
