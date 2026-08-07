#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/bin/.local/bin/funk-notify"
notifier_fixture="$root/tests/fixtures/terminal-notifier"
test_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-notify-test.XXXXXX")
trap 'rm -rf "$test_home"' EXIT
log="$test_home/notifications"

fail() {
    printf 'funk-notify test: %s\n' "$*" >&2
    exit 1
}

run() {
    FUNK_TERMINAL_NOTIFIER_BIN="$notifier_fixture" FUNK_TEST_NOTIFIER_LOG="$log" \
        "$helper" "$@"
}

last() { tail -n 1 "$log"; }

: >"$log"
run --title T --message M || fail "a plain notification must succeed"
case "$(last)" in
    *"<-title> <T>"*"<-message> <M>"*"<-ignoreDnD>"*) ;;
    *) fail "title, message and DnD override must be passed: $(last)" ;;
esac

: >"$log"
run --title T --message M --sound default --group G || fail "sound and group must succeed"
case "$(last)" in
    *"<-sound> <default>"*"<-group> <G>"*) ;;
    *) fail "sound and group must be passed: $(last)" ;;
esac

# A remedy that talks to a terminal must get one, or its output goes nowhere.
: >"$log"
run --title T --message M --terminal "gog auth login" || fail "--terminal must succeed"
case "$(last)" in
    *"<-execute> <osascript"*"Terminal"*"gog auth login"*) ;;
    *) fail "--terminal must open a terminal: $(last)" ;;
esac

: >"$log"
run --title T --message M --execute "open https://example.com" || fail "--execute must succeed"
case "$(last)" in
    *"<-execute> <open https://example.com>"*) ;;
    *) fail "--execute must pass the command verbatim: $(last)" ;;
esac

run --title T --message M --execute a --terminal b 2>/dev/null \
    && fail "--execute and --terminal must not be combined"
run --message M 2>/dev/null && fail "--title must be required"
run --title T 2>/dev/null && fail "--message must be required"

# A missing notifier is not the caller's failure: the outcome is the product.
: >"$log"
FUNK_TERMINAL_NOTIFIER_BIN=/nonexistent PATH=/nonexistent "$helper" \
    --title T --message M || fail "a missing notifier must still exit zero"
[ ! -s "$log" ] || fail "a missing notifier must post nothing"

printf 'funk-notify tests passed\n'
