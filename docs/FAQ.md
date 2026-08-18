# FAQ

## Shell setup

The installer detects your login shell (`$SHELL`) and wires PATH +
tab-completions automatically. Doing it by hand is two lines:

**bash** (Termux default) — add to `~/.bashrc`:

```bash
export PATH="$HOME/bin:$PATH"
# completions:
opencode completion bash > /data/data/com.termux/files/usr/etc/bash_completion.d/opencode
```

**zsh** — add to `~/.zshrc`:

```zsh
export PATH="$HOME/bin:$PATH"
fpath=(~/.zsh/completions $fpath) && autoload -Uz compinit && compinit
# completions:
opencode completion zsh > ~/.zsh/completions/_opencode
```

**fish** — add to `~/.config/fish/config.fish`:

```fish
fish_add_path ~/bin
# completions:
opencode completion fish > ~/.config/fish/completions/opencode.fish
```

Detection missed your shell? Re-run with `OPENCODE_TERMUX_SHELL=bash|zsh|fish`,
or skip it entirely with `OPENCODE_TERMUX_NO_PATH=1`.

## Upgrading

Re-run the installer; it always fetches the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/rexroze/opencode-native-termux/main/install.sh | sh
# or pin a version
sh install.sh --version v1.18.18
# npm users: the opencode-termux command re-runs the installer
opencode-termux
```

## Uninstalling

```bash
sh install.sh --uninstall
# optionally also: pkg uninstall glibc
```

## Which shells are supported?

bash (Termux default), zsh, and fish. The installer auto-detects `$SHELL`
and configures PATH + tab-completions for it (see above); override with
`OPENCODE_TERMUX_SHELL`.

## Why not just use proot-distro?

Proot adds a syscall translation layer and a full distro filesystem. This
runs the binary directly on the Android kernel — the same way Termux runs
Node, git, or anything else. No overhead, no extra filesystem.

## Why not run it from source with Bun?

Termux has no `bun` package, and Bun's official binaries have the same libc
problem. Using OpenCode's own compiled release is simpler and always
matches upstream.

## Does the TUI work?

Yes — alternate screen, mouse, keybindings, the works. It runs fine inside
tmux sessions too.

## Does `opencode upgrade` work?

The self-updater replaces its own binary, so use this installer to upgrade
instead (see above).

## Is x86_64 supported?

OpenCode ships `opencode-linux-x64.tar.gz` and Termux's glibc repo covers
x86_64, so it *should* work — but it's untested. Patches welcome.

## Does this need root?

No.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `sh: .../opencode: not found` on first run | Not on PATH — open a new shell or run `fish_add_path ~/bin` (bash: add the export from Shell setup) |
| `invalid ELF header` | An `LD_PRELOAD` got through — run `env -u LD_PRELOAD ~/bin/opencode`; if it works, your launcher is stale (re-run installer) |
| Segfault at startup | The binary was patched (e.g. `glibc-runner --configure`) — restore it: re-run installer |
| `cannot execute: required file not found` | The binary is the *musl* variant — re-run installer (it downloads the glibc build) |

## Credits

The `glibc` / `glibc-repo` packages used by this installer come from the
[Termux glibc project](https://github.com/termux-pacman/glibc-packages).
