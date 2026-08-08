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
libexec/install-agentvoice-skills
libexec/install-agentvoice-app
libexec/stow-config
libexec/initialize-configs
libexec/configure-orca
libexec/install-ai-tools
libexec/install-update-agent
libexec/install-tailscale-agent
libexec/install-home-awake
libexec/install-home-awake-agent
libexec/install-local-services
libexec/verify-local-services
libexec/install-transcript-vault-agent
libexec/install-transcript-vault-agent
libexec/configure-macos
libexec/verify-notifications
libexec/configure-system
libexec/funk-harden-client
libexec/install-hardening
libexec/funk-yabai
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

/bin/zsh -n zsh/.zshrc zsh/.zsh/aliases/agents.zsh
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
brew "llm"
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
update_agentvoice_root="$update_home/code/agentvoice"
mkdir -p "$update_agentvoice_root"
cat >"$update_agentvoice_root/package.json" <<'EOF'
{
  "name": "agentvoice",
  "scripts": {
    "skills:install": "bun run src/agentvoice.ts tools skills install"
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
        FUNK_TEST_BUN_LOG="$update_bun_log" \
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
    || fail "funk update ran the AgentVoice installer after a Brewfile failure"

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
    FUNK_TEST_BUN_LOG="$update_bun_log" \
    FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
    FUNK_NPX_BIN="$root/tests/fixtures/npx" \
    FUNK_BUN_BIN="$root/tests/fixtures/bun" \
    FUNK_ORCA_BINARY="$update_running_binary" \
    FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
    "$root/bin/funk" update --notify >/dev/null
grep -F 'brew-stub <upgrade> <--cask> <--greedy> <--yes> <stablyai/orca/orca>' \
    "$update_brew_log" >/dev/null \
    || fail "scheduled update did not explicitly upgrade installed Orca"
grep -F 'npx-stub <--yes> <skills> <add> <https://github.com/stablyai/orca>' \
    "$update_npx_log" >/dev/null \
    || fail "scheduled update did not synchronize Orca skills"
grep -F "bun-stub <run> <--cwd> <$update_agentvoice_root> <skills:install>" \
    "$update_bun_log" >/dev/null \
    || fail "scheduled update did not invoke the AgentVoice skill installer"
# The six-hour background path must never rebuild or relaunch the desktop app.
if grep -F 'app:install' "$update_bun_log" >/dev/null; then
    fail "scheduled update installed the AgentVoice desktop application"
fi
if grep -F 'install-agentvoice-app' libexec/funk-update >/dev/null; then
    fail "scheduled updater references the interactive AgentVoice app installer"
fi
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

# Homebrew replaces Orca's bundle without quitting it, so a running Orca serves
# the old bundle until restarted. On a machine where Orca is always open that is
# otherwise invisible, so the upgrade must say so -- in its own notification
# group, not buried in the "Updated: ..." summary.
restart_notification=$(grep -F '<Restart Orca>' "$update_notifier_log" | tail -n 1 || true)
[ -n "$restart_notification" ] \
    || fail "upgrading a running Orca did not prompt for a restart"
printf '%s\n' "$restart_notification" | grep -F '1.0.0' >/dev/null \
    || fail "Orca restart prompt omitted the version now on disk"
printf '%s\n' "$restart_notification" \
    | grep -F '<-group> <com.arthack.funk.orca-restart>' >/dev/null \
    || fail "Orca restart prompt shares the general update notification group"

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

: >"$update_bun_log"
: >"$update_notifier_log"
set +e
update_output=$(
    HOME="$update_home" \
        PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_TEST_BREW_EXIT=0 \
        FUNK_TEST_BREW_PREFIX="$update_test_dir/prefix" \
        FUNK_TEST_BREW_STATE="$update_state" \
        FUNK_TEST_BREW_LOG="$update_brew_log" \
        FUNK_TEST_NPX_LOG="$update_npx_log" \
        FUNK_TEST_BUN_LOG="$update_bun_log" \
        FUNK_TEST_BUN_EXIT=17 \
        FUNK_TEST_NOTIFIER_LOG="$update_notifier_log" \
        FUNK_NPX_BIN="$root/tests/fixtures/npx" \
        FUNK_TERMINAL_NOTIFIER_BIN="$root/tests/fixtures/terminal-notifier" \
        "$root/bin/funk" update --notify 2>&1
)
update_status=$?
set -e
[ "$update_status" -eq 17 ] \
    || fail "funk update did not propagate an AgentVoice installer failure"
printf '%s\n' "$update_output" | grep -F 'FAILED with exit status 17' >/dev/null \
    || fail "funk update did not log the AgentVoice installer failure"
grep -F 'brew-stub <upgrade> <--cask> <--greedy> <--yes> <stablyai/orca/orca>' \
    "$update_brew_log" >/dev/null \
    || fail "AgentVoice installer failure test did not converge Orca before failing"
grep -F "bun-stub <run> <--cwd> <$update_agentvoice_root> <skills:install>" \
    "$update_bun_log" >/dev/null \
    || fail "AgentVoice installer failure test did not invoke the installer"
failure_notification=$(tail -n 1 "$update_notifier_log")
printf '%s\n' "$failure_notification" | grep -F '<-title> <Funk Update Failed>' >/dev/null \
    || fail "AgentVoice installer failure did not send the failure notification"
printf '%s\n' "$failure_notification" \
    | grep -F '<-message> <Installer failed; no updates completed. See update.log.>' \
        >/dev/null \
    || fail "AgentVoice installer failure notification omitted the log pointer"

agentvoice_missing_home="$update_test_dir/agentvoice-missing-home"
mkdir -p "$agentvoice_missing_home"
set +e
agentvoice_missing_output=$(
    HOME="$agentvoice_missing_home" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        "$root/libexec/install-agentvoice-skills" 2>&1
)
agentvoice_missing_status=$?
set -e
[ "$agentvoice_missing_status" -eq 1 ] \
    || fail "AgentVoice skill installer did not fail without a local checkout"
printf '%s\n' "$agentvoice_missing_output" \
    | grep -F \
        "AgentVoice checkout not found: $agentvoice_missing_home/code/agentvoice/package.json is missing" \
        >/dev/null \
    || fail "AgentVoice skill installer did not report the missing checkout clearly"

# The desktop application bridge: Funk provisions Zig and the pinned Native SDK
# CLI, then calls AgentVoice's own app:install contract. These cases use stubs
# only; nothing is installed globally, no bundle is written, no app is launched.
app_installer="$root/libexec/install-agentvoice-app"
app_bun_log="$update_test_dir/app-bun.log"
app_home="$update_test_dir/agentvoice-app-home"
app_agentvoice_root="$app_home/code/agentvoice"
mkdir -p "$app_agentvoice_root"
cat >"$app_agentvoice_root/package.json" <<'EOF'
{
  "name": "agentvoice",
  "scripts": {
    "app:install": "bun run src/agentvoice.ts ui app --install"
  }
}
EOF

run_app_installer() {
    set +e
    app_output=$(
        HOME="$app_home" \
            PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
            FUNK_BUN_BIN="$root/tests/fixtures/bun" \
            FUNK_TEST_BUN_LOG="$app_bun_log" \
            /usr/bin/env "$@" "$app_installer" 2>&1
    )
    app_status=$?
    set -e
}

app_missing_home="$update_test_dir/agentvoice-app-missing-home"
mkdir -p "$app_missing_home"
set +e
app_missing_output=$(
    HOME="$app_missing_home" \
        PATH="$root/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_BUN_BIN="$root/tests/fixtures/bun" \
        "$app_installer" 2>&1
)
app_missing_status=$?
set -e
[ "$app_missing_status" -eq 1 ] \
    || fail "AgentVoice app installer did not fail without a local checkout"
printf '%s\n' "$app_missing_output" \
    | grep -F \
        "AgentVoice checkout not found: $app_missing_home/code/agentvoice/package.json is missing" \
        >/dev/null \
    || fail "AgentVoice app installer did not report the missing checkout clearly"

: >"$app_bun_log"
set +e
app_no_zig_output=$(
    HOME="$app_home" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        FUNK_BUN_BIN="$root/tests/fixtures/bun" \
        FUNK_TEST_BUN_LOG="$app_bun_log" \
        "$app_installer" 2>&1
)
app_no_zig_status=$?
set -e
[ "$app_no_zig_status" -eq 1 ] \
    || fail "AgentVoice app installer did not fail without Zig"
printf '%s\n' "$app_no_zig_output" | grep -F 'zig is not installed' >/dev/null \
    || fail "AgentVoice app installer did not report a missing Zig toolchain"
[ ! -s "$app_bun_log" ] \
    || fail "AgentVoice app installer called AgentVoice without Zig"

: >"$app_bun_log"
run_app_installer FUNK_TEST_ZIG_VERSION=0.15.1
[ "$app_status" -eq 1 ] \
    || fail "AgentVoice app installer accepted a Zig older than 0.16"
printf '%s\n' "$app_output" \
    | grep -F 'requires Zig 0.16 or newer, found 0.15.1' >/dev/null \
    || fail "AgentVoice app installer did not name the incompatible Zig version"
[ ! -s "$app_bun_log" ] \
    || fail "AgentVoice app installer called AgentVoice with an incompatible Zig"

: >"$app_bun_log"
run_app_installer FUNK_TEST_ZIG_VERSION=0.16.0-dev.512+abcdef
[ "$app_status" -eq 0 ] \
    || fail "AgentVoice app installer rejected a compatible Zig development build"
grep -F "bun-stub <run> <--cwd> <$app_agentvoice_root> <app:install>" \
    "$app_bun_log" >/dev/null \
    || fail "AgentVoice app installer did not invoke the AgentVoice app:install contract"

# Repeat interactive setup is not a Funk-side no-op: every run delegates to
# AgentVoice again, and AgentVoice decides whether it can replace the bundle.
: >"$app_bun_log"
run_app_installer FUNK_TEST_ZIG_VERSION=0.16.1
[ "$app_status" -eq 0 ] || fail "first AgentVoice app install run failed"
run_app_installer FUNK_TEST_ZIG_VERSION=0.16.1
[ "$app_status" -eq 0 ] \
    || fail "repeat AgentVoice app install failed against an inactive installed app"
[ "$(grep -c -F "<app:install>" "$app_bun_log")" -eq 2 ] \
    || fail "AgentVoice app installer did not delegate both runs to AgentVoice"

# An installed copy that is currently running makes AgentVoice refuse, and that
# refusal must reach the user with its quit-and-rerun instruction and status.
: >"$app_bun_log"
run_app_installer FUNK_TEST_ZIG_VERSION=0.16.1 FUNK_TEST_AGENTVOICE_APP_RUNNING=1
[ "$app_status" -eq 3 ] \
    || fail "AgentVoice app installer did not propagate the running-app refusal status"
printf '%s\n' "$app_output" \
    | grep -F 'quit it and rerun this installer' >/dev/null \
    || fail "AgentVoice app installer swallowed the running-app diagnostic"
grep -F "bun-stub <run> <--cwd> <$app_agentvoice_root> <app:install>" \
    "$app_bun_log" >/dev/null \
    || fail "running-app refusal test did not reach the AgentVoice contract"

: >"$app_bun_log"
run_app_installer FUNK_TEST_ZIG_VERSION=0.16.1 FUNK_TEST_BUN_EXIT=19
[ "$app_status" -eq 19 ] \
    || fail "AgentVoice app installer did not propagate the AgentVoice failure status"

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
[ -L "$stow_home/Library/Application Support/io.datasette.llm/extra-openai-models.yaml" ] \
    || fail "LLM package was not stowed"
[ -L "$stow_home/.config/orca" ] && [ -f "$stow_home/.config/orca/settings.json" ] \
    || fail "Orca settings overlay was not stowed with normal directory folding"
[ -L "$stow_home/AGENTS.md" ] \
    || fail "home-level agent guidance was not stowed"
# install-ai-tools renders every skill against these three files, so a fresh
# account that lacks them installs skills with the extensions silently missing.
[ -L "$stow_home/.config/arthack" ] \
    && [ -f "$stow_home/.config/arthack/SYSTEM.md" ] \
    && [ -f "$stow_home/.config/arthack/GUIDELINES.md" ] \
    && [ -f "$stow_home/.config/arthack/TOOLS.md" ] \
    || fail "Art Hack extension prompts were not stowed with normal directory folding"
[ -s "$stow_home/.config/arthack/TOOLS.md" ] \
    || fail "Art Hack extension prompts must not be empty — install-ai-tools renders every skill against them"
# Global advice belongs in the Art Hack extension prompts, so the stowed home
# guidance stays deliberately empty; the tripwire keeps advice from accreting
# back into every session.
[ ! -s "$stow_home/AGENTS.md" ] \
    || fail "home-level agent guidance should stay empty — global advice belongs in the Art Hack extension prompts"
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

ai_install_plan=$(libexec/install-ai-tools --check)
for required_ai_install in \
    'brew install or upgrade gh  # intentional duplicate of the Brewfile' \
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
    'brew install or upgrade zig  # AgentVoice native packaging needs 0.16 or newer' \
    'npm install --global @native-sdk/cli@0.7  # AgentVoice refuses other lines' \
    "bun run --cwd \"\$HOME/code/agentvoice\" app:install  # AgentVoice owns packaging and launch" \
    'codex mcp add shadcn -- npx shadcn@latest mcp' \
    'claude mcp add --scope user shadcn -- npx shadcn@latest mcp' \
    'opencode mcp add shadcn -- npx shadcn@latest mcp' \
    'native skills list' \
    'ln -sfn ~/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md' \
    'ln -sfn ~/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files' \
    'npx --yes skills add https://github.com/stablyai/orca --agent codex claude-code opencode pi --skill orca-cli orchestration computer-use --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/skills --agent codex claude-code opencode pi --skill find-skills --global --yes' \
    'npx --yes skills add https://github.com/anthropics/skills --agent codex claude-code opencode pi --skill frontend-design --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code opencode pi --skill web-design-guidelines --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/agent-skills --agent codex claude-code opencode pi --skill vercel-react-best-practices --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai --agent codex claude-code opencode pi --skill ai-sdk --global --yes' \
    'npx --yes skills add https://github.com/vercel/ai-elements --agent codex claude-code opencode pi --skill ai-elements --global --yes' \
    'npx --yes skills add https://github.com/shadcn/ui --agent codex claude-code opencode pi --skill shadcn --global --yes' \
    'npx --yes skills add https://github.com/vercel-labs/native --agent codex claude-code opencode pi --skill native-sdk --global --yes' \
    "npx --yes skills add \"\$HOME/code/arthack\" --agent codex claude-code opencode pi --skill hack resource-create resource-update --global --yes" \
    "\"\$HOME/code/arthack/scripts/render\""; do
    printf '%s\n' "$ai_install_plan" | grep -F "$required_ai_install" >/dev/null \
        || fail "AI installation plan is missing: $required_ai_install"
done
if printf '%s\n' "$ai_install_plan" | grep -Eq -- '--skill ([^[:space:]]+ )*funk([[:space:]]|$)'; then
    fail "AI installation plan still installs the retired Funk priming skill"
fi
if printf '%s\n' "$ai_install_plan" | grep -qi 'livekit'; then
    fail "AI installation plan still includes LiveKit setup"
fi
grep -F "art_hack_root=\"\$HOME/code/arthack\"" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not own the Art Hack skill source"
grep -F "npx --yes skills add \"\$art_hack_root\"" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not synchronize the Hack skill"
grep -F "\"\$art_hack_root/scripts/render\"" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not render the Art Hack skills"
grep -F "\$art_hack_root/hack/SKILL.md" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not validate the Hack skill source"
grep -F "\$art_hack_root/hack/agents/openai.yaml" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not validate the Hack skill manifest"
grep -F 'link_agent_guidance' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not link the shared agent guidance"
# shellcheck disable=SC2016 # Match the literal target paths in the script.
grep -F '"$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not target both CLI guidance locations"
grep -F 'refusing to replace independent guidance' libexec/install-ai-tools >/dev/null \
    || fail "AI installer would replace independent guidance files"
grep -F 'install_or_upgrade_formula gh' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not deliberately converge the GitHub CLI"

# AgentVoice's native packaging refuses a Native SDK CLI outside 0.7 and a Zig
# older than 0.16, so both prerequisites must be converged before Funk calls the
# AgentVoice-owned desktop application installer.
grep -F 'native_sdk_version=0.7' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not pin the Native SDK CLI to the compatible 0.7 line"
if grep -F '@native-sdk/cli@latest' libexec/install-ai-tools >/dev/null; then
    fail "AI installer still tracks the latest Native SDK CLI release"
fi
grep -F 'install_or_upgrade_formula zig' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not converge the Zig toolchain"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agentvoice-app"' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not install the AgentVoice desktop application"
ai_zig_line=$(grep -n -F 'install_or_upgrade_formula zig' libexec/install-ai-tools | cut -d: -f1)
ai_native_sdk_line=$(grep -n -F 'native_sdk_version=0.7' libexec/install-ai-tools | cut -d: -f1)
ai_agentvoice_app_line=$(
    # shellcheck disable=SC2016 # Match the literal helper invocation in the script.
    grep -n -F '"$script_dir/install-agentvoice-app"' libexec/install-ai-tools | cut -d: -f1
)
[ "$ai_zig_line" -lt "$ai_agentvoice_app_line" ] \
    && [ "$ai_native_sdk_line" -lt "$ai_agentvoice_app_line" ] \
    || fail "AI installer installs the AgentVoice app before its native prerequisites"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agentvoice_app_status"' libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not propagate an AgentVoice app installation failure"
grep -F 'quit a running AgentVoice.app' libexec/install-ai-tools >/dev/null \
    || fail "AI installer failure guidance omits quitting a running AgentVoice.app"

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
if grep -Eqi 'bundle cleanup|uninstall|fetch-head|telegram|sudo' \
    bin/funk libexec/funk-update libexec/install-update-agent \
    libexec/install-orca libexec/converge-brewfile libexec/converge-brew-casks \
    libexec/repair-cask-artifacts libexec/install-agentvoice-skills \
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
