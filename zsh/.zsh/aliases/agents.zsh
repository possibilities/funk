alias claude="keeper agent claude"
alias pi="keeper agent pi"

function link-manager {
    cd ~/code/links && \
    arthack-claude-headless-clean.sh "$@" \
        --chrome \
        --mcp keep \
        --prompt-prefix 'Use /link-manager skill' \
        --prompt-prefix-separator ', '
}

function spotify {
    cd ~/code/spotify && \
    arthack-claude-headless-clean.sh "$@" \
        --mcp spotify lastfm \
        --prompt-prefix 'Use /serendipity skill' \
        --prompt-prefix-separator ', '
}
