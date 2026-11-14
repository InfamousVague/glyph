#!/usr/bin/env python3
"""
Ghost Messaging's app icon from one square picture (art/app-icon.png), as Ghost Keyboard's tool/app_icon.py makes its.

Matt, 2026-11-13: "update the icon to use the one from the desktop" (the white ghost that is a speech bubble, on
black, ~/Desktop/ghost_messenger.png).

    python3 tool/app_icon.py ~/Desktop/ghost_messenger.png    copies it to art/app-icon.png, then writes every icon
    python3 tool/app_icon.py                                  writes every icon from art/app-icon.png
    python3 tool/app_icon.py --check <the built Mac app>      says whether macOS will draw its icon whole (mac_icon)

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


def mac_shape(side):
    """
    The outline of a macOS icon, [side] across, as a mask (white inside): a superellipse, |x|^5 + |y|^5 = 1,
    measured from Ghost.md's Mac icon (it fits to under two pixels in 824). It is how the icon looks on a macOS
    that masks nothing itself; it is not what keeps the icon off a plate (see mac_icon).
    """
    import math
    from PIL import ImageDraw
    big = 4
    s = side * big
    half = s / 2
    steps = 720
    outline = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, n = math.cos(t), math.sin(t)
        # The point of the superellipse in the direction t: each coordinate's sign, and its size to the 2/5.
        outline.append((half + half * math.copysign(abs(c) ** 0.4, c), half + half * math.copysign(abs(n) ** 0.4, n)))
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    return mask.resize((side, side), LANCZOS)


# The least blue anything in the Mac icon has: its black is (0, 0, 2), which no eye tells from black.
MAC_TINT = 2


def mac_icon(picture, size):
    """
    The picture as a macOS icon: 824 of the 1024 across, in the outline above, with a soft shadow under it.

    Matt, 2026-11-13: "the icon on the mac app is also not full width and height, it's inset". macOS 27 drew it
    small on a grey plate of its own. The cause was not the outline (three were tried, and a plain square too):
    this picture is black and white and nothing else, Xcode's asset catalog stores a picture with no colour in it
    as greyscale ("Monochrome"), and macOS puts a greyscale icon on a plate. With one pixel that is not grey the
    catalog stores it as colour and macOS draws it whole, in any outline. So the black here carries [MAC_TINT] of
    blue, and main() refuses to write a Mac icon that is all grey.

    The test is the app as built, since an .icns beside it is not read: `python3 tool/app_icon.py --check
    "build/macos/Build/Products/Release/Ghost Messaging.app"` says how its catalog stored the icon, and
    `NSWorkspace.shared.icon(forFile:)` on it is what the Dock draws.
    """
    from PIL import ImageFilter
    work, inner = 1024, 824
    at = (work - inner) // 2
    mask = mac_shape(inner)
    # The shadow: the shape, a little lower, blurred, at a third of black.
    shadow = Image.new('L', (work, work), 0)
    shadow.paste(mask, (at, at + 12))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.3))
    out = Image.new('RGBA', (work, work), (0, 0, 0, 0))
    out.putalpha(shadow)
    out.paste(picture.convert('RGB').resize((inner, inner), LANCZOS), (at, at), mask)
    if size != work:
        out = out.resize((size, size), LANCZOS)
    # The tint last, at the size it is kept at: shrinking would round some of it away.
    red, green, blue, alpha = out.split()
    return Image.merge('RGBA', (red, green, blue.point(lambda v: max(v, MAC_TINT)), alpha))


def has_colour(icon):
    """Whether any pixel of [icon] that is not clear is not grey: what the asset catalog needs to keep it as colour."""
    red, green, blue, alpha = icon.convert('RGBA').split()
    solid = alpha.point(lambda v: 255 if v == 255 else 0)
    from PIL import ImageChops
    return ImageChops.multiply(ImageChops.difference(red, blue), solid).getbbox() is not None or \
        ImageChops.multiply(ImageChops.difference(red, green), solid).getbbox() is not None


def check_built(app):
    """How the built Mac app's asset catalog stored its icon: every size must be colour (see mac_icon)."""
    import json
    import subprocess
    car = os.path.join(app, 'Contents', 'Resources', 'Assets.car')
    rows = json.loads(subprocess.run(['xcrun', 'assetutil', '--info', car], capture_output=True, text=True, check=True).stdout)
    icons = [r for r in rows if r.get('AssetType') == 'Icon Image']
    grey = [r for r in icons if r.get('ColorModel') != 'RGB']
    for r in icons:
        print(f"{r.get('PixelWidth')}px @{r.get('Scale')}x: {r.get('ColorModel')}")
    if not icons or grey:
        raise SystemExit('the Mac icon is stored as greyscale: macOS will draw it small on a plate' if grey else 'no icon in ' + car)
    print('the Mac icon is stored as colour in', car)


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
    if len(sys.argv) > 2 and sys.argv[1] == '--check':
        return check_built(sys.argv[2])
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
        icon = mac_icon(picture, size)
        if not has_colour(icon):
            raise SystemExit(f'the Mac icon at {size} is all grey: macOS would draw it small on a plate (mac_icon)')
        icon.save(os.path.join(MAC, f'app_icon_{size}.png'), optimize=True)
    print('icons written from', ART)


if __name__ == '__main__':
    main()
