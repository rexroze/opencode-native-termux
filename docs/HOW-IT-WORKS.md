# How it works

OpenCode is compiled with [Bun](https://bun.sh/) into a standalone binary.
The release assets are:

| Asset | Libc | Problem on Termux |
|---|---|---|
| `opencode-linux-arm64.tar.gz` | glibc | Needs `/lib/ld-linux-aarch64.so.1` — Android has no `/lib`, and Termux's own libc is bionic |
| `opencode-linux-arm64-musl.tar.gz` | musl | Needs `/lib/ld-musl-aarch64.so.1` + musl libc — no musl package exists in Termux repos |

Termux *does* ship a real glibc (2.44) via the `glibc` package — loader and
all — under `$PREFIX/glibc/`. So the launcher just invokes the official
binary through that loader:

```sh
#!/bin/sh
exec env -u LD_PRELOAD "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" \
  --library-path "$PREFIX/glibc/lib" \
  "$INSTALL_DIR/opencode.bin" "$@"
```

## The two traps we hit (and solved)

1. **`LD_PRELOAD` must be unset.** Termux preloads `libtermux-exec` (a
   *bionic* library) into every process. Feed it to the glibc loader and you
   get `error while loading shared libraries: .../libc.so: invalid ELF
   header` (the preload's own `libc.so` dependency resolves to glibc's
   linker script).

2. **Never patch the binary.** `glibc-runner --configure` (the official
   Termux tool) rewrites the ELF interpreter with patchelf. On this 183 MB
   bun-compiled binary that produces an instant **segfault** — the loader
   dies processing the program header before the main binary is even
   mapped. Invoking the loader explicitly avoids any file modification.

No `proot`, no `glibc-runner`, no compiler, no patching — the binary on
disk is byte-identical to what upstream publishes, and downloads are
verified against the sha256 digest GitHub publishes for each release asset.

## What gets installed

| Path | What it is |
|---|---|
| `~/bin/opencode.bin` | The official `opencode-linux-arm64` release binary (unmodified) |
| `~/bin/opencode` | 3-line POSIX sh launcher bridging bionic → glibc |
| PATH setup | Added to your login shell's config — auto-detected: bash → `~/.bashrc`, zsh → `~/.zshrc`, fish → `fish_add_path` |
| Tab-completions | For your login shell: bash → `$PREFIX/etc/bash_completion.d/opencode` (yargs-generated), zsh → `~/.zsh/completions/opencode.zsh` via `bashcompinit`, fish → static set at `~/.config/fish/completions/opencode.fish` |
| `glibc` package | Termux's native glibc 2.44 + dynamic loader (shared with other glibc apps) |

## Requirements

- **Termux** from [F-Droid](https://f-droid.org/) (Play Store builds are outdated)
- **aarch64 (ARM64)** device — the only architecture OpenCode ships a Linux build for
- An internet connection for the ~60 MB download

## Verification

Verified working on Android 14 / aarch64 / Termux (F-Droid): CLI, TUI,
`opencode run`, and free models all confirmed against `v1.18.18`.

- `sh scripts/test.sh` — smoke-tests installer + launcher + shell wiring
  (bash/zsh/fish) in isolated HOMEs
- Installer self-checks: sha256 digest verification, `--version` sanity
  check after install, `--no-download` repair mode, `--uninstall`
