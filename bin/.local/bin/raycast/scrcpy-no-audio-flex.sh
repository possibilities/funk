#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Android flex (no audio)
# @raycast.mode silent
# Optional parameters:
# @raycast.icon 📱
# @raycast.packageName Funk

set -euo pipefail

# Raycast runs this without the interactive shell's environment, so put the
# Homebrew and Tailscale locations on PATH before looking for adb and scrcpy.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH
export ADB_MDNS_AUTO_CONNECT=0
export ADB_USB=0
export ADB_SERVER_SOCKET=tcp:localhost:5038

connect_helper=${ADB_WIRELESS_CONNECT:-"$HOME/.local/bin/adb-wireless-connect"}
scrcpy_bin=${SCRCPY:-scrcpy}
if ! serial=$("$connect_helper" --print-serial); then
    printf 'Android: connection recovery failed.\n' >&2
    exit 1
fi
case "$serial" in
    ''|*'
'*) printf 'Android: connection helper returned an invalid serial.\n' >&2; exit 1 ;;
esac

"$scrcpy_bin" -s "$serial" --stay-awake --keep-active --keyboard=uhid --no-audio --new-display --flex-display &
disown
