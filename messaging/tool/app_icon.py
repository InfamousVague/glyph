#!/usr/bin/env python3
"""
Ghost Messaging's app icon from one square picture (art/app-icon.png), as Ghost Keyboard's tool/app_icon.py makes its.

Matt, 2026-11-13: "update the icon to use the one from the desktop" (the white ghost that is a speech bubble, on
black, ~/Desktop/ghost_messenger.png).

    python3 tool/app_icon.py ~/Desktop/ghost_messenger.png    copies it to art/app-icon.png, then writes every icon
    python3 tool/app_icon.py                                  writes every icon from art/app-icon.png

Android's adaptive icon (minSdk 29, so no legacy PNGs): the foreground is the picture shrunk so the ghost, its tail
included, sits inside the mask's 66dp safe circle, its black carried on past the edges to the full 108dp, over a black
background; the monochrome layer is the ghost alone (its brightness as alpha), for themed icons. The notification's
small icon is the same shape, white on nothing, cut to its own edges. The site's icons are the full square.
"""

import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, 'art', 'app-icon.png')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
SITE = os.path.join(ROOT, 'site')
# The ghost's farthest point (the tip of its tail) is 39% of the picture from its centre: 42dp of the 108. At 0.74 it is
# 31dp, inside the safe circle's 33.
SCALE = 0.74
BACKGROUND = (0, 0, 0)
DENSITIES = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
# The status bar's icon is 24dp.
SMALL = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}
LANCZOS = Image.Resampling.LANCZOS


def shrunk(picture, size, mode):
    inner = round(size * SCALE)
    small = picture.resize((inner, inner), LANCZOS)
    offset = ((size - inner) // 2, (size - inner) // 2)
    if mode == 'foreground':
        out = Image.new('RGB', (size, size), BACKGROUND)
        out.paste(small, offset)
        return out
    alpha = Image.new('L', (size, size), 0)
    alpha.paste(small.convert('L'), offset)
    out = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def silhouette(picture, size):
    """The ghost alone, white with its brightness as alpha, cut to its own edges and centred in a square of [size]."""
    # What is all but black is nothing: a faint box would show round the ghost wherever it is drawn over a colour.
    grey = picture.convert('L').point(lambda v: 0 if v < 24 else v)
    box = grey.point(lambda v: 255 if v > 40 else 0).getbbox()
    shape = grey.crop(box)
    side = max(shape.size)
    square = Image.new('L', (side, side), 0)
    square.paste(shape, ((side - shape.width) // 2, (side - shape.height) // 2))
    # A little room round it, as the status bar's own icons have.
    inner = round(size * 0.9)
    alpha = Image.new('L', (size, size), 0)
    alpha.paste(square.resize((inner, inner), LANCZOS), ((size - inner) // 2, (size - inner) // 2))
    out = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def main():
    if len(sys.argv) > 1:
        os.makedirs(os.path.dirname(ART), exist_ok=True)
        shutil.copyfile(os.path.expanduser(sys.argv[1]), ART)
    picture = Image.open(ART).convert('RGB')
    for density, size in DENSITIES.items():
        folder = os.path.join(RES, 'mipmap-' + density)
        os.makedirs(folder, exist_ok=True)
        shrunk(picture, size, 'foreground').save(os.path.join(folder, 'ic_launcher_foreground.png'), optimize=True)
        shrunk(picture, size, 'monochrome').save(os.path.join(folder, 'ic_launcher_monochrome.png'), optimize=True)
    for density, size in SMALL.items():
        folder = os.path.join(RES, 'drawable-' + density)
        os.makedirs(folder, exist_ok=True)
        silhouette(picture, size).save(os.path.join(folder, 'ic_stat_ghost.png'), optimize=True)
    # The page: its icon in a browser's tab and on a phone's home screen, and the mark at its top.
    picture.resize((512, 512), LANCZOS).save(os.path.join(SITE, 'icon.png'), optimize=True)
    picture.resize((180, 180), LANCZOS).save(os.path.join(SITE, 'apple-touch-icon.png'), optimize=True)
    # In the app: the mark on the setup screen.
    os.makedirs(os.path.join(ROOT, 'assets', 'art'), exist_ok=True)
    silhouette(picture, 256).save(os.path.join(ROOT, 'assets', 'art', 'ghost-mark.png'), optimize=True)
    print('icons written from', ART)


if __name__ == '__main__':
    main()
