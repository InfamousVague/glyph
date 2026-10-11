#!/usr/bin/env python3
"""
The Mac's own app icon, from the square picture every other platform uses (design/app-icon.png).

macOS draws an app's icon as it is: it doesn't cut it to a rounded shape the way iOS and Android do. A full-square
picture shows its square corners inside the Dock's space for it (Matt: "The icon on Mac is a square with no bleed so I
see the corners of the image on the app icon container"). So the Mac gets the picture as Apple's grid lays one out: on a
1024 canvas, an 824 squircle in the middle with clear corners around it and a soft shadow under it, the size and shape
of every other icon in the Dock.

Writes design/app-icon-macos.png and src-tauri/icons/icon.icns, which tauri.conf.json lists, so the bundler uses it
rather than making an icns of its own from the square PNGs. Run it again after `npx tauri icon design/icon.json`, which
writes a square icon.icns over this one.

    python3 scripts/mac-icon.py
"""

import os
import shutil
import subprocess
import tempfile
from math import copysign, cos, pi, sin

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'design', 'app-icon.png')
OUT_PNG = os.path.join(ROOT, 'design', 'app-icon-macos.png')
OUT_ICNS = os.path.join(ROOT, 'src-tauri', 'icons', 'icon.icns')

CANVAS = 1024
# Apple's grid for a Mac app icon: the body is 824 of the 1024, centred, with room round it for the shadow.
BODY = 824
# The body's shape: a superellipse, |x|^n + |y|^n = 1, close to Apple's continuous-corner rounded square.
EXPONENT = 5
# The shadow: straight down a little, soft, faint, as the Dock's own icons have it.
SHADOW_Y = 10
SHADOW_BLUR = 12
SHADOW_ALPHA = 0.3
# The mask is drawn this much larger and brought down, for a smooth edge.
SUPERSAMPLE = 4


def squircle_mask(size: int, exponent: float) -> Image.Image:
    big = size * SUPERSAMPLE
    half = big / 2
    points = []
    steps = 720
    for i in range(steps):
        t = 2 * pi * i / steps
        c, s = cos(t), sin(t)
        x = half + half * copysign(abs(c) ** (2 / exponent), c)
        y = half + half * copysign(abs(s) ** (2 / exponent), s)
        points.append((x, y))
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    picture = Image.open(SOURCE).convert('RGBA').resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY, EXPONENT)
    body = Image.new('RGBA', (BODY, BODY), (0, 0, 0, 0))
    body.paste(picture, (0, 0), mask)

    offset = (CANVAS - BODY) // 2
    shadow_alpha = Image.new('L', (CANVAS, CANVAS), 0)
    shadow_alpha.paste(mask, (offset, offset + SHADOW_Y))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    shadow_alpha = shadow_alpha.point(lambda v: int(v * SHADOW_ALPHA))
    icon = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.putalpha(shadow_alpha)
    icon.alpha_composite(body, (offset, offset))
    icon.save(OUT_PNG)

    # The icns: every size macOS asks for, each drawn down from the 1024.
    work = tempfile.mkdtemp()
    iconset = os.path.join(work, 'icon.iconset')
    os.mkdir(iconset)
    try:
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                name = f'icon_{points}x{points}{"@2x" if scale == 2 else ""}.png'
                icon.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(iconset, name))
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', OUT_ICNS], check=True)
    finally:
        shutil.rmtree(work)
    print(f'wrote {os.path.relpath(OUT_PNG, ROOT)} and {os.path.relpath(OUT_ICNS, ROOT)}')


if __name__ == '__main__':
    main()
