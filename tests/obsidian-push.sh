#!/bin/bash
set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/funk-obsidian-push.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
export HOME="$scratch/home"
export FUNK_TEST_GIT_BIN
FUNK_TEST_GIT_BIN=$(command -v git)
mkdir -p "$HOME/obsidian/work/.obsidian/plugins/obsidian-livesync" "$scratch/bin"
printf 'note\n' >"$HOME/obsidian/work/note.md"
printf 'credential\n' >"$HOME/obsidian/work/.obsidian/plugins/obsidian-livesync/data.json"
printf 'hidden\n' >"$HOME/obsidian/work/.obsidian/secret.md"
cat >"$scratch/bin/gh" <<'EOF'
#!/bin/bash
if [ "${FUNK_TEST_PUBLIC:-0}" -eq 1 ]; then printf 'PUBLIC\n'; else printf 'PRIVATE\n'; fi
EOF
cat >"$scratch/bin/git" <<'EOF'
#!/bin/bash
if [ "$1" = push ]; then
    printf 'pushed\n' >>"$HOME/push-log"
    exit 0
fi
exec "$FUNK_TEST_GIT_BIN" "$@"
EOF
chmod +x "$scratch/bin/gh" "$scratch/bin/git"
export PATH="$scratch/bin:$PATH"
vault="$HOME/obsidian/work"
git -C "$vault" init -b main -q
git -C "$vault" config user.name Test
git -C "$vault" config user.email test@example.invalid
git -C "$vault" remote add origin https://github.com/possibilities/obsidian-work.git

"$root/bin/.local/bin/obsidian-push" >/dev/null
[ "$(git -C "$vault" ls-files | sort)" = "$(printf '.gitignore\nnote.md')" ] \
    || { printf 'obsidian-push staged unexpected files\n' >&2; exit 1; }
[ "$(wc -l <"$HOME/push-log" | tr -d ' ')" = 1 ] || exit 1

if FUNK_TEST_PUBLIC=1 "$root/bin/.local/bin/obsidian-push" >/dev/null 2>&1; then
    printf 'obsidian-push accepted a public repository\n' >&2
    exit 1
fi
git -C "$vault" add -f .obsidian/secret.md
if "$root/bin/.local/bin/obsidian-push" >/dev/null 2>&1; then
    printf 'obsidian-push accepted a hidden tracked note\n' >&2
    exit 1
fi
[ "$(wc -l <"$HOME/push-log" | tr -d ' ')" = 1 ] || exit 1
printf 'obsidian-push tests passed\n'
