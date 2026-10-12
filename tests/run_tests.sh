#!/usr/bin/env bash
# OVERSHOT OS — post-install smoke tests. Runs on the target system (also works
# in a chroot). Read-only. Exit 1 if any FAIL.
# NOTE: ldd is only used on first-party binaries shipped by this project.
set -u
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [SKIP] %s\n' "$1"; SKIP=$((SKIP+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== OVERSHOT OS smoke tests =="

# 1. binaries
for b in hyprland hyprctl; do
    have "$b" && ok "$b on PATH" || bad "$b missing"
done
[ -x /usr/local/bin/Hyprland ] && ok "/usr/local/bin/Hyprland executable" || bad "Hyprland binary missing"

# 2. library resolution + RPATH
MISS="$(ldd /usr/local/bin/Hyprland 2>/dev/null | grep -c 'not found' || true)"
[ "${MISS:-1}" = "0" ] && ok "Hyprland: all shared libraries resolve" || bad "Hyprland: $MISS libraries not found"
if have readelf; then
    readelf -d /usr/local/bin/Hyprland 2>/dev/null | grep -q hyprland-antix \
        && ok "RPATH for pinned libs present" || bad "RPATH missing"
else skip "readelf not available for RPATH check"; fi

# 3. pinned libs private: present, but NOT in the ldconfig cache
for l in libxkbcommon.so.0 libinput.so.10; do
    [ -f "/usr/local/lib/hyprland-antix/$l" ] && ok "pinned $l installed privately" || bad "pinned $l missing"
done
N="$(ldconfig -p 2>/dev/null | grep -c hyprland-antix || true)"
[ "${N:-0}" = "0" ] && ok "pinned libs not in system ldconfig cache (no shadowing)" || bad "pinned libs leaked into ldconfig cache"

# 4. seatd
[ -f /etc/init.d/seatd-antix ] && ok "seatd init script present" || bad "seatd init script missing"
[ -S /run/seatd.sock ] && ok "seatd socket active" || bad "seatd socket missing"
getent group seat >/dev/null 2>&1 && ok "seat group exists" || bad "seat group missing"

# 5. system-wide OVERSHOT tree
SHARE=/usr/local/share/overshot
[ -f "$SHARE/config/hypr/hyprland.conf" ] && ok "hyprland default config shipped" || bad "hyprland default config missing"
[ -f "$SHARE/config/waybar/config.jsonc" ]  && ok "waybar config shipped" || bad "waybar config missing"
[ -f "$SHARE/config/waybar/dock.jsonc" ]   && ok "dock config shipped" || bad "dock config missing"
[ -f "$SHARE/config/mimeapps.list" ]       && ok "default file associations shipped" || bad "mimeapps.list missing"
[ -f "$SHARE/assets/overshot-wallpaper.png" ] && ok "wallpaper asset shipped" || bad "wallpaper asset missing"
for n in powermenu settings dock-toggle perf browser shot doctor benchmark lock record clipboard; do
    [ -e "/usr/local/bin/overshot-$n" ] && ok "overshot-$n command" || bad "overshot-$n command missing"
done

# 6. per-user configs (check root + every home)
USER_HOMES="/root"
for h in /home/*; do [ -d "$h" ] && USER_HOMES="$USER_HOMES $h"; done
for H in $USER_HOMES; do
    [ -f "$H/.config/hypr/hyprland.conf" ] && ok "$H: hyprland.conf" || bad "$H: hyprland.conf missing"
    [ -f "$H/.config/waybar/config.jsonc" ] && ok "$H: waybar config" || bad "$H: waybar config missing"
    [ -f "$H/.config/mimeapps.list" ] && ok "$H: file associations" || bad "$H: mimeapps.list missing"
done

# 7. waybar configs are valid JSONC (after comment stripping)
if have python3; then
    for f in "$SHARE/config/waybar/config.jsonc" "$SHARE/config/waybar/dock.jsonc"; do
        if python3 - "$f" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
raw = re.sub(r'//[^\n"]*$', '', raw, flags=re.M)
json.loads(raw)
PY
        then ok "$f parses as JSON"; else bad "$f is not valid JSON"; fi
    done
else skip "python3 not available for JSON validation"; fi

# 8. graceful degradation markers must be gone when backends are missing
if ! have pactl; then
    grep -q STRIP:audio /root/.config/waybar/config.jsonc 2>/dev/null \
        && bad "audio module left in config without pactl" || ok "audio module correctly absent/stripped"
fi
if ! have firefox-esr && ! have firefox && ! have chromium; then
    grep -q STRIP:browser /root/.config/waybar/dock.jsonc 2>/dev/null \
        && bad "browser module left in dock without a browser" || ok "browser dock icon correctly absent/stripped"
fi
if ! have audacious; then
    grep -q STRIP:music /root/.config/waybar/dock.jsonc 2>/dev/null \
        && bad "music module left in dock without audacious" || ok "music dock icon correctly absent/stripped"
fi

# 9. application suite — mandatory apps must really be there
for b in foot thunar udisksctl dunst swaybg swaylock grim slurp wl-copy \
          cliphist xarchiver 7z unzip zathura imv-wayland mousepad htop ncdu brightnessctl \
          audacious pavucontrol desktop-file-validate; do
    have "$b" && ok "app: $b" || bad "app: $b missing (mandatory)"
done

[ -x /usr/lib/x86_64-linux-gnu/tumbler-1/tumblerd ] || [ -x /usr/libexec/tumblerd ] \
    && ok "app: tumblerd (file previews)" || bad "tumblerd missing (mandatory)"
[ -f /usr/libexec/imv/imv ] && ok "app: imv viewer binary" || bad "imv viewer binary missing"

# 9b. manifest consumption: every mandatory manifest package must be installed
MISSED=0
for mf in core.txt apps-mandatory.txt; do
    MF="/opt/hyprland-antix/packages/$mf"
    [ -f "$MF" ] || { bad "manifest missing: $mf"; MISSED=$((MISSED+1)); continue; }
    LIST="$(grep -vE '^[[:space:]]*(#|$)' "$MF")"
    [ -n "$LIST" ] || { bad "manifest $mf is empty (mandatory)"; MISSED=$((MISSED+1)); continue; }
    while read -r pkg; do
        case "$pkg" in ''|'#'*) continue ;; esac
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ok "manifest $mf: $pkg installed"
        else
            bad "manifest $mf: $pkg NOT installed (mandatory)"
            MISSED=$((MISSED+1))
        fi
    done <<< "$LIST"
done
[ "$MISSED" -eq 0 ] && ok "all mandatory manifest packages consumed" || true
# recommended manifest: report-only (optional set)
if [ -f /opt/hyprland-antix/packages/apps-recommended.txt ]; then
    ROK=0; RBAD=0
    RLIST="$(grep -vE '^[[:space:]]*(#|$)' /opt/hyprland-antix/packages/apps-recommended.txt)"
    while read -r pkg; do
        case "$pkg" in ''|'#'*) continue ;; esac
        if dpkg -s "$pkg" >/dev/null 2>&1; then ROK=$((ROK+1)); else RBAD=$((RBAD+1)); fi
    done <<< "$RLIST"
    if [ "$RBAD" -eq 0 ]; then
        ok "recommended manifest fully installed ($ROK packages)"
    else
        skip "recommended manifest: $ROK installed, $RBAD absent (optional)"
    fi
fi

# 9c. checksum tamper safety: a modified archive must be rejected
RAW="https://raw.githubusercontent.com/Bertbikercodes/hyprland-antix/main/install.sh"
if command -v curl >/dev/null 2>&1 && curl -fsL --retry 2 -o /tmp/overshot-verify-test-install.sh "$RAW" 2>/dev/null && [ -s /tmp/overshot-verify-test-install.sh ]; then
    printf 'this is not the release tarball' > /tmp/overshot-tampered.tar.gz
    if bash /tmp/overshot-verify-test-install.sh --verify-tarball /tmp/overshot-tampered.tar.gz >/dev/null 2>&1; then
        bad "checksum tamper test: modified archive was ACCEPTED (must abort!)"
    else
        if bash /tmp/overshot-verify-test-install.sh --verify-tarball /tmp/overshot-tampered.tar.gz 2>&1 | grep -qi "checksum mismatch"; then
            ok "checksum tamper test: modified archive rejected with checksum mismatch"
        else
            bad "checksum tamper test: rejected but without checksum-mismatch message"
        fi
    fi
    rm -f /tmp/overshot-verify-test-install.sh /tmp/overshot-tampered.tar.gz
else
    skip "checksum tamper test: canonical installer not reachable"
fi

# 10. stacks
if have pactl || have pipewire || have pulseaudio; then
    ok "audio stack present ($(have pipewire && echo pipewire || echo pulseaudio))"
else bad "no audio stack (pulseaudio/pipewire) present"; fi
if [ -x /etc/init.d/connman ] || [ -x /etc/init.d/network-manager ] || have NetworkManager; then
    ok "network stack present (connman/NetworkManager)"
else bad "no network manager present"; fi
if have cmst; then ok "network GUI (cmst) present"; else skip "cmst absent (NetworkManager kept?)"; fi

# 11. desktop menu entries valid + launchers point at installed programs
DFV="$(command -v desktop-file-validate || true)"
ENTRIES=0
for f in /usr/local/share/applications/overshot-*.desktop; do
    [ -e "$f" ] || continue
    ENTRIES=$((ENTRIES+1))
    if [ -n "$DFV" ] && ! "$DFV" "$f" >/dev/null 2>&1; then
        bad "invalid desktop entry: $(basename "$f")"
        continue
    fi
    EXE="$(grep -m1 '^Exec=' "$f" | sed 's/^Exec=//' | awk '{print $1}')"
    [ -z "$EXE" ] && { bad "$(basename "$f") has no Exec"; continue; }
    have "$EXE" && ok "menu entry $(basename "$f") -> $EXE" || bad "$(basename "$f") Exec target '$EXE' missing"
done
[ "$ENTRIES" -ge 5 ] && ok "$ENTRIES desktop menu entries installed" || bad "only $ENTRIES desktop entries installed"

# 12. keybinds for the new suite shipped in the default config
for pat in "overshot-powermenu" "overshot-clipboard" "overshot-record" "swaylock" "galculator"; do
    grep -q "$pat" "$SHARE/config/hypr/keybinds.conf" \
        && ok "keybind present: $pat" || bad "keybind missing: $pat"
done

# 13. recommended components (skipped in minimal mode — not a failure)
for b in firefox-esr galculator wf-recorder lxappearance synaptic; do
    have "$b" && ok "recommended app: $b" || skip "$b not installed (recommended, minimal mode?)"
done

# 14. install report
[ -f "$SHARE/install-report.txt" ] && ok "install report written" || skip "install report not present yet (written at end of install)"

# 15. Hyprland actually runs
mkdir -p /tmp/overshot-test-runtime
if OUT="$(XDG_RUNTIME_DIR=/tmp/overshot-test-runtime hyprland --version 2>&1 | head -1)" && [ -n "$OUT" ]; then
    ok "hyprland --version: $OUT"
else bad "hyprland --version failed"; fi

echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} skipped =="
[ "$FAIL" = 0 ] && exit 0 || exit 1
