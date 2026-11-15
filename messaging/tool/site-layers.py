#!/usr/bin/env python3
"""Cuts the app's own screenshots into the pictures gogho.st uses (site/shots/).

Matt, 2026-11-15: "the phone isn't using a real screenshot from the app, i'd like it to be composed of an "exploded"
view of the app". The screen tests draw the app pixel for pixel (test/shots/*-light.png, at twice size), so the site
shows the real thing: whole screens, and the pieces of one conversation lifted apart for the hero's exploded view.
The site is mostly white (Matt: "a white green so a mostly white with a hint of teal / bluegreen"), so the light
screens are used. Each piece is cut from the app's near-white background (253, 253, 253), which is made see-through
from the crop's edges inwards, so a bubble floats on its own.

  python3 tool/site-layers.py      (after the screen tests redraw: flutter test --update-goldens test/screens_test.dart)
"""
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "test" / "shots"
OUT = ROOT / "site" / "shots"

# The app's light background, and how near a pixel must be to count as it (a bubble's grey, 240, is not).
BG = 253
NEAR = 4


def cut(image, box):
    """The crop with the background around its edges made see-through (a flood from every edge pixel)."""
    piece = image.crop(box).convert("RGBA")
    w, h = piece.size
    px = piece.load()
    seen = bytearray(w * h)
    todo = deque()

    def bg(x, y):
        r, g, b, _ = px[x, y]
        return max(abs(r - BG), abs(g - BG), abs(b - BG)) <= NEAR

    for x in range(w):
        todo.append((x, 0))
        todo.append((x, h - 1))
    for y in range(h):
        todo.append((0, y))
        todo.append((w - 1, y))
    while todo:
        x, y = todo.popleft()
        i = y * w + x
        if seen[i] or not bg(x, y):
            continue
        seen[i] = 1
        px[x, y] = (0, 0, 0, 0)
        if x > 0: todo.append((x - 1, y))
        if x < w - 1: todo.append((x + 1, y))
        if y > 0: todo.append((x, y - 1))
        if y < h - 1: todo.append((x, y + 1))
    # The edge of what is left is softened by a pixel, so it does not show a dark fringe on the page.
    alpha = piece.getchannel("A")
    for y in range(h):
        for x in range(w):
            if alpha.getpixel((x, y)) and any(
                0 <= x + dx < w and 0 <= y + dy < h and not alpha.getpixel((x + dx, y + dy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
            ):
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 150)
    return piece


def pill(image, box, radius):
    """A crop kept to a rounded rectangle: for what floats over other things in the app (the dock, the call banner)."""
    piece = image.crop(box).convert("RGBA")
    mask = Image.new("L", piece.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, piece.size[0] - 1, piece.size[1] - 1), radius=radius, fill=255)
    piece.putalpha(mask)
    return piece


def save(piece, name):
    OUT.mkdir(parents=True, exist_ok=True)
    piece.save(OUT / f"{name}.webp", "WEBP", quality=88, method=6)
    print(f"ok site/shots/{name}.webp {piece.size[0]}x{piece.size[1]}")


def main():
    thread = Image.open(SHOTS / "2-thread-light.png")
    tabs = Image.open(SHOTS / "20-layout-tabs-light.png")
    hangout = Image.open(SHOTS / "21-hangout-light.png")

    # The hero's exploded conversation (2-thread): each piece where it sits on the 824 x 1784 screen.
    pieces = {
        "x-header": (thread, (0, 44, 824, 160)),
        "x-link": (thread, (20, 174, 664, 316)),
        "x-place": (thread, (46, 344, 656, 478)),
        "x-out1": (thread, (164, 574, 806, 709)),
        "x-out2": (thread, (420, 709, 806, 800)),
        "x-heart": (thread, (440, 796, 500, 848)),
        "x-ticks": (thread, (520, 846, 800, 912)),
        "x-in": (thread, (20, 920, 664, 1058)),
        "x-laugh": (thread, (582, 1058, 644, 1106)),
        "x-emoji": (thread, (34, 1222, 232, 1326)),
        "x-chips": (thread, (20, 1382, 516, 1464)),
        "x-compose": (thread, (20, 1636, 806, 1744)),
    }
    for name, (image, box) in pieces.items():
        save(cut(image, box), name)
    # Floating pieces from other screens.
    save(pill(tabs, (28, 1597, 669, 1716), 60), "x-callbar")
    save(pill(tabs, (689, 1210, 807, 1696), 59), "x-dock")
    save(cut(hangout, (20, 300, 804, 790)), "x-people")
    save(cut(hangout, (160, 1590, 664, 1724)), "x-calldock")

    # Settings › Voice and video from its Volume section down: the boost, Music mode, noise suppression.
    save(Image.open(SHOTS / "19-voice-settings-light.png").convert("RGB").crop((0, 590, 824, 2200)), "voice-settings")

    # Whole screens, for the sections below the hero.
    for src, name in (("2-thread-light.png", "thread"), ("20-layout-tabs-light.png", "list"), ("21-hangout-light.png", "hangout"), ("11-frame-wide-thread-light.png", "wide"), ("21-hangout-chat-light.png", "hangout-chat")):
        path = SHOTS / src
        if path.exists():
            save(Image.open(path).convert("RGB"), name)


if __name__ == "__main__":
    main()
