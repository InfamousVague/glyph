"""The app's web fonts as TrueType, for Flutter, which reads no woff2.

    python3 -m venv .venv && .venv/bin/pip install fonttools brotli
    .venv/bin/python tool/fonts.py tauri/node_modules assets/fonts

Maple Mono's four weights and two italics (Latin, all @fontsource/maple-mono has), and Inter Variable with its optical
size axis in each subset the page loads by unicode-range. The other faces Settings offers, as the page loads them:
Fira Code Variable (its weight axis; Latin, Latin Extended and its symbols), Noto Sans Variable (its weight axis,
upright and italic; Latin and Latin Extended) and IBM Plex Sans at 400, the one weight `@fontsource/ibm-plex-sans`
registers (a bolder word is the engine's own emboldening there, as it is on the page).
"""
import os
import sys

from fontTools.ttLib import TTFont

modules, out = sys.argv[1], sys.argv[2]
jobs = {}
for weight in (400, 500, 600, 700):
    jobs[f"MapleMono-{weight}.ttf"] = f"{modules}/@fontsource/maple-mono/files/maple-mono-latin-{weight}-normal.woff2"
for weight in (400, 700):
    jobs[f"MapleMono-{weight}-Italic.ttf"] = f"{modules}/@fontsource/maple-mono/files/maple-mono-latin-{weight}-italic.woff2"
for subset in ("latin", "latin-ext", "cyrillic", "cyrillic-ext", "greek", "greek-ext", "vietnamese"):
    for style in ("normal", "italic"):
        source = f"{modules}/@fontsource-variable/inter/files/inter-{subset}-opsz-{style}.woff2"
        if os.path.exists(source):
            jobs[f"InterVariable-{subset}{'-Italic' if style == 'italic' else ''}.ttf"] = source
for subset in ("latin", "latin-ext", "symbols2"):
    jobs[f"FiraCodeVariable-{subset}.ttf"] = f"{modules}/@fontsource-variable/fira-code/files/fira-code-{subset}-wght-normal.woff2"
for subset in ("latin", "latin-ext"):
    for style in ("normal", "italic"):
        jobs[f"NotoSansVariable-{subset}{'-Italic' if style == 'italic' else ''}.ttf"] = f"{modules}/@fontsource-variable/noto-sans/files/noto-sans-{subset}-wght-{style}.woff2"
    jobs[f"IBMPlexSans-{subset}-400.ttf"] = f"{modules}/@fontsource/ibm-plex-sans/files/ibm-plex-sans-{subset}-400-normal.woff2"
os.makedirs(out, exist_ok=True)
for name, source in jobs.items():
    font = TTFont(source)
    font.flavor = None
    font.save(os.path.join(out, name))
    print(name)
