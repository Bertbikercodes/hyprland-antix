#!/bin/sh
# OVERSHOT OS — toggle screen recording with wf-recorder (Win+Shift+R)
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/overshot-record.pid"
VID="$HOME/Videos"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    notify-send "OVERSHOT" "Recording stopped — saved in $VID"
else
    command -v wf-recorder >/dev/null 2>&1 || {
        notify-send "OVERSHOT" "wf-recorder not installed (recommended app missing)"
        exit 1
    }
    mkdir -p "$VID"
    notify-send -t 2000 "OVERSHOT" "Recording started (Win+Shift+R to stop)"
    wf-recorder -f "$VID/overshot-recording-$(date +%Y%m%d-%H%M%S).mkv" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
fi
