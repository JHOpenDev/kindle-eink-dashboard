#!/usr/bin/env python3
# 渲染 Kindle 息屏图（微信读书 App 的自定义屏保）：1072×1448 白底黑字。
# 输出 render/sleep.png，部署到设备 /mnt/us/weread/sleep.png。
# 想换自己的图：随便做一张 1072×1448 的 PNG 覆盖设备上的 sleep.png 即可。
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

W, H = 1072, 1448
FONT = Path(__file__).resolve().parent.parent / "downloads/weread-kindle/kindle/fonts/WRSans-Medium.otf"
OUT = Path(__file__).resolve().parent.parent / "render/sleep.png"

img = Image.new("L", (W, H), 255)
d = ImageDraw.Draw(img)

# 主文案「休 息 中」
f_main = ImageFont.truetype(str(FONT), 150)
main = "休 息 中"
w = d.textlength(main, font=f_main)
d.text(((W - w) / 2, 600), main, font=f_main, fill=0)

# 分隔短线
d.line([(W / 2 - 90, 850), (W / 2 + 90, 850)], fill=0, width=3)

# 提示语
f_hint = ImageFont.truetype(str(FONT), 44)
hint = "按电源键继续阅读"
hw = d.textlength(hint, font=f_hint)
d.text(((W - hw) / 2, 900), hint, font=f_hint, fill=120)

img.save(OUT)
print(f"OK {OUT} ({OUT.stat().st_size} bytes)")
