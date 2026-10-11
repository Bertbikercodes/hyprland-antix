# OVERSHOT OS — troubleshooting

Run the doctor first — it checks binaries, libraries, RPATH, seatd, configs and
device groups, and prints a clear OK/FAIL report:

```sh
overshot-doctor
```

Install logs live in `/tmp/overshot-install-*.log`. If Hyprland fails to start,
run it from the TTY again and read the output directly.

| Symptom | Cause / fix |
|---|---|
| installer: "not enough disk space" | free at least 700 MB on / (1.5 GB recommended) |
| installer: "checksum mismatch" | the download was corrupted or tampered; retry, do NOT bypass |
| installer: "libraries missing" after apt | run `sudo apt update`, then reinstall |
| `hyprland: command not found` | install did not finish; rerun the installer (idempotent) |
| black screen, back to console | check `ls /dev/dri` (empty = GPU driver issue); read the console error output |
| black screen + "seatd socket missing" | `sudo service seatd-antix start`; check `ls -l /run/seatd.sock` |
| cannot open terminal (Win+Enter does nothing) | `sudo apt install foot` |
| no app launcher (Win+Space) | `sudo apt install wofi` |
| no wallpaper | `sudo apt install swaybg`, relog (started by exec-once in hyprland.conf) |
| battery module missing on desktops | expected: waybar shows the battery only when one exists |
| audio module missing | no pulse/pipewire on the system (`sudo apt install pipewire` + pavucontrol) |
| browser dock icon missing | no browser installed (`sudo apt install firefox-esr`) |
| reboot/shutdown from power menu does nothing | they need passwordless sudo or a root console — a deliberate limitation; use `sudo reboot` |
| dock covers a fullscreen game | Win+D (or Ctrl+Alt+D) toggles the dock |
| panel looks wrong / old style | `pkill waybar`, then relog; check `~/.config/waybar/` |

## Removing everything

```sh
curl -fsSL https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh -o /tmp/inst
sudo bash /tmp/inst --uninstall
```

apt packages and your user configs are intentionally kept.
