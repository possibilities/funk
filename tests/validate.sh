#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fail() {
    printf 'validate: %s\n' "$*" >&2
    exit 1
}

shell_files="
install
bin/funk
libexec/funk-update
libexec/install-update-agent
libexec/funk-harden-client
libexec/install-hardening
libexec/funk-yabai
libexec/install-window-manager
system/funk-harden
system/install-hardening-root
system/funk-yabai-maintain
system/install-yabai-root
config/yabai/yabairc
tests/fixtures/brew
tests/validate.sh
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    # The checker treats the skhd DSL as shell, so it is intentionally excluded.
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

/usr/bin/plutil -lint launchd/com.arthack.funk.update.plist.in >/dev/null
/usr/bin/plutil -lint system/com.arthack.funk.harden-boot.plist >/dev/null
update_plist=launchd/com.arthack.funk.update.plist.in
[ "$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Hour' "$update_plist")" = 10 ] \
    || fail "daily updater hour is not 10"
[ "$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Minute' "$update_plist")" = 0 ] \
    || fail "daily updater minute is not 00"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$update_plist")" = update ] \
    || fail "daily updater does not invoke funk update"
if /usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$update_plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$update_plist" >/dev/null 2>&1; then
    fail "daily updater has an unapproved extra trigger"
fi

if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      data = JSON.parse(File.read(ARGV.fetch(0)))
      rules = data.fetch("profiles").fetch(0)
                  .fetch("complex_modifications").fetch("rules")
      abort "unexpected Karabiner rule count" unless rules.length == 2
      abort "unexpected Karabiner manipulator counts" unless rules.map { |r| r.fetch("manipulators").length } == [9, 9]
    ' \
        config/karabiner/karabiner.json
elif command -v jq >/dev/null 2>&1; then
    jq -e '
      (.profiles[0].complex_modifications.rules | length) == 2 and
      ([.profiles[0].complex_modifications.rules[].manipulators | length] == [9, 9])
    ' config/karabiner/karabiner.json >/dev/null
else
    fail "Ruby or jq is required to validate Karabiner JSON"
fi

expected_brewfile='tap "asmvik/formulae"
brew "asmvik/formulae/yabai"
brew "asmvik/formulae/skhd"
cask "tailscale-app"
cask "ghostty"
cask "google-chrome"
cask "google-chrome@canary"
cask "brave-browser"
cask "chatgpt"
cask "claude"
cask "obsidian"
cask "raycast"
cask "karabiner-elements"'
actual_brewfile=$(grep -Ev '^[[:space:]]*$' Brewfile)
[ "$actual_brewfile" = "$expected_brewfile" ] \
    || fail "Brewfile declarations differ from the approved set"

if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --formula >/dev/null
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --cask >/dev/null
fi

set +e
update_output=$(
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_TEST_BREW_EXIT=23 \
        "$root/bin/funk" update 2>&1
)
update_status=$?
set -e
[ "$update_status" -eq 23 ] || fail "funk update did not propagate brew exit 23"
printf '%s\n' "$update_output" \
    | grep -F "brew-stub <bundle> <install> <--file=$root/Brewfile>" >/dev/null \
    || fail "funk update invoked an unexpected brew command"
printf '%s\n' "$update_output" | grep -F 'FAILED with exit status 23' >/dev/null \
    || fail "funk update did not log failure"

PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_BREW_EXIT=0 \
    "$root/bin/funk" update >/dev/null
"$root/bin/funk" install-updater --check >/dev/null

[ "$(grep -Ec '^f(13|14|15|16|17|18|19|20|21) : yabai -m space --focus [1-9]$' config/skhd/skhdrc)" -eq 9 ] \
    || fail "skhd numbered-Space focus bindings are incomplete"
[ "$(grep -Ec '^cmd \+ shift - [1-9] : yabai -m window --space [1-9]$' config/skhd/skhdrc)" -eq 9 ] \
    || fail "skhd numbered-Space move bindings are incomplete"
if grep -Eq 'right_option|left_command|left_option|Swap .*Command|hjkl to arrow' \
    config/karabiner/karabiner.json; then
    fail "unapproved Karabiner rules found"
fi

if grep -Eqi 'bundle cleanup|uninstall|quarantine|fetch-head|telegram|notify|sudo' \
    bin/funk libexec/funk-update libexec/install-update-agent \
    launchd/com.arthack.funk.update.plist.in; then
    fail "daily updater contains a prohibited operation"
fi

if grep -R -E '/Users/[^/]+|greybird|home.router|telegram|agentnotify|TCC\.db|security import|yabai-cert' \
    Brewfile bin config launchd libexec system >/dev/null; then
    fail "old-account or prohibited privileged machinery leaked into Funk"
fi

if grep -R -E 'NOPASSWD:[[:space:]]*(ALL|/[^[:space:]]+[[:space:]]+\*)' \
    system >/dev/null; then
    fail "broad passwordless sudo rule found"
fi

if [ "$(uname -s)" = Darwin ] && [ -x /sbin/pfctl ]; then
    "$root/system/funk-harden" render | /sbin/pfctl -nf - >/dev/null 2>&1
fi

git diff --check
printf 'validate: all non-destructive checks passed\n'
