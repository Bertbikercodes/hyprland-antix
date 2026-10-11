#!/bin/sh
# OVERSHOT OS — launch the first available web browser.
for b in firefox-esr firefox chromium chromium-browser epiphany-browser; do
    if command -v "$b" >/dev/null 2>&1; then
        exec "$b"
    fi
done
notify-send "OVERSHOT" "No web browser installed (optional: sudo apt install firefox-esr)"
