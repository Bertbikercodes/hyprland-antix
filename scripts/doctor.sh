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

if [ -n "${SUDO_USER:-}" ] && id "${SUDO_USER}" >/dev/null 2>&1; then
    GRPS=$(id -nG "${SUDO_USER}")
    case "$GRPS" in *video*|*input*|*seat*) ok "user ${SUDO_USER} has device groups ($GRPS)" ;;
        *) bad "user ${SUDO_USER} missing video/input/seat groups" ;; esac
fi

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ] && exit 0 || exit 1
