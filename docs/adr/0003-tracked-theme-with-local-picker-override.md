# 0003: Track a named theme and retain the machine-local picker override

Status: Retrospective, recorded 2026-09-08 from the existing theme contract.

The tracked Ghostty configuration selects one installed named theme. Other
managed layers use the resulting terminal palette through ANSI indices and
default colors; Funk does not copy theme files or maintain another raw palette.
This keeps one authored color choice and avoids deleting tmux's status styling
during a palette cleanup, a regression already recorded at commit `24663c1`.

Retain the upstream picker, but pin its output to Ghostty's machine-local
Application Support configuration. Its temporary-file-and-rename write would
replace the XDG Stow symlink if aimed there. Ghostty loads the local file after
the tracked file, so a pick overrides the checkout until someone promotes the
choice and removes the local override. Silent local drift is an accepted cost
of keeping the picker; this record does not add a warning or synchronization
mechanism.

Evidence: [theme and promotion procedure](../configuration.md#terminal-theme-and-local-picker),
[tracked configuration](../../ghostty/.config/ghostty/config),
[picker wrapper](../../bin/.local/bin/ghostty-themes), and
[validation](../../tests/validate.sh). These own the current procedure and checks.
