#!/usr/bin/env bash
# OVERSHOT OS installer — hyprland-antix / HyDE-style menu
# TESTING BUILD: private test project for the owner. NOT a supported release.
#
# Modes, picked automatically from system glibc:
#   native    (glibc >= 2.38, e.g. Debian 13 / trixie based antiX):
#             runtime libs from the antiX/Debian repos via apt; only the
#             Hypr-family libs + binaries go to /usr/local. No bundled loader.
#   portable  (older glibc, e.g. Debian 12 / bookworm based antiX 23):
#             self-contained bundle with its own loader and libs in /opt.
#
# Flags:  --doctor    read-only diagnostics, exit 1 on problems
#         --dry-run   show the plan, change nothing
#         --uninstall remove all project-owned files (same as menu option 5)
#         --help      usage
set -eu

REPO="Bertbikercodes/hyprland-antix"
VER="0.56.2-antix1"
DEST="/opt/hyprland-antix"
TARBALL="hyprland-antix-${VER}-x86_64.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VER}/${TARBALL}"
CHECKSUM_URL="https://raw.githubusercontent.com/${REPO}/main/checksums/${TARBALL}.sha256"

# fallback lists if the bundle manifests are missing (older bundle)
FALLBACK_CORE="libcairo2 libgbm1 libinput10 libxkbcommon0 libwayland-client0"
FALLBACK_APPS="foot waybar wofi grim slurp dunst swaybg wl-clipboard thunar fonts-font-awesome"

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
                       testing build  |  on antiX
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
    case "$FREE" in ''|*[!0-9]*) warn "cannot determine free disk space"; return ;; esac
    if [ "$FREE" -lt 700000 ]; then
        die "not enough disk space: $((FREE/1024)) MB free on / (need ~700 MB; 1.5 GB recommended)"
    fi
    [ "$FREE" -lt 1500000 ] && warn "only $((FREE/1024)) MB free on / — 1.5 GB recommended"
    return 0
}

usage() {
    cat <<'USAGE'
OVERSHOT OS installer (hyprland-antix) — private test build

  install.sh                  interactive menu (1: Full 2: Core 3: Apps 4: Extras 5: Uninstall)
  install.sh --doctor         read-only diagnostics, exit 1 on problems
  install.sh --dry-run        show the plan, change nothing
  install.sh --uninstall      remove all project-owned files
  curl -fsSL <raw url> | sudo bash            non-interactive full install
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
        # accept "<hash> <filename>" or bare "<hash>"
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
    [ "$SRC" != "${HYPRLAND_ANTIX_TARBALL:-}" ] && [ -n "${HYPRLAND_ANTIX_TARBALL:-}" ] || rm -f "$SRC"
    [ -f "$DEST/bin/Hyprland" ] || die "bundle incomplete (bin/Hyprland missing)"
}

apt_install_tolerant() {
    if ! apt-get install -y -qq "$@" >/dev/null 2>&1; then
        for p in "$@"; do
            apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "package '$p' not found — continuing"
        done
    fi
}

# ---------- native mode ----------
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

# ---------- portable mode ----------
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

install_apps() {
    say "recommended desktop components (see packages/apps.txt)"
    # shellcheck disable=SC2046
    apt_install_tolerant $(manifest apps.txt "$FALLBACK_APPS")
    command -v foot >/dev/null 2>&1    || warn "foot missing — install it manually (no terminal otherwise)"
    command -v waybar >/dev/null 2>&1   || warn "waybar missing — install it manually (no panel/dock)"
    command -v wofi >/dev/null 2>&1     || warn "wofi missing — install it manually (no launcher)"
}

install_extras() {
    say "extras: fonts, GPU tools (see packages/extras.txt)"
    # shellcheck disable=SC2046
    apt_install_tolerant $(manifest extras.txt "fonts-noto-core mesa-utils")
}

install_optional() {
    say "optional components (see packages/optional.txt)"
    # shellcheck disable=SC2046
    apt_install_tolerant $(manifest optional.txt "firefox-esr swaylock")
}

uninstall_all() {
    bash "$DEST/uninstall.sh" 2>/dev/null || {
        # bundle not present (interrupted download): remove the known paths
        say "bundle missing — removing known paths"
        for b in Hyprland hyprctl hyprpm seatd; do rm -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"; done
        rm -f /usr/local/bin/hyprland
        for l in $HYPRLAND_LIBS; do rm -f "/usr/local/lib/$l"; done
        rm -rf "$PINNED_DIR" /usr/local/share/overshot
        for n in powermenu settings dock-toggle perf browser shot doctor benchmark; do
            rm -f "/usr/local/bin/overshot-$n"
        done
        ldconfig
        update-rc.d -f seatd-antix remove >/dev/null 2>&1 || true
        rm -f /etc/init.d/seatd-antix
    }
    printf "${G}removed (apt packages and user configs were left alone).${R}\n"
}

# ---------- menu (1-5, HyDE-style) ----------
menu() {
    banner
    printf "Welcome to the ${B}OVERSHOT OS${R} installer (hyprland-antix)\n"
    printf "Detected: glibc ${GLIBC} → ${B}${MODE}${R} mode\n\n"
    printf "  ${B}1)${R}  Full install       (Hyprland + panel/dock + apps + extras)\n"
    printf "  ${B}2)${R}  Hyprland core only (compositor, seatd, configs)\n"
    printf "  ${B}3)${R}  Recommended apps   (foot, waybar, wofi, dock set)\n"
    printf "  ${B}4)${R}  Extras             (fonts, GPU tools)\n"
    printf "  ${B}5)${R}  Uninstall\n"
    printf "  ${B}q)${R}  Quit\n\n"
    read -rp "Select an option [1-5/q]: " choice || true
    case "$choice" in
        1) confirm && install_core && install_apps && install_extras && post_full ;;
        2) confirm && install_core ;;
        3) install_apps ;;
        4) install_extras ;;
        5) read -rp "Really remove hyprland-antix? [y/N] " yn || true
           [[ "$yn" == "y" || "$yn" == "Y" ]] && uninstall_all || say "cancelled" ;;
        q) say "bye" ;;
        *) warn "unknown option"; menu ;;
    esac
}

confirm() {
    read -rp "This installs ~95 apt packages (native mode). Continue? [Y/n] " yn || true
    [[ "${yn:-y}" == "y" || "${yn:-y}" == "Y" ]] || { say "cancelled"; exit 0; }
}

post_full() {
    local REPLY
    read -rp "Also install optional components (browser, screen lock, audio/bluetooth tools)? [y/N] " yn || true
    case "$yn" in y|Y) install_optional ;; *) say "skipped optional components (menu option 3/4 any time)" ;; esac
    if [ -f "$DEST/tests/run_tests.sh" ]; then
        say "running smoke tests"
        bash "$DEST/tests/run_tests.sh" || warn "some smoke tests failed — see output above (overshot-doctor for details)"
    fi
    printf "${G}Done.${R} Start from a TTY console (Ctrl+Alt+F2, not inside X): ${B}hyprland${R}\n"
    printf "This is a ${Y}private test build${R} — if it breaks, it breaks.\n"
}

# ---------- main ----------
REAL_USER="${SUDO_USER:-}"

case "${1:-}" in
    --doctor)    doctor ;;
    --dry-run)   banner
                 printf "mode: %s (glibc %s)\n" "$MODE" "$GLIBC"
                 printf "would download %s (%s) and verify its sha256\n" "$TARBALL" "$URL"
                 printf "would install core libs via apt from packages/core.txt\n"
                 printf "would copy Hyprland/hyprctl/hyprpm/seatd to /usr/local\n"
                 printf "would install apps from packages/apps.txt, then extras\n"
                 printf "disk free on /: %s MB\n" "$(( $(free_kb_root) / 1024 ))"
                 exit 0 ;;
    --uninstall) [ "$(id -u)" = "0" ] || die "run as root (sudo)"
                 read -rp "Really remove hyprland-antix? [y/N] " yn || true
                 if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
                     # uninstall works without the bundle if needed
                     uninstall_all
                 else say "cancelled"; fi
                 exit 0 ;;
    --help|-h)   usage; exit 0 ;;
    "")          : ;;
    *)           die "unknown option '$1' (supported: --doctor --dry-run --uninstall --help)" ;;
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

if [ -t 0 ] && [ -t 1 ]; then
    menu
else
    # non-interactive (curl | sudo bash): full install
    banner
    say "non-interactive mode: full install (${MODE})"
    install_core
    install_apps
    install_extras
    if [ -f "$DEST/tests/run_tests.sh" ]; then
        say "running smoke tests"
        bash "$DEST/tests/run_tests.sh" || warn "some smoke tests failed — see output above"
    fi
    printf "${G}Done.${R} Start from a TTY console (Ctrl+Alt+F2, not inside X): ${B}hyprland${R}\n"
    printf "This is a ${Y}private test build${R} — if it breaks, it breaks.\n"
fi
