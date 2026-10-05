#!/bin/bash
# studio_shot.sh OUT.png : capture the Studio window WITHOUT raising or focusing it
# (xwd reads it as composited on screen; windows on top of Studio show up too).
w=$(xdotool search --name "Roblox Studio" | tail -1)
tmp=$(mktemp --suffix .xwd)
xwd -id "$w" -silent > "$tmp" && ffmpeg -v error -y -i "$tmp" "$1"
rm -f "$tmp"
