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
libexec/install-ai-tools
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
bin/.local/bin/focus-address-bar
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
brew "asmvik/formulae/yabai", trusted: true
brew "asmvik/formulae/skhd", trusted: true
cask "tailscale-app"
cask "ghostty"
cask "google-chrome"
cask "google-chrome@canary"
cask "brave-browser"
cask "firefox"
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
    || fail "Ghostty config was not stowed"
[ -L "$stow_home/.config/nvim" ] && [ -f "$stow_home/.config/nvim/init.lua" ] \
    || fail "Neovim config was not stowed"
[ -L "$stow_home/.local/bin/tmux-cycle-session" ] && [ ! -L "$stow_home/.local" ] \
    || fail "bin package did not use --no-folding"
[ -L "$stow_home/.local/bin/focus-address-bar" ] \
    || fail "browser address-bar helper was not stowed"
[ -L "$stow_home/Library/Application Support/io.datasette.llm/extra-openai-models.yaml" ] \
    || fail "LLM package was not stowed"
HOME="$stow_home" "$root/bin/funk" stow --check >/dev/null 2>&1
grep -F "\"\$funk_command\" stow" install >/dev/null \
    || fail "default install does not stow user configuration"
grep -F "\"\$funk_root/libexec/initialize-configs\"" install >/dev/null \
    || fail "default install does not initialize config dependencies"
grep -F "\"\$funk_root/libexec/install-ai-tools\"" install >/dev/null \
    || fail "default install does not install AI tools"
grep -F 'with_windows=1' install >/dev/null \
    || fail "default install does not enable the window stack"
grep -F -- '--without-windows) with_windows=0' install >/dev/null \
    || fail "default window stack has no explicit opt-out"
grep -F 'tmux-fzf.git' libexec/initialize-configs >/dev/null \
    || fail "tmux-fzf is not initialized"
if grep -R -Eqi \
    'tinty|tinted-theming|catppuccin|base16|base24|syntax-theme|color_theme|theme_background' \
    Brewfile README.md AGENTS.md libexec ghostty nvim tmux zsh btop starship git; then
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

ai_install_plan=$(libexec/install-ai-tools --check)
for required_ai_install in \
    'brew install gh  # intentional duplicate of the Brewfile' \
    'brew install --cask claude' \
    'brew install --cask chatgpt' \
    'brew install --cask stablyai/orca/orca' \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path' \
    'curl -fsSL https://pi.dev/install.sh | sh'; do
    printf '%s\n' "$ai_install_plan" | grep -F "$required_ai_install" >/dev/null \
        || fail "AI installation plan is missing: $required_ai_install"
done
grep -F "\"\$brew_bin\" install gh" libexec/install-ai-tools >/dev/null \
    || fail "AI installer does not deliberately duplicate the GitHub CLI install"
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
