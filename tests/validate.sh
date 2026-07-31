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
libexec/converge-brewfile
libexec/converge-brew-casks
libexec/release-cask-quarantine
libexec/repair-cask-artifacts
libexec/reclaim-app-ownership
libexec/list-unattendable-casks
libexec/install-orca
libexec/stow-config
libexec/initialize-configs
libexec/configure-orca
libexec/install-ai-tools
libexec/install-update-agent
libexec/install-tailscale-agent
libexec/configure-macos
libexec/configure-system
libexec/funk-harden-client
libexec/install-hardening
libexec/funk-yabai
libexec/install-window-manager
system/funk-harden
system/install-hardening-root
system/funk-yabai-maintain
system/install-yabai-root
system/apply-system-settings
yabai/.config/yabai/yabairc
bin/.local/bin/tmux-cycle-session
bin/.local/bin/tmux-move-window
bin/.local/bin/focus-address-bar
bin/.local/bin/ginit
bin/.local/bin/ghinit
bin/.local/bin/tailscale-ensure-online
bin/.local/bin/adb-wireless-connect
bin/.local/bin/adb-wireless-pair
bin/.local/bin/raycast/scrcpy.sh
bin/.local/bin/raycast/scrcpy-no-audio.sh
bin/.local/bin/raycast/scrcpy-flex.sh
bin/.local/bin/raycast/scrcpy-no-audio-flex.sh
tests/adb-wireless.sh
tests/scrcpy-launchers.sh
tests/tailscale-online.sh
tests/fixtures/adb
tests/fixtures/brew
tests/fixtures/dscacheutil
tests/fixtures/dns-sd
tests/fixtures/gh
tests/fixtures/nc
tests/fixtures/npx
tests/fixtures/scrcpy
tests/fixtures/spctl
tests/fixtures/tailscale
tests/fixtures/terminal-notifier
tests/validate.sh
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

/bin/zsh -n zsh/.zshrc zsh/.zsh/aliases/agents.zsh
if grep -R -Eqi 'keeper|KEEPER_ZSH_DROPINS' zsh; then
    fail "removed Keeper shell integration is still present"
fi

if command -v shellcheck >/dev/null 2>&1; then
    # The checker treats the skhd DSL as shell, so it is intentionally excluded.
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

/usr/bin/plutil -lint launchd/com.arthack.funk.update.plist.in >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.tailscale-online.plist.in >/dev/null
/usr/bin/plutil -lint system/com.arthack.funk.harden-boot.plist >/dev/null
update_plist=launchd/com.arthack.funk.update.plist.in
expected_update_hours='0
6
12
18'
actual_update_hours=$(
    for index in 0 1 2 3; do
        /usr/libexec/PlistBuddy \
            -c "Print :StartCalendarInterval:$index:Hour" "$update_plist"
    done
)
[ "$actual_update_hours" = "$expected_update_hours" ] \
    || fail "updater does not run every six hours"
for index in 0 1 2 3; do
    [ "$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:$index:Minute" "$update_plist")" = 0 ] \
        || fail "updater minute is not 00"
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$update_plist")" = update ] \
    || fail "scheduled updater does not invoke funk update"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$update_plist")" = --notify ] \
    || fail "scheduled updater does not request a notification"
if /usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$update_plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$update_plist" >/dev/null 2>&1; then
    fail "scheduled updater has an unapproved extra trigger"
fi

tailscale_plist=launchd/com.arthack.funk.tailscale-online.plist.in
[ "$(/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$tailscale_plist")" = true ] \
    || fail "Tailscale recovery agent does not run at login"
[ "$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$tailscale_plist")" = 300 ] \
    || fail "Tailscale recovery agent does not run every five minutes"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$tailscale_plist")" \
    = __TAILSCALE_ENSURE_ONLINE__ ] \
    || fail "Tailscale recovery agent does not invoke the shared helper"
[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HOME' "$tailscale_plist")" \
    = __FUNK_HOME__ ] \
    || fail "Tailscale recovery agent does not pin the target user HOME"
if /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$tailscale_plist" \
    >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$tailscale_plist" \
        >/dev/null 2>&1; then
    fail "Tailscale recovery agent has an unapproved argument or trigger"
fi

if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      data = JSON.parse(File.read(ARGV.fetch(0)))
      rules = data.fetch("profiles").fetch(0)
                  .fetch("complex_modifications").fetch("rules")
      abort "unexpected Karabiner rule count" unless rules.length == 5
      abort "unexpected Karabiner manipulator counts" unless rules.map { |r| r.fetch("manipulators").length } == [9, 9, 4, 2, 1]

      browser_ids = [
        "^com\\.google\\.Chrome$",
        "^com\\.google\\.Chrome\\.canary$",
        "^com\\.brave\\.Browser$",
        "^org\\.mozilla\\.firefox$"
      ]
      browser_rules = rules.fetch(0).fetch("manipulators")
      abort "unexpected Karabiner browser applications" unless browser_rules.all? { |m|
        m.fetch("conditions").fetch(0).fetch("bundle_identifiers") == browser_ids
      }

      focus_keys = rules.fetch(1).fetch("manipulators").map { |m| m.fetch("to").fetch(0).fetch("key_code") }
      abort "unexpected Karabiner Space focus keys" unless focus_keys == %w[f13 f14 f15 f16 f17 f18 f19 f20 f12]

      arrow_rules = rules.fetch(2).fetch("manipulators")
      abort "unexpected Karabiner arrow sources" unless arrow_rules.map { |m| m.dig("from", "key_code") } == %w[h j k l]
      abort "unexpected Karabiner arrow targets" unless arrow_rules.map { |m| m.dig("to", 0, "key_code") } == %w[left_arrow down_arrow up_arrow right_arrow]
      abort "Right Option arrow modifiers do not preserve Shift" unless arrow_rules.all? { |m|
        m.dig("from", "modifiers") == {
          "mandatory" => ["right_option"],
          "optional" => ["shift"]
        }
      }

      swap_rules = rules.fetch(3).fetch("manipulators")
      abort "unexpected built-in modifier swap" unless swap_rules.map { |m|
        [m.dig("from", "key_code"), m.dig("to", 0, "key_code")]
      } == [["left_command", "left_option"], ["left_option", "left_command"]]
      abort "modifier swap is not limited to the built-in keyboard" unless swap_rules.all? { |m|
        m.dig("conditions", 0, "type") == "device_if" &&
          m.dig("conditions", 0, "identifiers") == [{ "is_built_in_keyboard" => true }]
      }

      caps_rule = rules.fetch(4).fetch("manipulators").fetch(0)
      abort "Caps Lock does not send Escape" unless
        caps_rule.dig("from", "key_code") == "caps_lock" &&
        caps_rule.dig("to", 0, "key_code") == "escape"
    ' \
        karabiner/.config/karabiner/karabiner.json
elif command -v jq >/dev/null 2>&1; then
    jq -e '
      (.profiles[0].complex_modifications.rules | length) == 5 and
      ([.profiles[0].complex_modifications.rules[].manipulators | length] == [9, 9, 4, 2, 1]) and
      (all(.profiles[0].complex_modifications.rules[0].manipulators[];
        .conditions[0].bundle_identifiers ==
          ["^com\\.google\\.Chrome$", "^com\\.google\\.Chrome\\.canary$",
           "^com\\.brave\\.Browser$", "^org\\.mozilla\\.firefox$"])) and
      ([.profiles[0].complex_modifications.rules[1].manipulators[].to[0].key_code] ==
        ["f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20", "f12"]) and
      ([.profiles[0].complex_modifications.rules[2].manipulators[].from.key_code] ==
        ["h", "j", "k", "l"]) and
      ([.profiles[0].complex_modifications.rules[2].manipulators[].to[0].key_code] ==
        ["left_arrow", "down_arrow", "up_arrow", "right_arrow"]) and
      (all(.profiles[0].complex_modifications.rules[2].manipulators[];
        .from.modifiers == {"mandatory": ["right_option"], "optional": ["shift"]})) and
      ([.profiles[0].complex_modifications.rules[3].manipulators[] |
        [.from.key_code, .to[0].key_code]] ==
        [["left_command", "left_option"], ["left_option", "left_command"]]) and
      (all(.profiles[0].complex_modifications.rules[3].manipulators[];
        .conditions[0] ==
          {"type": "device_if", "identifiers": [{"is_built_in_keyboard": true}]})) and
      (.profiles[0].complex_modifications.rules[4].manipulators[0].from.key_code ==
        "caps_lock") and
      (.profiles[0].complex_modifications.rules[4].manipulators[0].to[0].key_code ==
        "escape")
    ' karabiner/.config/karabiner/karabiner.json >/dev/null
else
    fail "Ruby or jq is required to validate Karabiner JSON"
fi

expected_brewfile='tap "asmvik/formulae"
tap "oven-sh/bun"
brew "git-delta"
brew "bat"
brew "neovim"
brew "tmux"
brew "nvm"
brew "gh"
brew "jq"
brew "terminal-notifier"
brew "yq"
brew "ripgrep"
brew "fzf"
brew "btop"
brew "uv"
brew "starship"
brew "stow"
brew "pnpm"
brew "oven-sh/bun/bun", trusted: true
brew "llm"
brew "scrcpy"
brew "asmvik/formulae/yabai", trusted: true
brew "asmvik/formulae/skhd", trusted: true
cask "tailscale-app", greedy: true
cask "alt-tab", greedy: true
cask "ghostty", greedy: true
cask "google-chrome", greedy: true
cask "google-chrome@canary", greedy: true
cask "brave-browser", greedy: true
cask "firefox", greedy: true
cask "obs", greedy: true
cask "obsidian", greedy: true
cask "raycast", greedy: true
cask "android-platform-tools", greedy: true
cask "karabiner-elements", greedy: true
cask "font-0xproto-nerd-font", greedy: true
cask "finetune", greedy: true'
actual_brewfile=$(grep -Ev '^[[:space:]]*$' Brewfile)
[ "$actual_brewfile" = "$expected_brewfile" ] \
    || fail "Brewfile declarations differ from the approved set"

if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --formula >/dev/null
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --cask >/dev/null
fi

update_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/funk-update-test.XXXXXX")
update_home="$update_test_dir/home"
update_state="$update_test_dir/brew-state"
update_brew_log="$update_test_dir/brew.log"
update_npx_log="$update_test_dir/npx.log"
update_notifier_log="$update_test_dir/notifier.log"
mkdir -p "$update_home/.agents"
printf '%s\n' \
    $'formula:terminal-notifier\t1.0.0' \
    $'cask:orca\t0.9.0' \
    >"$update_state"
cat >"$update_home/.agents/.skill-lock.json" <<'EOF'
{
  "skills": {
    "orca-cli": {"skillFolderHash": "1111111111111111111111111111111111111111"},
    "orchestration": {"skillFolderHash": "2222222222222222222222222222222222222222"},
    "computer-use": {"skillFolderHash": "3333333333333333333333333333333333333333"}
  }
}
EOF

set +e
update_output=$(
    HOME="$update_home" \
        PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_TEST_BREW_EXIT=23 \
        FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
        FUNK_TEST_BREW_STATE="$update_state" \
        FUNK_TEST_BREW_LOG="$update_brew_log" \
        "$root/bin/funk" update 2>&1
)
update_status=$?
set -e
[ "$update_status" -eq 23 ] || fail "funk update did not propagate brew exit 23"
grep -F "brew-stub <bundle> <install> <--upgrade> <--file=$root/Brewfile>" \
    "$update_brew_log" >/dev/null \
    || fail "funk update did not explicitly request Brewfile upgrades"
printf '%s\n' "$update_output" | grep -F 'FAILED with exit status 23' >/dev/null \
    || fail "funk update did not log failure"

HOME="$update_home" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_BREW_EXIT=0 \
    FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
    FUNK_TEST_BREW_STATE="$update_state" \
    FUNK_TEST_BREW_LOG="$update_brew_log" \
    FUNK_TEST_FORMULA_NEW=2.0.0 \
    FUNK_TEST_ORCA_NEW=1.0.0 \
    FUNK_TEST_ORCA_CLI_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    FUNK_TEST_NPX_LOG="$update_npx_log" \
    FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
    FUNK_NPX_BIN="$root/tests/fixtures/npx" \
    FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
    "$root/bin/funk" update --notify >/dev/null
grep -F 'brew-stub <upgrade> <--cask> <--greedy> <--yes> <stablyai/orca/orca>' \
    "$update_brew_log" >/dev/null \
    || fail "scheduled update did not explicitly upgrade installed Orca"
grep -F 'npx-stub <--yes> <skills> <add> <https://github.com/stablyai/orca>' \
    "$update_npx_log" >/dev/null \
    || fail "scheduled update did not synchronize Orca skills"
notification=$(tail -n 1 "$update_notifier_log")
printf '%s\n' "$notification" | grep -F 'terminal-notifier 1.0.0 → 2.0.0' >/dev/null \
    || fail "change-aware notification omitted the upgraded formula"
printf '%s\n' "$notification" | grep -F 'Orca 0.9.0 → 1.0.0' >/dev/null \
    || fail "change-aware notification omitted the upgraded Orca cask"
printf '%s\n' "$notification" | grep -F 'orca-cli skill rev 11111111 → aaaaaaaa' >/dev/null \
    || fail "change-aware notification omitted the updated Orca skill revision"
if printf '%s\n' "$notification" | grep -Eq 'orchestration|computer-use'; then
    fail "change-aware notification listed unchanged Orca skills"
fi

: >"$update_notifier_log"
HOME="$update_home" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_BREW_EXIT=0 \
    FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
    FUNK_TEST_BREW_STATE="$update_state" \
    FUNK_TEST_BREW_LOG="$update_brew_log" \
    FUNK_TEST_FORMULA_NEW=2.0.0 \
    FUNK_TEST_ORCA_NEW=1.0.0 \
    FUNK_TEST_ORCA_CLI_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    FUNK_TEST_NPX_LOG="$update_npx_log" \
    FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
    FUNK_NPX_BIN="$root/tests/fixtures/npx" \
    FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
    "$root/bin/funk" update --notify >/dev/null
grep -F '<-message> <Installer ran; no updates.>' "$update_notifier_log" >/dev/null \
    || fail "no-op scheduled update did not send the required concise notification"

quarantine_home="$update_test_dir/quarantine-home"
quarantine_app="$quarantine_home/Applications/Funk Test.app"
quarantine_info="$update_test_dir/cask-info.json"
quarantine_spctl_log="$update_test_dir/spctl.log"
mkdir -p "$quarantine_app/Contents"
quarantine_app_canonical=$(
    cd -P -- "$(dirname -- "$quarantine_app")" && pwd
)
quarantine_app_canonical="$quarantine_app_canonical/$(basename -- "$quarantine_app")"
touch "$quarantine_app/Contents/test"
/usr/bin/xattr -w com.apple.quarantine '0081;funk-test' "$quarantine_app"
/usr/bin/xattr -w com.apple.quarantine '0081;funk-test' "$quarantine_app/Contents/test"
/usr/bin/jq -n --arg target "$quarantine_app" \
    '{casks:[{artifacts:[{app:["Funk Test.app"],target:$target}]}]}' \
    >"$quarantine_info"
HOME="$quarantine_home" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_CASK_INFO="$quarantine_info" \
    FUNK_TEST_SPCTL_LOG="$quarantine_spctl_log" \
    FUNK_SPCTL_BIN="$root/tests/fixtures/spctl" \
    "$root/libexec/release-cask-quarantine" funk-test >/dev/null
grep -F "spctl-stub <--assess> <--type> <execute> <$quarantine_app_canonical>" \
    "$quarantine_spctl_log" >/dev/null \
    || fail "cask helper did not Gatekeeper-assess the exact declared app"
remaining_quarantine=$(
    /usr/bin/xattr -pr com.apple.quarantine "$quarantine_app" 2>/dev/null || true
)
[ -z "$remaining_quarantine" ] \
    || fail "scoped cask helper left quarantine on a declared app artifact"

/usr/bin/xattr -w com.apple.quarantine '0081;funk-test' "$quarantine_app"
set +e
HOME="$quarantine_home" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_CASK_INFO="$quarantine_info" \
    FUNK_TEST_SPCTL_EXIT=42 \
    FUNK_SPCTL_BIN="$root/tests/fixtures/spctl" \
    "$root/libexec/release-cask-quarantine" rejected-test >/dev/null 2>&1
gatekeeper_status=$?
set -e
[ "$gatekeeper_status" -ne 0 ] \
    || fail "cask helper ignored a failed Gatekeeper assessment"
/usr/bin/xattr -p com.apple.quarantine "$quarantine_app" >/dev/null \
    || fail "cask helper removed quarantine after Gatekeeper rejection"

outside_app="$update_test_dir/Outside.app"
mkdir -p "$outside_app"
/usr/bin/xattr -w com.apple.quarantine '0081;funk-test' "$outside_app"
/usr/bin/jq -n --arg target "$outside_app" \
    '{casks:[{artifacts:[{app:["Outside.app"],target:$target}]}]}' \
    >"$quarantine_info"
set +e
HOME="$quarantine_home" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_CASK_INFO="$quarantine_info" \
    FUNK_SPCTL_BIN="$root/tests/fixtures/spctl" \
    "$root/libexec/release-cask-quarantine" hostile-test >/dev/null 2>&1
outside_status=$?
set -e
[ "$outside_status" -ne 0 ] \
    || fail "cask quarantine helper accepted an app outside approved directories"
/usr/bin/xattr -p com.apple.quarantine "$outside_app" >/dev/null \
    || fail "cask quarantine helper modified a rejected target"

# An upgrade that aborts after Homebrew's backup step leaves a real directory in
# the Caskroom where a completed install leaves a symlink to the app. Homebrew
# then fails every later upgrade of that cask, so the repair helper must restore
# the symlink whenever the installed application is still in place.
repair_home="$update_test_dir/repair-home"
repair_prefix="$update_test_dir/repair-prefix"
repair_info="$update_test_dir/repair-info.json"
repair_target="$repair_home/Applications/Funk Repair.app"
repair_backup="$repair_prefix/Caskroom/funk-repair/1.0.0/Funk Repair.app"
mkdir -p "$repair_target/Contents" "$repair_backup/Contents"
touch "$repair_target/Contents/live" "$repair_backup/Contents/stale"
/usr/bin/jq -n --arg target "$repair_target" \
    '{casks:[{token:"funk-repair",installed:"1.0.0",
              artifacts:[{app:["Funk Repair.app"],target:$target}]}]}' \
    >"$repair_info"
HOME="$repair_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_BREW_PREFIX="$repair_prefix" \
    FUNK_TEST_CASK_INFO="$repair_info" \
    "$root/libexec/repair-cask-artifacts" funk-repair >/dev/null \
    || fail "cask repair helper failed on an aborted-upgrade backup"
[ -L "$repair_backup" ] \
    || fail "cask repair helper did not replace the stale backup with a symlink"
repair_target_canonical=$(cd -P -- "$(dirname -- "$repair_target")" && pwd)
repair_target_canonical="$repair_target_canonical/$(basename -- "$repair_target")"
[ "$(readlink "$repair_backup")" = "$repair_target_canonical" ] \
    || fail "cask repair helper linked the Caskroom at the wrong target"
[ -f "$repair_target/Contents/live" ] \
    || fail "cask repair helper modified the installed application"

# A healthy Caskroom is already a symlink and must be left exactly as it is.
HOME="$repair_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_BREW_PREFIX="$repair_prefix" \
    FUNK_TEST_CASK_INFO="$repair_info" \
    "$root/libexec/repair-cask-artifacts" funk-repair >/dev/null \
    || fail "cask repair helper was not idempotent"
[ -L "$repair_backup" ] && [ -f "$repair_target/Contents/live" ] \
    || fail "cask repair helper disturbed an already-linked cask"

# Without the installed application the Caskroom copy is the only one left, so
# the helper must leave it for Homebrew instead of deleting or relinking it.
rm -rf "$repair_target" "$repair_backup"
mkdir -p "$repair_backup/Contents"
touch "$repair_backup/Contents/only-copy"
HOME="$repair_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_BREW_PREFIX="$repair_prefix" \
    FUNK_TEST_CASK_INFO="$repair_info" \
    "$root/libexec/repair-cask-artifacts" funk-repair >/dev/null 2>&1 \
    || fail "cask repair helper failed when the installed application was absent"
[ -f "$repair_backup/Contents/only-copy" ] && [ ! -L "$repair_backup" ] \
    || fail "cask repair helper destroyed the only remaining copy of an app"

# The helper deletes directories, so an artifact target outside an approved
# Applications directory must be refused rather than followed.
repair_outside="$update_test_dir/Repair Outside.app"
repair_outside_backup="$repair_prefix/Caskroom/funk-repair/1.0.0/Repair Outside.app"
mkdir -p "$repair_outside" "$repair_outside_backup/Contents"
touch "$repair_outside_backup/Contents/stale"
/usr/bin/jq -n --arg target "$repair_outside" \
    '{casks:[{token:"funk-repair",installed:"1.0.0",
              artifacts:[{app:["Repair Outside.app"],target:$target}]}]}' \
    >"$repair_info"
set +e
HOME="$repair_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_BREW_PREFIX="$repair_prefix" \
    FUNK_TEST_CASK_INFO="$repair_info" \
    "$root/libexec/repair-cask-artifacts" funk-repair >/dev/null 2>&1
repair_outside_status=$?
set -e
[ "$repair_outside_status" -ne 0 ] \
    || fail "cask repair helper accepted an app outside approved directories"
[ -d "$repair_outside" ] && [ ! -L "$repair_outside" ] \
    || fail "cask repair helper modified a rejected target"
[ -f "$repair_outside_backup/Contents/stale" ] \
    || fail "cask repair helper deleted a backup before rejecting its target"

# The scheduled LaunchAgent has no terminal, so a cask that installs a pkg or
# runs a sudo uninstall script must be named for HOMEBREW_BUNDLE_CASK_SKIP
# instead of failing the whole unattended run.
unattendable_info="$update_test_dir/unattendable-info.json"
unattendable_home="$update_test_dir/unattendable-home"
mkdir -p "$unattendable_home/Applications"
/usr/bin/jq -n '{casks:[
    {token:"funk-pkg",installed:"1.0.0",artifacts:[{pkg:["Funk.pkg"]}]},
    {token:"funk-sudo-script",installed:"1.0.0",
     artifacts:[{uninstall:[{early_script:{executable:"/x",sudo:true}}]}]},
    {token:"funk-zap-sudo",installed:"1.0.0",
     artifacts:[{zap:[{script:{executable:"/x",sudo:true}}]}]},
    {token:"funk-plain-script",installed:"1.0.0",
     artifacts:[{uninstall:[{script:{executable:"/x"}}]}]},
    {token:"funk-ordinary",installed:"1.0.0",
     artifacts:[{app:["Funk Ordinary.app"]}]}
]}' >"$unattendable_info"
unattendable=$(
    HOME="$unattendable_home" \
        FUNK_BREW_BIN="$root/tests/fixtures/brew" \
        FUNK_TEST_BREW_PREFIX="$repair_prefix" \
        FUNK_TEST_CASK_INFO="$unattendable_info" \
        "$root/libexec/list-unattendable-casks" funk-ordinary
)
expected_unattendable='funk-pkg
funk-sudo-script
funk-zap-sudo'
[ "$unattendable" = "$expected_unattendable" ] \
    || fail "unattendable cask triage did not match the required set: $unattendable"

# Ownership reclamation must stay silent when every application already belongs
# to this account, so ./install never asks for a password it does not need.
ownership_home="$update_test_dir/ownership-home"
ownership_info="$update_test_dir/ownership-info.json"
ownership_app="$ownership_home/Applications/Funk Owned.app"
mkdir -p "$ownership_app/Contents"
/usr/bin/jq -n --arg target "$ownership_app" \
    '{casks:[{token:"funk-owned",installed:"1.0.0",
              artifacts:[{app:["Funk Owned.app"],target:$target}]}]}' \
    >"$ownership_info"
ownership_casks=$(
    HOME="$ownership_home" \
        FUNK_BREW_BIN="$root/tests/fixtures/brew" \
        FUNK_TEST_CASK_INFO="$ownership_info" \
        "$root/libexec/reclaim-app-ownership" --list-casks funk-owned
)
[ -z "$ownership_casks" ] \
    || fail "ownership helper flagged an application this account already owns"
HOME="$ownership_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_CASK_INFO="$ownership_info" \
    "$root/libexec/reclaim-app-ownership" --check funk-owned >/dev/null \
    || fail "ownership helper failed its no-op check"

rm -rf "$update_test_dir"

"$root/bin/funk" install-updater --check >/dev/null
"$root/bin/funk" install-tailscale-recovery --check >/dev/null
"$root/bin/funk" configure-macos --check

stow_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-stow-test.XXXXXX")
trap 'rm -rf "$stow_home"' EXIT
HOME="$stow_home" "$root/bin/funk" stow
[ -L "$stow_home/.config/git/config" ] || fail "git package was not stowed"
[ -L "$stow_home/.ssh/config" ] || fail "ssh config was not stowed"
[ -d "$stow_home/.ssh" ] && [ ! -L "$stow_home/.ssh" ] \
    || fail "ssh package did not use --no-folding"
[ -L "$stow_home/.config/ghostty/config" ] \
    || fail "Ghostty config was not stowed"
[ -L "$stow_home/.config/nvim" ] && [ -f "$stow_home/.config/nvim/init.lua" ] \
    || fail "Neovim config was not stowed"
[ -L "$stow_home/.local/bin/tmux-cycle-session" ] && [ ! -L "$stow_home/.local" ] \
    || fail "bin package did not use --no-folding"
[ -L "$stow_home/.local/bin/focus-address-bar" ] \
    || fail "browser address-bar helper was not stowed"
[ -x "$stow_home/.local/bin/ginit" ] \
    || fail "ginit was not stowed as an executable"
[ -x "$stow_home/.local/bin/ghinit" ] \
    || fail "ghinit was not stowed as an executable"
[ -x "$stow_home/.local/bin/adb-wireless-pair" ] \
    || fail "wireless ADB pairing helper was not stowed as an executable"
[ -x "$stow_home/.local/bin/tailscale-ensure-online" ] \
    || fail "Tailscale recovery helper was not stowed as an executable"
[ -L "$stow_home/.local/bin/raycast/scrcpy.sh" ] \
    || fail "Raycast scrcpy command was not stowed"
[ -L "$stow_home/Library/Application Support/io.datasette.llm/extra-openai-models.yaml" ] \
    || fail "LLM package was not stowed"
[ -L "$stow_home/.config/orca" ] && [ -f "$stow_home/.config/orca/settings.json" ] \
    || fail "Orca settings overlay was not stowed with normal directory folding"
[ -L "$stow_home/AGENTS.md" ] \
    || fail "home-level agent guidance was not stowed"
# shellcheck disable=SC2016 # Match the literal Markdown path.
grep -F 'Upstream and third-party project clones live under `/Users/arthack/src`.' \
    "$stow_home/AGENTS.md" >/dev/null \
    || fail "home-level agent guidance lost the upstream project location"
grep -F "The user's own projects live under \`/Users/arthack/code\`." \
    "$stow_home/AGENTS.md" >/dev/null \
    || fail "home-level agent guidance lost the user project location"
grep -F 'archive it after its work is complete' "$stow_home/AGENTS.md" >/dev/null \
    || fail "home-level agent guidance lost completed-task archival"
HOME="$stow_home" "$root/bin/funk" stow --check >/dev/null 2>&1
orca_state="$stow_home/Library/Application Support/orca/orca-data.json"
mkdir -p "$(dirname "$orca_state")"
printf '%s\n' \
    '{"repos":[{"id":"preserve-me"}],"settings":{"showMenuBarIcon":false,"notifications":{"enabled":false}}}' \
    >"$orca_state"
HOME="$stow_home" FUNK_TEST_ORCA_RUNNING=0 "$root/bin/funk" configure-orca >/dev/null
jq -e '
  .repos == [{"id":"preserve-me"}] and
  .settings.showMenuBarIcon == false and
  .settings.notifications.enabled == false and
  .settings.defaultTuiAgent == "codex" and
  .settings.mobilePairingConnectionMode == "local-only" and
  .settings.openLinksInApp == true and
  .settings.openLinksInAppPreferencePrompted == true and
  .settings.refreshLocalBaseRefOnWorktreeCreate == true and
  .settings.showMobileButton == false and
  .settings.tabAutoGenerateTitle == true and
  .settings.terminalFontFamily == "0xProto Nerd Font" and
  .settings.terminalFontSize == 20 and
  .settings.terminalMacOptionAsAlt == "true" and
  .settings.terminalMacOptionAsAltMigrated == true and
  .settings.notifications.terminalBell == true and
  .settings.theme == "dark"
' "$orca_state" >/dev/null || fail "Orca settings overlay did not preserve unrelated state"
HOME="$stow_home" FUNK_TEST_ORCA_RUNNING=1 "$root/bin/funk" configure-orca >/dev/null
orca_state_tmp="$orca_state.tmp"
jq '.settings.theme = "system"' "$orca_state" >"$orca_state_tmp"
mv "$orca_state_tmp" "$orca_state"
set +e
orca_running_output=$(
    HOME="$stow_home" FUNK_TEST_ORCA_RUNNING=1 \
        "$root/bin/funk" configure-orca 2>&1
)
orca_running_status=$?
set -e
[ "$orca_running_status" -ne 0 ] \
    || fail "Orca settings reconciliation raced a running divergent profile"
# EX_TEMPFAIL distinguishes "repeat this after quitting Orca" from a broken
# installation, so ./install can report it instead of failing the whole run.
[ "$orca_running_status" -eq 75 ] \
    || fail "running-Orca guard did not exit EX_TEMPFAIL: $orca_running_status"
printf '%s\n' "$orca_running_output" | grep -F 'quit Orca' >/dev/null \
    || fail "Orca running-profile guard did not explain how to reconcile"
HOME="$stow_home" FUNK_TEST_ORCA_RUNNING=0 "$root/bin/funk" configure-orca >/dev/null
jq -e '.settings.theme == "dark"' "$orca_state" >/dev/null \
    || fail "Orca settings did not reconcile after the running-profile guard cleared"
mv "$orca_state" "$orca_state.merged-test"
HOME="$stow_home" FUNK_TEST_ORCA_RUNNING=0 "$root/bin/funk" configure-orca >/dev/null
jq -e '
  .settings.defaultTuiAgent == "codex" and
  .settings.mobilePairingConnectionMode == "local-only" and
  .settings.openLinksInApp == true and
  .settings.openLinksInAppPreferencePrompted == true and
  .settings.refreshLocalBaseRefOnWorktreeCreate == true and
  .settings.showMobileButton == false and
  .settings.tabAutoGenerateTitle == true and
  .settings.terminalMacOptionAsAltMigrated == true and
  .settings.notifications == {"terminalBell":true}
' "$orca_state" >/dev/null || fail "Orca settings did not seed a fresh profile"
HOME="$stow_home" "$root/bin/funk" configure-orca --check >/dev/null

mcd_path="$stow_home/mcd parent/mcd child"
cmkdir_path="$stow_home/cmkdir parent/cmkdir child"
HOME="$stow_home" MCD_TEST_PATH="$mcd_path" CMKDIR_TEST_PATH="$cmkdir_path" \
    /bin/zsh -c '
        source "$HOME/.zsh/aliases/core.zsh"
        mcd "$MCD_TEST_PATH"
        [[ "$PWD" -ef "$MCD_TEST_PATH" ]]
        eval "cmkdir \"\$CMKDIR_TEST_PATH\""
        [[ "$PWD" -ef "$CMKDIR_TEST_PATH" ]]
    ' || fail "mcd or cmkdir did not create and enter a directory"

helper_home="$stow_home/helper-home"
mkdir -p "$helper_home/code/ginit-project"
git config --file "$helper_home/gitconfig" init.defaultBranch main
git config --file "$helper_home/gitconfig" user.name 'Funk Validate'
git config --file "$helper_home/gitconfig" user.email 'funk-validate@example.invalid'
(
    cd "$helper_home/code/ginit-project"
    HOME="$helper_home" \
        GIT_CONFIG_GLOBAL="$helper_home/gitconfig" \
        GIT_CONFIG_NOSYSTEM=1 \
        "$root/bin/.local/bin/ginit" >/dev/null
    first_head=$(git rev-parse HEAD)
    HOME="$helper_home" "$root/bin/.local/bin/ginit"
    [ "$(git rev-parse HEAD)" = "$first_head" ] \
        || fail "ginit was not idempotent"
    [ "$(git log -1 --format=%s)" = 'New repo' ] \
        || fail "ginit did not create the expected initial commit"
)

gh_log="$helper_home/gh.log"
HOME="$helper_home" \
    PATH="$root/bin/.local/bin:$root/tests/fixtures:/usr/bin:/bin" \
    FUNK_TEST_GH_LOG="$gh_log" \
    GIT_CONFIG_GLOBAL="$helper_home/gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 \
    "$root/bin/.local/bin/ghinit" gh-project --description 'Funk test' >/dev/null
gh_project_dir=$(cd -P -- "$helper_home/code/gh-project" && pwd)
expected_gh_log=$(printf '%s\n' \
    "cwd=$gh_project_dir" \
    'arg=--source=.' \
    'arg=--private' \
    'arg=--push' \
    'arg=--description' \
    'arg=Funk test')
[ "$(cat "$gh_log")" = "$expected_gh_log" ] \
    || fail "ghinit invoked gh repo create with unexpected arguments"

set +e
HOME="$helper_home" "$root/bin/.local/bin/ghinit" ../outside >/dev/null 2>&1
ghinit_traversal_status=$?
set -e
[ "$ghinit_traversal_status" -ne 0 ] && [ ! -e "$helper_home/outside" ] \
    || fail "ghinit allowed a project name to escape ~/code"

grep -F "\"\$funk_command\" stow" install >/dev/null \
    || fail "default install does not stow user configuration"
# shellcheck disable=SC2016 # Match the literal shared Brewfile helper path.
grep -F '"$funk_root/libexec/converge-brewfile"' install >/dev/null \
    || fail "default install does not converge Brewfile upgrades before Node setup"
grep -F "\"\$funk_root/libexec/initialize-configs\"" install >/dev/null \
    || fail "default install does not initialize config dependencies"
grep -F "\"\$funk_root/libexec/install-ai-tools\"" install >/dev/null \
    || fail "default install does not install AI tools"
grep -F "\"\$funk_command\" configure-orca" install >/dev/null \
    || fail "default install does not reconcile Orca settings"
grep -F "\"\$funk_command\" install-tailscale-recovery" install >/dev/null \
    || fail "default install does not load Tailscale recovery"
# Reopening Karabiner on every install only raises a window the user did not ask
# for; it exists to request permissions that are already granted once its
# per-user services are up.
grep -F 'if karabiner_is_active; then' libexec/install-window-manager >/dev/null \
    || fail "window installer reopens Karabiner even when it is already running"
grep -F 'pgrep -x karabiner_console_user_server' libexec/install-window-manager >/dev/null \
    || fail "Karabiner activity check does not test its per-user session service"

# A running Orca must not fail the whole installation.
grep -F 'orca_status" -eq 75' install >/dev/null \
    || fail "default install treats a deferred Orca reconciliation as a failure"
grep -F 'funk configure-orca' install >/dev/null \
    || fail "default install does not report how to finish a deferred Orca step"
grep -F 'with_windows=1' install >/dev/null \
    || fail "default install does not enable the window stack"
grep -F -- '--without-windows) with_windows=0' install >/dev/null \
    || fail "default window stack has no explicit opt-out"
grep -F 'tmux-fzf.git' libexec/initialize-configs >/dev/null \
    || fail "tmux-fzf is not initialized"
if grep -R -Eqi \
    'tinty|tinted-theming|catppuccin|base16|base24|syntax-theme|color_theme|theme_background' \
    Brewfile README.md libexec ghostty nvim tmux zsh btop starship git; then
    fail "managed configuration contains a prohibited theme or theme manager"
fi
if grep -R -Eq \
    "%C\\(|%C[a-z]|%\\(color:|fg=colour|bg=colour|style = '(black|red|green|yellow|blue|magenta|cyan|white)'" \
    ghostty nvim tmux zsh btop starship git; then
    fail "managed configuration contains a theme-specific named color"
fi
grep -F 'save_config_on_exit = false' btop/.config/btop/btop.conf >/dev/null \
    || fail "btop can rewrite theme defaults into its managed config"
# shellcheck disable=SC2016 # Match the literal shell variable in the script.
grep -F '"$funk_root/bin/funk" yabai maintain' libexec/install-window-manager >/dev/null \
    || fail "window installer does not reconcile the Yabai scripting addition"
# shellcheck disable=SC2016 # Match the literal shell variables in the script.
grep -F 'wait_for_numbered_spaces "$yabai_bin"' libexec/funk-yabai >/dev/null \
    || fail "Yabai maintenance does not wait for numbered Spaces"
# shellcheck disable=SC2016 # Match the literal shell variable in the script.
grep -F '"$yabai_bin" -m query --spaces --space 9' libexec/funk-yabai >/dev/null \
    || fail "Yabai maintenance does not verify Space 9"
grep -F 'trap cleanup EXIT' system/funk-yabai-maintain >/dev/null \
    || fail "Yabai root maintenance does not register stable temporary-file cleanup"
# shellcheck disable=SC2016 # Match the literal shell expression in the script.
grep -F 'cleanup_tmpdir=$(mktemp -d /private/tmp/funk-yabai-maintain.XXXXXX)' \
    system/funk-yabai-maintain >/dev/null \
    || fail "Yabai root maintenance cleanup does not retain its temporary directory"
# shellcheck disable=SC2016 # Match the literal function-local shell variable.
if grep -F 'trap '\''rm -rf "$tmpdir"'\'' EXIT' system/funk-yabai-maintain >/dev/null; then
    fail "Yabai root maintenance cleanup references a function-local variable at exit"
fi
if grep -F 'Run: funk yabai maintain' libexec/install-window-manager >/dev/null; then
    fail "window installer still delegates initial Yabai maintenance to the user"
fi

# The floating set is reviewed as a whole: every entry must name an application
# that Funk installs or that macOS ships, and the order is asserted because
# Yabai applies all matching rules in registration order, letting a later rule
# override an earlier value.
expected_float_rules='app="^Google Chrome$" title="^Picture in Picture$"
app="^System Settings$"
app="^Tailscale$"
app="^Karabiner-Elements$"
app="^Karabiner-EventViewer$"
app="^AltTab$"
app="^Activity Monitor$"
app="^Calculator$"
app="^Archive Utility$"
app="^Installer$"
app="^scrcpy$"'
actual_float_rules=$(
    sed -n 's/^yabai -m rule --add \(.*\) manage=off$/\1/p' \
        yabai/.config/yabai/yabairc
)
[ "$actual_float_rules" = "$expected_float_rules" ] \
    || fail "Yabai floating rules do not match the reviewed set"
if grep -E '^yabai -m rule --add ' yabai/.config/yabai/yabairc \
    | grep -qv 'app="\^'; then
    fail "a Yabai rule is not scoped to a named application"
fi
# AltTab's switcher windows should float instead of entering the tiling stack.
grep -Fx 'yabai -m rule --add app="^AltTab$" manage=off' \
    yabai/.config/yabai/yabairc >/dev/null \
    || fail "AltTab is missing its Yabai floating rule"
# browserctl-display belonged to the retired virtual-display viewer.
if grep -F 'app="^browserctl-display$"' \
    yabai/.config/yabai/yabairc >/dev/null; then
    fail "Yabai floats browserctl-display even though Funk does not install it"
fi

ai_install_plan=$(libexec/install-ai-tools --check)
for required_ai_install in \
    'brew install or upgrade gh  # intentional duplicate of the Brewfile' \
    'brew install or upgrade livekit-cli' \
    'brew install or upgrade --cask --greedy claude' \
    'brew install or upgrade --cask --greedy chatgpt' \
    'brew install --cask --yes stablyai/orca/orca  # when missing' \
    'brew upgrade --cask --greedy --yes stablyai/orca/orca  # when installed' \
    'remove com.apple.quarantine only from Homebrew'\''s declared Orca.app target' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'gh release view --repo anomalyco/opencode --json tagName  # avoids the anonymous API limit' \
    'curl -fsSL https://opencode.ai/install | VERSION=<resolved> bash -s -- --no-modify-path' \
    'curl -fsSL https://pi.dev/install.sh | sh  # in its own session, no controlling terminal' \
    'npm install --global @native-sdk/cli@latest' \
    'codex mcp add --url https://docs.livekit.io/mcp livekit-docs' \
    'claude mcp add --scope user --transport http livekit-docs https://docs.livekit.io/mcp' \
    'opencode mcp add livekit-docs --url https://docs.livekit.io/mcp' \
    'codex mcp add shadcn -- npx shadcn@latest mcp' \
    'claude mcp add --scope user shadcn -- npx shadcn@latest mcp' \
    'opencode mcp add shadcn -- npx shadcn@latest mcp' \
    'lk docs overview' \
    'native skills list' \
    'npx --yes skills add https://github.com/stablyai/orca --agent codex claude-code opencode pi --skill orca-cli orchestration computer-use --global --yes' \
    'npx --yes skills remove livekit-agents --global --yes  # when installed' \
    'npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code opencode pi --skill find-skills --global --yes' \
    'npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code opencode pi --skill frontend-design --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code opencode pi --skill web-design-guidelines --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code opencode pi --skill vercel-react-best-practices --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai --agent codex claude-code opencode pi --skill ai-sdk --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code opencode pi --skill ai-elements --global --yes' \
    'npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code opencode pi --skill shadcn --global --yes' \
    'npx --yes skills add https://github.com/livekit/agent-skills --agent codex claude-code opencode pi --skill livekit-simulations --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code opencode pi --skill native-sdk --global --yes' \
    "npx --yes skills add \"\$HOME/code/arthack\" --agent codex claude-code opencode pi --skill hack --global --yes"; do
    printf '%s\n' "$ai_install_plan" | grep -F "$required_ai_install" >/dev/null \
        || fail "AI installation plan is missing: $required_ai_install"
done
if printf '%s\n' "$ai_install_plan" | grep -Eq -- '--skill ([^[:space:]]+ )*funk([[:space:]]|$)'; then
    fail "AI installation plan still installs the retired Funk priming skill"
fi
if printf '%s\n' "$ai_install_plan" | grep -Eq -- '--skill ([^[:space:]]+ )*livekit-agents([[:space:]]|$)'; then
    fail "AI installation plan still installs the removed LiveKit agent-development skill"
fi
grep -F "art_hack_root=\"\$HOME/code/arthack\"" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not own the Art Hack skill source"
grep -F "npx --yes skills add \"\$art_hack_root\"" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not synchronize the Hack skill"
grep -F "\$art_hack_root/hack/SKILL.md" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not validate the Hack skill source"
grep -F "\$art_hack_root/hack/agents/openai.yaml" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not validate the Hack skill manifest"
grep -F 'install_or_upgrade_formula gh' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not deliberately converge the GitHub CLI"

# OpenCode's installer fails the whole run once the 60-an-hour anonymous GitHub
# API limit is exhausted, so the release must be resolved through gh instead.
# shellcheck disable=SC2016 # Match the literal shell variables in the script.
grep -F 'VERSION="$version" /bin/bash -s -- --no-modify-path' \
    libexec/install-ai-tools >/dev/null \
    || fail "OpenCode install does not supply a gh-resolved release version"
# shellcheck disable=SC2016 # Match the literal scoped repository variable.
grep -F 'gh release view --repo "$repo"' libexec/install-ai-tools >/dev/null \
    || fail "OpenCode release is not resolved with the authenticated GitHub CLI"

# Pi reads its prompts from /dev/tty, so only removing the controlling terminal
# keeps ./install unattended and stops it editing Funk's Stow-managed profile.
grep -F 'run_without_controlling_terminal /bin/sh' libexec/install-ai-tools >/dev/null \
    || fail "Pi installer is not detached from the controlling terminal"
grep -F 'POSIX::setsid()' libexec/install-ai-tools >/dev/null \
    || fail "Pi installer detachment does not start a new session"
grep -F '^[[:space:]]*oauth_token:' libexec/install-ai-tools >/dev/null \
    || fail "GitHub CLI migration does not require a portable token"
grep -F 'Preserving existing GitHub CLI credentials' libexec/install-ai-tools >/dev/null \
    || fail "GitHub CLI migration does not preserve an existing login"
if grep -Eq '^cask "(chatgpt|claude)"$|stablyai/orca/orca' Brewfile; then
    fail "AI desktop application leaked back into the bootstrap Brewfile"
fi

for required_setting in \
    'NSGlobalDomain AppleInterfaceStyle -string "Dark"' \
    'com.apple.dock autohide -bool true' \
    'com.apple.dock persistent-apps -array' \
    'com.apple.WindowManager HideDesktop -bool true' \
    'com.apple.finder FXICloudDriveDesktop -bool false' \
    'com.apple.finder FXICloudDriveDocuments -bool false' \
    'NSGlobalDomain com.apple.swipescrolldirection -bool false' \
    'com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64' \
    'com.raycast.macos raycastGlobalHotkey -string "Command-2"' \
    'com.raycast.macos onboardingCompleted -bool true' \
    'com.apple.ControlCenter AirplayRecieverEnabled -bool false'; do
    grep -F "$required_setting" libexec/configure-macos >/dev/null \
        || fail "required macOS setting is missing: $required_setting"
done
grep -F '/usr/bin/killall Raycast' libexec/configure-macos >/dev/null \
    || fail "Raycast is not stopped before its hotkey preference is written"
# Stopping Raycast discards what the user was doing and forces it to re-register
# its global hotkey, so it must happen only when a preference actually differs.
grep -F 'raycast_default_matches raycastGlobalHotkey "Command-2"' \
    libexec/configure-macos >/dev/null \
    || fail "Raycast is stopped without first reading its current preferences"
grep -F 'Raycast preferences already match; leaving it running.' \
    libexec/configure-macos >/dev/null \
    || fail "converged Raycast is not left running"
if grep -Eqi 'wallpaper|desktop-image|DesktopImageURL' libexec/configure-macos; then
    fail "user-level macOS preferences still enforce a wallpaper"
fi
if grep -Eq 'mdutil|nvram|launchctl disable|pmset' \
    libexec/configure-macos; then
    fail "machine-wide setting found in user-level macOS preferences"
fi

"$root/bin/funk" configure-system --check
# Literal dollar signs below verify that the root helper passes its validated
# runtime values instead of embedding an account name or boot-argument string.
# shellcheck disable=SC2016
for required_system_setting in \
    '/usr/bin/mdutil -i off -a' \
    '/usr/bin/pmset -c displaysleep 5' \
    '/bin/launchctl disable system/com.apple.smbd' \
    '/usr/sbin/sharing -r "$share_name"' \
    '/usr/sbin/nvram "boot-args=$desired_boot_args"'; do
    grep -F "$required_system_setting" system/apply-system-settings >/dev/null \
        || fail "required system setting is missing: $required_system_setting"
done
if grep -F '/Users/mike' system/apply-system-settings >/dev/null; then
    fail "old account leaked into system settings"
fi

[ "$(grep -Ec '^f(13|14|15|16|17|18|19) : yabai -m space --focus [1-7]$' skhd/.config/skhd/skhdrc)" -eq 7 ] \
    || fail "skhd numbered-Space 1-7 focus bindings are incomplete"
grep -Fx '0x5A : yabai -m space --focus 8' skhd/.config/skhd/skhdrc >/dev/null \
    || fail "skhd Space 8 focus binding is missing its F20 keycode"
grep -Fx 'f12 : yabai -m space --focus 9' skhd/.config/skhd/skhdrc >/dev/null \
    || fail "skhd Space 9 focus binding is missing"
[ "$(grep -Ec '^cmd \+ shift - [1-9] : yabai -m window --space [1-9]$' skhd/.config/skhd/skhdrc)" -eq 9 ] \
    || fail "skhd numbered-Space move bindings are incomplete"
grep -F 'cmd + shift - v : /usr/bin/open "raycast://extensions/raycast/clipboard-history/clipboard-history"' \
    skhd/.config/skhd/skhdrc >/dev/null \
    || fail "Raycast Clipboard History shortcut is missing"
grep -F 'ctrl - l [' skhd/.config/skhd/skhdrc >/dev/null \
    || fail "browser address-bar shortcut is missing"
for browser_name in "Google Chrome" "Google Chrome Canary" Firefox "Brave Browser"; do
    grep -F "\"$browser_name\" : ~/.local/bin/focus-address-bar" \
        skhd/.config/skhd/skhdrc >/dev/null \
        || fail "browser address-bar shortcut is missing $browser_name"
done
if grep -Eq '^cmd - (return|b) :' skhd/.config/skhd/skhdrc; then
    fail "removed application launcher shortcut is present"
fi
grep -F 'menu item "Open Location…"' bin/.local/bin/focus-address-bar >/dev/null \
    || fail "browser address-bar helper does not use the browser menu"
grep -Fx 'brew "scrcpy"' Brewfile >/dev/null \
    || fail "scrcpy is missing from the Brewfile"
grep -Fx 'cask "android-platform-tools", greedy: true' Brewfile >/dev/null \
    || fail "Android Platform Tools are missing from the Brewfile"
"$root/tests/tailscale-online.sh"
"$root/tests/adb-wireless.sh"
"$root/tests/scrcpy-launchers.sh"
grep -F '@raycast.title Android (audio)' bin/.local/bin/raycast/scrcpy.sh >/dev/null \
    || fail "audio scrcpy Raycast command is missing"
grep -F '@raycast.title Android (no audio)' bin/.local/bin/raycast/scrcpy-no-audio.sh >/dev/null \
    || fail "no-audio scrcpy Raycast command is missing"
grep -F '@raycast.title Android flex (audio)' bin/.local/bin/raycast/scrcpy-flex.sh >/dev/null \
    || fail "flex audio scrcpy Raycast command is missing"
grep -F '@raycast.title Android flex (no audio)' bin/.local/bin/raycast/scrcpy-no-audio-flex.sh >/dev/null \
    || fail "flex no-audio scrcpy Raycast command is missing"
# The mirror window keeps the device aspect ratio and refuses resize, so the
# stack layout must never hand it a tile. Matching on the application alone
# covers the plain and --new-display Raycast variants.
grep -Fx 'yabai -m rule --add app="^scrcpy$" manage=off' \
    yabai/.config/yabai/yabairc >/dev/null \
    || fail "scrcpy is missing its Yabai floating rule"

# shellcheck disable=SC2016 # Match literal Brewfile convergence variables.
grep -F '"$brew_bin" bundle install --upgrade --file="$brewfile"' \
    libexec/converge-brewfile >/dev/null \
    || fail "Brewfile convergence does not override Homebrew's no-upgrade setting"
# shellcheck disable=SC2016 # Match the literal scoped target variable.
grep -F '/usr/bin/xattr -dr com.apple.quarantine "$target"' \
    libexec/release-cask-quarantine >/dev/null \
    || fail "cask helper does not remove only the quarantine attribute"
# shellcheck disable=SC2016 # Match the literal scoped Gatekeeper target.
grep -F '"$spctl_bin" --assess --type execute "$target"' \
    libexec/release-cask-quarantine >/dev/null \
    || fail "cask helper does not Gatekeeper-assess an app before release"
if grep -Eq '/usr/bin/xattr -(c|d[^r])|xattr[^[:cntrl:]]+(where_from|provenance)' \
    libexec/release-cask-quarantine; then
    fail "cask helper weakens extended attributes beyond recursive quarantine removal"
fi
if grep -Eqi 'bundle cleanup|uninstall|fetch-head|telegram|sudo' \
    bin/funk libexec/funk-update libexec/install-update-agent \
    libexec/install-orca libexec/converge-brewfile libexec/converge-brew-casks \
    libexec/repair-cask-artifacts \
    launchd/com.arthack.funk.update.plist.in; then
    fail "scheduled updater contains a prohibited operation"
fi

# The triage helper reads Homebrew's removal metadata, so it names the privileged
# stanzas it looks for and cannot join the literal scan above. It still runs on
# the scheduled path, so assert directly that it can never elevate.
if grep -Eq '(^|[[:space:];&|(])(/usr/bin/)?sudo([[:space:]]|$)' \
    libexec/list-unattendable-casks; then
    fail "unattended cask triage can invoke sudo"
fi
if grep -Fq 'reclaim-app-ownership' libexec/list-unattendable-casks; then
    fail "unattended cask triage depends on the privileged ownership helper"
fi
grep -F 'HOMEBREW_BUNDLE_CASK_SKIP' libexec/funk-update >/dev/null \
    || fail "scheduled updater does not skip casks that need administrator authentication"

# Homebrew fails every later upgrade of a cask left in the aborted-upgrade state,
# so both convergence paths must repair it before asking Homebrew to move an app.
# shellcheck disable=SC2016 # Match the literal repair invocation in the script.
grep -F '"$repair_artifacts" --brewfile "$brewfile"' \
    libexec/converge-brewfile >/dev/null \
    || fail "Brewfile convergence does not repair aborted-upgrade Caskroom state"
# shellcheck disable=SC2016 # Match the literal repair invocation in the script.
grep -F '"$repair_artifacts" "$@"' libexec/converge-brew-casks >/dev/null \
    || fail "cask convergence does not repair aborted-upgrade Caskroom state"
grep -F 'libexec/reclaim-app-ownership' install >/dev/null \
    || fail "installer does not reclaim applications left by a previous account"

if grep -R -E '/Users/[A-Za-z0-9._-]+|home.router|telegram|agentnotify|TCC\.db|security import|yabai-cert' \
    Brewfile bin launchd libexec system yabai skhd karabiner >/dev/null; then
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
