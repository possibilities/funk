#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Android (audio)
# @raycast.mode silent
# Optional parameters:
# @raycast.icon 📱
# @raycast.packageName Funk

set -euo pipefail
serial=$("$HOME/.local/bin/adb-wireless-connect" --print-serial)
scrcpy -s "$serial" --stay-awake --keep-active --keyboard=uhid &
disown
