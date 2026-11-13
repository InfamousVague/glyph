#!/usr/bin/env python3
"""
Ghost.md's app icons, every set the releases ship, from one square picture (design/app-icon.png in tauri/).

Matt, 2026-11-13: "update and release the new app icons" (the white ghost on black, ~/Desktop/ghost_markdown.png).

    python3 tool/app_icons.py ~/Desktop/ghost_markdown.png
    (cd tauri && npx tauri icon design/icon.json && python3 scripts/mac-icon.py)
    python3 tool/app_icons.py --flutter-only

The first run writes the source pictures (tauri/design/app-icon.png, the adaptive foreground) and every Flutter,
web and landing icon; the Tauri step makes the Windows/Mac/Tauri sets and the Mac's squircle
(tauri/design/app-icon-macos.png), which the last run copies into the Flutter Mac app.

Android's adaptive icon: the foreground is the ghost alone (white, its eyes cut through) on a clear 108dp canvas,
shrunk so its corners sit inside the 66dp safe circle every mask keeps; the background is black; the same layer is
the monochrome one that themed icons tint.
"""

import json
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.join(ROOT, 'tauri', 'design')
SOURCE = os.path.join(DESIGN, 'app-icon.png')
FOREGROUND = os.path.join(DESIGN, 'app-icon-foreground.png')
MAC_SQUIRCLE = os.path.join(DESIGN, 'app-icon-macos.png')
BACKGROUND = '#000000'
# The ghost on the 108dp canvas, as a share of the source's framing: its corners reach 40dp from the centre at 1.0.
FOREGROUND_SCALE = 0.78
# A maskable web icon keeps a circle of 80% of its width.
MASKABLE_SCALE = 0.9

LANCZOS = Image.Resampling.LANCZOS


def square(src, size):
    return src.resize((size, size), LANCZOS)


def ghost_layer(src, scale, size):
    """The ghost alone, white with its luminance as alpha, scaled about the centre onto a clear square."""
    big = src.convert('L')
    side = big.width
    inner = round(side * scale)
    shape = big.resize((inner, inner), LANCZOS)
    alpha = Image.new('L', (side, side), 0)
    alpha.paste(shape, ((side - inner) // 2, (side - inner) // 2))
    layer = Image.new('RGBA', (side, side), (255, 255, 255, 0))
    layer.putalpha(alpha)
    return layer.resize((size, size), LANCZOS)


def on_black(layer):
    out = Image.new('RGBA', layer.size, BACKGROUND)
    out.alpha_composite(layer)
    return out


def masked(img, radius_share):
    """The picture cut to a rounded square (radius_share of the side; 0.5 is a circle), drawn 4x for a smooth edge."""
    size = img.width
    big = size * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=round(big * radius_share), fill=255)
    out = img.convert('RGBA')
    out.putalpha(mask.resize((size, size), LANCZOS))
    return out


def save(img, path, opaque=False):
    if opaque:
        img = img.convert('RGB')
    img.save(path, optimize=True)
    print('wrote', os.path.relpath(path, ROOT), img.size[0])


def each_png(folder):
    for name in sorted(os.listdir(folder)):
        if name.endswith('.png'):
            path = os.path.join(folder, name)
            with Image.open(path) as old:
                yield name, path, old.width


def flutter_mac():
    squircle = Image.open(MAC_SQUIRCLE).convert('RGBA')
    for _, path, size in each_png(os.path.join(ROOT, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')):
        save(square(squircle, size), path)


def main():
    if '--flutter-only' in sys.argv:
        flutter_mac()
        return
    picture = Image.open(os.path.expanduser(sys.argv[1])).convert('RGB')
    src = square(picture, 1024) if picture.width != 1024 else picture

    # The sources the Tauri bundler reads (design/icon.json).
    save(src, SOURCE, opaque=True)
    save(ghost_layer(picture, FOREGROUND_SCALE, 1024), FOREGROUND)
    with open(os.path.join(DESIGN, 'icon.json'), 'w') as f:
        json.dump({'default': 'app-icon.png', 'bg_color': BACKGROUND, 'android_fg': 'app-icon-foreground.png',
                   'android_fg_scale': 100}, f, indent=2)
        f.write('\n')

    # Android, the phone app.
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
        folder = os.path.join(res, 'mipmap-' + density)
        for name, path, size in each_png(folder):
            if name == 'ic_launcher_foreground.png':
                save(ghost_layer(picture, FOREGROUND_SCALE, size), path)
            elif name == 'ic_launcher_round.png':
                save(masked(square(picture, size), 0.5), path)
            else:
                save(square(picture, size), path)
    with open(os.path.join(res, 'values', 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                f'  <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n')
    with open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '  <background android:drawable="@color/ic_launcher_background"/>\n'
                '  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '  <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')

    # Android, the watch app: a rounded square and a circle, as before.
    wear = os.path.join(ROOT, 'android', 'wear', 'src', 'main', 'res')
    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
        for name, path, size in each_png(os.path.join(wear, 'mipmap-' + density)):
            save(masked(square(picture, size), 0.5 if 'round' in name else 0.18), path)

    # iOS: full squares without alpha (App Store Connect refuses an icon with one).
    for _, path, size in each_png(os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')):
        save(square(picture, size), path, opaque=True)

    # The web app.
    web = os.path.join(ROOT, 'web')
    for name, path, size in each_png(os.path.join(web, 'icons')):
        if 'maskable' in name:
            save(on_black(ghost_layer(picture, MASKABLE_SCALE, size)), path, opaque=True)
        else:
            save(square(picture, size), path, opaque=name.startswith('apple'))
    if os.path.exists(os.path.join(web, 'favicon.png')):
        with Image.open(os.path.join(web, 'favicon.png')) as old:
            save(square(picture, old.width), os.path.join(web, 'favicon.png'))

    # ghostmarkdown.com.
    landing = os.path.join(ROOT, 'landing')
    for name in ('icon.png', 'favicon.png', 'apple-touch-icon.png'):
        path = os.path.join(landing, name)
        with Image.open(path) as old:
            size = old.width
        save(square(picture, size), path, opaque=name.startswith('apple'))

    if os.path.exists(MAC_SQUIRCLE):
        print('(run the Tauri step, then --flutter-only for the Mac app)')


if __name__ == '__main__':
    main()
