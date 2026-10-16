# OVERSHOT OS — customization

All user configs live in your home and are **never overwritten** by updates.
The pristine defaults stay in `/usr/local/share/overshot/config/` — copy any
file back if you break yours.

## Hyprland

- `~/.config/hypr/hyprland.conf` — entry point; sources `theme.conf` and
  `keybinds.conf` from the same folder.
- `~/.config/hypr/theme.conf` — gaps, borders, rounding, blur, shadows,
  animations.
- `~/.config/hypr/keybinds.conf` — all key bindings.
- `~/.config/hypr/user-overrides.conf` — **sourced last, always wins.** Put
  your own tweaks here; they survive reinstalls and updates.

Apply changes live: `hyprctl reload` (most settings) or relog.

## Performance mode

```sh
overshot-perf          # toggle: disables animations + blur + shadows
overshot-perf          # again: restores full visuals
```
It writes/clears `user-overrides.conf`. For permanently-lean setups, just keep
it on.

## Waybar top panel

- `~/.config/waybar/config.jsonc` — modules (left/center/right).
- `~/.config/waybar/style.css` — colors, sizes, accent `#5fd0f0`.

Accent color recipe: replace `5fd0f0` in `style.css` and `rgba(95,208,240,...)`
in `theme.conf` with your color of choice.

Reload: `overshot-settings` → "Reload waybar", or relog.

## The dock

- The dock is a second waybar instance: `~/.config/waybar/dock.jsonc` +
  `dock.css`. Add/remove/reorder entries by editing the `modules-center` list.
- Toggle with Win+D. It floats (doesn't reserve screen space) and is
  documented as such: it does not auto-hide during fullscreen apps.
- Running windows appear after the pinned icons (wlr/taskbar) with an accent
  underline on the focused window.

## App launcher (wofi)

`~/.config/wofi/config` and `style.rasi` — matching dark theme by default.

## Wallpaper

Replace `/usr/local/share/overshot/assets/overshot-wallpaper.png` (system-wide)
or change the `swaybg -i ...` line in `~/.config/hypr/hyprland.conf` to your own image (per user).

## Branding / identity

- Wallpaper: `assets/overshot-wallpaper.png`
- Logo: `assets/logo.svg`
- Panel brand text: `custom/brand` module in the waybar config.

## Benchmark

```sh
overshot-benchmark              # writes /tmp/overshot-benchmark.txt
```
Reports measured RSS of the desktop components, free RAM, process count.
Measured vs estimated values are labeled in the report.

## Panel music visualizer

`scripts/waybar-cava` pipes cava's raw mode (12 bars, 8-bit) through od+awk
and emits Waybar JSON as thin pipe strokes: `|` soft, `||` medium, `|||` loud.
Every bar sits in a fixed 4-character slot, so the panel never shifts while
music plays. It appears on the right of the panel while sound plays and hides
itself after ~25 silent frames. Click it to open the music player.
Tweak `config/cava/cava.conf` (bars, framerate, smoothing) and re-login.

## Quick settings

`overshot-quickmenu` (panel gear icon or Win+A) opens a wofi menu with
volume +/-/mute (pactl), audio mixer (pavucontrol), Wi-Fi (cmst), Bluetooth
(blueman, or bluetoothctl in foot if blueman is absent) and a link to the
full settings menu (Win+S). No daemon: every option is an on-demand command.
