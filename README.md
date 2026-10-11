# OVERSHOT OS (hyprland-antix)

**A fast, minimal, polished desktop on antiX Core — Hyprland without systemd.**

OVERSHOT OS is the desktop layer of this repo: Hyprland 0.56.2 + a thin top
panel (waybar) + a compact floating dock + wofi launcher + swaybg
wallpaper + dunst notifications, all SysVinit/seatd-compatible, all native
antiX packages where possible. Dark theme, restrained cyan accent.

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

Diagnostic / dry-run / removal:

```sh
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash -s -- --doctor
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash -s -- --dry-run
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash -s -- --uninstall
```

Full step-by-step guide incl. verification commands: **docs/installation.md**.

## What you get

| Component | Version | Notes |
|---|---|---|
| Hyprland | 0.56.2 | `-DNO_SYSTEMD=ON -DNO_RTKIT=ON -DNO_UWSM=ON`, gcc-15 build |
| aquamarine | 0.15.1 | libseat mode → works with seatd |
| seatd | 1.0.0 | static binary, SysVinit service `seatd-antix` |
| waybar panel | Debian pkg | top, 30px, translucent dark, cyan accent, clock w/ calendar, net/volume/battery/cpu/ram/tray, power menu |
| dock | waybar 2nd instance | bottom, floating, centered, launcher+files+terminal+browser+running-windows, Win+D toggle |
| wofi | Debian pkg | dark app launcher (Win+Space) |
| swaybg/dunst/foot/thunar | Debian pkgs | wallpaper, notifications, terminal, file manager |
| screenshot | grim+slurp+wl-clipboard | Print key → selection → clipboard |

Two install modes, auto-selected by glibc:

- **Native** (≥ 2.38, antiX 26 / Debian 13 base): ~95 runtime libs via apt from
  the antiX/Debian repos; only Hyprland + Hypr-family libs + static seatd go
  to `/usr/local`. Pinned `libxkbcommon` 1.11 / `libinput` 1.29 live in a
  private dir reached only via Hyprland's RPATH — the system's own libs are
  never shadowed.
- **Portable** fallback (< 2.38, antiX 23 / Debian 12 base): self-contained
  bundle with its own loader in `/opt/hyprland-antix`.

Requirements, layout, key bindings, benchmarking: **docs/**.

## Repo structure

```
install.sh                 installer entry (menu 1–5, --doctor/--dry-run/--uninstall)
uninstall.sh               safe removal (project-owned files only)
packages/                  apt manifests: core / apps / extras / optional
config/hypr/               hyprland.conf, theme.conf, keybinds.conf
config/waybar/             panel + dock (jsonc) and styling (css)
config/launcher/           wofi config + theme
services/seatd-antix       SysVinit service template
scripts/                   setup.sh + overshot-* helpers (powermenu, perf, doctor, ...)
tests/run_tests.sh         post-install smoke tests (also run by the installer)
assets/                    original wallpaper + logo (this project's own work)
docs/                      installation, troubleshooting, customization
build/ · patches/          trixie build system + gcc-15 compatibility patches
```

## Reliability & security notes

- Downloaded tarballs are **sha256-verified** (checksum served from this repo);
  a mismatch aborts the install. Local-file installs skip the download path.
- Disk-space check (≥ 700 MB) before install; clear `die()` on missing
  mandatory libs (ldd check after apt install).
- Installs are idempotent; user configs are only copied when **absent** —
  your edits survive every reinstall/update.
- Logs: `/tmp/overshot-install-*.log`. Post-install smoke tests run
  automatically (`tests/run_tests.sh`), and `overshot-doctor` gives a full
  read-only diagnostic.
- Uninstall removes only project-owned files; apt packages and user dotfiles
  are kept.

## Tested vs not tested — honest status

**Tested (automated, clean Debian trixie chroot + bookworm chroot):**

- end-to-end install (native + portable), reinstall (idempotency), uninstall
- `hyprland --version` runs natively; hyprctl loads; **no** unresolved
  libraries (ldd); RPATH correct; pinned libs NOT in the ldconfig cache
- seatd SysVinit service starts and creates its socket; seat group created
- waybar/wofi/dock configs parse as valid JSON; module stripping works when
  pactl / a browser is absent; swaybg wallpaper autostart + wallpaper asset in place
- per-user configs land in root + every /home/*; user-overrides.conf pattern
- installer flags: --doctor / --dry-run / --uninstall; smoke tests pass

**NOT tested (needs real hardware / a real GPU session) — owner validation pending:**

- actual compositing, animations, blur, the rendered look of panel + dock
- GPU drivers (Intel/AMD), multi-monitor, battery on a laptop, NVIDIA path
  (NVIDIA + Wayland remains experimental upstream — nouveau/AMD/Intel advised)
- login-to-desktop latency (use `overshot-benchmark` on the real machine)
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
