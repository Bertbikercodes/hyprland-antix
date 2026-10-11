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
[ -f "$SHARE/assets/overshot-wallpaper.png" ] && ok "wallpaper asset shipped" || bad "wallpaper asset missing"
for n in powermenu settings dock-toggle perf browser shot doctor benchmark; do
    [ -e "/usr/local/bin/overshot-$n" ] && ok "overshot-$n command" || bad "overshot-$n command missing"
done

# 6. per-user configs (check root + every home)
USER_HOMES="/root"
for h in /home/*; do [ -d "$h" ] && USER_HOMES="$USER_HOMES $h"; done
for H in $USER_HOMES; do
    [ -f "$H/.config/hypr/hyprland.conf" ] && ok "$H: hyprland.conf" || bad "$H: hyprland.conf missing"
    [ -f "$H/.config/waybar/config.jsonc" ] && ok "$H: waybar config" || bad "$H: waybar config missing"
done

# 7. waybar configs are valid JSONC (after comment stripping)
if have python3; then
    for f in "$SHARE/config/waybar/config.jsonc" "$SHARE/config/waybar/dock.jsonc"; do
        if python3 - "$f" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)          # // comments (own lines + trailing handled below)
raw = re.sub(r'//[^\n"]*$', '', raw, flags=re.M)         # trailing // STRIP:xxx markers without quote confusion
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

# 9. optional components must not break the core
have swaylock || skip "swaylock not installed (optional)"
have firefox-esr || skip "firefox not installed (optional)"

# 10. Hyprland actually runs
mkdir -p /tmp/overshot-test-runtime
if OUT="$(XDG_RUNTIME_DIR=/tmp/overshot-test-runtime hyprland --version 2>&1 | head -1)" && [ -n "$OUT" ]; then
    ok "hyprland --version: $OUT"
else bad "hyprland --version failed"; fi

echo "== ${PASS} passed, ${FAIL} failed, ${SKIP} skipped =="
[ "$FAIL" = 0 ] && exit 0 || exit 1
