#!/usr/bin/env bash
# hyprland-antix installer — HyDE-style menu
# TESTING BUILD: private test project for the owner. NOT a supported release.
#
# Two install modes, picked automatically:
#   native    (system glibc >= 2.38, e.g. Debian 13 / trixie based antiX):
#             installs all runtime libs from the antiX/Debian repos via apt,
#             installs only the Hypr-family libs + binaries to /usr/local,
#             runs natively (no bundled loader, no shadow copies of system libs).
#   portable  (older glibc, e.g. Debian 12 / bookworm based antiX 23):
#             self-contained bundle with its own loader and libs in /opt.
set -eu

REPO="Bertbikercodes/hyprland-antix"
VER="0.56.2-antix1"
DEST="/opt/hyprland-antix"
TARBALL="hyprland-antix-${VER}-x86_64.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VER}/${TARBALL}"

# libs Hyprland needs from the antiX/Debian repos (native mode)
APT_LIBS="libabsl20240722 libatomic1 libblkid1 libbrotli1 libbz2-1.0 libc6 \
libcairo-gobject2 libcairo2 libcap2 libdatrie1 libdav1d7 libdisplay-info2 libdrm2 \
libegl1 libegl-mesa0 libeis1 libevdev2 libexpat1 libffi8 libfontconfig1 libfreetype6 \
libfribidi0 libgbm1 libgcc-s1 libgdk-pixbuf-2.0-0 libgles2 libglib2.0-0t64 libglvnd0 \
libglx-mesa0 libgl1-mesa-dri libgomp1 libgraphite2-3 libgudev-1.0-0 libharfbuzz0b \
libinput10 libjpeg62-turbo liblcms2-2 liblzma5 libmagic1t64 libmount1 libmtdev1t64 \
libmuparser2v5 libopengl0 libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 \
libpcre2-8-0 libpixman-1-0 libpng16-16t64 libre2-11 librsvg2-2 libseat1 libselinux1 \
libsharpyuv0 libssl3t64 libstdc++6 libsystemd0 libthai0 libtomlplusplus3t64 libudev1 \
libuuid1 libwacom9 libwayland-client0 libwayland-server0 libwebp7 libx11-6 libxau6 \
libxcb-composite0 libxcb-errors0 libxcb-icccm4 libxcb-render0 libxcb-res0 libxcb-shm0 \
libxcb-xfixes0 libxcb1 libxcursor1 libxdmcp6 libxext6 libxfixes3 libxkbcommon0 \
libxkbcommon-x11-0 libxml2 libxrender1 libzip5 libzstd1 zlib1g patchelf \
libreadline8t64 libtinfo6 xkb-data xwayland dbus"

# Hypr-family libs that ship in the bundle (NOT in the Debian repos)
HYPRLAND_LIBS="libaquamarine.so.14 libhyprcursor.so.0 libhyprgraphics.so.4 \
libhyprlang.so.2 libhyprutils.so.13 libhyprwire.so.3"

# libs pinned newer than trixie/antiX ships; installed PRIVATELY in
# /usr/local/lib/hyprland-antix (not in the ldconfig cache) so only Hyprland
# can see them (via RPATH). Everything else keeps using the system libs.
PINNED_LIBS="libxkbcommon.so.0 libinput.so.10"
PINNED_DIR="/usr/local/lib/hyprland-antix"

B="\033[1m"; R="\033[0m"; G="\033[1;32m"; Y="\033[1;33m"; RD="\033[1;31m"

say()    { printf "${G}==>${R} %s\n" "$*"; }
warn()   { printf "${Y}WARNING:${R} %s\n" "$*"; }
die()    { printf "${RD}ERROR:${R} %s\n" "$*" >&2; exit 1; }

banner() {
cat <<'EOF'
 _   _                       _             _       _
| | | | ___ _   _ _ __  __ _| |_ __   ___ | | __ _| |_   _
| |_| |/ _ \ | | | '_ \/ _` | | '_ \ / _ \| |/ _` | | | | |
|  _  |  __/ |_| | | | (_| | | |_) | (_) | | (_| | | |_| |
|_| |_|\___|\__,_|_|  \__,_|_| .__/ \___/|_|\__,_|_|\__, |
                             |_|  testing build     |___/
EOF
printf "${Y}>> PRIVATE TEST BUILD — owner testing only. Not a usable project. <<${R}\n\n"
}

[ "$(id -u)" = "0" ] || die "run as root (sudo)"
[ "$(uname -m)" = "x86_64" ] || die "x86_64 only"
REAL_USER="${SUDO_USER:-}"

# ---------- mode detection ----------
# Hyprland was built against glibc 2.38 symbols.
glibc_version() { ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1; }
ver_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

GLIBC="$(glibc_version)"
if ver_ge "$GLIBC" "2.38"; then
    MODE="native"
else
    MODE="portable"
fi

# ---------- shared ----------
download_unpack() {
    if [ -n "${HYPRLAND_ANTIX_TARBALL:-}" ] && [ -f "${HYPRLAND_ANTIX_TARBALL}" ]; then
        say "using local tarball ${HYPRLAND_ANTIX_TARBALL}"
        if [ "${HYPRLAND_ANTIX_TARBALL}" != "/tmp/${TARBALL}" ]; then
            cp -f "${HYPRLAND_ANTIX_TARBALL}" "/tmp/${TARBALL}"
        fi
    else
        say "downloading ${TARBALL}"
        if command -v curl >/dev/null 2>&1; then
            curl -fL --retry 3 -o "/tmp/${TARBALL}" "$URL" || die "download failed"
        else
            wget -O "/tmp/${TARBALL}" "$URL" || die "download failed"
        fi
    fi
    say "unpacking to ${DEST}"
    rm -rf "$DEST"; mkdir -p "$DEST"
    tar -xzf "/tmp/${TARBALL}" -C "$DEST" --strip-components=1
    rm -f "/tmp/${TARBALL}"
}

apt_install_tolerant() {
    # try the whole list at once; fall back to per-package
    if ! apt-get install -y -qq "$@" >/dev/null 2>&1; then
        for p in "$@"; do
            apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "package '$p' not found — continuing"
        done
    fi
}

# ---------- native mode (antiX on Debian 13 / glibc >= 2.38) ----------
install_core_native() {
    say "glibc ${GLIBC} >= 2.38 -> native install (libs from antiX/Debian repos)"
    say "installing runtime libs via apt (~95 packages incl. mesa drivers)"
    apt-get update -qq || true
    # shellcheck disable=SC2086
    apt_install_tolerant $APT_LIBS
    say "installing Hyprland binaries + Hypr-family libs to /usr/local"
    for f in Hyprland hyprctl hyprpm; do cp -f "$DEST/bin/$f" /usr/local/bin/; done
    ln -sf /usr/local/bin/Hyprland /usr/local/bin/hyprland
    cp -f "$DEST/bin/seatd" /usr/local/bin/seatd
    for l in $HYPRLAND_LIBS; do cp -f "$DEST/lib/$l" /usr/local/lib/; done
    ldconfig
    say "installing pinned xkb/input libs privately + RPATH (system stays untouched)"
    mkdir -p "$PINNED_DIR"
    for l in $PINNED_LIBS; do cp -f "$DEST/lib/$l" "$PINNED_DIR/"; done
    for b in Hyprland hyprctl hyprpm; do
        if patchelf --force-rpath --set-rpath "/usr/local/lib/hyprland-antix" /usr/local/bin/$b >/dev/null 2>&1; then
            : # RPATH set: only Hyprland resolves the pinned libs
        else
            warn "patchelf failed — using LD_LIBRARY_PATH wrapper for $b"
            mv -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"
            printf '#!/bin/sh\nexport LD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\nexec %s.real "$@"\n' \
                "$PINNED_DIR" "/usr/local/bin/$b" > "/usr/local/bin/$b"
            chmod 755 "/usr/local/bin/$b"
        fi
    done
    # keep $DEST only for reference/uninstall; the shadow libs are not on any linker path
    bash "$DEST/scripts/setup.sh" native "$REAL_USER"
    printf "${G}Hyprland ${VER} installed natively.${R}\n"
}

# ---------- portable mode (Debian 12 based antiX 23) ----------
install_core_portable() {
    warn "glibc ${GLIBC} < 2.38 -> portable install (self-contained bundle)"
    say "host packages (xkb data, xwayland)"
    apt-get update -qq || true
    for p in curl ca-certificates xkb-data xwayland; do
        apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "package '$p' not found — continuing"
    done
    bash "$DEST/scripts/setup.sh" portable "$REAL_USER"
    printf "${G}Hyprland ${VER} installed (portable).${R}\n"
}

# ---------- core ----------
install_core() {
    download_unpack
    if [ "$MODE" = "native" ]; then install_core_native; else install_core_portable; fi
}

install_apps() {
    say "recommended Wayland apps (terminal, bar, launcher, screenshots)"
    apt-get install -y -qq foot waybar wofi grim slurp 2>/dev/null \
        || warn "some apps not found in your repos — install them manually"
}

install_extras() {
    say "extras: fonts, cursor theme, GPU tools"
    apt-get install -y -qq fonts-noto-core fonts-symbola 2>/dev/null || true
    apt-get install -y -qq mesa-utils 2>/dev/null || true
}

uninstall_all() {
    say "removing hyprland-antix (native bits in /usr/local, bundle in ${DEST})"
    rm -f /usr/local/bin/Hyprland /usr/local/bin/hyprland /usr/local/bin/hyprctl \
          /usr/local/bin/hyprpm /usr/local/bin/seatd
    for l in $HYPRLAND_LIBS; do rm -f "/usr/local/lib/$l"; done
    for b in Hyprland hyprctl hyprpm; do rm -f "/usr/local/bin/$b" "/usr/local/bin/$b.real"; done
    rm -rf "$PINNED_DIR"
    ldconfig
    update-rc.d -f seatd-antix remove >/dev/null 2>&1 || true
    service seatd-antix stop >/dev/null 2>&1 || true
    rm -f /etc/init.d/seatd-antix
    rm -rf "$DEST"
    say "removed (system packages installed via apt were left alone)"
}

# ---------- HyDE-style menu ----------
menu() {
    banner
    printf "Welcome to the ${B}hyprland-antix${R} installer\n"
    printf "Detected: glibc ${GLIBC} → ${B}${MODE}${R} mode\n\n"
    printf "  ${B}1)${R}  Full install       (Hyprland + apps + extras)\n"
    printf "  ${B}2)${R}  Hyprland core only (compositor, seatd)\n"
    printf "  ${B}3)${R}  Recommended apps   (foot, waybar, wofi, grim, slurp)\n"
    printf "  ${B}4)${R}  Extras             (fonts, themes, mesa-utils)\n"
    printf "  ${B}5)${R}  Uninstall\n"
    printf "  ${B}q)${R}  Quit\n\n"
    read -rp "Select an option [1-5/q]: " choice
    case "$choice" in
        1) confirm && install_core && install_apps && install_extras ;;
        2) confirm && install_core ;;
        3) install_apps ;;
        4) install_extras ;;
        5) read -rp "Really remove hyprland-antix? [y/N] " yn
           [[ "$yn" == "y" || "$yn" == "Y" ]] && uninstall_all || say "cancelled" ;;
        q|*) say "bye"; exit 0 ;;
    esac
}

confirm() {
    if [ "$MODE" = "native" ]; then
        printf "\nThis will ${B}install Hyprland 0.56.2 (test build)${R} natively:\n"
        printf "  • ~95 runtime libs from the antiX/Debian repos (apt)\n"
        printf "  • Hyprland + Hypr libs to /usr/local, a seatd service, 'hyprland' on PATH\n"
        printf "  • NO bundled system libs — your system's own libs are used\n\n"
    else
        printf "\nThis will ${B}install Hyprland 0.56.2 (test build)${R} as a portable bundle in ${DEST},\n"
        printf "add a seatd service and put 'hyprland' on your PATH.\n\n"
    fi
    read -rp "Proceed? [y/N] " yn
    [[ "$yn" == "y" || "$yn" == "Y" ]] || { say "aborted"; exit 0; }
}

if [ -t 0 ]; then
    menu
else
    # piped (curl | bash) or non-interactive: default full install
    banner
    say "non-interactive mode: full install (${MODE})"
    install_core
    install_apps || true
    install_extras || true
fi

printf "\n${G}Done.${R} Start from a TTY console (Ctrl+Alt+F2, not inside X): ${B}hyprland${R}\n"
printf "This is a ${Y}private test build${R} — if it breaks, it breaks.\n"
