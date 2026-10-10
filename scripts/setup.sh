#!/bin/sh
# setup.sh — called by install.sh from the unpacked bundle
# Sets up: /usr/local/bin/hyprland wrapper, seatd sysVinit service, user groups.
set -eu
DEST="/opt/hyprland-antix"
REAL_USER="${1:-}"

[ "$(id -u)" = "0" ] || { echo "setup.sh must run as root" >&2; exit 1; }

# 1. launcher wrapper on PATH
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
# bundled mesa drivers first, then system libs (libudev from eudev stays system-side)
export LIBGL_DRIVERS_PATH="$HL/lib/dri"
export __EGL_VENDOR_LIBRARY_PATHS="$HL/share/glvnd/egl_vendor.d"
exec "$HL/lib/ld-linux-x86-64.so.2" \
  --library-path "$HL/lib:$HL/lib/dri:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu" \
  "$HL/bin/Hyprland" "$@"
WRAP
chmod 755 /usr/local/bin/hyprland

# 2. seatd sysVinit service (use distro seatd if present, else the bundled static binary)
SEATD_BIN="$(command -v seatd || true)"
[ -x "$SEATD_BIN" ] || SEATD_BIN="$DEST/bin/seatd"

cat > /etc/init.d/seatd-antix <<INIT
#!/bin/sh
### BEGIN INIT INFO
# Provides:          seatd-antix
# Required-Start:    \$local_fs
# Required-Stop:     \$local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: seat management daemon for Hyprland
### END INIT INFO
DAEMON="$SEATD_BIN"
PIDFILE=/run/seatd-antix.pid
SEATD_GROUP="seat"
case "\$1" in
  start)
    # socket path both seatd and libseat defaults agree on
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE \\
      --exec \$DAEMON -- -g \$SEATD_GROUP -u root
    ;;
  stop)
    start-stop-daemon --stop --pidfile \$PIDFILE --retry 5
    rm -f \$PIDFILE /run/seatd.sock
    ;;
  restart) \$0 stop; sleep 1; \$0 start ;;
  *) echo "Usage: \$0 {start|stop|restart}"; exit 1 ;;
esac
exit 0
INIT
chmod 755 /etc/init.d/seatd-antix

# group 'seat' for seatd socket access, then service
getent group seat >/dev/null || addgroup --system seat
update-rc.d seatd-antix defaults >/dev/null
service seatd-antix start >/dev/null 2>&1 || /etc/init.d/seatd-antix start || true
[ -S /run/seatd.sock ] && chmod 775 /run/seatd.sock || true

# 3. user groups: video, input, seat (+render for GPU)
if [ -n "$REAL_USER" ] && id "$REAL_USER" >/dev/null 2>&1; then
    for g in video input render seat; do
        adduser "$REAL_USER" "$g" >/dev/null 2>&1 || true
    done
    echo "user '$REAL_USER' added to video/input/render/seat"
else
    echo "could not detect invoking user — add yourself manually:"
    echo "  sudo adduser \$USER video; sudo adduser \$USER input; sudo adduser \$USER seat"
fi
echo "setup complete"
