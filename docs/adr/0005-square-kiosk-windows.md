# 0005: Square kiosk windows

- Status: Accepted
- Date: 2026-09-14

## Decision

The three kiosk launcher applications share a pure borderless AppKit window
with an opaque rectangular background and native shadow. Hidden titlebar
furniture on a titled window leaves the system's rounded frame; no private
corner APIs or view-class replacement is used.

The launcher now owns the missing native interaction boundaries: key/main
focus eligibility, a transparent top-20-point drag region, and a 6-point outer
resize region with a 640×400 minimum. Dragging uses the public Window Server
handoff. Resizing derives every frame from the initial frame and event-global
pointer displacement so queued events cannot accumulate origin feedback.
Ordinary web content outside these regions retains its input routing.

The existing Close menu action now requests application termination before
closing the window. This preserves [ADR 0004's pagehide handshake](0004-kiosk-persistence-lifecycle-and-instance-identity.md).
The window also exposes accessibility frame changes and Close/Minimize actions.
Full-screen Spaces stay disabled; window names, frame autosave identity, data
store and kiosk persistence identity are unchanged.

## Consequences

Window management is explicit launcher code instead of inherited titled-window
behavior. Geometry, hit routing and minimum bounds have native headless tests;
visible drag, resize, text entry, shadow, accessibility and close behavior need
a disposable-window check when these mechanisms change. Never substitute a
relaunch of a human's kiosk for a test fixture without an explicit handoff.
