#!/bin/bash
set -euo pipefail
root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-notification-diagnosis.XXXXXX")
trap 'rm -rf "$fixture_home"' EXIT
mkdir -p "$fixture_home/.local/bin"
cat >"$fixture_home/.local/bin/terminal-notifier" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$DIAGNOSE_LOG"
case "$1" in
    --version) printf 'agentnotify 0.1.0\n' ;;
    diagnose) printf '{"data":{"native":{"authorization":"%s"}}}\n' "$TEST_AUTHORIZATION" ;;
    *) exit 99 ;;
esac
EOF
chmod +x "$fixture_home/.local/bin/terminal-notifier"
for authorization in authorized denied not-determined; do
    : >"$fixture_home/calls"
    result=0
    HOME="$fixture_home" DIAGNOSE_LOG="$fixture_home/calls" TEST_AUTHORIZATION="$authorization" \
        "$root/libexec/verify-notifications" >"$fixture_home/output" 2>&1 || result=$?
    if [ "$authorization" = authorized ]; then [ "$result" -eq 0 ]; else [ "$result" -eq 1 ]; fi
    grep -F AgentNotify "$fixture_home/output" >/dev/null
    [ "$(wc -l <"$fixture_home/calls" | tr -d ' ')" = 2 ]
    grep -Fx diagnose "$fixture_home/calls" >/dev/null
done
printf 'Managed notifier diagnosis passed without sending or removing inbox items.\n'
