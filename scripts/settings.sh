#!/bin/sh
# OVERSHOT OS — lightweight settings menu (wofi driven, no daemon).
MENUCONF=/usr/local/share/overshot/config/launcher/wofi-config
MENUCSS=/usr/local/share/overshot/config/launcher/wofi-style.rasi

CHOICE=$(printf 'Cancel\nToggle performance mode\nToggle dock\nReload Hyprland config\nReload waybar\nEdit Hyprland config\nEdit waybar config\nGPU info (glxinfo)\nAbout OVERSHOT\n' \
    | wofi --dmenu -p "Settings" -i -c "$MENUCONF" -s "$MENUCSS" 2>/dev/null)

case "$CHOICE" in
    'Toggle performance mode') overshot-perf ;;
    'Toggle dock')             overshot-dock-toggle ;;
    'Reload Hyprland config')  hyprctl reload ;;
    'Reload waybar')           pkill waybar; sleep 1
                               waybar -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" &
                               waybar -c "$HOME/.config/waybar/dock.jsonc" -s "$HOME/.config/waybar/dock.css" & ;;
    'Edit Hyprland config')    foot -e nano "$HOME/.config/hypr/hyprland.conf" ;;
    'Edit waybar config')      foot -e nano "$HOME/.config/waybar/config.jsonc" ;;
    'GPU info (glxinfo)')      foot -e sh -c 'glxinfo | grep -E "renderer|vendor" | head -5; echo; read -r _ dummy' ;;
    'About OVERSHOT')          notify-send "OVERSHOT OS" "Hyprland 0.56.2 on antiX Core — no systemd. Private test build." ;;
    *) : ;;
esac
