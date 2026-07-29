#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Android flex (no audio)
# @raycast.mode silent
# Optional parameters:
# @raycast.icon 📱
# @raycast.packageName Funk

set -euo pipefail
serial=$("$HOME/.local/bin/adb-wireless-connect" --print-serial)
scrcpy -s "$serial" --stay-awake --keep-active --keyboard=uhid --no-audio --new-display --flex-display &
disown
