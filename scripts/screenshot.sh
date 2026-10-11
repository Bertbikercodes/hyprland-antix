#!/bin/sh
# OVERSHOT OS — screenshot: interactive selection -> clipboard + file.
# Needs grim, slurp, wl-clipboard (all in the recommended app set).
set -e
DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/overshot-shots"
mkdir -p "$DIR"
FILE="$DIR/shot-$(date +%Y%m%d-%H%M%S).png"

GEOM=$(slurp 2>/dev/null) || { notify-send "OVERSHOT" "Screenshot cancelled"; exit 0; }

if [ -n "$GEOM" ]; then
    grim -g "$GEOM" "$FILE"
else
    grim "$FILE"
fi
wl-copy < "$FILE"
notify-send "OVERSHOT" "Screenshot saved to $FILE (also on clipboard)"
