#!/bin/bash
RENDER_DIR="/Users/JH/Documents/ZCode/工具/kindle-jailbreak/render"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --force-device-scale-factor=1 --user-data-dir=/tmp/kindle-render-profile --no-first-run \
  --window-size=1072,1448 --screenshot="$RENDER_DIR/dash.png" \
  --hide-scrollbars --virtual-time-budget=2000 \
  "file://$RENDER_DIR/dashboard.html" 2>/dev/null
[ -s "$RENDER_DIR/dash.png" ] && python3 -I "$RENDER_DIR/png2raw.py" "$RENDER_DIR/dash.png" "$RENDER_DIR/dash.raw" && echo "PNG+RAW OK" || { echo FAIL; exit 1; }
