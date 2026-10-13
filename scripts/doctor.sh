#!/bin/sh
# OVERSHOT OS — post-install doctor. Read-only diagnostics, exit 1 on problems.
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== OVERSHOT OS doctor =="
echo "  system: $(cat /etc/os-release 2>/dev/null | grep PRETTY | cut -d'"' -f2)"
echo "  arch:   $(uname -m)   init: $(ps -p 1 -o comm= 2>/dev/null)"
echo "  glibc:  $(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
echo "  disk /: $(df -h / 2>/dev/null | tail -1 | awk '{print "free " $4}')"

have hyprland   && ok "hyprland binary"        || bad "hyprland binary missing"
have hyprctl    && ok "hyprctl binary"         || bad "hyprctl binary missing"
have foot       && ok "foot terminal"          || bad "foot terminal missing (apps set)"
have waybar     && ok "waybar"                 || bad "waybar missing (apps set)"
have wofi       && ok "wofi launcher"          || bad "wofi missing (apps set)"
have swaybg     && ok "swaybg wallpaper"       || bad "swaybg missing (apps set)"
have dunst      && ok "dunst notifications"    || bad "dunst missing (apps set)"

# application suite
have thunar     && ok "thunar file manager"     || bad "thunar missing (mandatory)"
have xarchiver  && ok "xarchiver archives"      || bad "xarchiver missing (mandatory)"
have zathura    && ok "zathura PDF viewer"     || bad "zathura missing (mandatory)"
have imv-wayland && ok "imv image viewer"      || bad "imv missing (mandatory)"
have mousepad   && ok "mousepad text editor"   || bad "mousepad missing (mandatory)"
have audacious  && ok "audacious music player" || bad "audacious missing (mandatory)"
have swaylock   && ok "swaylock screen lock"   || bad "swaylock missing (mandatory)"
have grim       && ok "grim screenshots"       || bad "grim missing (mandatory)"
have wl-copy    && ok "wl-clipboard"           || bad "wl-clipboard missing (mandatory)"
have cliphist   && ok "cliphist history"       || bad "cliphist missing (mandatory)"
have pavucontrol && ok "pavucontrol mixer"      || bad "pavucontrol missing (mandatory)"
have htop       && ok "htop monitor"           || bad "htop missing (mandatory)"
if have firefox-esr; then ok "firefox-esr browser"; else echo "  [INFO] firefox-esr not installed (recommended set)"; fi
if have pactl || have pipewire || have pulseaudio; then
    ok "audio stack present"
else bad "no audio stack — sound will not work"; fi
if [ -x /etc/init.d/connman ] || [ -x /etc/init.d/network-manager ]; then
    ok "network manager present"
else bad "no network manager present"; fi
N=$(ls /usr/local/share/applications/overshot-*.desktop 2>/dev/null | wc -l)
[ "$N" -ge 5 ] && ok "$N desktop menu entries" || bad "desktop menu entries missing (re-run installer)"

MISSING=$(ldd /usr/local/bin/Hyprland 2>/dev/null | grep -c "not found" || true)
[ "${MISSING:-0}" = "0" ] && ok "all Hyprland shared libraries resolve (ldd)" \
                        || bad "$MISSING Hyprland libraries not found"

readelf -d /usr/local/bin/Hyprland 2>/dev/null | grep -q hyprland-antix \
    && ok "RPATH for pinned libs present" || bad "RPATH missing (reinstall recommended)"

[ -S /run/seatd.sock ] && ok "seatd socket active" || bad "seatd socket missing (service seatd-antix start)"
[ -f /etc/init.d/seatd-antix ] && ok "seatd init script present" || bad "seatd init script missing"
getent group seat >/dev/null 2>&1 && ok "seat group exists" || bad "seat group missing"

[ -f "$HOME/.config/hypr/hyprland.conf" ] && ok "Hyprland config present" || bad "Hyprland config missing (run setup again)"
[ -f "$HOME/.config/waybar/config.jsonc" ] && ok "waybar config present" || bad "waybar config missing"
[ -f /usr/local/share/overshot/assets/overshot-wallpaper.png ] && ok "wallpaper asset present" || bad "wallpaper asset missing"

# GPU / NVIDIA state (read-only)
GPULIB=/usr/local/share/overshot/scripts/nvidia-lib.sh
if [ -f "$GPULIB" ] && command -v gpu_nvidia_present >/dev/null 2>&1; then
    :  # already sourced (e.g. via overshot-gpu tests)
fi
if [ -f "$GPULIB" ]; then
    # shellcheck disable=SC1091
    . "$GPULIB"
    if gpu_nvidia_present; then
        if gpu_dpkg_has nvidia-driver; then
            gpu_module_loaded && ok "nvidia module loaded" || bad "nvidia driver installed but module not loaded (reboot; then dmesg | grep -i nvrm)"
            gpu_modeset_on && ok "nvidia-drm modeset enabled (Wayland-ready)" || bad "nvidia-drm modeset disabled — Hyprland will fail (run: sudo overshot-gpu repair)"
            [ -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ] && ok "nvidia EGL vendor present" || bad "nvidia EGL vendor file missing (reinstall driver)"
            [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ] && ok "nvidia Vulkan ICD present" || bad "nvidia Vulkan ICD missing"
            CONF=$(gpu_conflicting_branches)
            [ -z "$CONF" ] && ok "no conflicting driver branches" || bad "conflicting drivers: $CONF"
            grep -qF "OVERSHOT nvidia env" "$HOME/.config/hypr/hyprland.conf" 2>/dev/null \
                && ok "hyprland NVIDIA env enabled" || bad "hyprland NVIDIA env not sourced (sudo overshot-gpu repair)"
        else
            ok "NVIDIA GPU on the free nouveau driver ('overshot-gpu install' adds the proprietary one)"
        fi
    else
        ok "no NVIDIA GPU — free mesa drivers in charge"
    fi
else
    bad "gpu: nvidia-lib.sh missing (GPU diagnostics unavailable)"
fi

if [ -n "${SUDO_USER:-}" ] && id "${SUDO_USER}" >/dev/null 2>&1; then
    GRPS=$(id -nG "${SUDO_USER}")
    case "$GRPS" in *video*|*input*|*seat*) ok "user ${SUDO_USER} has device groups ($GRPS)" ;;
        *) bad "user ${SUDO_USER} missing video/input/seat groups" ;; esac
fi

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ] && exit 0 || exit 1
