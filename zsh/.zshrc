# Raise the open-file soft limit. macOS defaults to 256, which a multiplexer
# server hosting many panes exhausts (EMFILE, "Too many open files").
# 16384 is well under the 75000 kern.maxfilesperproc hard cap.
ulimit -n 16384 2>/dev/null

# Node via static PATH instead of sourcing nvm.sh, which costs ~1.9s per
# shell. The version is pinned — the same pin lives in bootstrap.sh; bump
# both together when moving to a new LTS. `nvm` lazy-loads on first use.
export NVM_DIR="$HOME/.nvm"
export PATH="$NVM_DIR/versions/node/v24.16.0/bin:$PATH"

# Balanced harness launches: AgentLaunch shims outrank the real binaries
# (`funk install-agentlaunch-shims`). Guarded so machines without them are
# untouched; must stay below every other bin-dir prepend to win.
[ -d "$HOME/.local/share/agentlaunch/shims" ] && export PATH="$HOME/.local/share/agentlaunch/shims:$PATH"
nvm() {
  unfunction nvm
  [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
  nvm "$@"
}

# Emacs keybindings
bindkey -e
bindkey "^[OA" history-beginning-search-backward
bindkey "^[OB" history-beginning-search-forward
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward
bindkey '^X^R' history-incremental-search-backward

# Completions — full compaudit security scan at most once a day; otherwise
# trust the cached dump (-C), which skips ~100ms of stat calls per shell.
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
  touch ~/.zcompdump
else
  compinit -C
fi
setopt complete_in_word
setopt extendedglob notify
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Auto escape carets
bindkey '^' self-insert-backslash
function self-insert-backslash() { LBUFFER+='\'; zle .self-insert }
zle -N self-insert-backslash

if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS="--popup center,60%,40%"
  source <(fzf --zsh)
  bindkey '^R' fzf-history-widget
fi

for file in ~/.zsh/aliases/*.zsh; do
  [[ -r $file ]] && source "$file"
done

# History — one file, never truncate; each shell writes immediately,
# but up-arrow stays per-shell (no live cross-pane interleave)
HISTFILE=~/.local/share/zsh/history
HISTSIZE=100000000
SAVEHIST=100000000
setopt INC_APPEND_HISTORY_TIME
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt HIST_NO_STORE
setopt HIST_EXPIRE_DUPS_FIRST

# Report cwd to terminal via OSC 7 (enables ghostty split-in-same-dir)
chpwd() { printf '\e]7;file://%s%s\e\\' "$HOST" "$PWD" }
chpwd  # emit once at shell startup

# Allow comments in shell
setopt interactivecomments

# Automatically change into directories without `cd`
setopt auto_cd

# automatically pushd
setopt auto_pushd
export dirstacksize=5

# Enable extended globbing
setopt EXTENDED_GLOB

# Default terminal
export TERMINAL='ghostty'

# pnpm (PATH setup in .zshenv)

# Android development
if JAVA_17_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null); then
  export JAVA_HOME="$JAVA_17_HOME"
fi
if [[ -d /opt/homebrew/share/android-commandlinetools ]]; then
  export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
fi
# Do not put the command line tools' platform-tools on PATH. It ships its own
# adb that shadows the Brewfile's android-platform-tools cask, and a client
# talking to a server of a different version restarts the server and drops
# every wireless connection. ANDROID_HOME still points build tooling at the SDK.

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
