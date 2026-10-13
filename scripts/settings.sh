#!/bin/sh
# OVERSHOT OS — settings menu (wofi driven, no daemon, no heavyweight stack).
MENUCONF=/usr/local/share/overshot/config/launcher/wofi-config
MENUCSS=/usr/local/share/overshot/config/launcher/wofi-style.rasi
HY="$HOME/.config/hypr"

CHOICE=$(printf 'Cancel\nAppearance (GTK theme)\nAudio mixer\nNetwork connections\nBluetooth devices\nKeyboard layout\nSet wallpaper\nDate, time & timezone\nPackage manager (synaptic)\nToggle performance mode\nToggle dock\nReload Hyprland config\nReload waybar\nEdit Hyprland config\nEdit keybinds\nEdit waybar config\nGPU manager (detect / NVIDIA driver)\nGPU info\nAbout OVERSHOT\n' \
    | wofi --dmenu -p "Settings" -i -c "$MENUCONF" -s "$MENUCSS" 2>/dev/null)

case "$CHOICE" in
    'Appearance (GTK theme)')     lxappearance ;;
    'Audio mixer')                pavucontrol ;;
    'Network connections')        cmst ;;
    'Bluetooth devices')          if command -v blueman-manager >/dev/null 2>&1; then
                                      blueman-manager
                                  else
                                      notify-send "OVERSHOT" "No bluetooth adapter or blueman not installed"
                                  fi ;;
    'Keyboard layout')            L=$(printf 'us\nde\nfr\nnl\nes\nit\npl\nse\n' | wofi --dmenu -p "Layout" -c "$MENUCONF" -s "$MENUCSS" 2>/dev/null)
                                  [ -n "$L" ] && sed -i "s/^kb_layout = .*/kb_layout = $L/" "$HY/hyprland.conf" && \
                                      notify-send "OVERSHOT" "Keyboard layout set to $L (next login)" ;;
    'Set wallpaper')             IMG=$(find /usr/local/share/overshot/assets/ -name '*.png' -o -name '*.jpg' 2>/dev/null | wofi --dmenu -p "Wallpaper" -c "$MENUCONF" -s "$MENUCSS" 2>/dev/null)
                                  [ -n "$IMG" ] && { pkill -x swaybg; swaybg -i "$IMG" -m fill >/dev/null 2>&1 &
                                      sed -i "s|^exec-once = swaybg .*|exec-once = swaybg -i $IMG -m fill|" "$HY/hyprland.conf"
                                      notify-send "OVERSHOT" "Wallpaper changed"; } ;;
    'Date, time & timezone')      foot -- sh -c 'sudo dpkg-reconfigure tzdata; echo; echo done - press Enter; read -r x' ;;
    'Package manager (synaptic)') if command -v synaptic >/dev/null 2>&1; then
                                      foot -- sudo synaptic
                                  else
                                      notify-send "OVERSHOT" "synaptic not installed (recommended app missing)"
                                  fi ;;
    'Toggle performance mode')    overshot-perf ;;
    'Toggle dock')                overshot-dock-toggle ;;
    'Reload Hyprland config')     hyprctl reload ;;
    'Reload waybar')              pkill waybar; sleep 1
                                  waybar -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" &
                                  waybar -c "$HOME/.config/waybar/dock.jsonc" -s "$HOME/.config/waybar/dock.css" & ;;
    'Edit Hyprland config')       foot -e nano "$HY/hyprland.conf" ;;
    'Edit keybinds')              foot -e nano "$HY/keybinds.conf" ;;
    'Edit waybar config')          foot -e nano "$HOME/.config/waybar/config.jsonc" ;;
    'GPU manager (detect / NVIDIA driver)')
                                  if command -v overshot-gpu >/dev/null 2>&1; then
                                      foot -e overshot-gpu
                                  else
                                      notify-send "OVERSHOT" "GPU manager not installed (run the installer)"
                                  fi ;;
    'GPU info')                   foot -e sh -c 'glxinfo | grep -E "renderer|vendor" | head -5; echo; read -r _ dummy' ;;
    'About OVERSHOT')             notify-send "OVERSHOT OS" "Hyprland 0.56.2 on antiX Core — no systemd. Private test build." ;;
    *) : ;;
esac
