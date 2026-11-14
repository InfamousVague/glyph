#!/usr/bin/env python3
"""
The effects' characters, moving (Matt, 2026-11-13: "I'm adding animated versions of each asset soon", "6 frame
animations for each asset in a sprite sheet", then "Wire up the animated pack from the desktop").

    python3 tool/effect_frames.py [folder]        (the folder is ~/Desktop/Animated where none is given)

A sheet is one character of one effect doing one thing: `<effect>_r1c<n> · <what it does>.png`, a square picture on
a clear background with six frames of the motion in three columns and two rows, read left to right, top to bottom.
`r1c<n>` is the character's place on the effect's still sheet (row 1, column n), which is `<effect>-h<n>.webp` in
assets/effects/ (tool/effect_sprites.py), so the moving one takes the still one's place.

Each sheet becomes a strip, `assets/effects/<effect>-h<n>-f6.webp`: its six frames side by side, every frame cut to
the same box (the box all six fit in, so what moves is the drawing and not the cut), 256 pixels on its longer side. The app steps through the strip as the character flies (lib/effects.dart, EffectSprites). A
character with no sheet keeps its still picture.

Also written: build/effect-frames/<effect>.png, each effect's strips one under another, to look over.
The sheets themselves are not kept in the repository: at 227 MB they stay where Matt made them.
"""

import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'effects')
LOOK = os.path.join(ROOT, 'build', 'effect-frames')
COLUMNS, ROWS = 3, 2
FRAMES = COLUMNS * ROWS
SIDE = 256          # pixels: a frame's longer side (a still sprite's is 300; these are six to a character)
SOLID = 24          # alpha above this is part of the drawing
NAME = re.compile(r'^([A-Za-z]+)_r1c(\d)\b')
LANCZOS = Image.Resampling.LANCZOS


def strip(path):
    """The six frames of the sheet at [path], each cut to the one box that holds them all, side by side."""
    sheet = Image.open(path).convert('RGBA')
    alpha = np.array(sheet)[:, :, 3]
    height, width = alpha.shape
    cw, ch = width / COLUMNS, height / ROWS
    cells = []
    for row in range(ROWS):
        for column in range(COLUMNS):
            box = (round(column * cw), round(row * ch), round((column + 1) * cw), round((row + 1) * ch))
            cells.append(sheet.crop(box))
    left = top = 10 ** 9
    right = bottom = 0
    for cell in cells:
        ys, xs = np.where(np.array(cell)[:, :, 3] > SOLID)
        if len(xs) == 0:
            raise ValueError('a frame with nothing in it')
        left, top = min(left, xs.min()), min(top, ys.min())
        right, bottom = max(right, xs.max() + 1), max(bottom, ys.max() + 1)
    pad = 3
    box = (max(0, left - pad), max(0, top - pad), min(cells[0].width, right + pad), min(cells[0].height, bottom + pad))
    w, h = box[2] - box[0], box[3] - box[1]
    scale = SIDE / max(w, h)
    fw, fh = max(1, round(w * scale)), max(1, round(h * scale))
    out = Image.new('RGBA', (fw * FRAMES, fh), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        out.paste(cell.crop(box).resize((fw, fh), LANCZOS), (i * fw, 0))
    return out


def main():
    folder = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/Desktop/Animated')
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(LOOK, exist_ok=True)
    made = {}
    for name in sorted(os.listdir(folder)):
        m = NAME.match(name)
        if not m or not name.lower().endswith('.png'):
            continue
        effect, hero = m.group(1), int(m.group(2))
        if not os.path.exists(os.path.join(OUT, f'{effect}-h{hero}.webp')):
            print(f'  {name}: there is no still {effect}-h{hero}.webp for it to take the place of; left out')
            continue
        frames = strip(os.path.join(folder, name))
        frames.save(os.path.join(OUT, f'{effect}-h{hero}-f{FRAMES}.webp'), quality=78, method=6)
        made.setdefault(effect, []).append((hero, frames))
    total = 0
    for effect, strips in sorted(made.items()):
        strips.sort(key=lambda s: s[0])
        look = Image.new('RGBA', (max(s.width for _, s in strips), sum(s.height for _, s in strips)), (40, 40, 48, 255))
        y = 0
        for _, s in strips:
            look.alpha_composite(s, (0, y))
            y += s.height
        look.save(os.path.join(LOOK, f'{effect}.png'))
        total += len(strips)
        print(f'{effect}: {", ".join("h" + str(h) for h, _ in strips)}')
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if re.search(r'-h\d+-f\d+\.webp$', f))
    print(f'{total} strips in {OUT}, {size / 1024 / 1024:.1f} MB; pictures of them in {LOOK}')


if __name__ == '__main__':
    main()
