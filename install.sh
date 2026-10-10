#!/usr/bin/env bash
# hyprland-antix installer — HyDE-style menu
# TESTING BUILD: private test project for the owner. NOT a supported release.
set -eu

REPO="Bertbikercodes/hyprland-antix"
VER="0.56.2-antix1"
DEST="/opt/hyprland-antix"
TARBALL="hyprland-antix-${VER}-x86_64.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VER}/${TARBALL}"

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

# ---------- core ----------
install_core() {
    say "host packages (xkb data, xwayland, seatd if packaged)"
    apt-get update -qq || true
    for p in curl ca-certificates xkb-data xwayland seatd; do
        apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "package '$p' not found in repos — continuing"
    done
    say "downloading ${TARBALL}"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "/tmp/${TARBALL}" "$URL" || die "download failed"
    else
        wget -O "/tmp/${TARBALL}" "$URL" || die "download failed"
    fi
    say "unpacking to ${DEST}"
    rm -rf "$DEST"; mkdir -p "$DEST"
    tar -xzf "/tmp/${TARBALL}" -C "$DEST" --strip-components=1
    rm -f "/tmp/${TARBALL}"
    say "wrapper + seatd service"
    "$DEST/scripts/setup.sh" "$REAL_USER"
    printf "${G}Hyprland ${VER} installed.${R}\n"
}

install_apps() {
    say "recommended Wayland apps (terminal, bar, launcher, screenshots)"
    apt-get install -y -qq foot waybar wofi grim slurp 2>/dev/null \
        || warn "some apps not found in your repos — install them manually"
}

install_extras() {
    say "extras: fonts, cursor theme, GPU tools"
    apt-get install -y -qq fonts-noto-core fonts-symbola adwaita-qt 2>/dev/null || true
    apt-get install -y -qq mesa-utils 2>/dev/null || true
}

uninstall_all() {
    say "removing hyprland-antix"
    rm -rf "$DEST" /usr/local/bin/hyprland
    update-rc.d -f seatd-antix remove >/dev/null 2>&1 || true
    rm -f /etc/init.d/seatd-antix
    service seatd-antix stop >/dev/null 2>&1 || true
    say "removed (system packages from apt were left alone)"
}

# ---------- HyDE-style menu ----------
menu() {
    banner
    printf "Welcome to the ${B}hyprland-antix${R} installer\n\n"
    printf "  ${B}1)${R}  Full install       (Hyprland + apps + extras)\n"
    printf "  ${B}2)${R}  Hyprland core only (compositor, wrapper, seatd)\n"
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
    printf "\nThis will ${B}install Hyprland 0.56.2 (test build)${R} to ${DEST},\n"
    printf "add a seatd service and put 'hyprland' on your PATH.\n\n"
    read -rp "Proceed? [y/N] " yn
    [[ "$yn" == "y" || "$yn" == "Y" ]] || { say "aborted"; exit 0; }
}

if [ -t 0 ]; then
    menu
else
    # piped (curl | bash) or non-interactive: default full install
    banner
    say "non-interactive mode: full install"
    confirm_y="y"
    install_core
    install_apps || true
    install_extras || true
fi

printf "\n${G}Done.${R} Start from a TTY console (Ctrl+Alt+F2, not inside X): ${B}hyprland${R}\n"
printf "This is a ${Y}private test build${R} — if it breaks, it breaks.\n"
