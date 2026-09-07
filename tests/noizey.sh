#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
make_fixture() {
    mkdir -p "$1"
    printf 'module noizey\n\ngo 1.24.0\n' >"$1/go.mod"
    printf 'package main\nfunc main() {}\n' >"$1/main.go"
    git init -q "$1"
    git -C "$1" add go.mod main.go
    git -C "$1" -c user.name=Fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture
}
if [ "${1:-}" = --fixture ]; then
    [ "$#" -eq 2 ] || exit 64
    make_fixture "$2"
    exit 0
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/funk-noizey-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
export FUNK_NOIZEY_ROOT="$scratch/source tree"
export FUNK_NOIZEY_DIR="$scratch/native install"
export FUNK_NOIZEY_GO_BIN="$root/tests/fixtures/go-noizey"
export FUNK_STOW_BIN="$root/tests/fixtures/stow-noizey"
export FUNK_TEST_NOIZEY_STOW_LOG="$scratch/stow.log"
make_fixture "$FUNK_NOIZEY_ROOT"
binary="$FUNK_NOIZEY_DIR/noizey"
fail() { printf 'noizey test: %s\n' "$*" >&2; exit 1; }
run_install() { "$root/bin/funk" install-noizey; }

run_install >"$scratch/first.out"
[ -x "$binary" ] || fail "native binary not installed"
grep -F '<--no-folding>' "$FUNK_TEST_NOIZEY_STOW_LOG" >/dev/null \
    || fail "command installation did not use the existing Stow contract"
grep -Fx '<bin>' "$FUNK_TEST_NOIZEY_STOW_LOG" >/dev/null \
    || fail "command installation did not converge the bin package"
(
    cd /
    "$root/bin/.local/bin/noizey" --preset 'Deep sleep'
) >"$scratch/launch.out"
grep -Fx '<Deep sleep>' "$scratch/launch.out" >/dev/null \
    || fail "launcher did not preserve spaced arguments outside the checkout"
cp "$binary" "$scratch/previous"
run_install >"$scratch/repeat.out"
grep -F 'Noizey is current' "$scratch/repeat.out" >/dev/null \
    || fail "repeat install was not idempotent"
if FUNK_TEST_NOIZEY_GO_FAIL=1 run_install >"$scratch/fail.out" 2>&1; then
    fail "failed compiler was accepted"
fi
cmp -s "$binary" "$scratch/previous" || fail "failed build replaced the binary"
if FUNK_TEST_NOIZEY_EXEC_EXIT=12 run_install >"$scratch/probe.out" 2>&1; then
    fail "broken executable was installed"
fi
cmp -s "$binary" "$scratch/previous" || fail "failed startup probe replaced the binary"
if FUNK_TEST_NOIZEY_STOW_EXIT=1 run_install >"$scratch/stow.out" 2>&1; then
    fail "Stow collision was ignored"
fi
if FUNK_TEST_NOIZEY_DIRTY_BUILD=1 run_install >"$scratch/changed.out" 2>&1; then
    fail "concurrent source changes were installed"
fi
cmp -s "$binary" "$scratch/previous" || fail "source change replaced the binary"
if run_install >"$scratch/dirty.out" 2>&1; then fail "dirty source was installed"; fi
grep -F 'local modifications' "$scratch/dirty.out" >/dev/null \
    || fail "dirty-source failure did not explain the problem"

make_fixture "$scratch/clean"
export FUNK_NOIZEY_ROOT="$scratch/clean"
mkdir "$scratch/foreign"
printf 'unrelated\n' >"$scratch/foreign/noizey"
if FUNK_NOIZEY_DIR="$scratch/foreign" run_install >"$scratch/foreign.out" 2>&1; then
    fail "foreign installation directory was claimed"
fi
[ "$(cat "$scratch/foreign/noizey")" = unrelated ] || fail "foreign file changed"
ln -s "$scratch/foreign" "$scratch/linked"
if FUNK_NOIZEY_DIR="$scratch/linked" run_install >"$scratch/linked.out" 2>&1; then
    fail "symlinked installation directory was accepted"
fi
if FUNK_NOIZEY_ROOT="$scratch/missing" run_install >"$scratch/missing.out" 2>&1; then
    fail "missing checkout was ignored"
fi
printf 'noizey test: ok\n'
