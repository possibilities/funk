alias vim='nvim'
alias p="pnpm"
alias mkdir='mkdir -p'

# yq with syntax highlighting via bat
yqb() {
  yq -M "$@" | bat -l yaml
}

# mkdir and cd into it
mcd() {
  command mkdir -p "$1" && cd "$1"
}
alias cmkdir='mcd'
