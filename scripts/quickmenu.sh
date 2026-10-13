#!/bin/sh
# OVERSHOT OS — quick settings menu (wofi): volume, Wi-Fi, Bluetooth, settings.
# No daemon: every option is an on-demand command.
MENUCONF=/usr/local/share/overshot/config/launcher/wofi-config
MENUCSS=/usr/local/share/overshot/config/launcher/wofi-style.rasi

CHOICE=$(printf 'Volume +5\nVolume -5\nMute / unmute\nAudio mixer\nWi-Fi connections\nBluetooth devices\nAll settings\n' \
    | wofi --dmenu -p "Quick" -i -c "$MENUCONF" -s "$MENUCSS" 2>/dev/null)

case "$CHOICE" in
    'Volume +5')
        command -v pactl >/dev/null 2>&1 && pactl set-sink-volume @DEFAULT_SINK@ +5% \
            || notify-send "OVERSHOT" "pactl not available" ;;
    'Volume -5')
        command -v pactl >/dev/null 2>&1 && pactl set-sink-volume @DEFAULT_SINK@ -5% \
            || notify-send "OVERSHOT" "pactl not available" ;;
    'Mute / unmute')
        command -v pactl >/dev/null 2>&1 && pactl set-sink-mute @DEFAULT_SINK@ toggle \
            || notify-send "OVERSHOT" "pactl not available" ;;
    'Audio mixer')
        command -v pavucontrol >/dev/null 2>&1 && pavucontrol \
            || notify-send "OVERSHOT" "pavucontrol not installed" ;;
    'Wi-Fi connections')
        command -v cmst >/dev/null 2>&1 && cmst \
            || notify-send "OVERSHOT" "cmst not installed" ;;
    'Bluetooth devices')
        if command -v blueman-manager >/dev/null 2>&1; then
            blueman-manager
        elif command -v bluetoothctl >/dev/null 2>&1; then
            foot -- bluetoothctl
        else
            notify-send "OVERSHOT" "No bluetooth stack installed"
        fi ;;
    'All settings')
        overshot-settings ;;
    *) : ;;
esac
