#!/usr/bin/env bash
# OVERSHOT OS — nvidia-lib.sh: shared GPU detection/driver logic.
# Sourced by gpu-manager.sh, install.sh, doctor.sh. Not a standalone program.
#
# Detection works WITHOUT any NVIDIA driver installed: PCI scan via /sys
# (always present), lspci names when available (chip codename -> branch),
# Debian's official nvidia-detect as authoritative source when installed.
#
# Testability: OVERSHOT_GPU_TEST_DIR=<dir> redirects every external source to
# files (sys/, dpkg.txt, dkms.txt, apt-policy.txt, kver.txt, nvidia-detect.txt,
# module-version.txt, lspci.txt). Tests never need real hardware.

# ---------- test-mode redirection ----------
gpu_sysroot()   { [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && echo "${OVERSHOT_GPU_TEST_DIR}/sys" || echo /sys; }
gpu_kver()      { if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/kver.txt" ]; then cat "${OVERSHOT_GPU_TEST_DIR}/kver.txt"; else uname -r; fi; }
gpu_dpkg_has()  { # package name -> 0/1
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/dpkg.txt" ]; then
        grep -qx "$1" "${OVERSHOT_GPU_TEST_DIR}/dpkg.txt"
    else
        dpkg -s "$1" >/dev/null 2>&1
    fi
}
gpu_dkms_status() { # raw dkms status (may be empty)
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/dkms.txt" ]; then cat "${OVERSHOT_GPU_TEST_DIR}/dkms.txt"; return; fi
    command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null || true
}
gpu_apt_candidate() { # pkg -> candidate version or ""
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/apt-policy.txt" ]; then
        awk -F'|' -v p="$1" '$1==p{print $2; exit}' "${OVERSHOT_GPU_TEST_DIR}/apt-policy.txt"
        return
    fi
    apt-cache policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p' | head -1
}
gpu_nvidia_detect() { # output of official nvidia-detect, or ""
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/nvidia-detect.txt" ]; then cat "${OVERSHOT_GPU_TEST_DIR}/nvidia-detect.txt"; return; fi
    command -v nvidia-detect >/dev/null 2>&1 && nvidia-detect 2>/dev/null || true
}
gpu_module_version() { # loaded module version string, or ""
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/module-version.txt" ]; then cat "${OVERSHOT_GPU_TEST_DIR}/module-version.txt"; return; fi
    [ -r /proc/driver/nvidia/version ] && head -1 /proc/driver/nvidia/version | grep -oE '[0-9]+(\.[0-9]+)+' || true
}
gpu_lspci_raw() {
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/lspci.txt" ]; then cat "${OVERSHOT_GPU_TEST_DIR}/lspci.txt"; return; fi
    command -v lspci >/dev/null 2>&1 && lspci -nn 2>/dev/null || true
}

# ---------- PCI scan (no driver needed) ----------
# prints one line per display-class device:
#   pci_id|vendor|class|driver_in_use|description
gpu_scan_all() {
    local root; root="$(gpu_sysroot)"
    local dev vendor class dev_id driver desc
    if [ -d "$root/bus/pci/devices" ]; then
        for dev in "$root"/bus/pci/devices/*/; do
            [ -r "$dev/vendor" ] || continue
            vendor=$(cat "$dev/vendor" 2>/dev/null)
            class=$(cat "$dev/class" 2>/dev/null)
            case "$class" in 0x03*) ;; *) continue ;; esac        # display only
            dev_id=$(cat "$dev/device" 2>/dev/null)
            driver=""
            [ -L "$dev/driver" ] && driver=$(basename "$(readlink "$dev/driver")")
            desc=$(gpu_pci_name "${vendor#0x}:${dev_id#0x}" "$vendor" "$dev_id")
            echo "${dev%/}|${vendor#0x}:${dev_id#0x}|${vendor#0x}|${driver:-none}|${desc}"
        done
    fi
    # lspci names for pretty descriptions when /sys is unavailable
    if [ ! -d "$root/bus/pci/devices" ]; then
        gpu_lspci_raw | while IFS= read -r line; do
            case "$line" in *"[10de:"*|*"[1002:"*|*"[8086:"*) ;; *) continue ;; esac
            echo "$line|sys-unavailable"
        done
    fi
}

gpu_pci_name() { # pciid vendor devid -> best-effort description
    # lspci -nn: "01:00.0 VGA compatible controller: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:1b81]"
    local pciid="$1"
    local line; line=$(gpu_lspci_raw | grep -m1 "\[${pciid}\]")
    if [ -n "$line" ]; then
        echo "$line" | sed 's/^[0-9:.]* *//; s/^[^:]*: //; s/ *\[[0-9a-f:]*\] *$//; s/  */ /g' | head -c 120
    else
        case "$2" in
            10de) echo "NVIDIA GPU (10de:${3#0x})" ;;
            1002) echo "AMD GPU (${2#0x}:${3#0x})" ;;
            8086) echo "Intel GPU (8086:${3#0x})" ;;
            *)    echo "GPU $pciid" ;;
        esac
    fi
}

gpu_nvidia_present() { gpu_scan_all | grep -q '|10de|' ; }
gpu_has_display()    { [ -n "$(gpu_scan_all | head -1)" ]; }

# chip codename (GF104/GM204/TU104/GB202/...) from a description string
gpu_chip_of() { echo "$1" | grep -oE '\b(GF|GK|GM|GP|GV|TU|GA|AD|GB)[0-9A-Z]+' | head -1; }

# ---------- NVIDIA branch mapping (chip codename -> support level) ----------
# Prints: "<level> <explanation>"
# levels: supported / legacy-dropped / too-new / unknown
gpu_nvidia_branch_for_chip() {
    local chip="$1"
    [ -n "$chip" ] || { echo "unknown no-chip"; return; }
    case "$chip" in
        GF*|GK*)  echo "legacy-dropped 390xx legacy driver required (GTX 400-700) — removed from Debian repos; nouveau is the supported path here" ;;
        GM*|GP*|GV*) echo "supported 550 driver branch (last branch for Maxwell/Pascal/Volta)" ;;
        TU*|GA*|AD*) echo "supported 550 driver branch (Turing/Ampere/Ada)" ;;
        GB*)      echo "too-new Blackwell (RTX 50) needs driver 570+ — not in Debian trixie; limited nouveau or backports once available" ;;
        *)        echo "unknown unrecognized chip codename" ;;
    esac
}

# Full NVIDIA decision for one GPU line from gpu_scan_all.
# Prints a summary block; used by gpu-manager and installer.
gpu_nvidia_plan() {
    # input: "pciaddr|pciid|vendor|driver|desc"
    local in="$1" pci id drv desc chip level reason nd
    pci=$(echo "$in"  | cut -d'|' -f1)
    id=$(echo "$in"   | cut -d'|' -f2)
    drv=$(echo "$in"  | cut -d'|' -f4)
    desc=$(echo "$in" | cut -d'|' -f5)
    chip=$(gpu_chip_of "$desc")
    local nd_rec="" br
    nd=$(gpu_nvidia_detect)
    nd_rec=$(echo "$nd" | grep -oE 'nvidia[^ ]*driver[^ ]*' | head -1)
    br="$(gpu_nvidia_branch_for_chip "$chip")"     # "<level> <reason>"
    level="${br%% *}"
    reason="${br#* }"

    echo "gpu: $desc [$id]"
    echo "driver-in-use: $drv"
    echo "chip: ${chip:-unknown}"
    echo "nvidia-detect: ${nd_rec:-$([ -n "$nd" ] && echo 'no recommendation' || echo 'not installed')}"
    case "$level" in
        supported)
            local v; v=$(gpu_apt_candidate nvidia-driver)
            if [ -n "$v" ]; then
                echo "recommend: install nvidia-driver ($v) + nvidia-kernel-dkms"
            else
                echo "recommend: none — nvidia-driver not available (enable non-free/non-free-firmware)"
            fi ;;
        *)
            echo "recommend: no proprietary driver — $reason" ;;
    esac
    echo "level: $level"
}

# ---------- installed-driver state ----------
gpu_driver_packages() { # nvidia packages installed right now
    local p
    for p in nvidia-driver nvidia-driver-bin nvidia-kernel-dkms nvidia-legacy-390xx-driver nvidia-legacy-470xx-driver; do
        gpu_dpkg_has "$p" && echo "$p"
    done
}
gpu_conflicting_branches() { # prints conflicting package pair if found
    local has_current=0 has_legacy=0 p
    for p in $(gpu_driver_packages); do
        case "$p" in nvidia-legacy-*) has_legacy=1 ;; *) has_current=1 ;; esac
    done
    [ "$has_current" = 1 ] && [ "$has_legacy" = 1 ] && echo "nvidia-driver + nvidia-legacy-* both installed"
}
gpu_dkms_state() { # installed|broken|failed|missing|none (nvidia module)
    local st; st=$(gpu_dkms_status | grep '^nvidia/' | head -1)
    [ -z "$st" ] && { echo none; return; }
    case "$st" in
        *": installed") echo installed ;;
        *": broken")    echo broken ;;
        *"failed"*)     echo failed ;;
        *)              echo "unknown: $st" ;;
    esac
}
gpu_module_loaded() {  # 0/1
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ]; then [ -f "${OVERSHOT_GPU_TEST_DIR}/module-version.txt" ] && [ -s "${OVERSHOT_GPU_TEST_DIR}/module-version.txt" ]; return; fi
    grep -q '^nvidia ' /proc/modules 2>/dev/null
}
gpu_modeset_on() {    # 0/1
    if [ -n "${OVERSHOT_GPU_TEST_DIR:-}" ] && [ -f "${OVERSHOT_GPU_TEST_DIR}/modeset.txt" ]; then grep -qx 'Y' "${OVERSHOT_GPU_TEST_DIR}/modeset.txt"; return; fi
    [ -r /sys/module/nvidia_drm/parameters/modeset ] && grep -qi y /sys/module/nvidia_drm/parameters/modeset
}
gpu_headers_available() { # 0/1 for current kernel
    gpu_apt_candidate "linux-headers-$(gpu_kver)" | grep -q . && return 0
    # any generic headers package that matches this kernel also counts
    gpu_dpkg_has "linux-headers-$(gpu_kver)" && return 0
    return 1
}

# ---------- Hyprland / modprobe configuration (used by gpu-manager) ----------
GPU_SHARE() { [ -n "${OVERSHOT_GPU_TEST_SHARE:-}" ] && echo "$OVERSHOT_GPU_TEST_SHARE" || echo /usr/local/share/overshot; }
GPU_MODPROBE() { [ -n "${OVERSHOT_GPU_TEST_ETC:-}" ] && echo "$OVERSHOT_GPU_TEST_ETC/overshot-nvidia-modeset.conf" || echo /etc/modprobe.d/overshot-nvidia-modeset.conf; }
GPU_MODPROBE_DIR() { [ -n "${OVERSHOT_GPU_TEST_ETC:-}" ] && echo "$OVERSHOT_GPU_TEST_ETC" || echo /etc/modprobe.d; }
GPU_MARKER='# OVERSHOT nvidia env (auto-managed by overshot-gpu)'

configure_modeset() {
    # Wayland/Hyprland require nvidia-drm modeset. We never touch GRUB: a
    # modprobe.d file is enough and fully reversible.
    local dir; dir="$(GPU_MODPROBE_DIR)"
    local conf; conf="$(GPU_MODPROBE)"
    mkdir -p "$dir"
    if grep -sE 'options nvidia-drm .*(modeset=1|modeset=y)' "$dir"/*.conf >/dev/null 2>&1; then
        echo "   modeset: already enabled in an existing modprobe config — not duplicating"
        return 0
    fi
    if grep -sE 'options nvidia-drm .*modeset=0' "$dir"/*.conf >/dev/null 2>&1; then
        echo "   NOTE: an existing modprobe config sets modeset=0 — leaving YOUR file alone."
        echo "   Wayland needs modeset=1: edit that file or remove it, then reboot."
        return 0
    fi
    cat > "$conf" <<'MODEOF'
# OVERSHOT OS — required for Wayland (Hyprland) on NVIDIA
options nvidia-drm modeset=1
MODEOF
    echo "   wrote $conf (modeset=1)"
}

enable_hyprland_env() {
    # guarded, idempotent, backed-up: adds `source = nvidia.conf` to each
    # user's hyprland.conf only when an NVIDIA driver is actually installed.
    gpu_dpkg_has nvidia-driver || return 0
    local home hy conf
    for home in "${OVERSHOT_GPU_TEST_HOMES:-/root}" /home/*; do
        [ -d "$home" ] || continue
        hy="$home/.config/hypr"
        conf="$hy/hyprland.conf"
        [ -f "$conf" ] || continue
        cp -f "$(GPU_SHARE)/config/hypr/nvidia.conf" "$hy/nvidia.conf" 2>/dev/null || true
        if ! grep -qF "$GPU_MARKER" "$conf"; then
            cp -f "$conf" "$conf.overshot-gpu-backup"
            printf '\n%s\nsource = %s/nvidia.conf\n' "$GPU_MARKER" "$hy" >> "$conf"
            echo "   enabled NVIDIA env for $(basename "$home") (backup: hyprland.conf.overshot-gpu-backup)"
        else
            echo "   NVIDIA env already active for $(basename "$home")"
        fi
    done
}

disable_hyprland_env() { # used by repair/uninstall when no nvidia is present
    local home conf
    for home in "${OVERSHOT_GPU_TEST_HOMES:-/root}" /home/*; do
        conf="$home/.config/hypr/hyprland.conf"
        [ -f "$conf" ] || continue
        grep -qF "$GPU_MARKER" "$conf" || continue
        cp -f "$conf" "$conf.overshot-gpu-backup"
        sed -i "/$GPU_MARKER/d; /source = .*\/nvidia\.conf$/d" "$conf"
        echo "   removed NVIDIA env for $(basename "$home")"
    done
}
