#!/usr/bin/env python3
"""
Makes the app's sticker packs (lib/stickers.dart) from the ghost drawn for the message effects.

Matt, 2026-11-13: "generate 4 sticker packs using our ghost mascot we've developed including a sanrio one".

    python3 tool/sticker_packs.py
    python3 tool/sticker_packs.py mischief="~/Desktop/Mischief sticker sheet.png"     keeps a pack's own sheet, then makes all

The ghost's poses are the characters on the effects' sheets (art/effects/, cut by tool/effect_sprites.py, whose
cutting this uses at the sheets' full size). A sticker is one pose with a sticker's white edge round it, on a clear
square. Four packs, sixteen each:

    ghost   the everyday ones: hello, boo, wow, sorry, coffee, asleep
    love    hearts, kisses, flowers
    party   confetti, balloons, fireworks, music
    sweet   the pastel one: the ghost in soft pink, lilac, mint, butter and sky, with little hearts, flowers and
            sparkles. It is our own ghost in the cute pastel manner Matt asked for by naming Sanrio; none of Sanrio's
            characters, names or drawings are in it, since those are Sanrio's and not ours to ship.

A fifth pack is drawn for itself and not made from the effects (Matt, 2026-11-13: "sliced ... the sticker pack
from the desktop"): **mischief**, the dark-cute one, our ghost with little horns and a heart-tipped tail in black,
purple and hot pink. Its sheet is sixteen stickers, four across and four down, kept in art/stickers/mischief.webp
(nothing drawn is lost, the background remover's halo cleared) and cut by shape (effect_sprites.cut_grid).

Written to assets/stickers/<pack>/01.webp…, and to build/stickers/, one picture of each pack to look over.
A pack's order here is its order in the app.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import effect_sprites  # noqa: E402

ROOT = effect_sprites.ROOT
OUT = os.path.join(ROOT, 'assets', 'stickers')
LOOK = os.path.join(ROOT, 'build', 'stickers')
SIZE = 400          # pixels: a sticker's square as kept
OVER = 2            # drawn this many times larger, then brought down: smooth edges
EDGE = 11           # pixels at SIZE: the white edge round a sticker
RIM = 2             # pixels at SIZE: the faint line outside the white edge, so it shows on a white page
LANCZOS = Image.Resampling.LANCZOS

PACKS = {
    'ghost': [
        'bye-h1', 'ghosts-p1', 'ghosts-h1', 'ghosts-h2', 'wow-h1', 'wow-h2', 'wow-h4', 'echo-h1',
        'ghosts-p4', 'lasers-h2', 'sorry-h1', 'sorry-h2', 'hungry-h1', 'goodMorning-h2', 'ghosts-p3', 'ghosts-h4',
    ],
    'love': [
        'hearts-h1', 'hearts-h3', 'kisses-h2', 'kisses-h1', 'hearts-h2', 'ghosts-p2', 'hearts-h4', 'kisses-h4',
        'thanks-h1', 'thanks-h3', 'thanks-h4', 'getWell-h2', 'sorry-h4', 'balloons-h4', 'kisses-h3', 'hearts-p4',
    ],
    'party': [
        'confetti-h1', 'confetti-h3', 'confetti-h4', 'party-h1', 'party-h2', 'party-h4', 'lasers-h1', 'lasers-h4',
        'balloons-h2', 'fireworks-h1', 'fireworks-h2', 'fireworks-h4', 'celebration-h2', 'celebration-h4', 'spotlight-h4', 'goodMorning-h4',
    ],
    'sweet': [
        'ghosts-h3', 'hungry-h2', 'goodNight-h3', 'goodMorning-h3', 'getWell-h4', 'goodNight-h1', 'snow-h1', 'sorry-h3',
        'goodNight-h4', 'getWell-h3', 'snow-h4', 'thanks-h2', 'balloons-h1', 'goodNight-h2', 'hungry-h4', 'wow-h3',
    ],
}

# Packs drawn for themselves: the sheet in art/stickers/<pack>.webp, and how many across and down it holds.
SHEET_PACKS = {
    'mischief': (4, 4),
}
SHEETS = os.path.join(ROOT, 'art', 'stickers')

# The sweet pack's colours: what the ghost's white becomes, and what its grey line becomes.
PASTELS = [
    ((255, 226, 238), (226, 138, 178)),     # pink
    ((236, 228, 255), (158, 134, 222)),     # lilac
    ((220, 248, 236), (98, 188, 158)),      # mint
    ((255, 244, 210), (222, 172, 78)),      # butter
    ((222, 240, 255), (112, 160, 226)),     # sky
    ((255, 232, 220), (232, 146, 116)),     # peach
]

# The little things set beside a sweet sticker's ghost, two to a sticker.
TRIMS = [
    ('hearts-p1', 'hearts-p5'), ('thanks-p3', 'bye-p1'), ('thanks-p2', 'bye-p8'), ('balloons-p7', 'hearts-p3'),
    ('hearts-p5', 'thanks-p2'), ('kisses-p7', 'bye-p1'), ('hearts-p3', 'balloons-p7'), ('thanks-p2', 'hearts-p1'),
]

_cuts = {}


def sprite(name):
    """One sprite at its sheet's size, by its name as assets/effects/ has it (bye-h1)."""
    sheet, which = name.rsplit('-', 1)
    if sheet not in _cuts:
        _, _, _, found = effect_sprites.sprites_of(effect_sprites.sheet_path(sheet))
        _cuts[sheet] = {'%s%d' % (kind, i): piece for kind, i, piece in found}
    return _cuts[sheet][which]


def step(lo, hi, v):
    t = np.clip((v - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def pastel(picture, light, deep):
    """[picture] with what is white, grey or in between turned to a pastel: its white to [light], its grey line to
    [deep]. What is black (the eyes) and what has a colour of its own (a scarf, a teddy) stay as drawn."""
    px = np.asarray(picture).astype(np.float32)
    rgb = px[..., :3] / 255
    high, low = rgb.max(-1), rgb.min(-1)
    colour = np.where(high > 0, (high - low) / np.maximum(high, 1e-6), 0)
    bright = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    plain = (1 - step(0.10, 0.28, colour)) * step(0.18, 0.40, bright)
    k = step(0.45, 0.97, bright)[..., None]
    to = (np.array(deep, dtype=np.float32) * (1 - k) + np.array(light, dtype=np.float32) * k) / 255
    px[..., :3] = (rgb * (1 - plain[..., None]) + to * plain[..., None]) * 255
    return Image.fromarray(px.astype(np.uint8))


def grown(alpha, by):
    """A shape grown by [by] pixels every way, its corners round: a sticker's edge."""
    hard = alpha.point(lambda v: 255 if v >= 48 else 0)
    soft = hard.filter(ImageFilter.GaussianBlur(by / 1.645))
    return soft.point(lambda v: 255 if v >= 13 else 0).filter(ImageFilter.GaussianBlur(1.3))


def fitted(picture, side):
    scale = side / max(picture.size)
    return picture.resize((max(1, round(picture.width * scale)), max(1, round(picture.height * scale))), LANCZOS)


def sticker(name, number, sweet=False):
    big = SIZE * OVER
    edge = (EDGE + RIM) * OVER
    art = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    pose = sprite(name)
    if sweet:
        light, deep = PASTELS[number % len(PASTELS)]
        pose = fitted(pastel(pose, light, deep), round(big * 0.74))
        art.alpha_composite(pose, ((big - pose.width) // 2, (big - pose.height) // 2))
        # Its two little things go in the two corners the ghost leaves emptiest.
        alpha = np.asarray(art.getchannel('A'))
        half = big // 2
        corners = sorted(
            [(0, 0), (1, 0), (0, 1), (1, 1)],
            key=lambda c: int((alpha[c[1] * half:(c[1] + 1) * half, c[0] * half:(c[0] + 1) * half] > 40).sum()),
        )
        for (cx, cy), trim, part, turn in zip(corners, TRIMS[number % len(TRIMS)], (0.24, 0.17), (-14, 16)):
            piece = fitted(sprite(trim), round(big * part)).rotate(turn if cx else -turn, resample=Image.Resampling.BICUBIC, expand=True)
            inset = edge + round(big * 0.02)
            x = big - inset - piece.width if cx else inset
            y = big - inset - piece.height if cy else inset
            art.alpha_composite(piece, (x, y))
    else:
        pose = fitted(pose, big - 2 * edge - 4 * OVER)
        art.alpha_composite(pose, ((big - pose.width) // 2, (big - pose.height) // 2))
    return edged(art)


def from_sheet(pose):
    """One sticker of a pack drawn for itself: its drawing, fitted to the square, with the edge."""
    big = SIZE * OVER
    edge = (EDGE + RIM) * OVER
    art = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    pose = fitted(pose, big - 2 * edge - 4 * OVER)
    art.alpha_composite(pose, ((big - pose.width) // 2, (big - pose.height) // 2))
    return edged(art)


def edged(art):
    """[art], drawn large on a clear square, with a sticker's white edge round it, brought down to size."""
    big = art.width
    shape = art.getchannel('A')
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    out.paste((52, 54, 64, 255), mask=grown(shape, (EDGE + RIM) * OVER).point(lambda v: v * 30 // 100))
    out.paste((255, 255, 255, 255), mask=grown(shape, EDGE * OVER))
    out.alpha_composite(art)
    return out.resize((SIZE, SIZE), LANCZOS)


def look(pack, made):
    """One picture of a pack, half on a dark page and half on a light one: an edge has to hold on both."""
    cols, cell = 8, 210
    rows = (len(made) + cols - 1) // cols
    page = Image.new('RGB', (cols * cell, rows * cell * 2), (250, 250, 250))
    page.paste((16, 16, 20), (0, 0, cols * cell, rows * cell))
    for i, piece in enumerate(made):
        thumb = piece.resize((cell - 10, cell - 10), LANCZOS)
        for top in (0, rows * cell):
            page.paste(thumb, ((i % cols) * cell + 5, top + (i // cols) * cell + 5), thumb)
    page.save(os.path.join(LOOK, pack + '.png'))


def keep_sheet(pack, source):
    """Keeps a pack's own sheet in art/stickers/: every pixel as drawn, less the halo."""
    os.makedirs(SHEETS, exist_ok=True)
    px = np.array(Image.open(os.path.expanduser(source)).convert('RGBA'))
    px[px[..., 3] < effect_sprites.CLEAR] = 0
    Image.fromarray(px).save(os.path.join(SHEETS, pack + '.webp'), 'WEBP', lossless=True, quality=90, method=6)


def write(pack, made):
    folder = os.path.join(OUT, pack)
    os.makedirs(folder, exist_ok=True)
    # What was made before goes: a pack may have fewer than it had.
    for f in os.listdir(folder):
        if f.endswith('.webp'):
            os.remove(os.path.join(folder, f))
    size = 0
    for i, piece in enumerate(made):
        path = os.path.join(folder, '%02d.webp' % (i + 1))
        piece.save(path, 'WEBP', quality=90, method=6)
        size += os.path.getsize(path)
    look(pack, made)
    print('%-9s %d stickers' % (pack, len(made)))
    return size


def main():
    os.makedirs(LOOK, exist_ok=True)
    for arg in sys.argv[1:]:
        pack, _, source = arg.partition('=')
        if pack not in SHEET_PACKS or not source:
            sys.exit('%s: a pack with a sheet of its own is one of %s, given as pack=path' % (arg, ', '.join(SHEET_PACKS)))
        keep_sheet(pack, source)
    total = 0
    for pack, (cols, rows) in SHEET_PACKS.items():
        sheet = os.path.join(SHEETS, pack + '.webp')
        if not os.path.exists(sheet):
            print('%-9s no sheet in art/stickers/: left as it is' % pack)
            continue
        found = effect_sprites.cut_grid(sheet, cols, rows)
        missing = [i + 1 for i, f in enumerate(found) if f is None]
        if missing:
            sys.exit('%s: nothing was found in place %s of its sheet' % (pack, missing))
        total += write(pack, [from_sheet(piece) for piece, _ in found])
    if os.environ.get('ONLY_SHEETS'):
        print('in all %.1f MB' % (total / 1e6))
        return
    for pack, names in PACKS.items():
        total += write(pack, [sticker(name, i, sweet=pack == 'sweet') for i, name in enumerate(names)])
    print('in all %.1f MB, in %s; to look over: %s' % (total / 1e6, os.path.relpath(OUT, ROOT), os.path.relpath(LOOK, ROOT)))


if __name__ == '__main__':
    main()
