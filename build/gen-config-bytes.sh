#!/bin/sh
# hyprland-antix: generates DefaultConfigBytes.hpp from example/hyprland.lua
# (replaces C++26 #embed, which gcc-15 does not implement)
# usage: gen-config-bytes.sh /path/to/hyprland-src > DefaultConfigBytes.hpp
SRC="$1/example/hyprland.lua"
echo "#pragma once"
echo "// hyprland-antix: generated replacement for C++26 #embed (gcc-14/15 lack it)"
python3 -c "
import sys
data = open('$SRC','rb').read()
print('inline constexpr char EXAMPLE_CONFIG_BYTES_LUA[] = {' + ','.join('0x%02x'%b for b in data) + '};')
"
