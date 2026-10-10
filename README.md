# hyprland-antix

**Hyprland for antiX — including antiX Core — without systemd.**

antiX is a systemd-free distro (SysVinit/runit), and antiX Core has no X or
Wayland at all. This repo ships a self-contained, ready-to-run Hyprland
build that works on antiX 23 (Debian 12 bookworm base, glibc 2.36) and any
Debian 12/13 derivative, with **no systemd, no elogind** — seat management
is provided by [seatd](https://git.sr.ht/~kennylevinsen/seatd).

## Install command (owner testing)

From a root shell (or with sudo) on antiX with internet:

```sh
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash
```

That is the whole install. Then switch to a **text console** (Ctrl+Alt+F2 —
not inside X) and run:

```sh
hyprland
```

## What you get

| Component | Version | Notes |
|---|---|---|
| Hyprland | 0.56.2 | built with `-DNO_SYSTEMD=ON -DNO_RTKIT=ON -DNO_UWSM=ON` |
| hyprctl | 0.56.2 | included with Hyprland |
| aquamarine | 0.15.1 | Hyprland's backend, libseat mode → works with seatd |
| hyprwire | 0.3.1 | + gcc-14 compatibility patch |
| seatd | 1.0.0 | static binary, installed as a SysVinit service |
| glaze, mesa, wayland, ... | — | bundled runtime libs (see "Portable bundle" below) |

Everything lands in `/opt/hyprland-antix`, a wrapper in `/usr/local/bin/hyprland`,
and an init script in `/etc/init.d/seatd-antix`.

## Requirements on the antiX side

- antiX 23.x 64-bit (works on Core: that is what it was built for)
- a GPU with kernel KMS (intel/amd/nouveau — the kernel driver loads
  independently of userspace; `mesa-utils` optional)
- host packages the installer pulls from antiX repos: `xkb-data`, `xwayland`
  (optional but recommended), `curl`, `ca-certificates`
- your user in the `video`, `input` and `seat` groups (installer does this if
  run with sudo; otherwise `sudo adduser $USER video input seat`)

antiX Core tip: you do **not** need to install X or a display manager. You
need a Wayland *client* or two, e.g. `foot` (terminal) and `waybar` —
`sudo apt install foot waybar`. X apps run through the bundled Xwayland.

## Portable bundle — how this can run on bookworm

Hyprland 0.56 needs a gcc-15-era toolchain and current libstdc++ (C++23/26
features), which bookworm does not ship. So instead of fighting bookworm's
compiler, this project:

1. builds everything inside a Debian 13 (trixie) buildroot with gcc-15,
2. patches the small number of spots where Hyprland assumed systemd,
3. ships the result together with trixie's `ld.so`, glibc, libstdc++, mesa
   and the other runtime libs,
4. launches through the bundled loader:
   `ld-linux-x86-64.so.2 --library-path /opt/hyprland-antix/lib Hyprland`

Kernel-facing interfaces (drm, evdev, udev via antiX's **eudev**, seatd
socket) are stable ABIs, so userspace from a newer Debian runs fine on an
older one.

## systemd assumptions that were removed

| Spot | Upstream assumption | Fix here |
|---|---|---|
| aquamarine backend | libseat → systemd-logind | libseat → **seatd** (SysVinit service) |
| Hyprland CMake | `-DNO_SYSTEMD=ON` honoured | verified + used |
| rtkit/portal startup | rtkit daemon (systemd) | `-DNO_RTKIT=ON`, no portal in v1 |
| uwsm session wrapper | systemd user session | `-DNO_UWSM=ON` |
| libudev | systemd's udev | antiX's **eudev** libudev (ABI-compatible soname, kept system-side) |

Plus two compiler-compatibility patches (gcc-14 → also kept for gcc-15
builds; they are harmless there): `hyprwire` `append_range` → `insert`, and
XWM.hpp ternary type fix. See `patches/`.

## Build it yourself

The whole build is scripted and reproducible:

```sh
git clone https://github.com/Bertbikercodes/hyprland-antix
cd hyprland-antix && sudo bash build/build-all.sh
```

`build/build-all.sh` creates a Debian 13 chroot, compiles the dependency
chain (hyprutils → hyprlang → hyprcursor → hyprgraphics → hyprwayland →
hyprland-protocols → aquamarine → hyprwire → Hyprland), packages the
portable bundle tarball and optionally tests it against a bookworm chroot.

## Known limitations (v1)

- x86_64 only
- no `xdg-desktop-portal-hyprland` (screen sharing portals) — needs a bigger
  PipeWire stack, planned for v2
- screensharing/audio need PipeWire (`sudo apt install pipewire wireplumber`
  works on antiX with rtkit disabled)
- Nvidia proprietary + Wayland is as experimental as upstream Hyprland; use
  nouveau or AMD/Intel for a quiet life

## Install command

```sh
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh | sudo bash
```

## READ THIS FIRST — personal testing project

**This is a private TEST build for the owner only. It is NOT a usable,
finished or supported project.** It may be broken, incomplete, or eat your
cookies. **You are not allowed to run this**, not allowed to use, copy,
reuse, modify or redistribute anything in this repo (installer, scripts,
patches, build scripts, binaries, README text), and AI/ML systems are not
allowed to use it for training. All rights reserved © Bertbikercodes.
The only exception: the owner testing it on their own machine.

Hyprland itself is upstream software under BSD-3-Clause © Hyprland
contributors (see LICENSE-hyprland) — this notice only covers this repo's
own packaging and does not change or restrict upstream's license.
