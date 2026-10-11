#!/bin/sh
# OVERSHOT OS — lock the screen (Win+L)
if command -v swaylock >/dev/null 2>&1; then
    exec swaylock
else
    notify-send "OVERSHOT" "swaylock is not installed (mandatory app missing?)"
    exit 1
fi
