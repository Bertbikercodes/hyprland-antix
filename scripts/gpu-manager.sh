#!/usr/bin/env bash
# OVERSHOT OS — GPU manager (overshot-gpu)
# NVIDIA (and AMD/Intel) driver detection, installation, repair and rescue.
# No systemd, no daemons, runs on demand only.
#
# Commands:
#   overshot-gpu [menu]     interactive menu (numbered, works in foot/wofi)
#   overshot-gpu scan        list GPUs, drivers in use
#   overshot-gpu drivers     compatible driver analysis per NVIDIA GPU
#   overshot-gpu install     install the recommended driver (root needed)
#   overshot-gpu repair      re-check + rebuild a broken install (root)
#   overshot-gpu check       Wayland/Hyprland readiness verification
#   overshot-gpu report      diagnostic report -> /tmp/overshot-gpu-report.txt
#   overshot-gpu safe-mode   start Hyprland with software rendering (rescue)
set -u
. /usr/local/share/overshot/scripts/nvidia-lib.sh 2>/dev/null \
    || . "$(dirname "$0")/nvidia-lib.sh" \
    || { echo "ERROR: nvidia-lib.sh not found" >&2; exit 1; }

BOLD=$(printf '\033[1m'); RST=$(printf '\033[0m')
GRN=$(printf '\033[1;32m'); YLW=$(printf '\033[1;33m'); RED=$(printf '\033[1;31m')
LOG=/tmp/overshot-gpu.log
SHARE=/usr/local/share/overshot

hdr()  { printf "\n%s== %s ==%s\n" "$GRN" "$*" "$RST"; }
note() { printf "%sNOTE:%s %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%sERROR:%s %s\n" "$RED" "$RST" "$*" >&2; }

require_root() {
    [ "$(id -u)" = 0 ] || { err "this action needs root. Run: sudo overshot-gpu $1"; return 1; }
}

# ─────────────────────────── scan ───────────────────────────
cmd_scan() {
    hdr "GPU scan ($(gpu_kver) kernel)"
    local found=0
    GPUS="$(gpu_scan_all)"
    while IFS='|' read -r pci id vendor drv desc; do
        [ -n "$pci" ] || continue
        found=1
        local maker="unknown"
        case "$vendor" in 10de) maker=NVIDIA ;; 1002) maker=AMD ;; 8086) maker=Intel ;; esac
        printf "  %-9s %-24s [%s] pci-id %s driver: %s\n" "$maker" "${desc:0:24}" "$pci" "$id" "$drv"
    done <<< "$GPUS"
    [ "$found" = 0 ] && note "no PCI display devices visible (VM? run 'apt install pciutils')"
    return 0
}

# ─────────────────────────── drivers ───────────────────────────
cmd_drivers() {
    hdr "Driver compatibility analysis"
    local nvidia_seen=0
    GPUS="$(gpu_scan_all)"
    while IFS='|' read -r pci id vendor drv desc; do
        [ "$vendor" = 10de ] || continue
        nvidia_seen=1
        echo ""
        gpu_nvidia_plan "$pci|$id|$vendor|$drv|$desc"
        level=$(gpu_nvidia_plan "$pci|$id|$vendor|$drv|$desc" | grep '^level:' | cut -d' ' -f2-)
        if [ "$level" = supported ]; then
            if gpu_headers_available; then
                echo "kernel: headers for $(gpu_kver) available — DKMS build possible"
            else
                echo "kernel: headers for $(gpu_kver) MISSING — install them first (linux-headers-$(gpu_kver))"
            fi
            echo "vulkan: $(gpu_apt_candidate nvidia-vulkan-icd >/dev/null && echo available || echo check-repos) / egl: $(gpu_apt_candidate libnvidia-egl-wayland1 >/dev/null && echo available || echo part-of-driver)"
        fi
    done <<< "$GPUS"
    [ "$nvidia_seen" = 0 ] && note "no NVIDIA GPU detected — nothing to analyze (AMD/Intel use free drivers)"
    local conf; conf=$(gpu_conflicting_branches)
    [ -n "$conf" ] && err "CONFLICT: $conf — remove one branch before installing another"
    return 0
}

# ─────────────────────────── install ───────────────────────────
cmd_install() {
    require_root install || return 1
    hdr "NVIDIA driver installation"
    local target="" level="" v="" tdir="${OVERSHOT_GPU_TEST_DIR:-}"
    GPUS="$(gpu_scan_all)"
    while IFS='|' read -r pci id vendor drv desc; do
        [ "$vendor" = 10de ] || continue
        local plan level_t
        plan=$(gpu_nvidia_plan "$pci|$id|$vendor|$drv|$desc")
        level_t=$(echo "$plan" | grep '^level:' | cut -d' ' -f2-)
        echo "$plan"; echo ""
        if [ "$level_t" = supported ]; then target="nvidia"; level=supported; fi
    done <<< "$GPUS"
    [ -z "$target" ] && { note "no supported NVIDIA GPU found; nothing installed (nouveau stays active)"; return 0; }

    local conf; conf=$(gpu_conflicting_branches)
    [ -n "$conf" ] && { err "conflicting driver branches present: $conf"; err "fix first (sudo apt purge 'nvidia-legacy-*'), then re-run"; return 1; }

    v=$(gpu_apt_candidate nvidia-driver)
    [ -n "$v" ] || { err "nvidia-driver not found in repositories."; note "enable: deb ... main contrib non-free non-free-firmware"; return 1; }

    # keep a working setup: refuse to purge anything automatically
    if gpu_dpkg_has nvidia-driver; then
        local cur; cur=$(dpkg-query -W -f='${Version}' nvidia-driver 2>/dev/null)
        note "an nvidia-driver is already installed ($cur). Re-running install upgrades in place; nothing is removed."
    fi

    printf "Disk free: %s MB — driver needs ~500 MB\n" "$(( $(df -k / 2>/dev/null | awk 'NR==2{print $4}' || echo 99999999) / 1024 ))"

    if [ "${1:-}" != "--batch" ]; then
        read -rp "Install nvidia-driver $v + nvidia-kernel-dkms now? [y/N] " yn
        case "$yn" in y|Y) ;; *) note "cancelled — nothing changed"; return 0 ;; esac
    fi

    echo "-> installing nvidia-driver + nvidia-kernel-dkms (official Debian repo)"
    if apt-get install -y -qq nvidia-driver nvidia-kernel-dkms >>"$LOG" 2>&1; then
        echo "   packages installed"
    else
        err "apt install failed — see $LOG"
        note "your desktop keeps running on the previous driver; re-run when repositories/headers are fixed"
        return 1
    fi

    # DKMS build verification
    local st; st=$(gpu_dkms_state)
    case "$st" in
        installed) echo "   DKMS module built for kernel $(gpu_kver)" ;;
        broken|failed|unknown*)
            err "DKMS module state: $st — the driver is NOT usable yet."
            note "run: sudo apt install linux-headers-$(gpu_kver) && sudo overshot-gpu repair"
            note "your system still boots with nouveau — not broken, just not accelerated"
            return 1 ;;
        none) note "no dkms record (prebuilt module?) — checking module directly" ;;
    esac

    configure_modeset
    enable_hyprland_env
    echo ""
    printf "%sDone.%s Reboot to load the nvidia modules (nouveau is auto-blacklisted by the Debian package).\n" "$GRN" "$RST"
    echo "After reboot: 'overshot-gpu check' verifies the full graphics stack."
    return 0
}




# ─────────────────────────── repair ───────────────────────────
cmd_repair() {
    require_root repair || return 1
    hdr "GPU driver repair"
    local problems=0

    if ! gpu_nvidia_present; then
        note "no NVIDIA GPU — nothing to repair"
        return 0
    fi
    if ! gpu_dpkg_has nvidia-driver; then
        note "nvidia-driver not installed — run 'overshot-gpu install' instead"
        return 0
    fi

    # 1. kernel module
    if ! gpu_module_loaded; then
        echo "-> module not loaded; trying modprobe"
        if modprobe nvidia 2>>"$LOG"; then
            echo "   module loaded"
        else
            err "nvidia module failed to load"
            note "reboot first (new driver needs boot-time load); if it still fails:"
            echo "   sudo dmesg | grep -iE 'nvidia|nvrm'   # look for version mismatches"
            problems=$((problems+1))
        fi
    else
        echo "   module loaded ($(gpu_module_version || echo unknown))"
    fi

    # 2. DKMS
    local st; st=$(gpu_dkms_state)
    case "$st" in
        installed) echo "   DKMS module built for $(gpu_kver)" ;;
        broken|failed|unknown*)
            echo "-> DKMS state '$st' — rebuilding for kernel $(gpu_kver)"
            if command -v dkms >/dev/null 2>&1; then
                dkms autoinstall >>"$LOG" 2>&1 && echo "   dkms autoinstall done" || {
                    err "DKMS rebuild failed — see $LOG"
                    gpu_headers_available || note "install headers first: sudo apt install linux-headers-$(gpu_kver)"
                    problems=$((problems+1)); }
            else
                err "dkms tool missing — apt install dkms"
                problems=$((problems+1))
            fi ;;
        none) note "no dkms record — if the module above loaded, all good" ;;
    esac

    # 3. config files
    configure_modeset
    if gpu_dpkg_has nvidia-driver; then enable_hyprland_env; else disable_hyprland_env; fi

    [ "$problems" = 0 ] && printf "%srepair finished clean.%s Reboot if the module was rebuilt.\n" "$GRN" "$RST" \
                       || { err "$problems problem(s) remain — see $LOG and 'overshot-gpu report'"; return 1; }
    return 0
}

# ─────────────────────────── check ───────────────────────────
cmd_check() {
    hdr "Graphics stack verification"
    local nvidia=0 problems=0
    GPUS="$(gpu_scan_all)"
    while IFS='|' read -r pci id vendor drv desc; do
        [ "$vendor" = 10de ] && nvidia=1
    done <<< "$GPUS"

    if [ "$nvidia" = 1 ]; then
        if gpu_dpkg_has nvidia-driver; then
            if gpu_module_loaded; then
                echo "  [ OK ] nvidia module loaded ($(gpu_module_version))"
            else
                echo "  [BAD] nvidia driver installed but module not loaded (reboot? dmesg?)"; problems=$((problems+1))
            fi
            if gpu_modeset_on; then
                echo "  [ OK ] nvidia-drm modeset=1 (Wayland-ready)"
            else
                echo "  [BAD] modeset off — Hyprland will fail or fall back"; problems=$((problems+1))
            fi
            for f in /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/share/vulkan/icd.d/nvidia_icd.json; do
                [ -f "$f" ] && echo "  [ OK ] $(basename "$f")" || { echo "  [BAD] missing $f"; problems=$((problems+1)); }
            done
            dpkg --print-foreign-architectures 2>/dev/null | grep -q i386 \
                && echo "  [ OK ] i386 enabled (Steam-32bit ready)" \
                || note "32-bit libs not enabled (only needed for Steam/Wine: 'sudo dpkg --add-architecture i386')"
        else
            note "NVIDIA GPU present, no proprietary driver — nouveau is in use (install via 'overshot-gpu install')"
        fi
    fi

    # universal checks (all vendors)
    if command -v glxinfo >/dev/null 2>&1; then
        echo "  [ OK ] glxinfo available (mesa-utils)"
    else
        note "glxinfo absent — 'apt install mesa-utils' to inspect rendering"
    fi
    echo "  [ OK ] init: $(ps -p 1 -o comm= 2>/dev/null) (no systemd required by any OVERSHOT component)"
    [ "$problems" = 0 ] && printf "%sall checks passed%s\n" "$GRN" "$RST" || return 1
    return 0
}

# ─────────────────────────── report ───────────────────────────
cmd_report() {
    local out=/tmp/overshot-gpu-report.txt
    {
        echo "OVERSHOT OS GPU diagnostic report — $(date)"
        echo "kernel: $(gpu_kver)   init: $(ps -p 1 -o comm= 2>/dev/null)   user: $(id -un)"
        echo
        echo "== PCI scan =="
        GPUS="$(gpu_scan_all)"
        while IFS='|' read -r pci id vendor drv desc; do
            echo "$desc [$id] driver:$drv"
        done <<< "$GPUS"
        echo
        echo "== NVIDIA analysis (per GPU) =="
        GPUS="$(gpu_scan_all)"
    while IFS='|' read -r pci id vendor drv desc; do
            [ "$vendor" = 10de ] && gpu_nvidia_plan "$pci|$id|$vendor|$drv|$desc" && echo
        done <<< "$GPUS"
        echo "== installed driver =="
        echo "packages: $(gpu_driver_packages | tr '\n' ' ')"
        echo "conflicts: $(gpu_conflicting_branches || echo none)"
        echo "dkms: $(gpu_dkms_state)"
        echo "module loaded: $(gpu_module_loaded && echo yes || echo no) ($(gpu_module_version))"
        echo "modeset: $(gpu_modeset_on && echo 1 || echo 0)"
        echo "hyprland env: $(grep -lF "$GPU_MARKER" /root/.config/hypr/hyprland.conf /home/*/.config/hypr/hyprland.conf 2>/dev/null | wc -l) user config(s)"
        echo
        echo "== apt candidates =="
        for p in nvidia-driver nvidia-kernel-dkms nvidia-detect "linux-headers-$(gpu_kver)"; do
            echo "$p -> $(gpu_apt_candidate "$p" || echo unavailable)"
        done
        echo
        echo "== full log (last 40 lines) =="
        tail -40 "$LOG" 2>/dev/null
    } > "$out" 2>&1
    echo "report written to $out"
    echo "share this file if you ask for help"
}

# ─────────────────────────── safe mode ───────────────────────────
cmd_safe_mode() {
    hdr "Safe mode — software-rendered Hyprland session"
    echo "Starts Hyprland with the pixman software renderer: slow but usable."
    echo "Use this to rescue a session when a driver breaks graphics."
    if [ -n "${OVERSHOT_GPU_TEST_EXEC:-}" ]; then
        echo "(test mode) would exec: WLR_RENDERER=pixman hyprland"
        return 0
    fi
    read -rp "Start the safe-mode session from this TTY? [y/N] " yn
    case "$yn" in
        y|Y) exec env WLR_RENDERER=pixman hyprland ;;
        *) note "cancelled" ;;
    esac
}

# ─────────────────────────── menu ───────────────────────────
cmd_menu() {
    cat <<'MENU'

  OVERSHOT GPU manager
  ────────────────────────────────
  1)  Scan GPUs
  2)  Find compatible drivers
  3)  Install driver           (sudo)
  4)  Repair driver            (sudo)
  5)  Check graphics configuration
  6)  Generate diagnostic report
  7)  Safe mode (software rendering)
  q)  Quit
MENU
    read -rp "Select [1-7/q]: " c
    case "$c" in
        1) cmd_scan ;;
        2) cmd_drivers ;;
        3) cmd_install ;;
        4) cmd_repair ;;
        5) cmd_check ;;
        6) cmd_report ;;
        7) cmd_safe_mode ;;
        q) return 0 ;;
        *) note "unknown option"; cmd_menu ;;
    esac
    read -rp "
Press Enter for the menu (q to quit) " x
    [ "$x" = q ] || cmd_menu
}

case "${1:-menu}" in
    scan)        cmd_scan ;;
    drivers)     cmd_drivers ;;
    install)     cmd_install "${2:-}" ;;
    repair)      cmd_repair ;;
    check)       cmd_check ;;
    report)      cmd_report ;;
    safe-mode)   cmd_safe_mode ;;
    menu|"")     cmd_menu ;;
    -h|--help)   sed -n '3,15p' "$0" ;;
    *) err "unknown command '$1' (scan drivers install repair check report safe-mode)"; exit 1 ;;
esac
