#!/bin/sh
# OVERSHOT OS — benchmark / measurement script.
# MEASURED: live RSS of desktop components, free RAM, process count, uptime.
# Values marked ESTIMATE are rough indications, not measurements.
OUT="${1:-/tmp/overshot-benchmark.txt}"

{
echo "OVERSHOT OS benchmark — $(date)"
echo "host: $(uname -sr)  arch: $(uname -m)"
echo "cpu:  $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
echo "ram:  $(free -m | awk '/Mem:/ {print $2 " MB total, " $7 " MB available"}')"
echo
echo "-- MEASURED: RSS (MB) of running desktop components --"
for p in Hyprland waybar swaybg dunst foot wofi; do
    RSS=$(ps -eo rss,comm 2>/dev/null | awk -v n="$p" '$2 == n {s+=$1} END {printf "%.1f", s/1024}')
    [ -n "$RSS" ] && [ "$RSS" != "0.0" ] && printf '%-12s %s MB\n' "$p" "$RSS" || printf '%-12s not running\n' "$p"
done
echo
echo "-- MEASURED: background process count --"
echo "total processes: $(ps -e 2>/dev/null | tail -n +2 | wc -l)"
echo "user processes:  $(ps -u "${SUDO_USER:-$USER}" 2>/dev/null | tail -n +2 | wc -l)"
echo
echo "-- MEASURED: session uptime --"
echo "uptime: $(uptime 2>/dev/null | sed 's/.*up //; s/,.*load.*//')"
echo
echo "-- ESTIMATES (not measured here) --"
echo "login->desktop latency and compositor frame timing need a real session;"
echo "measure with: 'time hyprland' quick-exit or hyprctl plugin profiling."
} | tee "$OUT"

echo "report written to $OUT"
