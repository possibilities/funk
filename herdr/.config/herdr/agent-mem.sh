#!/bin/sh
# Tab-bar status: memory usage in GB per agent kind, e.g. "cc 3.4 / co 2.1"
# Sums RSS of each agent pane's full process tree (shell + descendants),
# grouped by herdr's detected agent kind. RSS overlaps shared pages, so
# treat the numbers as an indicator, not an accounting.
set -eu

tmpdir=$(mktemp -d) || exit 1
trap 'rm -rf "$tmpdir"' EXIT

ps -axo pid=,ppid=,rss= > "$tmpdir/ps"

herdr agent list 2>/dev/null \
    | jq -r '.result.agents[] | "\(.pane_id) \(.agent)"' \
    | while read -r pane_id kind; do
        shell_pid=$(herdr pane process-info --pane "$pane_id" 2>/dev/null \
            | jq -r '.result.process_info.shell_pid // empty')
        [ -n "$shell_pid" ] && printf '%s %s\n' "$kind" "$shell_pid"
    done > "$tmpdir/panes"

awk '
    NR == FNR { ppid[$1] = $2; rss[$1] = $3; next }
    { root[$2] = $1 }
    END {
        for (pid in ppid) {
            p = pid
            # walk up until we hit a pane shell or the top (depth-capped)
            for (d = 0; d < 64 && p != "" && !(p in root); d++) p = ppid[p]
            if (p in root) kb[root[p]] += rss[pid]
        }
        short["claude"] = "cc"; short["codex"] = "co"; short["pi"] = "pi"
        short["gemini"] = "gm"; short["cursor"] = "cu"; short["opencode"] = "oc"
        for (k in kb) {
            lbl = (k in short) ? short[k] : substr(k, 1, 2)
            out[++m] = sprintf("%s %.1f", lbl, kb[k] / 1048576)
        }
        # stable alphabetical order so the status text does not jitter
        for (i = 1; i <= m; i++)
            for (j = i + 1; j <= m; j++)
                if (out[j] < out[i]) { t = out[i]; out[i] = out[j]; out[j] = t }
        for (i = 1; i <= m; i++) printf "%s%s", (i > 1 ? " / " : ""), out[i]
        printf "\n"
    }' "$tmpdir/ps" "$tmpdir/panes"
