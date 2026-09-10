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
    diagnose) printf '{"data":{"native":{"authorization":"%s","available":%s}}}\n' "$TEST_AUTHORIZATION" "$TEST_NATIVE_AVAILABLE" ;;
    *) exit 99 ;;
esac
EOF
chmod +x "$fixture_home/.local/bin/terminal-notifier"
for policy in own-arrivals-only system-notifications; do
    : >"$fixture_home/calls"
    result=0
    if [ "$policy" = own-arrivals-only ]; then
        authorization=disabled
        native_available=false
    else
        authorization=authorized
        native_available=true
    fi
    HOME="$fixture_home" DIAGNOSE_LOG="$fixture_home/calls" TEST_AUTHORIZATION="$authorization" \
        TEST_NATIVE_AVAILABLE="$native_available" \
        "$root/libexec/verify-notifications" >"$fixture_home/output" 2>&1 || result=$?
    if [ "$policy" = own-arrivals-only ]; then
        [ "$result" -eq 0 ]
        grep -F 'macOS system notifications are disabled by design' "$fixture_home/output" >/dev/null
    else
        [ "$result" -eq 1 ]
        grep -F 'required own-arrivals-only policy' "$fixture_home/output" >/dev/null
    fi
    grep -F AgentNotify "$fixture_home/output" >/dev/null
    [ "$(wc -l <"$fixture_home/calls" | tr -d ' ')" = 2 ]
    grep -Fx diagnose "$fixture_home/calls" >/dev/null
done
printf 'Managed notifier own-arrivals-only diagnosis passed without sending or removing inbox items.\n'
