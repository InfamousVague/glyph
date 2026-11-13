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
MAC = os.path.join(ROOT, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
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


def _corner(r):
    """One corner of Apple's rounded square, from where it leaves the top edge to where it joins the side: three
    curves that ease into the straight edges (what UIBezierPath draws, measured by PaintCode), as points for a
    corner at the top right with the edge's end at (0, 0), x leftwards and y downwards, in units of [r]."""
    curves = [
        ((1.528665, 0), (1.08849296, 0), (0.86840694, 0), (0.63149379, 0.07491139)),
        ((0.63149379, 0.07491139), (0.37282383, 0.16905956), (0.16905956, 0.37282383), (0.07491139, 0.63149379)),
        ((0.07491139, 0.63149379), (0, 0.86840694), (0, 1.08849296), (0, 1.528665)),
    ]
    points = []
    for p0, p1, p2, p3 in curves:
        for i in range(25):
            t = i / 24
            u = 1 - t
            points.append((
                (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0]) * r,
                (u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]) * r,
            ))
    return points


def mac_shape(side, radius):
    """Apple's rounded square, [side] across with corners of [radius], as a mask: white inside."""
    from PIL import ImageDraw
    big = 4
    s, r = side * big, radius * big
    c = _corner(r)
    outline = (
        [(s - x, y) for x, y in c]                      # top right, going down the right side
        + [(s - y, s - x) for x, y in c]                # bottom right
        + [(x, s - y) for x, y in c]                    # bottom left
        + [(y, x) for x, y in c]                        # top left
    )
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    return mask.resize((side, side), LANCZOS)


def mac_icon(picture, size):
    """
    The picture as a macOS icon (Matt, 2026-11-13: "the icon on the mac app is also not full width and height, it's
    inset"). macOS (26 and later) fills its own icon shape only with an icon whose outline is Apple's: 824 of the
    1024 across, the corners eased into the edges, a soft shadow under it. Anything else (a plain square edge to
    edge, or corners that are arcs of a circle, which is what this drew first) it shrinks onto a plate of its own,
    which is the inset. Ghost.md's Mac icon has this outline, and is drawn whole.
    """
    from PIL import ImageFilter
    work, inner, radius = 1024, 824, 185.4
    at = (work - inner) // 2
    mask = mac_shape(inner, radius)
    # The shadow: the shape, a little lower, blurred, at a third of black.
    shadow = Image.new('L', (work, work), 0)
    shadow.paste(mask, (at, at + 12))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.3))
    out = Image.new('RGBA', (work, work), (0, 0, 0, 0))
    out.putalpha(shadow)
    out.paste(picture.convert('RGB').resize((inner, inner), LANCZOS), (at, at), mask)
    return out if size == work else out.resize((size, size), LANCZOS)


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
    # The Mac app's icon (macos/, the desktop companion), in the outline macOS draws whole (mac_icon).
    for size in (16, 32, 64, 128, 256, 512, 1024):
        mac_icon(picture, size).save(os.path.join(MAC, f'app_icon_{size}.png'), optimize=True)
    print('icons written from', ART)


if __name__ == '__main__':
    main()
