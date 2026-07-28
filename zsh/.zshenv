# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# Homebrew is not added to PATH automatically on every macOS installation.
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
elif [[ -x /usr/local/bin/brew ]]; then
  export HOMEBREW_PREFIX=/usr/local
fi
if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  export PATH="$HOMEBREW_PREFIX/bin:$PATH"
fi

# User-installed tools and Funk's Stow-managed helper commands.
export PATH="$HOME/.local/bin:$PATH"

# bun
export PATH="$HOME/.bun/bin:$PATH"

# rust
export PATH="$HOME/.cargo/bin:$PATH"

# Ask Homebrew cask commands to skip download quarantine when they honor the
# cask opt. Scheduled bundle runs also clear quarantine from Brewfile-managed app
# bundles after installs and upgrades.
export HOMEBREW_CASK_OPTS="--no-quarantine"

# Use nvim as an editor
export EDITOR='nvim'
export VISUAL='nvim'

# Word characters (excludes / - . so alt+backspace stops at path separators)
export WORDCHARS='*?[]~=&;!#$%^(){}'

# Browsers default to dark mode
export AGENT_BROWSER_COLOR_SCHEME=dark

# Some multiplexer helpers

multiplexer_name_tab_after_directory() {
  local name=$(basename "$PWD")
  if [ -n "$TMUX" ]; then
    tmux rename-window -t${TMUX_PANE} "$name"
  else
    printf '\e]2;%s\a' "$name"
  fi
}

multiplexer_name_tab() {
  local name=$(basename "$1")
  if [ -n "$TMUX" ]; then
    tmux rename-window -t${TMUX_PANE} "$name"
  else
    printf '\e]2;%s\a' "$name"
  fi
}

[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
