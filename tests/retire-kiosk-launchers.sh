#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-retire-kiosk-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'retire kiosk launchers test: %s\n' "$*" >&2
    exit 1
}

write_bundle() {
    local bundle=$1 identifier=$2

    mkdir -p "$bundle/Contents"
    cat >"$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$identifier</string></dict></plist>
EOF
}

test_home="$test_dir/home"
applications="$test_home/Applications"
lsregister="$test_dir/lsregister"
mkdir -p "$test_home"
cat >"$lsregister" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${FUNK_TEST_LSREGISTER_LOG:?}"
EOF
chmod 0755 "$lsregister"

run_retirement() {
    HOME="$test_home" FUNK_KIOSK_APPLICATIONS_DIR="$applications" \
        FUNK_LSREGISTER="$lsregister" FUNK_TEST_LSREGISTER_LOG="$test_dir/lsregister.log" \
        "$root/libexec/retire-kiosk-launchers"
}

# The former installer is no longer a public Funk command.
if "$root/bin/funk" install-kiosk-launchers >"$test_dir/public.out" 2>"$test_dir/public.err"; then
    fail 'retired kiosk installer remains a public command'
fi
grep -F 'unknown command: install-kiosk-launchers' "$test_dir/public.err" >/dev/null \
    || fail 'retired kiosk command did not report itself as unknown'

# A clean/fresh installation creates neither a replacement applications
# directory nor any wrappers.
run_retirement >"$test_dir/fresh.out"
[ ! -e "$applications" ] || fail 'fresh retirement created Applications'

mkdir -p "$applications" "$test_home/Library/WebKit/com.arthack.funk.kiosk.agentvoice" \
    "$test_home/.local/state/funk/chrome-kiosk"
printf 'WebKit history\n' >"$test_home/Library/WebKit/com.arthack.funk.kiosk.agentvoice/sentinel"
printf 'Chrome profile\n' >"$test_home/.local/state/funk/chrome-kiosk/sentinel"

write_bundle "$applications/AgentVoice Transcripts.app" com.arthack.funk.kiosk.agentvoice
write_bundle "$applications/AgentVoice TEST Transcripts.app" com.arthack.funk.kiosk.agentvoice-test
write_bundle "$applications/AgentHUD.app" com.example.foreign
write_bundle "$applications/AgentVoice.app" io.arthack.agentvoice.menu

# A known interrupted installer transaction is removable only after both the
# exact marker and embedded bundle identifier agree.
transaction="$applications/.AgentHUD.app.funk-transaction"
mkdir "$transaction"
printf '%s\n' 'funk-kiosk-launcher-transaction-v1:com.arthack.funk.kiosk.agenthud' \
    >"$transaction/owner"
write_bundle "$transaction/backup.app" com.arthack.funk.kiosk.agenthud

mkdir -p "$test_home/.local/bin/raycast" "$test_dir/old-funk/bin/.local/bin/raycast"
ln -s "$test_dir/old-funk/bin/.local/bin/raycast/localhost-8789-kiosk.sh" \
    "$test_home/.local/bin/raycast/localhost-8789-kiosk.sh"
ln -s "$test_dir/foreign-raycast.sh" "$test_home/.local/bin/raycast/foreign.sh"

run_retirement >"$test_dir/retire.out" 2>"$test_dir/retire.err"
[ ! -e "$applications/AgentVoice Transcripts.app" ] \
    || fail 'owned AgentVoice launcher survived retirement'
[ ! -e "$applications/AgentVoice TEST Transcripts.app" ] \
    || fail 'owned AgentVoice TEST launcher survived retirement'
[ ! -e "$transaction" ] || fail 'known transaction remnant survived retirement'
[ -d "$applications/AgentHUD.app" ] || fail 'foreign AgentHUD bundle was removed'
[ -d "$applications/AgentVoice.app" ] || fail 'native AgentVoice.app was removed'
[ "$(cat "$test_home/Library/WebKit/com.arthack.funk.kiosk.agentvoice/sentinel")" = 'WebKit history' ] \
    || fail 'WebKit data was changed'
[ "$(cat "$test_home/.local/state/funk/chrome-kiosk/sentinel")" = 'Chrome profile' ] \
    || fail 'Chrome kiosk profile was changed'
[ ! -e "$test_home/.local/bin/raycast/localhost-8789-kiosk.sh" ] \
    || fail 'owned Raycast kiosk launcher survived retirement'
[ -L "$test_home/.local/bin/raycast/foreign.sh" ] \
    || fail 'unrelated Raycast launcher was changed'
grep -F -- "-u $applications/AgentVoice Transcripts.app" "$test_dir/lsregister.log" >/dev/null \
    || fail 'owned AgentVoice launcher was not unregistered'
grep -F -- "-u $applications/AgentVoice TEST Transcripts.app" "$test_dir/lsregister.log" >/dev/null \
    || fail 'owned AgentVoice TEST launcher was not unregistered'
if grep -F -- "$applications/AgentHUD.app" "$test_dir/lsregister.log" >/dev/null \
    || grep -F -- "$applications/AgentVoice.app" "$test_dir/lsregister.log" >/dev/null; then
    fail 'a preserved bundle was unregistered'
fi

# Repeating convergence neither removes preserved data nor creates wrappers.
run_retirement >"$test_dir/repeat.out" 2>"$test_dir/repeat.err"
[ ! -s "$test_dir/repeat.out" ] || fail 'retirement was not idempotent'
[ -d "$applications/AgentHUD.app" ] || fail 'foreign bundle changed on repeat'
[ -d "$applications/AgentVoice.app" ] || fail 'native AgentVoice changed on repeat'

# Unknown transaction contents are not cleanup authority.
foreign_transaction="$applications/.AgentVoice TEST Transcripts.app.funk-transaction"
mkdir "$foreign_transaction"
printf '%s\n' 'funk-kiosk-launcher-transaction-v1:com.arthack.funk.kiosk.agentvoice-test' \
    >"$foreign_transaction/owner"
printf 'do not remove\n' >"$foreign_transaction/unrecognized"
run_retirement >"$test_dir/foreign-transaction.out" 2>"$test_dir/foreign-transaction.err"
[ -e "$foreign_transaction/unrecognized" ] \
    || fail 'unrecognized transaction artifact was removed'
grep -F 'preserving kiosk transaction with an unknown artifact' \
    "$test_dir/foreign-transaction.err" >/dev/null \
    || fail 'unrecognized transaction was not reported'

printf 'Kiosk retirement tests passed.\n'
