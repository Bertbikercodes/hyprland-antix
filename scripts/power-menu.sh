#!/bin/sh
# OVERSHOT OS — power menu (wofi). Logout always works; reboot/shutdown
# need passwordless sudo or a root console (documented limitation).
set -f
CHOICE=$(printf 'Cancel\nLock\nLogout\nReboot\nShutdown\n' \
    | wofi --dmenu -p "Power" -i -c /usr/local/share/overshot/config/launcher/wofi-config \
      -s /usr/local/share/overshot/config/launcher/wofi-style.rasi 2>/dev/null)

case "$CHOICE" in
    Lock)     command -v swaylock >/dev/null 2>&1 && swaylock || \
                  notify-send "OVERSHOT" "swaylock not installed (optional package)" ;;
    Logout)   hyprctl dispatch exit ;;
    Reboot)   if sudo -n true 2>/dev/null; then sudo reboot
              else notify-send "OVERSHOT" "Reboot needs sudo: run 'sudo reboot' in a terminal"; fi ;;
    Shutdown) if sudo -n true 2>/dev/null; then sudo shutdown -h now
              else notify-send "OVERSHOT" "Shutdown needs sudo: run 'sudo poweroff' in a terminal"; fi ;;
    *)        : ;;
esac
