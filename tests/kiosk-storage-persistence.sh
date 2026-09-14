#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-kiosk-storage-test.XXXXXX")
bundle_id="com.arthack.funk.tests.kioskpersistence.$$"
other_bundle_id="$bundle_id.other"
app="$test_dir/Funk Storage Harness.app"
server_pid=

cleanup() {
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid"
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
    rm -rf "$HOME/Library/WebKit/$bundle_id"
    rm -rf "$HOME/Library/WebKit/$other_bundle_id"
    rm -rf "$HOME/Library/Caches/$bundle_id"
    rm -rf "$HOME/Library/Caches/$other_bundle_id"
    rm -rf "$HOME/Library/HTTPStorages/$bundle_id"
    rm -rf "$HOME/Library/HTTPStorages/$other_bundle_id"
    rm -rf "$HOME/Library/Saved Application State/$bundle_id.savedState"
    rm -rf "$HOME/Library/Saved Application State/$other_bundle_id.savedState"
}
trap cleanup EXIT

fail() {
    printf 'kiosk storage persistence test: %s\n' "$*" >&2
    exit 1
}

render_bundle() {
    local destination=$1
    local identifier=${2:-$bundle_id}
    local contents="$destination/Contents"
    mkdir -p "$contents/MacOS"
    cp "$test_dir/kiosk-storage-harness" "$contents/MacOS/KioskStorageHarness"
    /usr/bin/plutil -create xml1 "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleDisplayName -string 'Funk Storage Harness' "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string KioskStorageHarness "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string "$identifier" "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleName -string 'Funk Storage Harness' "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundlePackageType -string APPL "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleShortVersionString -string 1.0 "$contents/Info.plist"
    /usr/bin/plutil -insert CFBundleVersion -string 1 "$contents/Info.plist"
    /usr/bin/plutil -insert LSBackgroundOnly -bool true "$contents/Info.plist"
    /usr/bin/codesign --force --sign - --identifier "$identifier" "$destination" >/dev/null
}

/usr/bin/clang -std=c11 -Os -Wall -Wextra -Werror -fobjc-arc \
    -mmacosx-version-min=13.0 \
    -I "$root/libexec" \
    -framework AppKit -framework Foundation -framework WebKit \
    "$root/tests/fixtures/kiosk-storage-harness.m" \
    -o "$test_dir/kiosk-storage-harness"

mkdir "$test_dir/site"
cat >"$test_dir/site/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<textarea id="composer"></textarea>
<script>
addEventListener('pagehide', () => {
  localStorage.setItem('funk-pagehide-draft', document.querySelector('#composer').value);
});
</script>
EOF

python3 - "$test_dir/site" "$test_dir/server-port" <<'PY' &
import http.server
import os
import pathlib
import socketserver
import sys

os.chdir(sys.argv[1])
with socketserver.TCPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler) as server:
    pathlib.Path(sys.argv[2]).write_text(str(server.server_address[1]))
    server.serve_forever()
PY
server_pid=$!

attempts=0
while [ ! -s "$test_dir/server-port" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || fail "fixture server did not start"
    sleep 0.05
done
url="http://127.0.0.1:$(cat "$test_dir/server-port")/"

cat >"$test_dir/write.js" <<'EOF'
localStorage.setItem('funk-fixture-draft', 'local draft survives');
sessionStorage.setItem('funk-fixture-draft', 'session draft ends');
document.querySelector('#composer').value = 'typed fixture text';
return {
  localStorage: localStorage.getItem('funk-fixture-draft'),
  sessionStorage: sessionStorage.getItem('funk-fixture-draft'),
  textarea: document.querySelector('#composer').value,
  persistenceInstanceId: window.funkKiosk?.persistenceInstanceId ?? null,
};
EOF
cat >"$test_dir/read.js" <<'EOF'
return {
  localStorage: localStorage.getItem('funk-fixture-draft'),
  sessionStorage: sessionStorage.getItem('funk-fixture-draft'),
  textarea: document.querySelector('#composer').value,
  pageHideDraft: localStorage.getItem('funk-pagehide-draft'),
  persistenceInstanceId: window.funkKiosk?.persistenceInstanceId ?? null,
};
EOF

render_bundle "$app"
"$app/Contents/MacOS/KioskStorageHarness" "$url" "$test_dir/write.js" 250 graceful \
    >"$test_dir/write.json"

# Match the kiosk installer's bundle swap: replace the application while no
# process is running, preserving its path and bundle identifier.
render_bundle "$test_dir/replacement.app"
mv "$app" "$test_dir/previous.app"
mv "$test_dir/replacement.app" "$app"

"$app/Contents/MacOS/KioskStorageHarness" "$url" "$test_dir/read.js" 0 graceful \
    >"$test_dir/read.json"

other_app="$test_dir/Other Storage Harness.app"
render_bundle "$other_app" "$other_bundle_id"
"$other_app/Contents/MacOS/KioskStorageHarness" "$url" "$test_dir/read.js" 0 graceful \
    >"$test_dir/read-other.json"

python3 - "$test_dir/write.json" "$test_dir/read.json" "$test_dir/read-other.json" \
    "$bundle_id" "$other_bundle_id" <<'PY'
import json
import sys

write = json.load(open(sys.argv[1]))
read = json.load(open(sys.argv[2]))
read_other = json.load(open(sys.argv[3]))
bundle_id = sys.argv[4]
other_bundle_id = sys.argv[5]

assert write["bundleIdentifier"] == bundle_id
assert read["bundleIdentifier"] == bundle_id
assert write["persistentDataStore"] is True
assert read["persistentDataStore"] is True
assert write["result"] == {
    "localStorage": "local draft survives",
    "persistenceInstanceId": bundle_id + ":main",
    "sessionStorage": "session draft ends",
    "textarea": "typed fixture text",
}
assert read["result"] == {
    "localStorage": "local draft survives",
    "pageHideDraft": "typed fixture text",
    "persistenceInstanceId": bundle_id + ":main",
    "sessionStorage": None,
    "textarea": "",
}
assert read_other["bundleIdentifier"] == other_bundle_id
assert read_other["persistentDataStore"] is True
assert read_other["result"] == {
    "localStorage": None,
    "pageHideDraft": None,
    "persistenceInstanceId": other_bundle_id + ":main",
    "sessionStorage": None,
    "textarea": "",
}
print(json.dumps({"write": write, "reopen": read, "otherBundle": read_other}, sort_keys=True))
PY

printf 'Kiosk default data store persists localStorage across process exit and bundle replacement.\n'
