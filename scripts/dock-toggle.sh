#!/bin/sh
# OVERSHOT OS — toggle the bottom dock (useful for fullscreen apps/games).
# The dock is the waybar instance with namespace 'overshot-dock'.
if pgrep -f "namespace overshot-dock" >/dev/null 2>&1 || \
   pgrep -f "waybar.*dock.jsonc" >/dev/null 2>&1; then
    pkill -f "waybar.*dock.jsonc" && exit 0
fi
exec waybar -c "$HOME/.config/waybar/dock.jsonc" -s "$HOME/.config/waybar/dock.css"
