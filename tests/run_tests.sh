#!/usr/bin/env bash
# OVERSHOT OS — post-install smoke tests. Runs on the target system (also works
# in a chroot). Read-only. Exit 1 if any FAIL.
# NOTE: ldd is only used on first-party binaries shipped by this project.
set -u
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== OVERSHOT OS smoke tests =="

# 1. binaries
for b in hyprland hyprctl; do
    have "$b" && ok "$b on PATH" || bad "$b missing"
done
[ -x /usr/local/bin/Hyprland ] && ok "/usr/local/bin/Hyprland executable" || bad "Hyprland binary missing"

# 2. library resolution + RPATH
MISS="$(ldd /usr/local/bin/Hyprland 2>/dev/null | grep -c 'not found' || true)"
[ "${MISS:-1}" = "0" ] && ok "Hyprland: all shared libraries resolve" || bad "Hyprland: $MISS libraries not found"
if have readelf; then
    readelf -d /usr/local/bin/Hyprland 2>/dev/null | grep -q hyprland-antix \
        && ok "RPATH for pinned libs present" || bad "RPATH missing"
else skip "readelf not available for RPATH check"; fi

# 3. pinned libs private: present, but NOT in the ldconfig cache
for l in libxkbcommon.so.0 libinput.so.10; do
    [ -f "/usr/local/lib/hyprland-antix/$l" ] && ok "pinned $l installed privately" || bad "pinned $l missing"
done
N="$(ldconfig -p 2>/dev/null | grep -c hyprland-antix || true)"
[ "${N:-0}" = "0" ] && ok "pinned libs not in system ldconfig cache (no shadowing)" || bad "pinned libs leaked into ldconfig cache"

# 4. seatd
[ -f /etc/init.d/seatd-antix ] && ok "seatd init script present" || bad "seatd init script missing"
[ -S /run/seatd.sock ] && ok "seatd socket active" || bad "seatd socket missing"
getent group seat >/dev/null 2>&1 && ok "seat group exists" || bad "seat group missing"

# 5. system-wide OVERSHOT tree
SHARE=/usr/local/share/overshot
[ -f "$SHARE/config/hypr/hyprland.conf" ] && ok "hyprland default config shipped" || bad "hyprland default config missing"
[ -f "$SHARE/config/waybar/config.jsonc" ]  && ok "waybar config shipped" || bad "waybar config missing"
[ -f "$SHARE/config/waybar/dock.jsonc" ]   && ok "dock config shipped" || bad "dock config missing"
[ -f "$SHARE/config/mimeapps.list" ]       && ok "default file associations shipped" || bad "mimeapps.list missing"
[ -f "$SHARE/assets/overshot-wallpaper.png" ] && ok "wallpaper asset shipped" || bad "wallpaper asset missing"
for n in powermenu settings dock-toggle perf browser shot doctor benchmark lock record clipboard; do
    [ -e "/usr/local/bin/overshot-$n" ] && ok "overshot-$n command" || bad "overshot-$n command missing"
done

# 6. per-user configs (check root + every home)
USER_HOMES="/root"
for h in /home/*; do [ -d "$h" ] && USER_HOMES="$USER_HOMES $h"; done
for H in $USER_HOMES; do
    [ -f "$H/.config/hypr/hyprland.conf" ] && ok "$H: hyprland.conf" || bad "$H: hyprland.conf missing"
    [ -f "$H/.config/waybar/config.jsonc" ] && ok "$H: waybar config" || bad "$H: waybar config missing"
    [ -f "$H/.config/mimeapps.list" ] && ok "$H: file associations" || bad "$H: mimeapps.list missing"
done

# 7. waybar configs are valid JSONC (after comment stripping)
if have python3; then
    for f in "$SHARE/config/waybar/config.jsonc" "$SHARE/config/waybar/dock.jsonc"; do
        if python3 - "$f" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
raw = re.sub(r'//[^\n"]*$', '', raw, flags=re.M)
json.loads(raw)
PY
        then ok "$f parses as JSON"; else bad "$f is not valid JSON"; fi
    done
else skip "python3 not available for JSON validation"; fi

# 8. graceful degradation markers must be gone when backends are missing
if ! have pactl; then
    grep -q STRIP:audio /root/.config/waybar/config.jsonc 2>/dev/null \
        && bad "audio module left in config without pactl" || ok "audio module correctly absent/stripped"
fi
if ! have firefox-esr && ! have firefox && ! have chromium; then
    grep -q STRIP:browser /root/.config/waybar/dock.jsonc 2>/dev/null \
        && bad "browser module left in dock without a browser" || ok "browser dock icon correctly absent/stripped"
fi
if ! have audacious; then
    grep -q STRIP:music /root/.config/waybar/dock.jsonc 2>/dev/null \
        && bad "music module left in dock without audacious" || ok "music dock icon correctly absent/stripped"
fi

# 9. application suite — mandatory apps must really be there
for b in foot thunar udisksctl dunst swaybg swaylock grim slurp wl-copy \
          cliphist xarchiver 7z unzip zathura imv-wayland mousepad htop ncdu brightnessctl \
          audacious pavucontrol desktop-file-validate; do
    have "$b" && ok "app: $b" || bad "app: $b missing (mandatory)"
done

[ -x /usr/lib/x86_64-linux-gnu/tumbler-1/tumblerd ] || [ -x /usr/libexec/tumblerd ] \
    && ok "app: tumblerd (file previews)" || bad "tumblerd missing (mandatory)"
[ -f /usr/libexec/imv/imv ] && ok "app: imv viewer binary" || bad "imv viewer binary missing"

# 9b. manifest consumption: every mandatory manifest package must be installed
MISSED=0
for mf in core.txt apps-mandatory.txt; do
    MF="/opt/hyprland-antix/packages/$mf"
    [ -f "$MF" ] || { bad "manifest missing: $mf"; MISSED=$((MISSED+1)); continue; }
    LIST="$(grep -vE '^[[:space:]]*(#|$)' "$MF")"
    [ -n "$LIST" ] || { bad "manifest $mf is empty (mandatory)"; MISSED=$((MISSED+1)); continue; }
    while read -r pkg; do
        case "$pkg" in ''|'#'*) continue ;; esac
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "manifest $mf: $pkg installed"
        else
            bad "manifest $mf: $pkg NOT installed (mandatory)"
            MISSED=$((MISSED+1))
        fi
    done <<< "$LIST"
done
[ "$MISSED" -eq 0 ] && ok "all mandatory manifest packages consumed" || true
# recommended manifest: report-only (optional set)
if [ -f /opt/hyprland-antix/packages/apps-recommended.txt ]; then
    ROK=0; RBAD=0
    RLIST="$(grep -vE '^[[:space:]]*(#|$)' /opt/hyprland-antix/packages/apps-recommended.txt)"
    while read -r pkg; do
        case "$pkg" in ''|'#'*) continue ;; esac
        if dpkg -s "$pkg" >/dev/null 2>&1; then ROK=$((ROK+1)); else RBAD=$((RBAD+1)); fi
    done <<< "$RLIST"
    if [ "$RBAD" -eq 0 ]; then
        ok "recommended manifest fully installed ($ROK packages)"
    else
        skip "recommended manifest: $ROK installed, $RBAD absent (optional)"
    fi
fi

# 9c. checksum tamper safety: a modified archive must be rejected
RAW="https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh"
if command -v curl >/dev/null 2>&1 && curl -fsL --retry 2 -o /tmp/overshot-verify-test-install.sh "$RAW" 2>/dev/null && [ -s /tmp/overshot-verify-test-install.sh ]; then
    printf 'this is not the release tarball' > /tmp/overshot-tampered.tar.gz
    if bash /tmp/overshot-verify-test-install.sh --verify-tarball /tmp/overshot-tampered.tar.gz >/dev/null 2>&1; then
        bad "checksum tamper test: modified archive was ACCEPTED (must abort!)"
    else
        if bash /tmp/overshot-verify-test-install.sh --verify-tarball /tmp/overshot-tampered.tar.gz 2>&1 | grep -qi "checksum mismatch"; then
            ok "checksum tamper test: modified archive rejected with checksum mismatch"
        else
            bad "checksum tamper test: rejected but without checksum-mismatch message"
        fi
    fi
    rm -f /tmp/overshot-verify-test-install.sh /tmp/overshot-tampered.tar.gz
else
    skip "checksum tamper test: canonical installer not reachable"
fi

# 9d. GPU manager (NVIDIA subsystem) — detection, mapping, conflicts, safety.
# All GPU data is FAKED via OVERSHOT_GPU_TEST_DIR (nvidia-lib.sh test hooks);
# no real GPU exists in this test environment.
GPULIB=/opt/hyprland-antix/scripts/nvidia-lib.sh
GPUMGR=/opt/hyprland-antix/scripts/gpu-manager.sh
if [ -f "$GPULIB" ] && [ -x "$GPUMGR" ]; then
    ok "gpu: nvidia-lib.sh + gpu-manager.sh present in bundle"
    # shellcheck disable=SC1090
    . "$GPULIB"

    mkgpu() { # mkgpu <dir> "<addr>|<vendor>|<device>|<class>"...
        D="$1"; mkdir -p "$D/sys/bus/pci/devices"
        shift
        for spec in "$@"; do
            IFS='|' read -r a v d c <<< "$spec"
            mkdir -p "$D/sys/bus/pci/devices/$a"
            echo "0x$v" > "$D/sys/bus/pci/devices/$a/vendor"
            echo "0x$d" > "$D/sys/bus/pci/devices/$a/device"
            echo "$c" > "$D/sys/bus/pci/devices/$a/class"
        done
    }

    # no GPU at all
    T=$(mktemp -d); mkgpu "$T"
    OVERSHOT_GPU_TEST_DIR="$T" gpu_nvidia_present && bad "gpu: false NVIDIA detection on empty system" || ok "gpu: no-GPU system correctly reports none"
    rm -rf "$T"

    # single NVIDIA GPU (GM204 = GTX 970)
    T=$(mktemp -d); mkgpu "$T" "0000:01:00.0|10de|1b81|0x030000"
    printf '01:00.0 VGA compatible controller: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:1b81]\n' > "$T/lspci.txt"
    OVERSHOT_GPU_TEST_DIR="$T" gpu_nvidia_present && ok "gpu: NVIDIA GPU detected via sysfs" || bad "gpu: NVIDIA GPU not detected"
    LINE=$(OVERSHOT_GPU_TEST_DIR="$T" gpu_scan_all | head -1)
    echo "$LINE" | grep -q "10de:1b81" && ok "gpu: PCI id parsed (10de:1b81)" || bad "gpu: PCI id parse failed ($LINE)"
    CHIP=$(OVERSHOT_GPU_TEST_DIR="$T" gpu_chip_of "NVIDIA GM204 [GeForce GTX 970]")
    [ "$CHIP" = "GM204" ] && ok "gpu: chip codename extracted (GM204)" || bad "gpu: chip extraction failed ($CHIP)"
    rm -rf "$T"

    # hybrid: Intel iGPU + NVIDIA dGPU — both visible, iGPU untouched
    T=$(mktemp -d); mkgpu "$T" "0000:00:02.0|8086|1912|0x030000" "0000:01:00.0|10de|2191|0x030000"
    N=$(OVERSHOT_GPU_TEST_DIR="$T" gpu_scan_all | wc -l)
    [ "$N" = 2 ] && ok "gpu: hybrid system lists both GPUs (iGPU preserved)" || bad "gpu: hybrid scan found $N GPUs"
    rm -rf "$T"

    # branch mapping matrix (chip -> support level)
    for pair in "GF104:legacy-dropped" "GK104:legacy-dropped" "GM204:supported" "GP104:supported" "TU106:supported" "GA102:supported" "AD103:supported" "GB202:too-new"; do
        CH=${pair%%:*}; WANT=${pair##*:}
        GOT=$(gpu_nvidia_branch_for_chip "$CH" | awk '{print $1}')
        [ "$GOT" = "$WANT" ] && ok "gpu: branch map $CH -> $WANT" || bad "gpu: branch map $CH -> $GOT (want $WANT)"
    done

    # conflicting driver branches installed together
    T=$(mktemp -d)
    printf 'nvidia-driver\nnvidia-legacy-390xx-driver\n' > "$T/dpkg.txt"
    C=$(OVERSHOT_GPU_TEST_DIR="$T" gpu_conflicting_branches)
    [ -n "$C" ] && ok "gpu: conflicting branches detected ($C)" || bad "gpu: conflict not detected"
    rm -rf "$T"

    # DKMS state parsing
    T=$(mktemp -d)
    for st in "installed" "broken" "failed"; do
        case "$st" in failed) echo "nvidia/550.163.01+deb13, 6.1.0, x86_64: install failed (bad exit status: 10)" ;; *) echo "nvidia/550.163.01+deb13, 6.1.0, x86_64: $st" ;; esac > "$T/dkms.txt"
        GOT=$(OVERSHOT_GPU_TEST_DIR="$T" gpu_dkms_state)
        [ "$GOT" = "$st" ] && ok "gpu: dkms state '$st' parsed" || bad "gpu: dkms parse got '$GOT' for $st"
    done
    : > "$T/dkms.txt"
    [ "$(OVERSHOT_GPU_TEST_DIR="$T" gpu_dkms_state)" = "none" ] && ok "gpu: dkms absent -> none" || bad "gpu: dkms none parse"
    rm -rf "$T"

    # missing kernel headers
    T=$(mktemp -d); printf 'kver\n' > /dev/null; echo "6.12.17-antix" > "$T/kver.txt"; : > "$T/apt-policy.txt"
    OVERSHOT_GPU_TEST_DIR="$T" gpu_headers_available && bad "gpu: headers reported available when missing" || ok "gpu: missing kernel headers detected"
    rm -rf "$T"

    # modeset parameter
    T=$(mktemp -d); echo Y > "$T/modeset.txt"
    OVERSHOT_GPU_TEST_DIR="$T" gpu_modeset_on && ok "gpu: modeset=1 detected" || bad "gpu: modeset=1 not detected"
    echo N > "$T/modeset.txt"
    OVERSHOT_GPU_TEST_DIR="$T" gpu_modeset_on && bad "gpu: modeset=0 misdetected as on" || ok "gpu: modeset=0 detected as off"
    rm -rf "$T"

    # offline / empty repos: install must refuse, not break
    T=$(mktemp -d); mkgpu "$T" "0000:01:00.0|10de|1b81|0x030000"
    printf '01:00.0 VGA compatible controller: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:1b81]\n' > "$T/lspci.txt"; : > "$T/apt-policy.txt"
    OUT=$(OVERSHOT_GPU_TEST_DIR="$T" bash "$GPUMGR" install --batch 2>&1); RC=$?
    echo "$OUT" | grep -q "not found in repositories" && ok "gpu: offline install refuses with clear error" || bad "gpu: offline install message unclear: $OUT"
    [ "$RC" != 0 ] && ok "gpu: offline install exits nonzero" || bad "gpu: offline install exited 0"
    rm -rf "$T"

    # safe mode prints the rescue command without starting a session
    OUT=$(OVERSHOT_GPU_TEST_EXEC=1 bash "$GPUMGR" safe-mode 2>&1)
    echo "$OUT" | grep -q "WLR_RENDERER=pixman" && ok "gpu: safe-mode uses software renderer (pixman)" || bad "gpu: safe-mode missing pixman renderer"
    echo "$OUT" | grep -q "test mode" && ok "gpu: safe-mode test hook works" || bad "gpu: safe-mode test hook missing"

    # no systemd anywhere in the GPU subsystem (static)
    if grep -rq "systemctl" "$GPULIB" "$GPUMGR" /opt/hyprland-antix/scripts/nvidia-lib.sh 2>/dev/null; then
        bad "gpu: systemctl usage found (must stay systemd-free)"
    else
        ok "gpu: GPU subsystem is systemctl-free"
    fi
else
    bad "gpu: manager scripts missing from bundle"
fi

# 9e. GPU desktop integration: real functions from nvidia-lib.sh
if [ -f "$GPULIB" ] && [ -x "$GPUMGR" ]; then
    D=/opt/hyprland-antix/share/applications/overshot-gpu.desktop
    [ -f "$D" ] && grep -q "Exec=foot -- overshot-gpu" "$D" \
        && ok "gpu: desktop menu entry present" || bad "gpu: desktop entry missing/invalid"
    grep -q "GPU manager" /opt/hyprland-antix/scripts/settings.sh \
        && ok "gpu: settings menu has GPU manager entry" || bad "gpu: settings entry missing"
    NC=/opt/hyprland-antix/config/hypr/nvidia.conf
    grep -q "GBM_BACKEND,nvidia-drm" "$NC" && grep -q "__GLX_VENDOR_LIBRARY_NAME,nvidia" "$NC" \
        && ok "gpu: nvidia.conf env template correct" || bad "gpu: nvidia.conf template wrong"

    # enable/disable via the REAL functions, isolated in a fake home + share
    T=$(mktemp -d)
    mkdir -p "$T/home/.config/hypr" "$T/share/config/hypr" "$T/etc"
    printf 'monitor = , preferred, auto, 1\n' > "$T/home/.config/hypr/hyprland.conf"
    cp /opt/hyprland-antix/config/hypr/nvidia.conf "$T/share/config/hypr/"
    printf 'nvidia-driver\n' > "$T/dpkg.txt"
    OUT=$(bash -c '
        . /opt/hyprland-antix/scripts/nvidia-lib.sh
        export OVERSHOT_GPU_TEST_DIR="$1" OVERSHOT_GPU_TEST_HOMES="$1/home" \
               OVERSHOT_GPU_TEST_SHARE="$1/share" OVERSHOT_GPU_TEST_ETC="$1/etc"
        enable_hyprland_env
        configure_modeset
    ' _ "$T" 2>&1)
    HC="$T/home/.config/hypr/hyprland.conf"
    grep -qF "OVERSHOT nvidia env" "$HC" && grep -q "source = $T/home/.config/hypr/nvidia.conf" "$HC" \
        && ok "gpu: hyprland nvidia env enabled via real function" || bad "gpu: env enable failed ($OUT)"
    [ -f "$HC.overshot-gpu-backup" ] && ok "gpu: hyprland.conf backed up before edit" || bad "gpu: no backup made"
    [ -f "$T/home/.config/hypr/nvidia.conf" ] && ok "gpu: user nvidia.conf placed" || bad "gpu: nvidia.conf not placed"
    [ -f "$T/etc/overshot-nvidia-modeset.conf" ] && grep -q "modeset=1" "$T/etc/overshot-nvidia-modeset.conf" \
        && ok "gpu: modprobe modeset config written" || bad "gpu: modprobe config missing"
    # re-run enable: must be idempotent (no duplicate lines)
    bash -c '. /opt/hyprland-antix/scripts/nvidia-lib.sh
        export OVERSHOT_GPU_TEST_DIR="$1" OVERSHOT_GPU_TEST_HOMES="$1/home" \
               OVERSHOT_GPU_TEST_SHARE="$1/share" OVERSHOT_GPU_TEST_ETC="$1/etc"
        enable_hyprland_env' _ "$T" >/dev/null 2>&1
    N=$(grep -cF "OVERSHOT nvidia env" "$HC")
    [ "$N" = 1 ] && ok "gpu: env enable idempotent (single source line)" || bad "gpu: enable duplicated lines ($N)"
    # disable: managed lines gone, user content preserved
    ORIG="monitor = , preferred, auto, 1"
    bash -c '. /opt/hyprland-antix/scripts/nvidia-lib.sh
        export OVERSHOT_GPU_TEST_DIR="$1" OVERSHOT_GPU_TEST_HOMES="$1/home" \
               OVERSHOT_GPU_TEST_SHARE="$1/share" OVERSHOT_GPU_TEST_ETC="$1/etc"
        disable_hyprland_env' _ "$T" >/dev/null 2>&1
    grep -qF "OVERSHOT nvidia env" "$HC" && bad "gpu: disable left managed lines behind" || ok "gpu: env disable clean"
    grep -qF "$ORIG" "$HC" && ok "gpu: user config content preserved through toggle" || bad "gpu: user config damaged"
    # a second disable must not touch anything (no error, no changes)
    S1=$(md5sum "$HC" | cut -d' ' -f1)
    bash -c '. /opt/hyprland-antix/scripts/nvidia-lib.sh
        export OVERSHOT_GPU_TEST_DIR="$1" OVERSHOT_GPU_TEST_HOMES="$1/home"
        disable_hyprland_env' _ "$T" >/dev/null 2>&1
    S2=$(md5sum "$HC" | cut -d' ' -f1)
    [ "$S1" = "$S2" ] && ok "gpu: disable idempotent (no churn when absent)" || bad "gpu: disable churned a clean config"
    rm -rf "$T"

    # modeset: existing user config with modeset=0 must NOT be overridden
    T=$(mktemp -d); mkdir -p "$T/etc" "$T/home/.config/hypr"
    printf 'options nvidia-drm modeset=0\n' > "$T/etc/myown.conf"
    printf 'nvidia-driver\n' > "$T/dpkg.txt"
    OUT=$(bash -c '. /opt/hyprland-antix/scripts/nvidia-lib.sh
        export OVERSHOT_GPU_TEST_DIR="$1" OVERSHOT_GPU_TEST_ETC="$1/etc" OVERSHOT_GPU_TEST_HOMES="$1/home"
        configure_modeset' _ "$T" 2>&1)
    echo "$OUT" | grep -q "leaving YOUR file alone" && ok "gpu: user modeset=0 config respected (warned, not overridden)" || bad "gpu: user modprobe overridden: $OUT"
    [ -f "$T/etc/overshot-nvidia-modeset.conf" ] && bad "gpu: wrote duplicate config next to user's own" || ok "gpu: no duplicate modprobe config written"
    rm -rf "$T"

    # installer integration: GPU phase exists in install.sh
    grep -q "install_gpu_driver_if_needed" /opt/hyprland-antix/install.sh \
        && ok "gpu: installer has GPU phase" || bad "gpu: installer GPU phase missing"
    # doctor knows about the GPU section
    grep -q "nvidia-lib" /opt/hyprland-antix/scripts/doctor.sh \
        && ok "gpu: doctor has GPU checks" || bad "gpu: doctor missing GPU checks"
fi

# 9f. music visualizer + quick settings menu
if [ -x "$SHARE/scripts/waybar-cava" ] && [ -f "$SHARE/scripts/quickmenu.sh" ]; then
    grep -qx "cava" /opt/hyprland-antix/packages/apps-mandatory.txt \
        && ok "vis: cava is a mandatory package" || bad "vis: cava missing from apps-mandatory.txt"
    CC="$SHARE/config/cava/cava.conf"
    grep -q "method = raw" "$CC" && grep -q "bit_format = 8bit" "$CC" \
        && ok "vis: cava raw-mode config shipped" || bad "vis: cava.conf wrong"
    # waybar wiring: both modules registered
    WC="$SHARE/config/waybar/config.jsonc"
    grep -q '"custom/visualizer"' "$WC" && grep -q '"custom/quick"' "$WC" \
        && ok "vis: waybar has visualizer + quick-settings modules" || bad "vis: waybar modules missing"
    grep -q '"modules-right": \["custom/visualizer"' "$WC" \
        && ok "vis: visualizer placed on the right bar" || bad "vis: visualizer not in modules-right"
    # functional: fake cava emits known frames -> bars, then hide on silence
    mkdir -p /tmp/vis-test
    cat > /tmp/vis-test/cava <<'EOFAKECAVA'
#!/bin/sh
printf '\010\030\050\070\110\130\150\170\210\230\250\270\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000'
EOFAKECAVA
    chmod +x /tmp/vis-test/cava
    cp "$CC" /tmp/vis-test/cava.conf
    OUT=$(PATH="/tmp/vis-test:$PATH" OVERSHOT_CAVA_CONF=/tmp/vis-test/cava.conf \
          OVERSHOT_CAVA_ONCE=1 OVERSHOT_QUIET_FRAMES=2 \
          timeout 10 "$SHARE/scripts/waybar-cava" 2>/dev/null)
    L1=$(printf '%s\n' "$OUT" | sed -n 1p)
    L3=$(printf '%s\n' "$OUT" | sed -n 3p)
    printf '%s' "$L1" | grep -qF '▁▁▂▂▃▃▄▄▅▅▆▆' \
        && ok "vis: bars rendered from cava raw data" || bad "vis: bar rendering wrong: $L1"
    [ "$L3" = '{"text": ""}' ] \
        && ok "vis: silence hides the module (empty JSON)" || bad "vis: silence not handled: $L3"
    # no cava binary -> clean exit, waybar exec-if hides module
    PATH="/usr/local/bin" OVERSHOT_CAVA_CONF="$CC" timeout 5 "$SHARE/scripts/waybar-cava" >/dev/null 2>&1
    # (cava from apt is present in a full install, so only assert the guard exists)
    grep -q 'command -v cava' "$SHARE/scripts/waybar-cava" \
        && ok "vis: cava presence guard in script" || bad "vis: no cava guard"
    rm -rf /tmp/vis-test

    # quick settings menu
    [ -x /usr/local/bin/overshot-quickmenu ] \
        && ok "quick: overshot-quickmenu on PATH" || bad "quick: symlink missing"
    QM="$SHARE/scripts/quickmenu.sh"
    grep -q "set-sink-volume @DEFAULT_SINK@" "$QM" && grep -q "set-sink-mute" "$QM" \
        && ok "quick: volume control wired" || bad "quick: volume handling missing"
    grep -q "cmst" "$QM" && grep -q "blueman-manager" "$QM" && grep -q "bluetoothctl" "$QM" \
        && ok "quick: wifi + bluetooth options with fallbacks" || bad "quick: wifi/bt handling missing"
    grep -q "overshot-settings" "$QM" \
        && ok "quick: menu links to the settings app" || bad "quick: settings link missing"
    # keybinds: settings + quick menu reachable from keyboard
    grep -q '$mainMod, S, exec, overshot-settings' /opt/hyprland-antix/config/hypr/keybinds.conf \
        && ok "quick: SUPER+S opens settings" || bad "quick: settings keybind missing"
    grep -q '$mainMod, A, exec, overshot-quickmenu' /opt/hyprland-antix/config/hypr/keybinds.conf \
        && ok "quick: SUPER+A opens quick menu" || bad "quick: quickmenu keybind missing"
    # uninstall covers the new symlink
    grep -q "overshot-\$n" /opt/hyprland-antix/install.sh \
        && grep -q "quickmenu" /opt/hyprland-antix/install.sh \
        && ok "quick: uninstall removes quickmenu link" || bad "quick: uninstall misses quickmenu"
fi

# 10. stacks
if have pactl || have pipewire || have pulseaudio; then
    ok "audio stack present ($(have pipewire && echo pipewire || echo pulseaudio))"
else bad "no audio stack (pulseaudio/pipewire) present"; fi
if [ -x /etc/init.d/connman ] || [ -x /etc/init.d/network-manager ] || have NetworkManager; then
    ok "network stack present (connman/NetworkManager)"
else bad "no network manager present"; fi
if have cmst; then ok "network GUI (cmst) present"; else skip "cmst absent (NetworkManager kept?)"; fi

# 11. desktop menu entries valid + launchers point at installed programs
DFV="$(command -v desktop-file-validate || true)"
ENTRIES=0
for f in /usr/local/share/applications/overshot-*.desktop; do
    [ -e "$f" ] || continue
    ENTRIES=$((ENTRIES+1))
    if [ -n "$DFV" ] && ! "$DFV" "$f" >/dev/null 2>&1; then
        bad "invalid desktop entry: $(basename "$f")"
        continue
    fi
    EXE="$(grep -m1 '^Exec=' "$f" | sed 's/^Exec=//' | awk '{print $1}')"
    [ -z "$EXE" ] && { bad "$(basename "$f") has no Exec"; continue; }
    have "$EXE" && ok "menu entry $(basename "$f") -> $EXE" || bad "$(basename "$f") Exec target '$EXE' missing"
done
[ "$ENTRIES" -ge 5 ] && ok "$ENTRIES desktop menu entries installed" || bad "only $ENTRIES desktop entries installed"

# 12. keybinds for the new suite shipped in the default config
for pat in "overshot-powermenu" "overshot-clipboard" "overshot-record" "swaylock" "galculator"; do
    grep -q "$pat" "$SHARE/config/hypr/keybinds.conf" \
        && ok "keybind present: $pat" || bad "keybind missing: $pat"
done

# 13. recommended components (skipped in minimal mode — not a failure)
for b in firefox-esr galculator wf-recorder lxappearance synaptic; do
    have "$b" && ok "recommended app: $b" || skip "$b not installed (recommended, minimal mode?)"
done

# 14. install report
[ -f "$SHARE/install-report.txt" ] && ok "install report written" || skip "install report not present yet (written at end of install)"

# 15. Hyprland actually runs
mkdir -p /tmp/overshot-test-runtime
if OUT="$(XDG_RUNTIME_DIR=/tmp/overshot-test-runtime hyprland --version 2>&1 | head -1)" && [ -n "$OUT" ]; then
    ok "hyprland --version: $OUT"
else bad "hyprland --version failed"; fi

echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} skipped =="
[ "$FAIL" = 0 ] && exit 0 || exit 1
