#!/bin/sh
# OVERSHOT OS — safe removal. Removes ONLY files owned by this project:
# binaries/libs in /usr/local, the bundle in /opt, the seatd service and
# the /usr/local/share/overshot config tree.
# NOT removed: apt packages (shared with the system), user dotfiles
# (~/.config/hypr, ~/.config/waybar, ...) — delete those by hand if you want.
set -eu
[ "$(id -u)" = "0" ] || { echo "run as root (sudo)" >&2; exit 1; }

HYPRLAND_LIBS="libaquamarine.so.14 libhyprcursor.so.0 libhyprgraphics.so.4 \
libhyprlang.so.2 libhyprutils.so.13 libhyprwire.so.3"

echo "removing hyprland-antix / OVERSHOT OS system files"
rm -f /usr/local/bin/Hyprland /usr/local/bin/hyprland /usr/local/bin/hyprctl \
      /usr/local/bin/hyprpm /usr/local/bin/seatd
for b in Hyprland hyprctl hyprpm; do rm -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"; done
for l in $HYPRLAND_LIBS; do rm -f "/usr/local/lib/$l"; done
rm -rf "/usr/local/lib/hyprland-antix"
for n in powermenu settings dock-toggle perf browser shot doctor benchmark; do
    rm -f "/usr/local/bin/overshot-$n"
done
rm -rf /usr/local/share/overshot
ldconfig

update-rc.d -f seatd-antix remove >/dev/null 2>&1 || true
service seatd-antix stop >/dev/null 2>&1 || true
rm -f /etc/init.d/seatd-antix /run/seatd-antix.pid

rm -rf /opt/hyprland-antix
echo "done. User configs (~/.config/hypr, ~/.config/waybar, ~/.config/wofi) were kept."
