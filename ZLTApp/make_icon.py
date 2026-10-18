#!/usr/bin/env python3
"""Draws the ZLT X28 app icon: a Windows 95-era window with a padlock.

32x32 pixel art, scaled with nearest-neighbour so every size stays crisp.
Full-bleed teal: no transparency anywhere (macOS puts a plinth behind see-through icons).
Outputs Resources/AppIcon.iconset and Resources/AppIcon.icns.
"""
import os
import struct
import subprocess
import sys
import zlib

TEAL = (0, 128, 128)
BLACK = (0, 0, 0)
GRAY = (192, 192, 192)
WHITE = (255, 255, 255)
DARK = (128, 128, 128)
NAVY = (0, 0, 128)
BLUE = (16, 132, 208)
GOLD = (255, 215, 0)
GOLD_HI = (255, 236, 140)
GOLD_LO = (196, 160, 0)
STEEL = (80, 80, 80)

SIZE = 32
art = [[TEAL for _ in range(SIZE)] for _ in range(SIZE)]


def rect(x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            art[y][x] = color


def hline(x0, x1, y, color):
    rect(x0, y, x1, y, color)


def vline(x, y0, y1, color):
    rect(x, y0, x, y1, color)


# --- the window ---
rect(1, 1, 30, 30, BLACK)            # outer frame
rect(2, 2, 29, 29, GRAY)             # body
rect(2, 2, 29, 9, NAVY)              # title bar
hline(2, 29, 9, BLUE)                # its bottom edge
# bevel
vline(2, 10, 29, WHITE)
hline(2, 29, 10, WHITE)
vline(29, 10, 29, DARK)
hline(2, 29, 29, DARK)

# three title-bar buttons
for bx in (18, 22, 26):
    rect(bx, 4, bx + 2, 6, DARK)
    rect(bx, 4, bx + 2, 4, GRAY)
    vline(bx, 5, 6, WHITE)

# "ZLT" in a 3x5 bitmap font, white
font = {
    "Z": ["111", "001", "010", "100", "111"],
    "L": ["100", "100", "100", "100", "111"],
    "T": ["111", "010", "010", "010", "010"],
}
x = 4
for ch in "ZLT":
    for row, bits in enumerate(font[ch]):
        for col, bit in enumerate(bits):
            if bit == "1":
                art[3 + row][x + col] = WHITE
    x += 4

# --- the padlock ---
# shackle: dark outline then steel core
rect(11, 11, 20, 12, BLACK)
rect(10, 12, 11, 18, BLACK)
rect(20, 12, 21, 18, BLACK)
rect(12, 12, 19, 13, STEEL)
rect(11, 13, 12, 17, STEEL)
rect(19, 13, 20, 17, STEEL)

# body: outline, gold, bevel, keyhole
rect(8, 18, 23, 27, BLACK)
rect(9, 19, 22, 26, GOLD)
hline(9, 22, 19, GOLD_HI)
vline(9, 19, 26, GOLD_HI)
hline(9, 22, 26, GOLD_LO)
vline(22, 19, 26, GOLD_LO)
rect(14, 21, 17, 22, BLACK)          # keyhole head
rect(15, 23, 16, 25, BLACK)          # keyhole slot

# --- write PNGs ---
def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def scaled(size):
    return [[art[y * SIZE // size][x * SIZE // size] for x in range(size)]
            for y in range(size)]


here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "Resources")
iconset = os.path.join(out, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)

targets = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}
for name, px in targets.items():
    write_png(os.path.join(iconset, name), scaled(px))

write_png(os.path.join(here, "icon-preview.png"), scaled(512))

icns = os.path.join(out, "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
print("wrote", icns)
