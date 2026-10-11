#!/usr/bin/env bash
# OVERSHOT OS installer — hyprland-antix
# TESTING BUILD: private test project for the owner. NOT a supported release.
#
# Modes, picked automatically from system glibc:
#   native    (glibc >= 2.38, e.g. Debian 13 / trixie based antiX):
#             runtime libs from the antiX/Debian repos via apt; only the
#             Hypr-family libs + binaries go to /usr/local. No bundled loader.
#   portable  (older glibc, e.g. Debian 12 / bookworm based antiX 23):
#             self-contained bundle with its own loader and libs in /opt.
#
# Desktop modes:
#   complete  (default) core + mandatory apps + recommended everyday apps
#   minimal             core + mandatory apps only (no browser etc.)
#
# Flags:  --doctor    read-only diagnostics, exit 1 on problems
#         --dry-run   show the plan (manifests, detections, size), change nothing
#         --uninstall remove all project-owned files
#         --minimal   non-interactive minimal install
#         --help      usage
set -eu

REPO="Bertbikercodes/hyprland-antix"
VER="0.56.2-antix1"
DEST="/opt/hyprland-antix"
TARBALL="hyprland-antix-${VER}-x86_64.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VER}/${TARBALL}"
CHECKSUM_URL="https://raw.githubusercontent.com/${REPO}/main/checksums/${TARBALL}.sha256"
REPORT="/tmp/overshot-install-report.txt"
SUITE="complete"   # or "minimal"

# fallback lists if the bundle manifests are missing (older bundle)
FALLBACK_CORE="libcairo2 libgbm1 libinput10 libxkbcommon0 libwayland-client0"
FALLBACK_MANDATORY="foot thunar tumbler udisks2 dunst swaybg swaylock grim slurp wl-clipboard xarchiver unzip zathura zathura-pdf-poppler imv mousepad htop ncdu acpi audacious audacious-plugins pavucontrol"
FALLBACK_RECOMMENDED="firefox-esr galculator fonts-noto-core fonts-font-awesome mesa-utils xwayland"

# Hypr-family libs that ship in the bundle (NOT in the Debian repos)
HYPRLAND_LIBS="libaquamarine.so.14 libhyprcursor.so.0 libhyprgraphics.so.4 \
libhyprlang.so.2 libhyprutils.so.13 libhyprwire.so.3"

# pinned newer-than-trixie libs; private dir, only Hyprland sees them (RPATH)
PINNED_LIBS="libxkbcommon.so.0 libinput.so.10"
PINNED_DIR="/usr/local/lib/hyprland-antix"

B="\033[1m"; R="\033[0m"; G="\033[1;32m"; Y="\033[1;33m"; RD="\033[1;31m"
say()  { printf "${G}==>${R} %s\n" "$*"; }
warn() { printf "${Y}WARNING:${R} %s\n" "$*"; }
die()  { printf "${RD}ERROR:${R} %s\n" "$*" >&2; exit 1; }

banner() {
cat <<'EOF'
  ___  ___  ___  ___  ___ ___  ___  _   ___   _   ___
 / __|/ _ \|   \| __| _ \ _ )/ _ \/_\ |   \ /_\ | _ \
 \__ \ (_) | |) | _||   / _ \ (_) / _ \| |) / _ \|   /
 |___/\___/|___/|___|_|_\___/\___/_/ \_\___/_/ \_\_|_\
                  complete desktop suite  |  on antiX
EOF
    printf "${Y}>> PRIVATE TEST BUILD — owner testing only. Not a usable project. <<${R}\n\n"
}

# ---------- helpers ----------
glibc_version() { ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1; }
ver_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

GLIBC="$(glibc_version)"
if ver_ge "$GLIBC" "2.38"; then MODE="native"; else MODE="portable"; fi

manifest() {
    # manifest <file-in-bundle> <fallback-list>
    if [ -f "$DEST/packages/$1" ]; then
        grep -vE '^[[:space:]]*(#|$)' "$DEST/packages/$1"
    else
        echo "$2"
    fi
}

free_kb_root() { df -k / | awk 'NR==2 {print $4}'; }

check_disk() {
    FREE="$(free_kb_root)"
    case "$FREE" in ''|*[!0-9]*) warn "cannot determine free disk space"; return 0 ;; esac
    if [ "$FREE" -lt 2200000 ]; then
        die "not enough disk space: $((FREE/1024)) MB free on / (complete desktop needs ~2.2 GB; 3 GB recommended)"
    fi
    [ "$FREE" -lt 3000000 ] && warn "only $((FREE/1024)) MB free on / — 3 GB recommended for the complete desktop"
    return 0
}

pkg_candidate() { apt-cache policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p' | head -1; }
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
pkg_exists() { [ -n "$(pkg_candidate "$1")" ] && [ "$(pkg_candidate "$1")" != "(none)" ]; }

# report line: both to stdout (if interactive-ish) and the report file
rep() { echo "$*" >> "$REPORT"; }

report_init() {
    {
        echo "OVERSHOT OS install report — $(date)"
        echo "system: $(grep PRETTY /etc/os-release 2>/dev/null | cut -d'"' -f2)  arch: $(uname -m)"
        echo "mode: ${MODE}   suite: ${SUITE}   version: ${VER}"
        echo
        echo "== applications =="
    } > "$REPORT"
}

usage() {
    cat <<'USAGE'
OVERSHOT OS installer (hyprland-antix) — private test build

  install.sh                  interactive menu (complete desktop is the default)
  install.sh --minimal        non-interactive minimal install (core + mandatory apps)
  install.sh --doctor         read-only diagnostics, exit 1 on problems
  install.sh --dry-run        show the plan (manifests, detection, sizes), change nothing
  install.sh --uninstall      remove all project-owned files (apt pkgs + user configs stay)
  curl -fsSL <raw url> | sudo bash                 non-interactive complete install
  sudo HYPRLAND_ANTIX_TARBALL=file.tar.gz bash install.sh   offline install from a local tarball
USAGE
}

# ---------- doctor ----------
doctor() {
    local problems=0
    printf "system : %s\n" "$(grep PRETTY /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    printf "arch   : %s\n" "$(uname -m)"
    printf "init   : %s\n" "$(ps -p 1 -o comm= 2>/dev/null)"
    printf "glibc  : %s -> mode: %s\n" "$GLIBC" "$MODE"
    printf "disk / : %s MB free\n" "$(( $(free_kb_root) / 1024 ))"
    command -v apt-get >/dev/null 2>&1 && printf "apt    : ok\n" || { printf "apt    : MISSING\n"; problems=$((problems+1)); }
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        printf "fetch  : ok\n"
    else printf "fetch  : no curl/wget (install: apt install curl)\n"; problems=$((problems+1)); fi
    if command -v apt-cache >/dev/null 2>&1 && apt-cache policy libcairo2 2>/dev/null | grep -q Candidate; then
        printf "repos  : package lists available\n"
    else printf "repos  : run 'apt update' first (no candidates)\n"; problems=$((problems+1)); fi
    # audio stack
    if command -v pipewire >/dev/null 2>&1 || command -v pulseaudio >/dev/null 2>&1; then
        printf "audio  : %s\n" "$(command -v pipewire >/dev/null 2>&1 && echo 'pipewire present' || echo 'pulseaudio present')"
    else
        printf "audio  : none detected (installer will install pulseaudio)\n"
    fi
    # network stack
    if pgrep -x connmand >/dev/null 2>&1 || dpkg -s connman >/dev/null 2>&1; then
        printf "network: connman (antiX default)\n"
    elif pgrep -x NetworkManager >/dev/null 2>&1 || dpkg -s network-manager >/dev/null 2>&1; then
        printf "network: NetworkManager (kept as-is)\n"
    else
        printf "network: none detected (installer will install connman + cmst)\n"
    fi
    # bluetooth
    if ls /sys/class/bluetooth/*/ >/dev/null 2>&1; then
        printf "bluetooth: adapter detected (installer will install blueman)\n"
    else
        printf "bluetooth: no adapter detected\n"
    fi
    [ -x /usr/local/bin/Hyprland ] && printf "state  : existing install found (this run will upgrade in place)\n" \
                                 || printf "state  : fresh install\n"
    if [ "$problems" -gt 0 ]; then
        printf "\nresult : %d problem(s) found\n" "$problems"
        exit 1
    fi
    printf "\nresult : all checks passed\n"
    exit 0
}

# ---------- download / unpack ----------
download_unpack() {
    local SRC=""
    if [ -n "${HYPRLAND_ANTIX_TARBALL:-}" ]; then
        [ -f "${HYPRLAND_ANTIX_TARBALL}" ] || die "HYPRLAND_ANTIX_TARBALL is not a readable file: ${HYPRLAND_ANTIX_TARBALL}"
        SRC="${HYPRLAND_ANTIX_TARBALL}"
        say "using local tarball ${SRC} (integrity check skipped for local files)"
    else
        say "downloading ${TARBALL}"
        SRC="$(mktemp /tmp/overshot-dl.XXXXXX.tar.gz)"
        if command -v curl >/dev/null 2>&1; then
            curl -fL --retry 3 -o "$SRC" "$URL" || die "download failed"
        else
            wget -O "$SRC" "$URL" || die "download failed"
        fi
        say "verifying checksum"
        local SUMFILE
        SUMFILE="$(mktemp /tmp/overshot-sum.XXXXXX)"
        if command -v curl >/dev/null 2>&1; then
            curl -fsL --retry 2 -o "$SUMFILE" "$CHECKSUM_URL" || die "cannot fetch checksum (${CHECKSUM_URL})"
        else
            wget -q -O "$SUMFILE" "$CHECKSUM_URL" || die "cannot fetch checksum (${CHECKSUM_URL})"
        fi
        local WANT HAVE
        WANT="$(head -1 "$SUMFILE" | awk '{print $1}')"
        rm -f "$SUMFILE"
        [ "${#WANT}" = "64" ] || die "checksum file malformed"
        HAVE="$(sha256sum "$SRC" | awk '{print $1}')"
        [ "$WANT" = "$HAVE" ] || die "checksum mismatch — download corrupted or tampered; refusing to install"
        say "checksum OK"
    fi
    say "unpacking to ${DEST}"
    rm -rf "$DEST"; mkdir -p "$DEST"
    tar -xzf "$SRC" -C "$DEST" --strip-components=1
    # only remove the temporary download; never delete a user-supplied local tarball
    if [ "$SRC" != "${HYPRLAND_ANTIX_TARBALL:-}" ]; then
        rm -f "$SRC"
    fi
    [ -f "$DEST/bin/Hyprland" ] || die "bundle incomplete (bin/Hyprland missing)"
    [ -f "$DEST/packages/apps-mandatory.txt" ] || warn "bundle has no app manifests (older bundle) — using fallback lists"
}

apt_install_tolerant() {
    if ! apt-get install -y -qq "$@" >/dev/null 2>&1; then
        for p in "$@"; do
            apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "package '$p' not found — continuing"
        done
    fi
}

# ---------- manifest installation with per-app reporting ----------
# usage: manifest_install <manifest-file> <fallback> <level>
# level: mandatory -> failure is fatal (with exact blocker message)
#        soft      -> skip + report
manifest_install() {
    local file="$1" fallback="$2" level="$3" failed=0 skipped=0 installed=0
    local pkgs; pkgs="$(manifest "$file" "$fallback")"
    [ -n "$pkgs" ] || { rep "  (empty: $file)"; return 0; }
    # shellcheck disable=SC2086
    for p in $pkgs; do
        if pkg_installed "$p"; then
            rep "  INSTALLED(before): $p (already present)"
            installed=$((installed+1)); continue
        fi
        if ! pkg_exists "$p"; then
            if [ "$level" = "mandatory" ]; then
                rep "  FAILED: $p — package not in your repositories"
                warn "MANDATORY app '$p' is not available in your repos — see $REPORT"
                failed=$((failed+1))
            else
                rep "  SKIPPED: $p — package not in your repositories"
                warn "optional/recommended app '$p' not found in your repos — skipped"
                skipped=$((skipped+1))
            fi
            continue
        fi
        if apt-get install -y -qq "$p" >/dev/null 2>&1; then
            rep "  INSTALLED: $p"
            installed=$((installed+1))
        else
            rep "  FAILED: $p — apt install returned an error (run: apt-get install $p)"
            warn "install of '$p' failed — see $REPORT"
            [ "$level" = "mandatory" ] && failed=$((failed+1)) || skipped=$((skipped+1))
        fi
    done
    rep "  summary $file: $installed installed, $skipped skipped, $failed failed"
    if [ "$failed" -gt 0 ] && [ "$level" = "mandatory" ]; then
        say ""
        die "mandatory applications failed to install ($failed). Exact reasons are in $REPORT.
Likely causes: 'apt update' not run, a missing repository component, or no internet.
Fix the cause and re-run the installer — already-installed parts will be kept."
    fi
    return 0
}

# ---------- stack detection ----------
install_audio_if_needed() {
    if command -v pipewire >/dev/null 2>&1 || command -v pipewire-pulse >/dev/null 2>&1; then
        say "audio: pipewire already present — leaving it alone"
        rep "  audio: pipewire detected, nothing installed"
        return 0
    fi
    if command -v pulseaudio >/dev/null 2>&1 || command -v pactl >/dev/null 2>&1; then
        say "audio: pulseaudio already present — leaving it alone"
        rep "  audio: pulseaudio detected, nothing installed"
        return 0
    fi
    say "audio: none detected — installing pulseaudio (works without systemd)"
    manifest_install apps-audio.txt "pulseaudio pulseaudio-utils" mandatory
}

install_network_if_needed() {
    if pgrep -x connmand >/dev/null 2>&1 || dpkg -s connman >/dev/null 2>&1; then
        say "network: connman (antiX default) present"
        rep "  network: connman present"
        if ! pkg_installed cmst; then manifest_install apps-net.txt "cmst" soft; fi
        return 0
    fi
    if pgrep -x NetworkManager >/dev/null 2>&1 || dpkg -s network-manager >/dev/null 2>&1; then
        say "network: NetworkManager present — keeping it (cmst not installed)"
        rep "  network: NetworkManager present, kept as-is"
        return 0
    fi
    say "network: none detected — installing connman + cmst (antiX default stack)"
    manifest_install apps-net.txt "connman wpasupplicant cmst" mandatory
}

install_bluetooth_if_present() {
    if ls /sys/class/bluetooth/*/ >/dev/null 2>&1; then
        say "bluetooth: adapter detected — installing blueman"
        manifest_install apps-hardware.txt "bluez blueman" soft
        rep "  bluetooth: adapter present, blueman installed"
    else
        say "bluetooth: no adapter detected — skipping (menu option 3 re-runs detection)"
        rep "  bluetooth: no adapter detected, skipped"
    fi
}

install_firmware_if_available() {
    local any=0
    # shellcheck disable=SC2046
    for p in $(manifest apps-firmware.txt "firmware-linux firmware-realtek firmware-iwlwifi firmware-amd-graphics firmware-misc-nonfree"); do
        if ! pkg_installed "$p" && pkg_exists "$p"; then
            if apt-get install -y -qq "$p" >/dev/null 2>&1; then
                rep "  INSTALLED: $p (hardware firmware)"
                any=$((any+1))
            else
                rep "  FAILED: $p"
            fi
        elif pkg_installed "$p"; then
            rep "  INSTALLED(before): $p"
        else
            rep "  SKIPPED: $p — not in repos (enable 'non-free-firmware' in /etc/apt/sources.list if you need it)"
        fi
    done
    [ "$any" -gt 0 ] && say "firmware: $any firmware package(s) installed" || say "firmware: none needed/available"
}

# ---------- desktop menu entries (launchers only for what is really installed) ----------
install_desktop_entries() {
    say "desktop menu entries (only for components that are actually present)"
    local copied=0
    mkdir -p /usr/local/share/applications
    local f exe
    for f in "$DEST"/share/applications/*.desktop; do
        [ -e "$f" ] || continue
        exec_cmd="$(grep -m1 '^Exec=' "$f" | sed 's/^Exec=//' | awk '{print $1}')"
        if [ -n "$exec_cmd" ] && command -v "$exec_cmd" >/dev/null 2>&1; then
            cp -f "$f" /usr/local/share/applications/
            rep "  MENU ENTRY: $(basename "$f") -> Exec target '$exec_cmd' present"
            copied=$((copied+1))
        else
            rep "  SKIPPED MENU ENTRY: $(basename "$f") — Exec target '$exec_cmd' not installed"
        fi
    done
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/local/share/applications || true
    rep "  summary desktop-entries: $copied installed"
}

# ---------- verify installed apps really exist ----------
verify_apps() {
    say "verifying installed applications"
    local bad=0
    local checks="foot foot
thunar Thunar
udisks2 udisksctl
dunst dunst
swaybg swaybg
swaylock swaylock
grim grim
slurp slurp
wl-clipboard wl-copy
cliphist cliphist
xarchiver xarchiver
7zip 7z
unzip unzip
zathura zathura
imv imv-wayland
mousepad mousepad
htop htop
ncdu ncdu
acpi acpi
brightnessctl brightnessctl
audacious audacious
pavucontrol pavucontrol
cmst cmst
desktop-file-utils desktop-file-validate"
    while read -r pkg bin; do
        [ -z "$pkg" ] && continue
        if pkg_installed "$pkg" && command -v "$bin" >/dev/null 2>&1; then
            rep "  VERIFY OK: $pkg ($bin)"
        elif pkg_installed "$pkg"; then
            rep "  VERIFY pkg-only: $pkg (package present, '$bin' not on PATH)"
        elif [ "$MODE" = "portable" ] && command -v "$bin" >/dev/null 2>&1; then
            rep "  VERIFY OK: $bin present (portable mode, dpkg not authoritative)"
        else
            rep "  VERIFY MISSING: $pkg"
            bad=$((bad+1))
        fi
    done <<< "$checks"
    if [ "$bad" -gt 0 ]; then
        warn "$b application(s) failed verification — see $REPORT"
    else
        say "all mandatory applications verified"
    fi
    rep "  summary verify: $bad problem(s)"
}

estimate_size() {
    # rough download size of pending packages
    local pkgs="$1" est=""
    est="$(apt-get -s install $pkgs 2>/dev/null | grep -oE 'Need to get [0-9.]+ ?[kmg]?B' | tail -1 || true)"
    echo "${est:-size unknown}"
}

# ---------- install phases ----------
install_core_native() {
    say "glibc ${GLIBC} >= 2.38 -> native install (libs from antiX/Debian repos)"
    say "installing runtime libs via apt (see packages/core.txt)"
    apt-get update -qq || true
    # shellcheck disable=SC2046
    apt_install_tolerant $(manifest core.txt "$FALLBACK_CORE")
    say "installing Hyprland binaries + Hypr-family libs to /usr/local"
    for f in Hyprland hyprctl hyprpm; do cp -f "$DEST/bin/$f" /usr/local/bin/; done
    cp -f "$DEST/bin/seatd" /usr/local/bin/seatd
    for l in $HYPRLAND_LIBS; do cp -f "$DEST/lib/$l" /usr/local/lib/; done
    ldconfig
    say "installing pinned xkb/input libs privately + RPATH (system stays untouched)"
    mkdir -p "$PINNED_DIR"
    for l in $PINNED_LIBS; do cp -f "$DEST/lib/$l" "$PINNED_DIR/"; done
    for b in Hyprland hyprctl hyprpm; do
        if patchelf --force-rpath --set-rpath "$PINNED_DIR" "/usr/local/bin/$b" >/dev/null 2>&1; then
            : # RPATH set: only Hyprland resolves the pinned libs
        else
            warn "patchelf failed — using LD_LIBRARY_PATH wrapper for $b"
            mv -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"
            printf '#!/bin/sh\nexport LD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\nexec %s.real "$@"\n' \
                "$PINNED_DIR" "/usr/local/bin/$b" > "/usr/local/bin/$b"
            chmod 755 "/usr/local/bin/$b"
        fi
    done
    # MANDATORY check: every Hyprland library must resolve, else fail loudly
    local MISS
    MISS="$(ldd /usr/local/bin/Hyprland 2>/dev/null | grep -c 'not found' || true)"
    if [ "${MISS:-0}" != "0" ]; then
        die "mandatory dependency check failed: ${MISS} libraries missing. Refusing to continue — run 'apt update' and retry."
    fi
    bash "$DEST/scripts/setup.sh" native "$REAL_USER"
    printf "${G}Hyprland ${VER} installed natively.${R}\n"
}

install_core_portable() {
    warn "glibc ${GLIBC} < 2.38 -> portable install (self-contained bundle)"
    say "host packages (xkb data, xwayland)"
    apt-get update -qq || true
    apt_install_tolerant curl ca-certificates xkb-data xwayland dbus
    bash "$DEST/scripts/setup.sh" portable "$REAL_USER"
    printf "${G}Hyprland ${VER} installed (portable).${R}\n"
}

install_core() {
    download_unpack
    if [ "$MODE" = "native" ]; then install_core_native; else install_core_portable; fi
}

install_app_suite() {
    # complete suite = mandatory + recommended (+ detections); minimal = mandatory only
    say "mandatory desktop applications (packages/apps-mandatory.txt)"
    rep "-- mandatory applications (every one required for a usable desktop) --"
    manifest_install apps-mandatory.txt "$FALLBACK_MANDATORY" mandatory

    if [ "$SUITE" = "complete" ]; then
        say "recommended everyday applications (packages/apps-recommended.txt)"
        rep "-- recommended applications (browser, calculator, fonts, GPU tools) --"
        manifest_install apps-recommended.txt "$FALLBACK_RECOMMENDED" soft
    else
        rep "-- recommended applications SKIPPED (minimal mode; menu option 3 adds them later) --"
    fi

    say "hardware-specific components (audio/network/bluetooth detection)"
    rep "-- hardware detection --"
    install_audio_if_needed
    install_network_if_needed
    install_bluetooth_if_present
    install_firmware_if_available

    install_desktop_entries
    verify_apps
}

generate_report() {
    {
        echo
        echo "== application menu =="
        echo "OVERSHOT entries: $(ls /usr/local/share/applications/overshot-*.desktop 2>/dev/null | wc -l) in /usr/local/share/applications/"
        echo "Package-provided entries: $(ls /usr/share/applications/*.desktop 2>/dev/null | wc -l) in /usr/share/applications/"
        echo "Launch with: Win+Space (wofi application launcher)"
        echo
        echo "== dock (bottom) =="
        grep -o '"modules-center": \[.*\]' /usr/local/share/overshot/config/waybar/dock.jsonc 2>/dev/null || true
        echo
        echo "== still needs REAL HARDWARE testing =="
        echo "  - GPU compositing, animations, multi-monitor (wlr-randr)"
        echo "  - audio output + pavucontrol mixer (speaker/mic test)"
        echo "  - Wi-Fi scan + connect via cmst (if wireless hardware)"
        echo "  - Bluetooth pairing (only when an adapter is present)"
        echo "  - brightness keys (brightnessctl), battery on laptops"
        echo "  - screenshots (grim), screen recording (wf-recorder)"
        echo "  - swaylock, powermenu reboot/shutdown (sudo rights)"
    } >> "$REPORT"
    cp -f "$REPORT" /usr/local/share/overshot/install-report.txt 2>/dev/null || true
    say "install report written to /usr/local/share/overshot/install-report.txt (and $REPORT)"
}

uninstall_all() {
    bash "$DEST/uninstall.sh" 2>/dev/null || {
        # bundle not present (interrupted download): remove the known paths
        say "bundle missing — removing known paths"
        for b in Hyprland hyprctl hyprpm seatd; do rm -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"; done
        rm -f /usr/local/bin/hyprland
        for l in $HYPRLAND_LIBS; do rm -f "/usr/local/lib/$l"; done
        rm -rf "$PINNED_DIR" /usr/local/share/overshot
        for n in powermenu settings dock-toggle perf browser shot doctor benchmark lock record clipboard; do
            rm -f "/usr/local/bin/overshot-$n"
        done
        rm -f /usr/local/share/applications/overshot-*.desktop
        ldconfig
        update-rc.d -f seatd-antix remove >/dev/null 2>&1 || true
        rm -f /etc/init.d/seatd-antix
    }
    printf "${G}removed (apt packages and user configs were left alone).${R}\n"
    printf "Re-run the installer any time to reinstall the suite.\n"
}

# ---------- menu ----------
menu() {
    banner
    printf "Welcome to the ${B}OVERSHOT OS${R} installer (hyprland-antix)\n"
    printf "Detected: glibc ${GLIBC} → ${B}${MODE}${R} mode\n\n"
    printf "  ${B}1)${R}  Complete desktop  (core + full application suite) ${Y}[default]${R}\n"
    printf "  ${B}2)${R}  Minimal install   (core + mandatory apps only)\n"
    printf "  ${B}3)${R}  Applications only (re-run app suite detection)\n"
    printf "  ${B}4)${R}  Uninstall\n"
    printf "  ${B}5)${R}  Doctor\n"
    printf "  ${B}q)${R}  Quit\n\n"
    read -rp "Select an option [1-5/q]: " choice || true
    case "$choice" in
        1) SUITE="complete"; confirm && install_core && install_app_suite && finish ;;
        2) SUITE="minimal";   confirm && install_core && install_app_suite && finish ;;
        3) [ -d "$DEST" ] || die "core not installed yet (menu option 1 first)"
           SUITE="complete"; install_app_suite && finish ;;
        4) read -rp "Really remove hyprland-antix? [y/N] " yn || true
           [[ "${yn:-n}" == "y" || "${yn:-n}" == "Y" ]] && uninstall_all || say "cancelled" ;;
        5) doctor ;;
        q) say "bye" ;;
        *) warn "unknown option"; menu ;;
    esac
}

confirm() {
    read -rp "Complete desktop: installs core + ${B}mandatory${R} apps + browser/fonts (~2 GB download+disk on a bare system). Continue? [Y/n] " yn || true
    [[ "${yn:-y}" == "y" || "${yn:-y}" == "Y" ]] || { say "cancelled"; exit 0; }
}

finish() {
    if [ -f "$DEST/tests/run_tests.sh" ]; then
        say "running smoke tests"
        rep "-- smoke tests --"
        if bash "$DEST/tests/run_tests.sh" | tee -a "$REPORT"; then
            :
        else
            warn "some smoke tests failed — see output above (overshot-doctor for details)"
        fi
    fi
    generate_report
    printf "\n${G}Done.${R} Log out, switch to a TTY console (Ctrl+Alt+F2) and type: ${B}hyprland${R}\n"
    printf "First session gives you: panel, dock, launcher (Win+Space), terminal, files,\n"
    printf "browser, music player, screenshots (Print), lock (Win+L), power menu (Win+Esc).\n"
    printf "Full report: ${B}/usr/local/share/overshot/install-report.txt${R}\n"
    printf "This is a ${Y}private test build${R} — if it breaks, it breaks.\n"
}

# ---------- main ----------
REAL_USER="${SUDO_USER:-}"

case "${1:-}" in
    --doctor)    doctor ;;
    --dry-run)   banner
                 printf "mode: %s (glibc %s)\n" "$MODE" "$GLIBC"
                 printf "suite: %s\n" "$SUITE"
                 printf "would download %s and verify its sha256\n" "$TARBALL"
                 printf "would install: core libs (packages/core.txt)\n"
                 printf "               mandatory apps (packages/apps-mandatory.txt)\n"
                 if [ "$SUITE" = "complete" ]; then
                     printf "               recommended apps (packages/apps-recommended.txt): browser, calculator, fonts\n"
                 fi
                 printf "detections would run: audio stack, network stack, bluetooth, firmware\n"
                 printf "disk free on /: %s MB (complete desktop wants ~2.2 GB)\n" "$(( $(free_kb_root) / 1024 ))"
                 exit 0 ;;
    --minimal)   SUITE="minimal"; NONINT=1 ;;
    --uninstall) [ "$(id -u)" = "0" ] || die "run as root (sudo)"
                 read -rp "Really remove hyprland-antix? [y/N] " yn || true
                 if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
                     uninstall_all
                 else say "cancelled"; fi
                 exit 0 ;;
    --help|-h)   usage; exit 0 ;;
    "")          : ;;
    *)           die "unknown option '$1' (supported: --minimal --doctor --dry-run --uninstall --help)" ;;
esac

# real installs need root; logging to /tmp for support
if [ "$(id -u)" = "0" ]; then
    # log everything to /tmp; process substitution needs /dev/fd (real systems have it)
    if [ -e /dev/fd ]; then
        exec > >(tee -a "/tmp/overshot-install-$(date +%Y%m%d-%H%M%S).log") 2>&1
    fi
else
    die "run as root (sudo)"
fi
[ "$(uname -m)" = "x86_64" ] || die "x86_64 only"
check_disk
report_init

if [ -t 0 ] && [ -t 1 ] && [ -z "${NONINT:-}" ]; then
    menu
else
    # non-interactive (curl | sudo bash): complete desktop by default
    banner
    say "non-interactive mode: ${SUITE} install (${MODE})"
    install_core
    install_app_suite
    finish
fi
