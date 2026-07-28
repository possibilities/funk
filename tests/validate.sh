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
libexec/stow-config
libexec/initialize-configs
libexec/install-update-agent
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
      focus_keys = rules.fetch(1).fetch("manipulators").map { |m| m.fetch("to").fetch(0).fetch("key_code") }
      abort "unexpected Karabiner Space focus keys" unless focus_keys == %w[f13 f14 f15 f16 f17 f18 f19 f20 f12]
    ' \
        karabiner/.config/karabiner/karabiner.json
elif command -v jq >/dev/null 2>&1; then
    jq -e '
      (.profiles[0].complex_modifications.rules | length) == 2 and
      ([.profiles[0].complex_modifications.rules[].manipulators | length] == [9, 9]) and
      ([.profiles[0].complex_modifications.rules[1].manipulators[].to[0].key_code] ==
        ["f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20", "f12"])
    ' karabiner/.config/karabiner/karabiner.json >/dev/null
else
    fail "Ruby or jq is required to validate Karabiner JSON"
fi

expected_brewfile='tap "asmvik/formulae"
tap "oven-sh/bun"
tap "tinted-theming/tinted"
brew "git-delta"
brew "bat"
brew "neovim"
brew "tmux"
brew "nvm"
brew "gh"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fzf"
brew "btop"
brew "uv"
brew "starship"
brew "stow"
brew "pnpm"
brew "oven-sh/bun/bun", trusted: true
brew "tinted-theming/tinted/tinty", trusted: true
brew "llm"
brew "asmvik/formulae/yabai", trusted: true
brew "asmvik/formulae/skhd", trusted: true
cask "tailscale-app"
cask "ghostty"
cask "google-chrome"
cask "google-chrome@canary"
cask "brave-browser"
cask "chatgpt"
cask "claude"
cask "obsidian"
cask "raycast"
cask "karabiner-elements"
cask "font-0xproto-nerd-font"'
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
"$root/bin/funk" configure-macos --check

stow_home=$(mktemp -d "${TMPDIR:-/tmp}/funk-stow-test.XXXXXX")
trap 'rm -rf "$stow_home"' EXIT
HOME="$stow_home" "$root/bin/funk" stow
[ -L "$stow_home/.config/git/config" ] || fail "git package was not stowed"
[ -L "$stow_home/.ssh/config" ] || fail "ssh config was not stowed"
[ -d "$stow_home/.ssh" ] && [ ! -L "$stow_home/.ssh" ] \
    || fail "ssh package did not use --no-folding"
[ -L "$stow_home/.config/ghostty/config" ] \
    || fail "Ghostty config was not stowed with room for generated themes"
[ -L "$stow_home/.local/bin/tmux-cycle-session" ] && [ ! -L "$stow_home/.local" ] \
    || fail "bin package did not use --no-folding"
[ -L "$stow_home/Library/Application Support/io.datasette.llm/extra-openai-models.yaml" ] \
    || fail "LLM package was not stowed"
HOME="$stow_home" "$root/bin/funk" stow --check >/dev/null 2>&1
grep -F "\"\$funk_command\" stow" install >/dev/null \
    || fail "default install does not stow user configuration"
grep -F "\"\$funk_root/libexec/initialize-configs\"" install >/dev/null \
    || fail "default install does not initialize config dependencies"
grep -F 'tmux-fzf.git' libexec/initialize-configs >/dev/null \
    || fail "tmux-fzf is not initialized"
grep -F 'tinty apply base16-catppuccin-mocha' libexec/initialize-configs >/dev/null \
    || fail "Tinty default theme is not initialized"

for required_setting in \
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
grep -F 'black-wallpaper.ppm' libexec/configure-macos >/dev/null \
    || fail "black wallpaper is not configured"
grep -F '$.NSWorkspace.sharedWorkspace' libexec/configure-macos >/dev/null \
    || fail "black wallpaper does not use the AppKit desktop-image API"
if grep -F 'tell application "System Events"' libexec/configure-macos >/dev/null; then
    fail "black wallpaper requires an Apple Events Automation grant"
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

[ "$(grep -Ec '^f(13|14|15|16|17|18|19|20) : yabai -m space --focus [1-8]$' skhd/.config/skhd/skhdrc)" -eq 8 ] \
    || fail "skhd numbered-Space 1-8 focus bindings are incomplete"
grep -Fx 'f12 : yabai -m space --focus 9' skhd/.config/skhd/skhdrc >/dev/null \
    || fail "skhd Space 9 focus binding is missing"
[ "$(grep -Ec '^cmd \+ shift - [1-9] : yabai -m window --space [1-9]$' skhd/.config/skhd/skhdrc)" -eq 9 ] \
    || fail "skhd numbered-Space move bindings are incomplete"
grep -F 'cmd + shift - v : /usr/bin/open "raycast://extensions/raycast/clipboard-history/clipboard-history"' \
    skhd/.config/skhd/skhdrc >/dev/null \
    || fail "Raycast Clipboard History shortcut is missing"
if grep -Eq 'right_option|left_command|left_option|Swap .*Command|hjkl to arrow' \
    karabiner/.config/karabiner/karabiner.json; then
    fail "unapproved Karabiner rules found"
fi

if grep -Eqi 'bundle cleanup|uninstall|quarantine|fetch-head|telegram|notify|sudo' \
    bin/funk libexec/funk-update libexec/install-update-agent \
    launchd/com.arthack.funk.update.plist.in; then
    fail "daily updater contains a prohibited operation"
fi

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
