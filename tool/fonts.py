"""The app's web fonts as TrueType, for Flutter, which reads no woff2.

    python3 -m venv .venv && .venv/bin/pip install fonttools brotli
    .venv/bin/python tool/fonts.py ../glyph/node_modules assets/fonts

Maple Mono's four weights and two italics (Latin, all @fontsource/maple-mono has), and Inter Variable with its optical
size axis in each subset the page loads by unicode-range.
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
os.makedirs(out, exist_ok=True)
for name, source in jobs.items():
    font = TTFont(source)
    font.flavor = None
    font.save(os.path.join(out, name))
    print(name)
