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
libexec/repair-cask-user-dirs
libexec/reclaim-app-ownership
libexec/list-unattendable-casks
libexec/install-orca
libexec/migrate-gh-credentials
libexec/stow-config
libexec/initialize-configs
libexec/install-update-agent
libexec/install-tailscale-agent
libexec/install-home-awake
libexec/install-home-awake-agent
libexec/install-local-services
libexec/verify-local-services
libexec/install-transcript-vault-agent
libexec/configure-macos
libexec/verify-notifications
libexec/configure-system
libexec/funk-harden-client
libexec/install-hardening
libexec/funk-yabai
libexec/reload-karabiner
libexec/install-window-manager
system/funk-harden
system/install-hardening-root
system/funk-home-awake
system/install-home-awake-root
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
bin/.local/bin/home-awake
bin/.local/bin/transcript-vault
bin/.local/bin/adb-wireless-connect
bin/.local/bin/adb-wireless-pair
bin/.local/bin/raycast/scrcpy.sh
bin/.local/bin/raycast/scrcpy-no-audio.sh
bin/.local/bin/raycast/scrcpy-flex.sh
bin/.local/bin/raycast/scrcpy-no-audio-flex.sh
bin/.local/bin/raycast/localhost-8789-kiosk.sh
tests/adb-wireless.sh
tests/home-awake.sh
tests/kiosk-launcher.sh
tests/scrcpy-launchers.sh
tests/tailscale-online.sh
tests/gog-authed.sh
tests/funk-notify.sh
tests/fixtures/adb
tests/fixtures/brew
tests/fixtures/bun
tests/fixtures/gog
tests/fixtures/chrome
tests/fixtures/dscacheutil
tests/fixtures/dns-sd
tests/fixtures/gh
tests/fixtures/nc
tests/fixtures/npx
tests/fixtures/scrcpy
tests/fixtures/spctl
tests/fixtures/systemextensionsctl
tests/fixtures/tailscale
tests/fixtures/terminal-notifier
tests/fixtures/zig
tests/validate.sh
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

/bin/zsh -n zsh/.zshrc
if grep -R -Eqi 'keeper|KEEPER_ZSH_DROPINS' zsh; then
    fail "removed Keeper shell integration is still present"
fi

if command -v shellcheck >/dev/null 2>&1; then
    # The checker treats the skhd DSL as shell, so it is intentionally excluded.
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

# A suite that reaches tailscale-ensure-online without pinning the notifier
# posts the fixture's fictional tailnet into the operator's real Notification
# Center, which reads as a genuine outage on a machine that is fine. Nothing in
# the run itself reports that, so the wiring is checked rather than the output.
for file in tests/*.sh; do
    [ "$file" != tests/validate.sh ] || continue
    grep -q 'tailscale-ensure-online\|adb-wireless-connect' "$file" || continue
    grep -q 'FUNK_TERMINAL_NOTIFIER_BIN' "$file" \
        || fail "$file drives the Tailscale helper without pinning the notifier"
done

# ./install runs with a deliberately minimal PATH, so a service check that
# probes Agentweb, Agentbrain, or Tailscale by bare name finds nothing and
# reports a healthy daemon as not answering — the shape of failure that looks
# like a broken machine and is really a broken probe.
grep -q '\.local/bin:/usr/local/bin:' libexec/verify-local-services \
    || fail "verify-local-services must resolve its CLIs outside the installer's minimal PATH"
for probe in agentweb agentbrain; do
    grep -q "command -v $probe" libexec/verify-local-services \
        || fail "verify-local-services must report a missing $probe as missing, not as an unhealthy service"
done

/usr/bin/plutil -lint launchd/com.arthack.funk.update.plist.in >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.tailscale-online.plist.in >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.gog-authed.plist.in >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.transcript-vault.plist.in >/dev/null
/usr/bin/plutil -lint system/com.arthack.funk.harden-boot.plist >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.home-awake.plist.in >/dev/null
/usr/bin/plutil -lint launchd/com.arthack.funk.home-awake-caffeinate.plist >/dev/null
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

home_awake_plist=launchd/com.arthack.funk.home-awake.plist.in
[ "$(/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$home_awake_plist")" = true ] \
    || fail "home-awake agent does not run at login"
[ "$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$home_awake_plist")" = 30 ] \
    || fail "home-awake agent does not re-check every thirty seconds"
[ "$(/usr/libexec/PlistBuddy -c 'Print :WatchPaths:0' "$home_awake_plist")" \
    = /Library/Preferences/SystemConfiguration ] \
    || fail "home-awake agent does not react to network changes"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$home_awake_plist")" \
    = __HOME_AWAKE__ ] \
    || fail "home-awake agent does not invoke the stowed helper"
[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HOME' "$home_awake_plist")" \
    = __FUNK_HOME__ ] \
    || fail "home-awake agent does not pin the target user HOME"
if /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$home_awake_plist" \
    >/dev/null 2>&1; then
    fail "home-awake agent has an unapproved argument"
fi

caffeinate_plist=launchd/com.arthack.funk.home-awake-caffeinate.plist
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$caffeinate_plist")" \
    = /usr/bin/caffeinate ] \
    || fail "home-awake idle-sleep job does not run caffeinate"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$caffeinate_plist")" = -i ] \
    || fail "home-awake idle-sleep job does not hold off idle sleep only"
[ "$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$caffeinate_plist")" = true ] \
    || fail "home-awake idle-sleep job does not stay running while bootstrapped"
if /usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$caffeinate_plist" >/dev/null 2>&1; then
    fail "home-awake idle-sleep job runs at load instead of on demand"
fi
# Everything in ~/Library/LaunchAgents loads at login, so this job has to be
# installed somewhere home-awake alone can bootstrap it.
# shellcheck disable=SC2016 # The installer's literal source line is the subject.
grep -F 'caffeinate_path="$state_dir/$caffeinate_label.plist"' \
    libexec/install-home-awake-agent >/dev/null \
    || fail "home-awake idle-sleep job would load at login"

# The privileged surface is exactly these five invocations; a wildcard anywhere
# else would hand the unattended agent a general-purpose root path.
expected_home_awake_rules='sleep 0
sleep 1
screenlock off
screenlock immediate
screenlock [0-9]*'
actual_home_awake_rules=$(
    grep -oE "NOPASSWD: %s [a-z]+ [^\\\\']+" system/install-home-awake-root \
        | sed 's/^NOPASSWD: %s //'
)
[ "$actual_home_awake_rules" = "$expected_home_awake_rules" ] \
    || fail "home-awake sudoers rules differ from the approved set"

# shellcheck disable=SC2016 # The installer's literal source line is the subject.
grep -F '"$funk_command" install-home-awake' install >/dev/null \
    || fail "installer does not install the trusted-network agent"

transcript_vault_plist=launchd/com.arthack.funk.transcript-vault.plist.in
[ "$(/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$transcript_vault_plist")" = true ] \
    || fail "transcript vault agent does not run at login"
[ "$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$transcript_vault_plist")" = 3600 ] \
    || fail "transcript vault agent does not run hourly"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$transcript_vault_plist")" \
    = __TRANSCRIPT_VAULT__ ] \
    || fail "transcript vault agent does not invoke the stowed helper"
[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HOME' "$transcript_vault_plist")" \
    = __FUNK_HOME__ ] \
    || fail "transcript vault agent does not pin the target user HOME"
if /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$transcript_vault_plist" \
    >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$transcript_vault_plist" \
        >/dev/null 2>&1; then
    fail "transcript vault agent has an unapproved argument or trigger"
fi

# The vault exists to preserve transcripts; nothing in it may ever delete
# archive or repository content, and its snapshots must stay identifiable.
if sed 's/#.*//' bin/.local/bin/transcript-vault \
    | grep -E -- '--delete|restic forget|restic prune' >/dev/null; then
    fail "transcript vault contains a deletion path"
fi
grep -q -- '--tag claude-transcripts' bin/.local/bin/transcript-vault \
    || fail "transcript vault snapshots are not tagged"

# shellcheck disable=SC2016 # The installer's literal source line is the subject.
grep -F '"$funk_command" install-transcript-vault' install >/dev/null \
    || fail "installer does not install the transcript vault agent"

if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      data = JSON.parse(File.read(ARGV.fetch(0)))
      rules = data.fetch("profiles").fetch(0)
                  .fetch("complex_modifications").fetch("rules")
      abort "unexpected Karabiner rule count" unless rules.length == 6
      abort "unexpected Karabiner manipulator counts" unless rules.map { |r| r.fetch("manipulators").length } == [9, 9, 4, 2, 4, 1]

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

      # Orca cannot match any Option chord on macOS: its matcher reads
      # KeyboardEvent.key, and Option+, arrives as a composed character whether
      # or not Command is held. Karabiner therefore sends the stock chords Orca
      # already ships, so nothing has to be bound inside Orca at all.
      #
      # The four sources sit in two QWERTY columns so the hand finds them
      # without looking: U and M share the J column, I and comma share the K
      # column. U and I take their direction from vim, where J is down and K is
      # up, so Option+U is the next worktree and Option+I the previous one. Tab
      # navigation keeps physical order instead, left key previous.
      orca_rules = rules.fetch(4).fetch("manipulators")
      abort "unexpected Orca navigation sources" unless orca_rules.map { |m|
        [m.dig("from", "key_code"), m.dig("from", "modifiers")]
      } == %w[m comma u i].map { |key| [key, { "mandatory" => ["option"] }] }
      abort "unexpected Orca navigation targets" unless orca_rules.map { |m| m.fetch("to") } ==
        %w[open_bracket close_bracket down_arrow up_arrow].map { |key|
          [{ "key_code" => key, "modifiers" => ["command", "shift"] }]
        }
      abort "Orca navigation is not scoped to Orca" unless orca_rules.all? { |m|
        m.dig("conditions", 0, "type") == "frontmost_application_if" &&
          m.dig("conditions", 0, "bundle_identifiers") == ["^com\\.stablyai\\.orca$"]
      }

      caps_rule = rules.fetch(5).fetch("manipulators").fetch(0)
      abort "Caps Lock does not send Escape" unless
        caps_rule.dig("from", "key_code") == "caps_lock" &&
        caps_rule.dig("to", 0, "key_code") == "escape"
    ' \
        karabiner/.config/karabiner/karabiner.json
elif command -v jq >/dev/null 2>&1; then
    jq -e '
      (.profiles[0].complex_modifications.rules | length) == 6 and
      ([.profiles[0].complex_modifications.rules[].manipulators | length] == [9, 9, 4, 2, 4, 1]) and
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
      ([.profiles[0].complex_modifications.rules[4].manipulators[] |
        [.from.key_code, .from.modifiers]] ==
        [["comma", {"mandatory": ["option"]}], ["period", {"mandatory": ["option"]}],
         ["u", {"mandatory": ["option"]}], ["i", {"mandatory": ["option"]}]]) and
      ([.profiles[0].complex_modifications.rules[4].manipulators[].to] ==
        [[{"key_code": "open_bracket", "modifiers": ["command", "shift"]}],
         [{"key_code": "close_bracket", "modifiers": ["command", "shift"]}],
         [{"key_code": "up_arrow", "modifiers": ["command", "shift"]}],
         [{"key_code": "down_arrow", "modifiers": ["command", "shift"]}]]) and
      (all(.profiles[0].complex_modifications.rules[4].manipulators[];
        .conditions[0] ==
          {"type": "frontmost_application_if",
           "bundle_identifiers": ["^com\\.stablyai\\.orca$"]})) and
      (.profiles[0].complex_modifications.rules[5].manipulators[0].from.key_code ==
        "caps_lock") and
      (.profiles[0].complex_modifications.rules[5].manipulators[0].to[0].key_code ==
        "escape")
    ' karabiner/.config/karabiner/karabiner.json >/dev/null
else
    fail "Ruby or jq is required to validate Karabiner JSON"
fi

expected_brewfile='tap "asmvik/formulae"
tap "oven-sh/bun"
tap "openclaw/tap"
brew "git-delta"
brew "bat"
brew "neovim"
brew "tmux"
brew "nvm"
brew "gh"
brew "jq"
# pdftotext, required by Agentscrape and Agentbrain to read PDFs.
brew "poppler"
brew "terminal-notifier"
brew "yq"
# Snapshots the Claude Code transcript archive to B2/silverbird (transcript-vault).
brew "restic"
brew "ripgrep"
brew "fzf"
brew "btop"
brew "uv"
brew "starship"
brew "stow"
brew "pnpm"
brew "oven-sh/bun/bun", trusted: true
brew "zig"
brew "scrcpy"
brew "asmvik/formulae/yabai", trusted: true
brew "asmvik/formulae/skhd", trusted: true
brew "openclaw/tap/gogcli", trusted: true
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
# The scheduled updater delegates skill synchronization to the Agentdots
# checkout, so these tests exercise the real sibling scripts against the
# fixture stubs. Resolve it from the real HOME before any test overrides it;
# a machine without the checkout cannot validate Funk, by design.
update_agentdots_root="${FUNK_AGENTDOTS_ROOT:-$HOME/code/agentdots}"
[ -x "$update_agentdots_root/scripts/sync-skills" ] \
    || fail "Funk requires the Agentdots checkout to validate: $update_agentdots_root"
update_home="$update_test_dir/home"
update_state="$update_test_dir/brew-state"
update_brew_log="$update_test_dir/brew.log"
update_npx_log="$update_test_dir/npx.log"
update_bun_log="$update_test_dir/bun.log"
update_notifier_log="$update_test_dir/notifier.log"
# Stand in for a running Orca. launchd is always running and needs no cleanup:
# spawning a process here instead would outlive any fail() exit, which happens
# before a cleanup line and holds this suite's output pipe open until it dies.
# Pinning something keeps the branch deterministic rather than depending on
# whether the machine running the tests happens to have Orca open.
update_running_binary=/sbin/launchd
# Orca's version now comes from the bundle rather than Homebrew's receipt,
# because the app updates itself and the receipt stops describing what is
# installed the moment it does. Pin a fixture bundle so the assertions below do
# not depend on which Orca the machine running the tests happens to have.
update_orca_plist="$update_test_dir/Orca-Info.plist"
write_orca_plist() {
    /bin/cat >"$update_orca_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>$1</string>
</dict>
</plist>
EOF
}
write_orca_plist 0.9.0
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
        FUNK_AGENTDOTS_ROOT="$update_agentdots_root" \
        PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_TEST_BREW_EXIT=23 \
        FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
        FUNK_TEST_BREW_STATE="$update_state" \
        FUNK_TEST_BREW_LOG="$update_brew_log" \
        FUNK_TEST_BUN_LOG="$update_bun_log" \
        FUNK_ORCA_INFO_PLIST="$update_orca_plist" \
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
[ ! -s "$update_bun_log" ] \
    || fail "funk update ran a checkout installer after a Brewfile failure"

HOME="$update_home" \
    FUNK_AGENTDOTS_ROOT="$update_agentdots_root" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_BREW_EXIT=0 \
    FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
    FUNK_TEST_BREW_STATE="$update_state" \
    FUNK_TEST_BREW_LOG="$update_brew_log" \
    FUNK_TEST_FORMULA_NEW=2.0.0 \
    FUNK_TEST_ORCA_BUNDLE_NEW=1.0.0 \
    FUNK_TEST_ORCA_CLI_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    FUNK_TEST_NPX_LOG="$update_npx_log" \
    FUNK_TEST_BUN_LOG="$update_bun_log" \
    FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
    FUNK_NPX_BIN="$root/tests/fixtures/npx" \
    FUNK_BUN_BIN="$root/tests/fixtures/bun" \
    FUNK_ORCA_BINARY="$update_running_binary" \
    FUNK_ORCA_INFO_PLIST="$update_orca_plist" \
    FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
    "$root/bin/funk" update --notify >/dev/null
# Orca ships its own updater and the cask marks itself auto_updates so Homebrew
# will not compete with it; --greedy is the one flag that overrides that. Doing
# it anyway replaces the bundle under a running app, whose renderer then cannot
# resolve the code-split chunks it was built against -- Preferences was the
# pane that surfaced it. An installed Orca must be left alone.
if grep -F '<--greedy>' "$update_brew_log" >/dev/null; then
    fail "scheduled update greedily upgraded a cask that updates itself"
fi
if grep -F 'brew-stub <upgrade> <--cask>' "$update_brew_log" >/dev/null; then
    fail "scheduled update upgraded Orca instead of leaving it to its own updater"
fi
grep -F 'brew-stub <list> <--cask> <--versions> <orca>' "$update_brew_log" >/dev/null \
    || fail "scheduled update did not check whether Orca is installed at all"
grep -F 'npx-stub <--yes> <skills> <add> <https://github.com/stablyai/orca>' \
    "$update_npx_log" >/dev/null \
    || fail "scheduled update did not synchronize Orca skills"
# Select by title rather than by position: an upgrade of a running Orca sends a
# second, separate notification, and reading whichever happened to be last would
# make these assertions depend on that.
notification=$(grep -F '<Funk Update>' "$update_notifier_log" | tail -n 1)
printf '%s\n' "$notification" | grep -F 'terminal-notifier 1.0.0 → 2.0.0' >/dev/null \
    || fail "change-aware notification omitted the upgraded formula"
printf '%s\n' "$notification" | grep -F 'Orca 0.9.0 → 1.0.0' >/dev/null \
    || fail "change-aware notification omitted the upgraded Orca cask"
printf '%s\n' "$notification" | grep -F 'orca-cli skill rev 11111111 → aaaaaaaa' >/dev/null \
    || fail "change-aware notification omitted the updated Orca skill revision"
if printf '%s\n' "$notification" | grep -Eq 'orchestration|computer-use'; then
    fail "change-aware notification listed unchanged Orca skills"
fi

# Whatever replaced the bundle -- now Orca's own updater rather than Homebrew --
# a running Orca goes on serving code that is no longer on disk. On a machine
# where Orca is always open that is otherwise invisible until a pane fails to
# load, so the run must say so, in its own notification group rather than buried
# in the "Updated: ..." summary.
restart_notification=$(grep -F '<Restart Orca>' "$update_notifier_log" | tail -n 1 || true)
[ -n "$restart_notification" ] \
    || fail "a bundle that changed under a running Orca did not prompt for a restart"
printf '%s\n' "$restart_notification" | grep -F '1.0.0' >/dev/null \
    || fail "Orca restart prompt omitted the version now on disk"
printf '%s\n' "$restart_notification" \
    | grep -F '<-group> <com.arthack.funk.orca-restart>' >/dev/null \
    || fail "Orca restart prompt shares the general update notification group"

: >"$update_notifier_log"
HOME="$update_home" \
    FUNK_AGENTDOTS_ROOT="$update_agentdots_root" \
    PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
    FUNK_TEST_BREW_EXIT=0 \
    FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
    FUNK_TEST_BREW_STATE="$update_state" \
    FUNK_TEST_BREW_LOG="$update_brew_log" \
    FUNK_TEST_FORMULA_NEW=2.0.0 \
    FUNK_TEST_ORCA_CLI_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    FUNK_TEST_NPX_LOG="$update_npx_log" \
    FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
    FUNK_NPX_BIN="$root/tests/fixtures/npx" \
    FUNK_ORCA_INFO_PLIST="$update_orca_plist" \
    FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
    "$root/bin/funk" update --notify >/dev/null
grep -F '<-message> <Installer ran; no updates.>' "$update_notifier_log" >/dev/null \
    || fail "no-op scheduled update did not send the required concise notification"

: >"$update_bun_log"
: >"$update_notifier_log"
set +e
update_output=$(
    HOME="$update_home" \
        FUNK_AGENTDOTS_ROOT="$update_agentdots_root" \
        PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_TEST_BREW_EXIT=0 \
        FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
        FUNK_TEST_BREW_STATE="$update_state" \
        FUNK_TEST_BREW_LOG="$update_brew_log" \
        FUNK_TEST_NPX_LOG="$update_npx_log" \
        FUNK_TEST_BUN_LOG="$update_bun_log" \
        FUNK_TEST_NPX_EXIT=17 \
        FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
        AGENTDOTS_NPX_BIN="$root/tests/fixtures/npx" \
        FUNK_NPX_BIN="$root/tests/fixtures/npx" \
        FUNK_ORCA_INFO_PLIST="$update_orca_plist" \
        FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
        "$root/bin/funk" update --notify 2>&1
)
update_status=$?
set -e
[ "$update_status" -eq 17 ] \
    || fail "funk update did not propagate an installer failure"
printf '%s\n' "$update_output" | grep -F 'FAILED with exit status 17' >/dev/null \
    || fail "funk update did not log the installer failure"
grep -F 'brew-stub <list> <--cask> <--versions> <orca>' "$update_brew_log" >/dev/null \
    || fail "installer failure test did not converge Orca before failing"
grep -F 'npx-stub <--yes> <skills> <add>' "$update_npx_log" >/dev/null \
    || fail "installer failure test did not reach a skill installer"
failure_notification=$(tail -n 1 "$update_notifier_log")
printf '%s\n' "$failure_notification" | grep -F '<-title> <Funk Update Failed>' >/dev/null \
    || fail "installer failure did not send the failure notification"
printf '%s\n' "$failure_notification" \
    | grep -F '<-message> <Installer failed; no updates completed. See update.log.>' \
        >/dev/null \
    || fail "installer failure notification omitted the log pointer"

# The skill synchronization behavior itself — the agent* scan, the AgentVoice
# skip, the Orca skill verification — is Agentdots' and is asserted by
# ~/code/agentdots/tests/validate.sh. Funk asserts only its own wiring: the
# scheduled updater must preflight and invoke the Agentdots sync path.
# shellcheck disable=SC2016 # Match the literal declaration in the script.
grep -F 'skill_sync="$agentdots_root/scripts/sync-skills"' \
    libexec/funk-update >/dev/null \
    || fail "scheduled updater does not preflight the Agentdots skill sync"
# shellcheck disable=SC2016 # Match the literal default checkout resolution.
grep -F 'agentdots_root="${FUNK_AGENTDOTS_ROOT:-$HOME/code/agentdots}"' \
    libexec/funk-update >/dev/null \
    || fail "scheduled updater does not resolve the Agentdots checkout"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$skill_sync" || status=$?' libexec/funk-update >/dev/null \
    || fail "scheduled updater does not synchronize the globally managed skills"

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

# A cask installed under a previous account records that account's user
# directories forever, so Homebrew hunts for the old version's artifacts in a
# home this account cannot read and fails the whole unattended run reporting
# only that a source file "is not there". The scheduled path skips those too,
# because repairing one is a reinstall and an unattended run is the wrong place
# to remove a working cask on the chance the reinstall succeeds.
user_dirs_home="$update_test_dir/user-dirs-home"
user_dirs_info="$update_test_dir/user-dirs-info.json"
mkdir -p "$user_dirs_home"
/usr/bin/jq -n '{casks:[
    {token:"funk-font-foreign",installed:"1.0.0",artifacts:[{font:["Funk.ttf"]}]},
    {token:"funk-font-mine",installed:"1.0.0",artifacts:[{font:["Mine.ttf"]}]},
    {token:"funk-app-foreign",installed:"1.0.0",artifacts:[{app:["Funk App.app"]}]}
]}' >"$user_dirs_info"
for user_dirs_token in funk-font-foreign funk-font-mine funk-app-foreign; do
    mkdir -p "$repair_prefix/Caskroom/$user_dirs_token/.metadata"
done
printf '{"default":{"fontdir":"/Users/someone-else/Library/Fonts"}}' \
    >"$repair_prefix/Caskroom/funk-font-foreign/.metadata/config.json"
printf '{"default":{"fontdir":"%s/Library/Fonts"}}' "$user_dirs_home" \
    >"$repair_prefix/Caskroom/funk-font-mine/.metadata/config.json"
printf '{"default":{"fontdir":"/Users/someone-else/Library/Fonts"}}' \
    >"$repair_prefix/Caskroom/funk-app-foreign/.metadata/config.json"
stale_user_dirs=$(
    HOME="$user_dirs_home" \
        FUNK_BREW_BIN="$root/tests/fixtures/brew" \
        FUNK_TEST_BREW_PREFIX="$repair_prefix" \
        FUNK_TEST_CASK_INFO="$user_dirs_info" \
        "$root/libexec/repair-cask-user-dirs" --list \
            funk-font-foreign funk-font-mine funk-app-foreign
)
# Only the font cask recording another home: a cask whose recorded directories
# this account owns converges normally, and an .app cask never installs into a
# user directory at all, so its recorded paths are inert.
[ "$stale_user_dirs" = 'funk-font-foreign' ] \
    || fail "cask user-dir triage did not match the required set: $stale_user_dirs"
# --list is what the scheduled path consumes, so it must report rather than
# exit nonzero the way --check does for an interactive caller.
HOME="$user_dirs_home" \
    FUNK_BREW_BIN="$root/tests/fixtures/brew" \
    FUNK_TEST_BREW_PREFIX="$repair_prefix" \
    FUNK_TEST_CASK_INFO="$user_dirs_info" \
    "$root/libexec/repair-cask-user-dirs" --list funk-font-foreign >/dev/null \
    || fail "cask user-dir triage exited nonzero when it found affected casks"

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
"$root/bin/funk" verify-notifications --check

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
[ -L "$stow_home/.local/bin/raycast/localhost-8789-kiosk.sh" ] \
    || fail "Raycast kiosk command was not stowed"
# Operator guidance and AI-tool configuration are Agentdots', linked by its
# installer: the home AGENTS.md, the extension prompts, the AgentVoice
# doctrine, the llm model configuration, and the Orca overlay (which its
# configure-orca reads straight from that checkout — no ~/.config/orca
# staging copy exists anymore). Funk stowing any of them again would be a
# second writer for the same paths.
[ ! -e "$stow_home/AGENTS.md" ] \
    || fail "the home guidance is Agentdots'; nothing in Funk may stow ~/AGENTS.md"
[ ! -e "$stow_home/.config/arthack" ] \
    || fail "the extension prompts are Agentdots'; nothing in Funk may stow ~/.config/arthack"
[ ! -e "$stow_home/.config/agentvoice" ] \
    || fail "the AgentVoice doctrine is Agentdots'; nothing in Funk may stow ~/.config/agentvoice"
[ ! -e "$stow_home/Library/Application Support/io.datasette.llm" ] \
    || fail "the llm configuration is Agentdots'; nothing in Funk may stow into io.datasette.llm"
[ ! -e "$stow_home/.config/orca" ] \
    || fail "the Orca overlay is Agentdots'; nothing in Funk may stow ~/.config/orca"
HOME="$stow_home" "$root/bin/funk" stow --check >/dev/null 2>&1
# The overlay's merge behavior is asserted by Agentdots' own suite; Funk
# asserts only its wiring: the subcommand must delegate to that checkout.
# shellcheck disable=SC2016 # Match the literal delegation path in bin/funk.
grep -F 'agentdots_configure="$HOME/code/agentdots/scripts/configure-orca"' \
    bin/funk >/dev/null \
    || fail "funk configure-orca does not delegate to the Agentdots overlay tooling"

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
# shellcheck disable=SC2016 # Match the literal helper invocations in ./install.
grep -F '"$funk_root/libexec/migrate-gh-credentials"' install >/dev/null \
    || fail "default install does not migrate GitHub CLI credentials"
# shellcheck disable=SC2016 # Match the literal cask converge in ./install.
grep -F '"$funk_root/libexec/converge-brew-casks" claude chatgpt' install >/dev/null \
    || fail "default install does not converge the AI desktop applications"
# shellcheck disable=SC2016 # Match the literal Orca installer call in ./install.
grep -F '"$funk_root/libexec/install-orca"' install >/dev/null \
    || fail "default install does not install the Orca cask"
# shellcheck disable=SC2016 # Match the literal Agentdots invocation in ./install.
grep -F '"$agentdots_root/scripts/install.sh" --install' install >/dev/null \
    || fail "default install does not run the Agentdots installer"
grep -F 'Agentdots owns the AI toolchain and is missing' install >/dev/null \
    || fail "default install does not stop loudly without the Agentdots checkout"
grep -F "\"\$funk_command\" configure-orca" install >/dev/null \
    || fail "default install does not reconcile Orca settings"
grep -F "\"\$funk_command\" install-tailscale-recovery" install >/dev/null \
    || fail "default install does not load Tailscale recovery"
# Unattended health checks report through terminal-notifier, so an installation
# that never confirms delivery can leave every future alert silent.
grep -F "\"\$funk_command\" verify-notifications" install >/dev/null \
    || fail "default install does not verify notification delivery"
grep -F 'notifications_blocked=1' install >/dev/null \
    || fail "install treats blocked notifications as fatal instead of reporting"
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

# The AI toolchain plan — vendor CLIs, npm globals, skills, extension prompts
# — is Agentdots' and is asserted by ~/code/agentdots/tests/validate.sh. Funk
# asserts only the surface it kept: the Orca cask plan and the GitHub CLI
# credential migration.
orca_plan=$(libexec/install-orca --check)
for required_orca_plan in \
    'brew install --cask --yes stablyai/orca/orca  # when missing' \
    'leave an installed Orca to its own updater  # never brew upgrade' \
    'remove com.apple.quarantine only from Homebrew'\''s declared Orca.app target' \
    'verify the cask receipt'; do
    printf '%s\n' "$orca_plan" | grep -F "$required_orca_plan" >/dev/null \
        || fail "Orca installation plan is missing: $required_orca_plan"
done
# The Orca harness skills moved to Agentdots' sync-skills; a skills line here
# would be the second synchronization path that split exists to prevent.
if printf '%s\n' "$orca_plan" | grep -Fq 'skills add'; then
    fail "Orca installation plan still synchronizes skills owned by Agentdots"
fi
if grep -F 'skills add' libexec/install-orca >/dev/null; then
    fail "the Orca installer still synchronizes skills owned by Agentdots"
fi

grep -F '^[[:space:]]*oauth_token:' libexec/migrate-gh-credentials >/dev/null \
    || fail "GitHub CLI migration does not require a portable token"
grep -F 'Preserving existing GitHub CLI credentials' libexec/migrate-gh-credentials >/dev/null \
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
    'com.apple.ControlCenter AirplayRecieverEnabled -bool false' \
    'io.tailscale.ipn.macsys SUEnableAutomaticChecks -bool false' \
    'io.tailscale.ipn.macsys SUAutomaticallyUpdate -bool false'; do
    grep -F "$required_setting" libexec/configure-macos >/dev/null \
        || fail "required macOS setting is missing: $required_setting"
done
# Tailscale's own updater staged a system extension upgrade that wedged on the
# next app restart and left no daemon. Homebrew has to be the only updater that
# touches this cask, so the reason has to survive in the source rather than
# reading as an arbitrary preference someone later "cleans up".
grep -F 'Sparkle' libexec/configure-macos >/dev/null \
    || fail "disabling Tailscale's own updater is unexplained"
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
"$root/tests/gog-authed.sh"
"$root/tests/funk-notify.sh"
"$root/tests/home-awake.sh"
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
"$root/tests/kiosk-launcher.sh"
kiosk_launcher=bin/.local/bin/raycast/localhost-8789-kiosk.sh
grep -F '@raycast.title Localhost 8789 (kiosk)' "$kiosk_launcher" >/dev/null \
    || fail "localhost kiosk Raycast command is missing"
# Launching through `open` reuses a running Chrome and discards --kiosk, so the
# launcher must keep invoking the binary with its own profile directory.
grep -F -- '--user-data-dir=' "$kiosk_launcher" >/dev/null \
    || fail "kiosk launcher lost the dedicated Chrome profile"
if grep -Eq '(^|[^-])open ' "$kiosk_launcher"; then
    fail "kiosk launcher routes Chrome through open and would drop --kiosk"
fi
grep -Fx 'cask "google-chrome", greedy: true' Brewfile >/dev/null \
    || fail "Google Chrome is missing from the Brewfile"
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
# The Agentdots skill sync joined the scheduled path when the updater started
# delegating to it, so it inherits the same prohibition even though it lives
# in the sibling checkout.
if grep -Eqi 'bundle cleanup|uninstall|fetch-head|telegram|sudo' \
    bin/funk libexec/funk-update libexec/install-update-agent \
    libexec/install-orca libexec/converge-brewfile libexec/converge-brew-casks \
    libexec/repair-cask-artifacts \
    "$update_agentdots_root/scripts/sync-skills" \
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
# shellcheck disable=SC2016 # Match the literal triage invocation in the script.
grep -F '"$cask_dir_lister" --list --brewfile "$brewfile"' \
    libexec/funk-update >/dev/null \
    || fail "scheduled updater does not skip casks installed under a previous account"

# Orca updates itself; the cask sets auto_updates so Homebrew will not compete,
# and --greedy is the single flag that overrides that. Overriding it replaces
# the bundle under a running app, which then fails to resolve the code-split
# chunks it was built against. Nothing on the scheduled path may ask for it.
grep -F -- '--install-only stablyai/orca/orca' libexec/install-orca >/dev/null \
    || fail "Orca installer does not leave an installed Orca to its own updater"
# Comments here explain why --greedy is wrong for Orca, so scan code only.
if grep -v '^[[:space:]]*#' libexec/install-orca | grep -F -- '--greedy' >/dev/null; then
    fail "Orca installer still asks Homebrew to upgrade a self-updating cask"
fi

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
grep -F 'libexec/repair-cask-user-dirs' install >/dev/null \
    || fail "installer does not repair casks installed under a previous account"

# Root ownership means an installer owns the bundle only when the cask ships a
# pkg. Treating every root-owned bundle that way let the scheduled updater
# attempt an app-cask upgrade that could only ever fail on a sudo prompt it
# cannot answer, so both helpers must consult the artifact metadata.
for ownership_helper in libexec/reclaim-app-ownership libexec/list-unattendable-casks; do
    grep -F 'pkg_casks' "$ownership_helper" >/dev/null \
        || fail "$ownership_helper treats every root-owned bundle as a pkg install"
done

if grep -R -E '/Users/[A-Za-z0-9._-]+|telegram|agentnotify|TCC\.db|security import|yabai-cert' \
    Brewfile bin launchd libexec system yabai skhd karabiner >/dev/null; then
    fail "old-account or prohibited privileged machinery leaked into Funk"
fi

# home-awake identifies the home network deliberately, so the blanket ban on
# router detection no longer fits the whole tree. The ban it replaces is the one
# that actually mattered: the travel firewall must never decide it is somewhere
# safe and relax itself. Nothing on the PF path may learn where it is.
if grep -R -E 'home.router|router_mac|arp |ipconfig getoption|ProfileID' \
    system/funk-harden system/install-hardening-root libexec/install-hardening \
    libexec/funk-harden-client >/dev/null; then
    fail "the travel firewall gained network-location detection"
fi
if grep -R -E 'funk-home-awake|home-awake' \
    system/funk-harden system/install-hardening-root >/dev/null; then
    fail "the travel firewall was coupled to home-awake"
fi

# Nothing counts as home until it is recorded on the machine itself. A shipped
# default would hand a fresh account somebody else's network.
if grep -R -E '^[^#]*(router_mac|default_router)=[0-9a-fA-F]{2}:' \
    bin/.local/bin/home-awake >/dev/null; then
    fail "home-awake ships a default home router"
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
