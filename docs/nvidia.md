# NVIDIA GPU support (OVERSHOT OS)

OVERSHOT OS ships a complete, systemd-free NVIDIA driver stack for antiX Core.
Everything is driven by one tool: **`overshot-gpu`** (menu: Settings → *GPU
manager*, or run `overshot-gpu` in a terminal).

## What it does

| Capability | How |
|---|---|
| Detects GPUs (NVIDIA/AMD/Intel, incl. hybrid laptops) | PCI scan via `/sys`, names via `lspci -nn` — no driver needed first |
| Picks the right driver branch | chip codename (GF/GK/GM/GP/TU/GA/AD/GB…) → branch map; `nvidia-detect` used as authoritative source when installed |
| Installs only official Debian packages | `nvidia-driver` + `nvidia-kernel-dkms` from `contrib`/`non-free`/`non-free-firmware` |
| Builds the kernel module | DKMS against `linux-headers-$(uname -r)`; missing headers are detected and reported before install |
| Wayland/Hyprland setup | `/etc/modprobe.d/overshot-nvidia-modeset.conf` (`nvidia-drm modeset=1`), guarded `source = nvidia.conf` in `~/.config/hypr/hyprland.conf` (GBM/EGL env + software cursors) |
| Safe recovery | every config edit is backed up (`.overshot-gpu-backup`); failed DKMS builds are detected; `safe-mode` starts Hyprland with the pixman software renderer; nouveau is never auto-removed |
| Full GUI manager | numbered menu with scan / drivers / install / repair / check / report / safe-mode |

No GRUB edits, no systemd, no daemons, no background polling — every check
runs on demand only.

## Driver support matrix (Debian trixie reality, checked 2026-10)

| GPU family | Chips | Driver | Status |
|---|---|---|---|
| RTX 50 (Blackwell) | GB… | needs 570+ | **not in trixie repos** → limited nouveau; backports later |
| RTX 40 (Ada) | AD… | 550 | supported |
| RTX 30 (Ampere) | GA… | 550 | supported |
| RTX 20 / GTX 16 (Turing) | TU… | 550 | supported |
| GTX 10 (Pascal), GTX 9 (Maxwell), Volta | GP/GM/GV | 550 | supported — **550 is the last branch for these** |
| GTX 6/7 (Kepler), GTX 4/5 (Fermi) | GK/GF | 390xx legacy | **dropped from Debian** → nouveau is the path |
| Quadro / RTX professional | same chip families | same | same rules |

Laptops with Intel/AMD iGPU + NVIDIA dGPU: both GPUs stay listed; the iGPU
driver (mesa) is never touched.

## Usage

```sh
overshot-gpu                 # interactive menu
sudo overshot-gpu install    # automatic: detect → install → verify
sudo overshot-gpu repair     # module/DKMS/config repair
overshot-gpu check           # Wayland/Hyprland readiness
overshot-gpu report          # /tmp/overshot-gpu-report.txt
overshot-gpu safe-mode       # software-rendered rescue session
```

The base installer auto-installs the driver during a full install when an
NVIDIA GPU is detected (minimal mode just reports). A failed driver install
never breaks the desktop — nouveau keeps working.

## 32-bit (Steam)

Not enabled by default. If you need it:
`sudo dpkg --add-architecture i386 && sudo apt update`, then install the
`libnvidia-gl1:i386` packages matching your driver branch.

## Troubleshooting

- **Hyprland black screen after driver install** — `overshot-gpu check` shows
  the modeset/EGL state; `sudo overshot-gpu repair` fixes config, DKMS and env.
- **DKMS build fails** — install the matching headers first:
  `sudo apt install linux-headers-$(uname -r)`, then `sudo overshot-gpu repair`.
- **Tested vs simulated**: detection, branch mapping, conflict checks, DKMS
  state parsing, env toggling, offline behavior — all covered by 40+ automated
  tests with faked PCI/dpkg/DKMS data. No physical NVIDIA GPU was available in
  the build environment: real-hardware validation is still pending.
