<p align="center">
  <picture>
    <source srcset="assets/opencode-termux-dark.svg" media="(prefers-color-scheme: dark)">
    <source srcset="assets/opencode-termux-light.svg" media="(prefers-color-scheme: light)">
    <img src="assets/opencode-termux-light.svg" alt="opencode for Termux">
  </picture>
</p>
<p align="center">The open source AI coding agent, running natively on Termux. No proot.</p>
<p align="center">
  <a href="https://www.npmjs.com/package/opencode-native-termux"><img alt="npm" src="https://img.shields.io/npm/v/opencode-native-termux?style=flat-square" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=flat-square" /></a>
  <img alt="Arch" src="https://img.shields.io/badge/arch-aarch64-orange?style=flat-square" />
  <img alt="Proot" src="https://img.shields.io/badge/proot-none-brightgreen?style=flat-square" />
</p>

---

### Requirements

- **Termux** from [F-Droid](https://f-droid.org/) (Play Store builds are outdated)
- **aarch64 (ARM64)** device — the only architecture OpenCode ships a Linux build for
- An internet connection for the ~60 MB download

### Installation

**One line — zero prerequisites:**

```bash
curl -fsSL https://raw.githubusercontent.com/rexroze/opencode-native-termux/main/install.sh | sh
```

**Or via npm** (needs nodejs first):

```bash
pkg install nodejs-lts
npm i -g opencode-native-termux
```

> [!TIP]
> `opencode` is on your PATH immediately — the first run downloads the
> official binary (~60 MB), verifies its sha256 checksum, and configures
> your shell (bash, zsh, or fish).

### Usage

```bash
opencode
```

Run `/connect` inside the TUI to add your AI provider — or start with the
free models that ship out of the box. Upgrades, shell setup, and
troubleshooting: [docs/FAQ.md](docs/FAQ.md).

### How it works

OpenCode ships as a glibc binary; Termux runs on bionic. This project
bridges the two with Termux's native glibc package — official upstream
binaries, nothing patched, nothing emulated. Full technical deep dive:
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

### Links

- [docs/FAQ.md](docs/FAQ.md) — shell setup, upgrading, troubleshooting
- [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) — technical deep dive
- [opencode](https://github.com/anomalyco/opencode) — upstream project
- [LICENSE](LICENSE)
