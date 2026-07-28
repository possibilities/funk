# shell_gpt: Alt+S to suggest shell command from current input
_sgpt_suggest() {
  _sgpt_prev_line="$BUFFER"
  BUFFER="$(sgpt --shell --no-interaction <<< "$BUFFER")"
  if [[ -z "$BUFFER" ]]; then
    BUFFER="$_sgpt_prev_line"
  fi
  zle end-of-line
}
zle -N _sgpt_suggest
bindkey '\es' _sgpt_suggest

# shorthand for shell command generation with interactive menu
alias s='sgpt --shell'
