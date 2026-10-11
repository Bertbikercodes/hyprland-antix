#!/bin/sh
# OVERSHOT OS — clipboard history picker (Win+V)
CHOICE=$(cliphist list | wofi --dmenu -p "Clipboard" -i \
    -c /usr/local/share/overshot/config/launcher/wofi-config \
    -s /usr/local/share/overshot/config/launcher/wofi-style.rasi 2>/dev/null)
[ -n "$CHOICE" ] && printf '%s' "$CHOICE" | cliphist decode | wl-copy
