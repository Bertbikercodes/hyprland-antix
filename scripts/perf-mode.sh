#!/bin/sh
# OVERSHOT OS — toggle performance mode.
# ON: disables animations + blur + shadows (written to user-overrides.conf,
# which is sourced last, so it wins over theme.conf).
# OFF: restores the default theme.
CONF="$HOME/.config/hypr/user-overrides.conf"

if [ -f "$CONF" ] && grep -q "overshot-perf" "$CONF" 2>/dev/null; then
    : > "$CONF"
    printf 'Performance mode OFF — full visuals restored.\n'
else
    cat > "$CONF" <<'EOF'
# overshot-perf: performance mode (overshot-perf toggles this file)
animations {
    enabled = false
}
decoration {
    shadow {
        enabled = false
    }
    blur {
        enabled = false
    }
}
EOF
    printf 'Performance mode ON — animations/blur/shadows disabled.\n'
fi
hyprctl reload >/dev/null 2>&1 || true
