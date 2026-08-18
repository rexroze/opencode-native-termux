#!/bin/sh
#
# Smoke test for install.sh — run inside Termux.
#
#   sh scripts/test.sh                uses ~/bin/opencode.bin as the source binary
#   sh scripts/test.sh /path/to/bin   use a specific binary
#
# Verifies: wrapper generation + PATH wiring for bash, zsh, and fish,
# each in an isolated throwaway HOME. Skips gracefully outside Termux
# or when no opencode binary is available.
set -eu

cd "$(dirname "$0")/.."

[ -n "${PREFIX:-}" ] || { echo "SKIP: not running inside Termux"; exit 0; }

BIN="${1:-$HOME/bin/opencode.bin}"
[ -f "$BIN" ] || { echo "SKIP: no opencode binary at $BIN (install opencode first)"; exit 0; }

run_case() {  # $1 = shell name, $2 = SHELL value
  name="$1"
  home="$(mktemp -d)"
  bin="$home/bin"
  mkdir -p "$bin"
  cp "$BIN" "$bin/opencode.bin"

  HOME="$home" SHELL="$2" OPENCODE_TERMUX_SHELL="$name" \
    OPENCODE_TERMUX_INSTALL_DIR="$bin" \
    sh install.sh --no-download >/dev/null 2>&1 || {
      echo "FAIL($name): installer exited nonzero"; rm -rf "$home"; exit 1
    }

  "$bin/opencode" --version >/dev/null 2>&1 || {
    echo "FAIL($name): launcher broken"; rm -rf "$home"; exit 1
  }

  case "$name" in
    bash) grep -q "PATH=\"$bin" "$home/.bashrc" \
            || { echo "FAIL(bash): no PATH line in .bashrc"; rm -rf "$home"; exit 1; }
          [ -s "$PREFIX/etc/bash_completion.d/opencode" ] \
            || { echo "FAIL(bash): completions missing/empty"; rm -rf "$home"; exit 1; } ;;
    zsh)  grep -q "PATH=\"$bin" "$home/.zshrc" \
            || { echo "FAIL(zsh): no PATH line in .zshrc"; rm -rf "$home"; exit 1; }
          [ -s "$home/.zsh/completions/opencode.zsh" ] \
            || { echo "FAIL(zsh): completions missing/empty"; rm -rf "$home"; exit 1; }
          grep -q "bashcompinit" "$home/.zshrc" \
            || { echo "FAIL(zsh): no bashcompinit in .zshrc"; rm -rf "$home"; exit 1; } ;;
    fish) grep -q "$bin" "$home/.config/fish/config.fish" \
            || { echo "FAIL(fish): no PATH line in fish config"; rm -rf "$home"; exit 1; }
          grep -q "complete -c opencode" "$home/.config/fish/completions/opencode.fish" \
            || { echo "FAIL(fish): completions missing"; rm -rf "$home"; exit 1; }
          grep -q "COMP_WORDS" "$home/.config/fish/completions/opencode.fish" \
            && { echo "FAIL(fish): completions contain bash code (COMP_WORDS)"; rm -rf "$home"; exit 1; }
          command -v fish >/dev/null 2>&1 \
            && fish --no-config -c "source \"$home/.config/fish/completions/opencode.fish\"" >/dev/null 2>&1 \
            || { [ -z "$(command -v fish)" ] || { echo "FAIL(fish): completions fail to source"; rm -rf "$home"; exit 1; }; } ;;
  esac

  rm -rf "$home"
  echo "PASS: $name"
}

run_case bash /data/data/com.termux/files/usr/bin/bash
run_case zsh  /data/data/com.termux/files/usr/bin/zsh
run_case fish /data/data/com.termux/files/usr/bin/fish

echo "all shell cases passed"
