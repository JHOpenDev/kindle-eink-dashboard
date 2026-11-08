#!/usr/bin/env python3
"""dash.png (1072x1448) -> dash.raw (8bpp, stride 1088, Kindle fb format)"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("L")
if img.size != (1072, 1448):
    img = img.resize((1072, 1448), Image.LANCZOS)
arr = np.array(img, dtype=np.uint8)
padded = np.full((1448, 1088), 255, dtype=np.uint8)
padded[:, :1072] = arr
open(dst, "wb").write(padded.tobytes())
