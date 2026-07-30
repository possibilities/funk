#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Android (audio)
# @raycast.mode silent
# Optional parameters:
# @raycast.icon 📱
# @raycast.packageName Funk

set -euo pipefail

# Raycast runs this without the interactive shell's environment, so put the
# Homebrew and Tailscale locations on PATH before looking for adb and scrcpy.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

if ! serial=$("$HOME/.local/bin/adb-wireless-connect" --print-serial 2>&1); then
    printf 'Android: %s\n' "$serial" >&2
    exit 1
fi

scrcpy -s "$serial" --stay-awake --keep-active --keyboard=uhid &
disown
