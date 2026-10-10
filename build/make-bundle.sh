#!/bin/bash
# make-bundle.sh — assemble the portable hyprland-antix tarball from the
# trixie buildroot. Runs INSIDE the chroot: paths are chroot-relative.
set -eu
DEST=/bundle
rm -rf $DEST && mkdir -p $DEST/bin $DEST/lib $DEST/share $DEST/scripts

copy_libs() {  # $1 = elf binary; recursive ldd closure, skip libudev (host eudev)
    local queue=("$1"); local seen=""
    while [ ${#queue[@]} -gt 0 ]; do
        local bin="${queue[0]}"; queue=("${queue[@]:1}")
        case " $seen " in *" $bin "*) continue;; esac
        seen="$seen $bin "
        local deps
        deps=$(ldd "$bin" 2>/dev/null | awk '/=> \//{print $3} /^\s*\//{print $1}' | sort -u) || true
        for d in $deps; do
            [ -f "$d" ] || continue
            local base=$(basename "$d")
            case "$base" in libudev.so*) continue;; esac
            if [ ! -f $DEST/lib/$base ]; then
                cp -L "$d" $DEST/lib/
                queue+=("$d")
            fi
        done
    done
}

for b in /usr/local/bin/Hyprland /usr/local/bin/hyprctl /usr/local/bin/hyprpm; do
    [ -f "$b" ] && cp "$b" $DEST/bin/ && copy_libs "$b"
done

# libgcc_s, ld.so: required by the loader trick
cp -L /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 $DEST/lib/ 2>/dev/null || cp -L /lib64/ld-linux-x86-64.so.2 $DEST/lib/
[ -f $DEST/lib/libgcc_s.so.1 ] || cp -L /lib/x86_64-linux-gnu/libgcc_s.so.1 $DEST/lib/

# mesa EGL vendor lib (dlopen'd by glvnd, invisible to ldd) + its deps
cp -L /usr/lib/x86_64-linux-gnu/libEGL_mesa.so.0 $DEST/lib/ 2>/dev/null && copy_libs /usr/lib/x86_64-linux-gnu/libEGL_mesa.so.0

# mesa DRI drivers (hardware + llvmpipe fallback)
mkdir -p $DEST/lib/dri
cp -L /usr/lib/x86_64-linux-gnu/dri/*_dri.so $DEST/lib/dri/ 2>/dev/null || true
for d in $DEST/lib/dri/*.so; do copy_libs "$d"; done

# EGL vendor json (mesa)
mkdir -p $DEST/share/glvnd/egl_vendor.d
cp /usr/share/glvnd/egl_vendor.d/50_mesa.json $DEST/share/glvnd/egl_vendor.d/ 2>/dev/null || true

# seatd static daemon + setup script come from the host side, already staged
echo "bundle assembled:"
du -sh $DEST $DEST/bin $DEST/lib
