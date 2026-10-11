#!/bin/sh
# OVERSHOT OS setup — called by install.sh from the unpacked bundle.
# Usage: setup.sh <native|portable> [real-user]
#
# native:   /usr/local/bin/hyprland is a plain symlink; system libs are used.
# portable: /usr/local/bin/hyprland wraps the bundled loader (older glibc).
#
# Both modes: seatd SysVinit service, device groups, OVERSHOT configs.
# User configs are ONLY copied when absent — updates never clobber user edits.
set -eu
DEST="/opt/hyprland-antix"
SHARE="/usr/local/share/overshot"
MODE="${1:-portable}"
REAL_USER="${2:-}"

[ "$(id -u)" = "0" ] || { echo "setup.sh must run as root" >&2; exit 1; }

# ── 1. launcher on PATH ─────────────────────────────────────────────
if [ "$MODE" = "native" ]; then
    # wrapper (NOT a bare symlink): a TTY login has no XDG_RUNTIME_DIR without
    # NOTE: remove first — /usr/local/bin/hyprland may be a symlink to Hyprland
    # (from an older install.sh), and writing through it would destroy the
    # real binary.
    rm -f /usr/local/bin/hyprland
    # elogind/systemd, and Hyprland refuses to start without it.
    cat > /usr/local/bin/hyprland <<'WRAP'
#!/bin/sh
# OVERSHOT OS launcher (native): ensure a runtime dir, then exec Hyprland
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if ! mkdir -p "$RUNTIME_DIR" 2>/dev/null; then
    RUNTIME_DIR="/tmp/overshot-runtime-$(id -u)"
    mkdir -p "$RUNTIME_DIR"
fi
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_SESSION_TYPE=wayland
exec /usr/local/bin/Hyprland "$@"
WRAP
    chmod 755 /usr/local/bin/hyprland
else
    cat > /usr/local/bin/hyprland <<'WRAP'
#!/bin/sh
# hyprland-antix launcher: runs the bundled Hyprland with its own libs
HL=/opt/hyprland-antix
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_SESSION_TYPE=wayland
export SEATD_SEAT="${SEATD_SEAT:-seat0}"
export LIBGL_DRIVERS_PATH="$HL/lib/dri"
export __EGL_VENDOR_LIBRARY_PATHS="$HL/share/glvnd/egl_vendor.d"
exec "$HL/lib/ld-linux-x86-64.so.2" \
  --library-path "$HL/lib:$HL/lib/dri:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu" \
  "$HL/bin/Hyprland" "$@"
WRAP
    chmod 755 /usr/local/bin/hyprland
fi

# ── 2. seatd sysVinit service ───────────────────────────────────────
SEATD_BIN="/usr/local/bin/seatd"
[ -x "$SEATD_BIN" ] || SEATD_BIN="$(command -v seatd || true)"
[ -x "$SEATD_BIN" ] || SEATD_BIN="$DEST/bin/seatd"

sed -e "s|@SEATD_BIN@|$SEATD_BIN|g" -e "s|@SEATD_GROUP@|seat|g" \
    "$DEST/services/seatd-antix" > /etc/init.d/seatd-antix
chmod 755 /etc/init.d/seatd-antix

getent group seat >/dev/null 2>&1 || groupadd -f seat 2>/dev/null || addgroup --system seat 2>/dev/null || true
update-rc.d seatd-antix defaults >/dev/null
service seatd-antix start >/dev/null 2>&1 || /etc/init.d/seatd-antix start || true
[ -S /run/seatd.sock ] && chmod 775 /run/seatd.sock || true

# ── 3. system-wide OVERSHOT files (configs, assets, helper scripts) ──
mkdir -p "$SHARE"
cp -r "$DEST/config" "$SHARE/config"
cp -r "$DEST/assets" "$SHARE/assets"
mkdir -p "$SHARE/scripts"
for s in power-menu.sh dock-toggle.sh perf-mode.sh settings.sh browser.sh screenshot.sh doctor.sh benchmark.sh lock.sh record.sh clipboard.sh; do
    [ -f "$DEST/scripts/$s" ] && cp -f "$DEST/scripts/$s" "$SHARE/scripts/$s"
done
chmod 755 "$SHARE/scripts"/*

for l in powermenu:power-menu.sh settings:settings.sh dock-toggle:dock-toggle.sh \
         perf:perf-mode.sh browser:browser.sh shot:screenshot.sh \
         doctor:doctor.sh benchmark:benchmark.sh lock:lock.sh \
         record:record.sh clipboard:clipboard.sh; do
    name="${l%%:*}"; src="${l#*:}"
    ln -sf "$SHARE/scripts/$src" "/usr/local/bin/overshot-$name"
done

# ── 4. device groups for the invoking user ───────────────────────────
if [ -n "$REAL_USER" ] && id "$REAL_USER" >/dev/null 2>&1; then
    for g in video input render seat; do
        adduser "$REAL_USER" "$g" >/dev/null 2>&1 || true
    done
    echo "user '$REAL_USER' added to video/input/render/seat"
else
    echo "could not detect invoking user — add yourself manually:"
    echo "  sudo adduser \$USER video; sudo adduser \$USER input; sudo adduser \$USER seat"
fi

# ── 5. per-user desktop configs (only where absent — never overwrite) ─
install_user_configs() {
    HOME_DIR="$1"
    HY="$HOME_DIR/.config/hypr"
    WB="$HOME_DIR/.config/waybar"
    WF="$HOME_DIR/.config/wofi"

    # Hyprland
    if [ ! -f "$HY/hyprland.conf" ]; then
        mkdir -p "$HY"
        cp -f "$DEST/config/hypr/hyprland.conf" "$HY/hyprland.conf"
        cp -f "$DEST/config/hypr/theme.conf" "$HY/theme.conf"
        cp -f "$DEST/config/hypr/keybinds.conf" "$HY/keybinds.conf"
        [ -f "$HY/user-overrides.conf" ] || : > "$HY/user-overrides.conf"
        : > "$HY/.overshot-default"
    elif [ ! -f "$HY/.overshot-default" ]; then
        # foreign or pre-OVERSHOT config: back it up, then install our defaults.
        # (Once the marker exists we NEVER touch the user's config again.)
        mkdir -p "$HY/overshot-backups"
        cp -f "$HY/hyprland.conf" "$HY/overshot-backups/hyprland.conf.$(date +%Y%m%d-%H%M%S)"
        echo "backed up existing hyprland.conf to $HY/overshot-backups/ (upgrading to OVERSHOT defaults)"
        cp -f "$DEST/config/hypr/hyprland.conf" "$HY/hyprland.conf"
        cp -f "$DEST/config/hypr/theme.conf" "$HY/theme.conf"
        cp -f "$DEST/config/hypr/keybinds.conf" "$HY/keybinds.conf"
        [ -f "$HY/user-overrides.conf" ] || : > "$HY/user-overrides.conf"
        : > "$HY/.overshot-default"
    fi

    # waybar (top panel + dock) — only installed fresh; user edits always win
    if [ ! -f "$WB/config.jsonc" ]; then
        mkdir -p "$WB"
        cp -f "$DEST/config/waybar/config.jsonc" "$WB/config.jsonc"
        cp -f "$DEST/config/waybar/style.css" "$WB/style.css"
        cp -f "$DEST/config/waybar/dock.jsonc" "$WB/dock.jsonc"
        cp -f "$DEST/config/waybar/dock.css" "$WB/dock.css"
        # graceful degradation: strip modules whose backends are missing
        if ! command -v pactl >/dev/null 2>&1; then
            sed -i '/STRIP:audio/d' "$WB/config.jsonc"
        fi
        if ! command -v firefox-esr >/dev/null 2>&1 && ! command -v firefox >/dev/null 2>&1 \
           && ! command -v chromium >/dev/null 2>&1; then
            sed -i '/STRIP:browser/d' "$WB/dock.jsonc"
        fi
        if ! command -v audacious >/dev/null 2>&1; then
            sed -i '/STRIP:music/d' "$WB/dock.jsonc"
        fi
    fi

    # wofi launcher
    if [ ! -f "$WF/config" ]; then
        mkdir -p "$WF"
        cp -f "$DEST/config/launcher/wofi-config" "$WF/config"
        cp -f "$DEST/config/launcher/wofi-style.rasi" "$WF/style.rasi"
    fi

    # default applications for file types (only fresh; user edits win)
    if [ ! -f "$HOME_DIR/.config/mimeapps.list" ]; then
        mkdir -p "$HOME_DIR/.config"
        cp -f "$DEST/config/mimeapps.list" "$HOME_DIR/.config/mimeapps.list"
    fi

    # dark GTK out of the box
    if [ ! -f "$HOME_DIR/.config/gtk-3.0/settings.ini" ]; then
        mkdir -p "$HOME_DIR/.config/gtk-3.0"
        printf '[Settings]\ngtk-application-prefer-dark-theme=true\n' \
            > "$HOME_DIR/.config/gtk-3.0/settings.ini"
    fi
}

for HOME_DIR in /root /home/*; do
    [ -d "$HOME_DIR" ] || continue
    install_user_configs "$HOME_DIR"
done

echo "setup complete (${MODE})"
