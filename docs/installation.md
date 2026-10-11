# OVERSHOT OS — installation

A dark, minimal desktop (Hyprland + waybar panel + compact dock) on antiX Core,
without systemd. Private test build — see the README notice.

## Supported systems

| Base | Status |
|---|---|
| antiX 26.x (Debian 13 trixie, glibc ≥ 2.38) | **native mode** — tested in a clean trixie chroot |
| antiX 23.x (Debian 12 bookworm, glibc 2.36) | portable fallback mode — tested in a clean bookworm chroot |
| Real antiX hardware (GPU, input, seat) | **NOT yet tested — owner validation pending** |

## Full command list (fresh antiX Core → running desktop)

```sh
# 0. on your other PC: download + flash antiX-26.1_x64-core.iso
#    https://antixlinux.com/download/   (Rufus on Windows, or dd)

# 1. boot USB, log in as root (password: root), run the installer
#    choose: English / keyboard English (US) / sysVinit / your own user

# 2. after reboot, on the antiX Core console: check internet
ping -c 3 deb.debian.org

# 3. install (one command)
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash

# 4. start the desktop
hyprland
```

Verify:

```sh
hyprland --version        # -> Hyprland 0.56.2
ls /run/seatd.sock        # -> socket exists
groups                    # -> video, input, seat listed
overshot-doctor           # full diagnostic report
```

## Installer flags

```sh
curl -fsSL <install.sh URL> | sudo bash -s -- --doctor      # diagnostics only, no changes
curl -fsSL <install.sh URL> | sudo bash -s -- --dry-run     # show the plan, change nothing
curl -fsSL <install.sh URL> | sudo bash -s -- --uninstall   # remove everything project-owned
```

Offline install: download the release tarball + install.sh first, then:

```sh
sudo HYPRLAND_ANTIX_TARBALL=./hyprland-antix-0.56.2-antix1-x86_64.tar.gz bash install.sh
```
(local tarballs skip the download; the sha256 check applies to downloaded ones).

Every install writes a log to `/tmp/overshot-install-*.log`.

## What gets installed where

- apt packages (~95, from the antiX/Debian repos): mesa, wayland, cairo, pango,
  fonts, drivers — see `packages/core.txt`, `apps.txt`, `extras.txt`.
- `/usr/local/bin`: Hyprland, hyprctl, hyprpm, seatd, `overshot-*` helpers.
- `/usr/local/lib`: the 6 Hypr-family libs.
- `/usr/local/lib/hyprland-antix`: pinned libxkbcommon/libinput, **only** visible
  to Hyprland (RPATH), never in the ldconfig cache.
- `/usr/local/share/overshot`: default configs, wallpaper, helper scripts.
- `~/.config/{hypr,waybar,wofi}`: user configs — copied only when absent, so
  updates never destroy your edits.
- `/etc/init.d/seatd-antix`: seat management service (starts at boot).

## Key bindings

$mainMod = the Windows key. Full list in `~/.config/hypr/keybinds.conf`.

| Keys | Action |
|---|---|
| Win + Enter | terminal (foot) |
| Win + Space | app launcher (wofi) |
| Win + Q | close window |
| Win + F | fullscreen |
| Win + Shift + Space | toggle floating |
| Win + 1..5 | workspace |
| Win + D | toggle dock |
| Win + Shift + P | performance mode |
| Win + L | lock (needs optional swaylock) |
| Win + Escape | power menu |
| Print | screenshot selection → clipboard |
| Win + M | quit to console |
