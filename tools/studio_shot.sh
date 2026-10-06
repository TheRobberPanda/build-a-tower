#!/bin/bash
# studio_shot.sh OUT.png : capture the Studio window WITHOUT raising or focusing it.
# Reads Studio's own offscreen image (tools/studio_shot.py), so it works even
# when other windows cover Studio.
w=$(xdotool search --name " - Roblox Studio" | tail -1)
python3 "$(dirname "$0")/studio_shot.py" "$w" "$1"
