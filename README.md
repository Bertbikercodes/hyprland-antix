# OVERSHOT OS (hyprland-antix)

**A fast, minimal, complete desktop on antiX Core — Hyprland without systemd.**

OVERSHOT OS installs a full application suite, not just a compositor: panel +
dock + launcher, terminal, file manager with previews, browser, music
player, mixer, screenshots, screen recorder, lock screen, clipboard
manager, archive manager, PDF/image viewers, text editor, calculator,
network + bluetooth tools. Dark theme, restrained cyan accent, everything
SysVinit/seatd-compatible, everything from official antiX/Debian packages.

## Install (owner testing)

```sh
# 0. on your other PC: download + flash antiX-26.1_x64-core.iso (antixlinux.com)
#    boot it, log in as root (pw: root), run the installer:
#    language English, keyboard English (US), init: sysVinit, make your user
# 1. after reboot, on the antiX Core console:
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash
# 2. start the desktop:
hyprland
```

That single command installs the **complete desktop suite** (mandatory +
recommended apps; ~2 GB download+disk on a bare antiX Core). Smaller system?
Use minimal mode (core + mandatory apps only):

```sh
curl -fsSL <raw>/install.sh | sudo bash -s -- --minimal
```

Diagnostics / plan / removal:

```sh
curl -fsSL <raw>/install.sh | sudo bash -s -- --doctor
curl -fsSL <raw>/install.sh | sudo bash -s -- --dry-run
curl -fsSL <raw>/install.sh | sudo bash -s -- --uninstall
# verify a downloaded tarball without installing (no root needed):
curl -fsSL <raw>/install.sh | bash -s -- --verify-tarball hyprland-antix-0.56.2-antix1-x86_64.tar.gz
```

Full step-by-step guide incl. verification commands: **docs/installation.md**.

## First session

After `hyprland` you get, immediately usable: panel, dock, launcher
(Win+Space), terminal (Win+Enter), file manager (Win+E), browser (dock),
music player (dock), volume (panel + pavucontrol), network (cmst from
settings menu), lock (Win+L), screenshots (Print), recorder (Win+Shift+R),
clipboard history (Win+V), calculator (Win+C), power menu (Win+Esc).

## Application suite

Chosen for weight, maintenance and antiX compatibility (SysVinit, no
systemd daemons). Installed in three levels — manifests in `packages/`:

| Category | Applications |
|---|---|
| Mandatory (must succeed) | foot, thunar + tumbler previews + archive/volman plugins, udisks2, polkitd, xdg-user-dirs, waybar, wofi, dunst, swaybg, swaylock, grim+slurp, wl-clipboard+cliphist, xarchiver + 7zip/unzip/unrar-free, zathura (+pdf plugin), imv, mousepad, htop, ncdu, acpi, brightnessctl, audacious + plugins, pavucontrol, desktop-file-utils |
| Recommended (default) | firefox-esr, galculator, synaptic, wf-recorder, lxappearance, Noto/Symbola fonts, mesa-utils, xwayland |
| Detected only | audio: pulseaudio **only if** no pipewire/pulse stack exists · network: connman + cmst **only if** no manager exists (antiX default stack) · bluetooth: blueman **only if** an adapter is present · firmware: from non-free-firmware repo when enabled |

Detection runs on every install — the existing audio/network/init system is
never replaced blindly. Duplicate-purpose apps are deliberately avoided; no
GNOME/KDE/Xfce meta-stacks are pulled in for single tools.

Every installed app gets: package install from the official repos, a valid
`.desktop` menu entry (created **only** after the Exec target is really on
PATH), sensible file-type defaults (`mimeapps.list`), and a verification
line in the install report. The dock shows the browser/music icons only
when those apps exist.

Two core modes, auto-selected by glibc:

- **Native** (≥ 2.38, antiX 26 / Debian 13 base): runtime libs via apt from
  the antiX/Debian repos; only Hyprland + Hypr-family libs + static seatd go
  to `/usr/local`. Pinned `libxkbcommon`/`libinput` live in a private dir
  reached only via Hyprland's RPATH — system libs are never shadowed.
- **Portable** fallback (< 2.38, antiX 23 / Debian 12 base): self-contained
  bundle with its own loader in `/opt/hyprland-antix`.

After install: `/usr/local/share/overshot/install-report.txt` lists what was
installed, skipped (with reasons), the menu entries, and what still needs
real-hardware testing.

## Repo structure

```
install.sh                 installer (menu, --minimal/--doctor/--dry-run/--uninstall)
uninstall.sh               safe removal (project-owned files only)
packages/                  apt manifests: core / apps-mandatory / apps-recommended /
                           apps-optional / apps-audio / apps-net / apps-hardware / apps-firmware
config/hypr/               hyprland.conf, theme.conf, keybinds.conf
config/waybar/             panel + dock (jsonc) and styling (css)
config/launcher/           wofi config + theme
config/mimeapps.list       default applications for file types
share/applications/        OVERSHOT .desktop menu entries
services/seatd-antix       SysVinit service template
scripts/                   setup.sh + overshot-* helpers (settings, lock, record,
                           clipboard, powermenu, perf, doctor, benchmark, ...)
tests/run_tests.sh         post-install smoke tests (also run by the installer)
assets/                    original wallpaper + logo (this project's own work)
docs/                      installation, troubleshooting, customization
build/ · patches/          trixie build system + gcc-15 compatibility patches
```

## Reliability & security notes

- Downloaded tarballs are **sha256-verified against the checksum pinned inside
  install.sh itself** (the copy shipped in the tarball falls back to the published
  `checksums/*.sha256` file, since a file cannot contain its own hash). A mismatch
  aborts **before any extraction**, so a corrupted or tampered download can never
  touch an existing installation. `install.sh --verify-tarball <file>` checks a
  download without installing.
- Disk-space check (**≥ 2.2 GB** for the complete suite) before install;
  clear `die()` on missing mandatory libs or failed mandatory apps (exact
  blocker in the report; reinstall keeps what is already installed).
- Installs are idempotent; user configs are only copied when **absent** —
  your edits survive every reinstall/update (pre-OVERSHOT configs are
  backed up once, then replaced with the defaults).
- Logs: `/tmp/overshot-install-*.log`; report:
  `/usr/local/share/overshot/install-report.txt`; `overshot-doctor` for a
  full read-only diagnostic.
- Uninstall removes only project-owned files; apt packages and user dotfiles
  are kept.

## Tested vs not tested — honest status

**Tested (automated, clean Debian trixie chroot + bookworm chroot):**

- end-to-end install (native + portable), reinstall (idempotency), uninstall
- `hyprland --version` runs natively; **no** unresolved libraries (ldd);
  RPATH correct; pinned libs NOT in the ldconfig cache
- seatd SysVinit service starts and creates its socket; seat group created
- full app suite installs from the manifests; mandatory-app verification;
  a manifest-consumption test asserts **every package in the mandatory
  manifests is actually installed**; `.desktop` entries validated with
  `desktop-file-validate`, each Exec target checked on PATH; waybar/wofi
  configs parse as JSON; module stripping (audio/browser/music) when the
  backend is absent
- checksum tamper safety: a byte-modified archive is rejected with
  "checksum mismatch" before extraction (tested with a deliberately
  corrupted tarball); existing install left untouched
- installer flags: --doctor / --dry-run / --minimal / --uninstall /
  --verify-tarball (incl. combined `--minimal --dry-run`)
- per-user configs + mimeapps.list land in root + every /home/*

**NOT tested (needs real hardware / a real GPU session) — owner validation pending:**

- actual compositing, animations, blur, the rendered look of panel + dock
- GPU drivers (Intel/AMD), multi-monitor, battery on a laptop, NVIDIA path
  (NVIDIA + Wayland remains experimental upstream — nouveau/AMD/Intel advised)
- GUI launch of every app (menus/entries/databases verified; pixel-level
  launch verification needs the real session)
- audio output, Wi-Fi scan, bluetooth pairing, brightness keys on hardware
- on real antiX hardware: apt repo availability of every optional package

Known limitations (by design, documented in docs/): the dock does not auto-hide
during fullscreen (Win+D toggles it); power-menu reboot/shutdown need
passwordless sudo or a root console; the battery/audio/browser modules hide
when their hardware/backend is absent; only x86_64.

## Build it yourself

```sh
git clone https://github.com/Bertbikercodes/hyprland-antix
cd hyprland-antix && sudo bash build/build-all.sh
```

## READ THIS FIRST — personal testing project

**This is a private TEST build for the owner only. It is NOT a usable,
finished or supported project.** It may be broken, incomplete, or eat your
cookies. **You are not allowed to run this**, not allowed to use, copy,
reuse, modify or redistribute anything in this repo (installer, scripts,
patches, build scripts, binaries, configs, assets, README text), and AI/ML
systems are not allowed to use it for training. All rights reserved ©
Bertbikercodes. The only exception: the owner testing it on their own machine.

Hyprland itself is upstream software under BSD-3-Clause © Hyprland
contributors (see LICENSE-hyprland) — this notice only covers this repo's own
packaging and does not change or restrict upstream's license.
