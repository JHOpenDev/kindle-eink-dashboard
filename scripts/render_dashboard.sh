#!/bin/bash
# render_dashboard.sh — Mac 端渲染管线
# dashboard.html → Chrome 无头截图 → png2raw.py → dash.raw（供设备拉取）
#
# 用法：
#   ./render_dashboard.sh          # 渲染一次（配合 HTTP 服务 + cron/循环使用）
#   ./render_dashboard.sh --loop   # 每 5 分钟循环渲染
#
# 需要：Google Chrome、Python3 + Pillow + numpy
# 服务：python3 -m http.server 8899 --directory <本目录>（提供 dash.raw 下载）

RENDER_DIR="$(cd "$(dirname "$0")/.." && pwd)/render"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$RENDER_DIR"

render_once() {
  "$CHROME" --headless --disable-gpu --force-device-scale-factor=1 \
    --window-size=1072,1448 --screenshot="$RENDER_DIR/dash.png" \
    --hide-scrollbars --virtual-time-budget=2000 \
    "file://$RENDER_DIR/dashboard.html" 2>/dev/null
  [ -s "$RENDER_DIR/dash.png" ] || { echo "FAIL: screenshot"; return 1; }
  python3 -I "$(dirname "$0")/png2raw.py" "$RENDER_DIR/dash.png" "$RENDER_DIR/dash.raw" \
    && echo "OK: $(date +%T) dash.raw updated"
}

if [ "$1" = "--loop" ]; then
  while true; do
    render_once >> "$RENDER_DIR/render.log" 2>&1
    sleep 300
  done
else
  render_once
fi
