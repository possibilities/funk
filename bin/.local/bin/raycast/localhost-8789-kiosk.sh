#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Localhost 8789 (kiosk)
# @raycast.mode silent
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Funk

set -euo pipefail

# Raycast runs this without the interactive shell's environment, so put the
# Homebrew locations on PATH before looking for anything outside /usr/bin.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

url=${FUNK_KIOSK_URL:-http://localhost:8789/}
chrome=${FUNK_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
# A dedicated profile is what makes kiosk mode reliable: launching through
# `open` reuses an already-running Chrome and silently discards --kiosk.
profile=${FUNK_KIOSK_PROFILE:-$HOME/.local/state/funk/chrome-kiosk}
nc=${NC:-/usr/bin/nc}

rest=${url#*://}
hostport=${rest%%/*}
host=${hostport%%:*}
port=${hostport##*:}
if [ "$port" = "$hostport" ]; then
    case "$url" in
        https://*) port=443 ;;
        *) port=80 ;;
    esac
fi
case "$host" in
    '') printf 'Kiosk: %s has no host to connect to.\n' "$url" >&2; exit 1 ;;
esac

if ! "$nc" -z -G 2 "$host" "$port" >/dev/null 2>&1; then
    printf 'Kiosk: nothing is listening on %s:%s.\n' "$host" "$port" >&2
    exit 1
fi

if [ ! -x "$chrome" ]; then
    printf 'Kiosk: Google Chrome is not installed at %s.\n' "$chrome" >&2
    exit 1
fi

mkdir -p "$profile"
# A fresh profile otherwise opens the welcome and default-browser prompts
# inside the kiosk window, where they are awkward to dismiss.
"$chrome" --user-data-dir="$profile" --no-first-run --no-default-browser-check \
    --kiosk --app="$url" >/dev/null 2>&1 &
disown
