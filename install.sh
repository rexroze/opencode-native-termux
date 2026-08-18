#!/usr/bin/env sh
#
# opencode-termux — run OpenCode natively on Termux (Android).
# No proot. No containers. No VMs. Official opencode binaries.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rexroze/opencode-native-termux/main/install.sh | sh
#   sh install.sh [--version v1.2.3] [--no-download] [--uninstall] [--help]
#
# Env overrides:
#   OPENCODE_VERSION             e.g. v1.18.18 (default: latest release)
#   OPENCODE_TERMUX_INSTALL_DIR  install dir (default: $HOME/bin)
#   OPENCODE_TERMUX_SHELL        bash|zsh|fish (default: auto-detect from $SHELL)
#   OPENCODE_TERMUX_NO_PATH      1 = skip PATH/completion setup entirely
#
set -eu

OPENCODE_REPO="anomalyco/opencode"
VERSION="${OPENCODE_VERSION:-latest}"
INSTALL_DIR="${OPENCODE_TERMUX_INSTALL_DIR:-$HOME/bin}"
NO_DOWNLOAD=0
DO_UNINSTALL=0

ARCH="$(uname -m 2>/dev/null || echo unknown)"
TERMUX_PREFIX="${PREFIX:-}"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;32m[opencode-termux]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[opencode-termux]\033[0m warning: %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[opencode-termux]\033[0m error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
opencode-termux installer

Usage:
  sh install.sh                install or upgrade opencode (latest release)
  sh install.sh -v v1.18.18    install a specific version
  sh install.sh --no-download  only (re)create the launcher wrapper, keep the
                               existing binary in place (repair mode)
  sh install.sh --uninstall    remove the wrapper and binary

Env:
  OPENCODE_VERSION              version to install (default: latest)
  OPENCODE_TERMUX_INSTALL_DIR   install directory (default: $HOME/bin)
  OPENCODE_TERMUX_SHELL         bash|zsh|fish (default: auto-detect from $SHELL)
  OPENCODE_TERMUX_NO_PATH       1 = don't touch PATH/completion config

Downloads are verified against the sha256 digest GitHub publishes for the
release asset.
Shell setup: a PATH line and tab-completions are added for your login shell
(bash: ~/.bashrc, zsh: ~/.zshrc, fish: ~/.config/fish/config.fish).
Note: opencode's `completion` command only emits bash scripts; fish gets a
static completion set instead (see completions_fish).
EOF
  exit 0
}

check_termux() {
  [ -n "$TERMUX_PREFIX" ] && [ -d "$TERMUX_PREFIX" ] \
    || die "Termux not detected. This installer only runs on Termux (Android)."
  command -v pkg >/dev/null 2>&1 \
    || die "Termux package manager (pkg) not found in PATH."
}

check_arch() {
  case "$ARCH" in
    aarch64|arm64) BIN_NAME="opencode-linux-arm64.tar.gz" ;;
    *)
      die "unsupported architecture: $ARCH. Only aarch64 (ARM64) is supported; \
opencode ships no other Android-compatible build."
      ;;
  esac
}

# glibc (the actual library, from the Termux glibc repo) is the only
# dependency. The official opencode binary is glibc-linked; Termux's own
# bionic libc can't run it.
ensure_glibc() {
  if [ ! -f "$TERMUX_PREFIX/glibc/lib/libc.so.6" ]; then
    info "installing glibc from the Termux glibc repository..."
    pkg install -y glibc-repo >/dev/null 2>&1 || pkg install -y glibc-repo
    pkg update >/dev/null 2>&1 || true
    pkg install -y glibc || die "failed to install glibc (run 'pkg install -y glibc' manually)"
  fi
  [ -f "$TERMUX_PREFIX/glibc/lib/libc.so.6" ] \
    || die "glibc is installed but libc.so.6 is missing in $TERMUX_PREFIX/glibc/lib"
}

resolve_release() {
  local url meta
  if [ "$VERSION" = "latest" ]; then
    url="https://api.github.com/repos/$OPENCODE_REPO/releases/latest"
  else
    url="https://api.github.com/repos/$OPENCODE_REPO/releases/tags/$VERSION"
  fi
  meta="$(curl -fsSL "$url")" || die "could not fetch release metadata ($url)"
  if [ "$VERSION" = "latest" ]; then
    VERSION="$(printf '%s' "$meta" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\(.*\)"/\1/')"
    [ -n "$VERSION" ] || die "could not resolve version from $url"
  fi
  # GitHub publishes a sha256 digest per release asset — grab ours.
  DIGEST="$(printf '%s' "$meta" | awk -v n="$BIN_NAME" '
    /"name":/ { gsub(/[",]/, ""); f=($2==n) }
    f && /"digest":/ { gsub(/[",]/, ""); print $2; exit }')"
  info "opencode version: $VERSION"
}

download_binary() {
  local tmp url
  tmp="$(mktemp -d "${TMPDIR:-$TERMUX_PREFIX/tmp}/opencode-termux.XXXXXX")"
  trap '[ -n "${tmp:-}" ] && rm -rf "$tmp"' EXIT INT TERM
  url="https://github.com/$OPENCODE_REPO/releases/download/$VERSION/$BIN_NAME"
  info "downloading $url ..."
  curl -fsSL -o "$tmp/$BIN_NAME" "$url" || die "download failed: $url"
  verify_checksum "$tmp/$BIN_NAME"
  tar -xzf "$tmp/$BIN_NAME" -C "$tmp" || die "extract failed (corrupt download?)"
  [ -f "$tmp/opencode" ] || die "archive did not contain the opencode binary"
  mv "$tmp/opencode" "$INSTALL_DIR/opencode.bin"
  chmod 755 "$INSTALL_DIR/opencode.bin"
  rm -f "$tmp/$BIN_NAME"
}

# Verify the tarball against the sha256 digest GitHub publishes for the
# release asset (fetched by resolve_release).
verify_checksum() {  # $1 = tarball path
  [ -n "${DIGEST:-}" ] || { warn "no sha256 digest published for this release; skipping checksum check"; return 0; }
  local hex
  hex="${DIGEST#sha256:}"
  case "$hex" in
    ""|*[!0-9a-fA-F]*) warn "unexpected digest format ($DIGEST); skipping checksum check"; return 0 ;;
  esac
  printf '%s  %s\n' "$hex" "$1" | sha256sum -c - >/dev/null 2>&1 \
    || die "sha256 checksum mismatch — download corrupt or tampered; retry"
  info "sha256 checksum verified"
}

# The launcher. The official binary is glibc-linked and expects /lib;
# Termux has no /lib, so we invoke it through the glibc loader directly,
# pointing at Termux's glibc tree. We must also unset LD_PRELOAD: Termux
# preloads libtermux-exec (a bionic library) which crashes the glibc loader.
write_wrapper() {
  local wrapper="$INSTALL_DIR/opencode"
  cat > "$wrapper" <<EOF
#!/bin/sh
exec env -u LD_PRELOAD "$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1" \\
  --library-path "$TERMUX_PREFIX/glibc/lib" \\
  "$INSTALL_DIR/opencode.bin" "\$@"
EOF
  chmod 755 "$wrapper"
}

detect_shell() {
  SHELL_NAME="${OPENCODE_TERMUX_SHELL:-}"
  if [ -z "$SHELL_NAME" ]; then
    case "${SHELL:-}" in
      */fish) SHELL_NAME=fish ;;
      */zsh)  SHELL_NAME=zsh ;;
      */bash) SHELL_NAME=bash ;;
      *)
        warn "could not detect a supported shell (SHELL=${SHELL:-unset})."
        warn "re-run with OPENCODE_TERMUX_SHELL=bash|zsh|fish, or add $INSTALL_DIR to PATH manually."
        ;;
    esac
  fi
}

add_path_line() {  # $1 = rc file, $2 = display name
  local rc="$1"
  mkdir -p "$(dirname "$rc")"
  [ -f "$rc" ] || touch "$rc"
  if ! grep -qF "PATH=\"$INSTALL_DIR:" "$rc"; then
    printf '\n# opencode-native-termux\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$rc"
    info "added $INSTALL_DIR to PATH in $2 ($rc)"
  fi
}

add_path_fish() {
  local rc="$HOME/.config/fish/config.fish"
  mkdir -p "$(dirname "$rc")"
  [ -f "$rc" ] || touch "$rc"
  if ! grep -qF "$INSTALL_DIR" "$rc"; then
    printf '\n# opencode-native-termux\nfish_add_path %s\n' "$INSTALL_DIR" >> "$rc"
    info "added $INSTALL_DIR to fish PATH ($rc)"
  fi
}

completions_file() {  # $1 = output path for the bash-style yargs script
  local out="$1"
  mkdir -p "$(dirname "$out")"
  if "$INSTALL_DIR/opencode" completion bash > "$out" 2>/dev/null && [ -s "$out" ]; then
    info "installed bash completions ($out)"
  else
    rm -f "$out"
    warn "could not generate bash completions (opencode completion failed)"
  fi
}

# opencode's `completion` command only emits a bash script (yargs). zsh can
# run it via bashcompinit; fish cannot, so fish gets a static set.
completions_zsh() {
  local f rc
  f="$HOME/.zsh/completions/opencode.zsh"
  rc="$HOME/.zshrc"
  mkdir -p "$(dirname "$f")"
  if "$INSTALL_DIR/opencode" completion bash > "$f" 2>/dev/null && [ -s "$f" ]; then
    info "installed zsh completions ($f)"
  else
    rm -f "$f"
    warn "could not generate zsh completions (opencode completion failed)"
  fi
  if [ -f "$f" ] && [ -f "$rc" ] && ! grep -qF "bashcompinit" "$rc"; then
    printf '\n# opencode-native-termux (zsh completions)\nautoload -Uz bashcompinit && bashcompinit\nsource %s\n' "$f" >> "$rc"
    info "enabled zsh completions in ~/.zshrc (bashcompinit)"
  fi
}

completions_fish() {
  local f="$HOME/.config/fish/completions/opencode.fish"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<'FISH_EOF'
# opencode completions for fish
# (opencode's `completion` command only emits bash scripts, so this is a
# static set covering opencode's subcommands and flags.)

set -l oc_commands acp attach completion db debug export github import mcp models plugin pr providers run serve session stats upgrade web

complete -c opencode -f
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a acp        -d "start ACP (Agent Client Protocol) server"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a attach     -d "attach to a running opencode server"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a completion -d "generate shell completion script"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a db         -d "database tools"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a debug      -d "debugging and troubleshooting tools"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a export     -d "export session data as JSON"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a github     -d "manage GitHub agent"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a import     -d "import session data from JSON file or URL"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a mcp        -d "manage MCP (Model Context Protocol) servers"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a models     -d "list all available models"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a plugin     -d "install plugin and update config"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a pr         -d "fetch and checkout a GitHub PR branch, then run opencode"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a providers  -d "manage AI providers and credentials"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a run        -d "run opencode with a message"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a serve      -d "starts a headless opencode server"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a session    -d "manage sessions"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a stats      -d "show token usage and cost statistics"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a upgrade    -d "upgrade opencode to the latest or a specific version"
complete -c opencode -n "not __fish_seen_subcommand_from $oc_commands" -a web        -d "start opencode server and open web interface"

complete -c opencode -s h -l help        -d "show help"
complete -c opencode -s v -l version     -d "show version number"
complete -c opencode -l print-logs       -d "print logs to stderr"
complete -c opencode -l log-level        -d "log level" -a "DEBUG INFO WARN ERROR"
complete -c opencode -l pure             -d "run without external plugins"
complete -c opencode -l port             -d "port to listen on"
complete -c opencode -l hostname         -d "hostname to listen on"
complete -c opencode -l mdns             -d "enable mDNS service discovery"
complete -c opencode -l mdns-domain      -d "custom domain name for mDNS service"
complete -c opencode -l cors             -d "additional domains to allow for CORS"
complete -c opencode -s m -l model       -d "model to use (provider/model)"
complete -c opencode -s c -l continue    -d "continue the last session"
complete -c opencode -s s -l session     -d "session id to continue"
complete -c opencode -l fork             -d "fork the session when continuing"
complete -c opencode -l prompt           -d "prompt to use"
complete -c opencode -l agent            -d "agent to use"
complete -c opencode -l auto             -d "auto-approve permissions not explicitly denied (dangerous!)"
complete -c opencode -l mini             -d "start the minimal interactive interface"
complete -c opencode -l no-replay        -d "disable mini session history replay"
complete -c opencode -l replay-limit     -d "cap visible mini replay to the newest N messages"
FISH_EOF
  info "installed fish completions ($f)"
}

setup_shell() {
  [ "${OPENCODE_TERMUX_NO_PATH:-0}" = "1" ] && return 0
  detect_shell
  case "$SHELL_NAME" in
    bash) add_path_line "$HOME/.bashrc" "~/.bashrc";
          completions_file "$TERMUX_PREFIX/etc/bash_completion.d/opencode" ;;
    zsh)  add_path_line "$HOME/.zshrc" "~/.zshrc";
          completions_zsh ;;
    fish) add_path_fish;
          completions_fish ;;
  esac
}

do_uninstall() {
  rm -f "$INSTALL_DIR/opencode" "$INSTALL_DIR/opencode.bin" \
        "$TERMUX_PREFIX/etc/bash_completion.d/opencode" \
        "$HOME/.config/fish/completions/opencode.fish" \
        "$HOME/.zsh/completions/opencode.zsh"
  info "removed opencode binary, launcher, and generated completion files"
  info "PATH/completion lines left in shell configs (remove manually if desired);"
  info "glibc package left in place (shared by other glibc programs); remove with: pkg uninstall glibc"
  exit 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)        usage ;;
      --uninstall)      DO_UNINSTALL=1 ;;
      --no-download)    NO_DOWNLOAD=1 ;;
      -v|--version)     shift; [ "$#" -gt 0 ] || die "--version requires an argument, e.g. -v v1.18.18"; VERSION="$1" ;;
      -v=*|--version=*) VERSION="${1#*=}" ;;
      -v*)              VERSION="${1#-v}" ;;
      *)                die "unknown argument: $1 (see --help)" ;;
    esac
    shift
  done
}

parse_args "$@"
check_termux
check_arch
[ "$DO_UNINSTALL" = "1" ] && do_uninstall

mkdir -p "$INSTALL_DIR"

if [ "$NO_DOWNLOAD" = "1" ]; then
  [ -f "$INSTALL_DIR/opencode.bin" ] || die "--no-download but no binary found in $INSTALL_DIR"
else
  ensure_glibc
  resolve_release
  download_binary
fi

write_wrapper
setup_shell

info "installed:"
info "  binary   $INSTALL_DIR/opencode.bin ($(du -h "$INSTALL_DIR/opencode.bin" 2>/dev/null | cut -f1))"
info "  launcher $INSTALL_DIR/opencode"
case "${SHELL_NAME:-}" in
  bash) info "shell refresh:  source ~/.bashrc   (or just open a new Termux session)" ;;
  zsh)  info "shell refresh:  source ~/.zshrc   (or just open a new Termux session)" ;;
  fish) info "shell refresh:  exec fish   (or just open a new Termux session)" ;;
  *)    info "shell refresh:  open a new Termux session" ;;
esac
info "then run 'opencode' and use /connect inside the TUI to add your AI provider."
"$INSTALL_DIR/opencode" --version || warn "launcher works but --version check failed"
