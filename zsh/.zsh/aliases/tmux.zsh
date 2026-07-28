alias t="tmux"
alias ta="tmux attach"

alias tn="multiplexer_name_tab"
alias tnd="multiplexer_name_tab_after_directory"

start-arthack() {
  if [[ "$1" == "--kill-server" ]]; then
    tmux kill-server 2>/dev/null
    rm -rf /tmp/tmux-$(id -u) 2>/dev/null
    shift
  fi
  cd ~/code/arthack && rm -rf ~/.claude/plugins/cache && ./scripts/preinstall.sh && ./scripts/install.sh && ./scripts/doctor.sh
}
