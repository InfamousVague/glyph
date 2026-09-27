# The feature graphic, 1024 × 500

Play Console › Main store listing › Feature graphic. `feature-1024x500.png` in this folder: 1024 × 500, 24-bit PNG
(RGB, no alpha channel, which is what Play accepts), 82 KB. The design is `../copy/feature-graphic.md`.

## What it shows

The app's ink on paper and nothing else: the light paper the screenshots use, faint rules across it at the icon's
spacing, the dotwork ghost left of centre with its hem on a rule, and to its right the wordmark Ghost.md in the app's
bold grotesk, with one line under it in the quieter ink the app uses for a gist:

```
Notes you say or type.
```

The ghost is the listening one, a hand cupped to where an ear would be and sound waves in the air beside it, so the
picture says what the app is for before the words do, and the waves point at the name.

## Where it came from

- **The ghost**: `src/app/art/ghosts/08-listening.webp`, one of the fourteen dotwork scenes `src/app/art/Ghost.tsx`
  draws in the app (docs/GHOSTS.md, scene 8, "the recorder, listening, before the first word"). It is the same
  character as the app icon, drawn whole: the icon's crop has no hem to stand on a rule. The scene is a mask (the
  dots are its alpha), so it takes the graphic's own ink and paper. A paper-coloured body was put under the dots by
  closing the stippled outline and flood-filling the outside (`gfx/ghost.mjs` in the scratchpad), so the rules stop at
  the ghost's outline the way the icon's do. It was scaled to 300 px with a box filter rather than by the browser,
  which aliases stipple.
- **The type**: Inter Variable, the app's interface face (`@fontsource-variable/inter`, the optical-size file
  `src/main.tsx` loads), at 700 with the app's display tracking `-0.045em` (`--app-tracking-display`, app.css) and
  its features `cv11` and `ss01`, 96 px for the wordmark; 30 px at 400 for the line.
- **The colours** are the app's tokens from `src/app/ink.css` as sRGB: paper `#fdfdfd` (`--app-gray-1`), ink
  `#0d0d0d` (`--app-gray-12`), the line's ink `#747474` (`--app-gray-9`, the third ink the gist is drawn in), rules
  `#cfcfcf` at 2 px, 72 px apart.
- **Rendered** by headless Chromium (Playwright 1.59.1) from an SVG page at 1024 × 500 and a scale of 1
  (`gfx/render.mjs`), then written without its alpha channel by pngjs.

## Safe margins

Play crops the edges on some surfaces, so everything sits inside the middle 80 percent (x 102 to 922, y 50 to 450):

| Element | Box |
|---|---|
| Ghost | x 138 to 433, y 86 to 386 |
| Wordmark | x 470 to 870, y 152 to 268 (baseline 245) |
| The line | x 472 to 759, y 281 to 317 (baseline 310) |

## Spares, in `spares/`

Not for upload unless chosen instead:

- `feature-1024x500-waving.png`: the same layout with the waving ghost (`14-welcome-first-run.webp`, both arms up,
  its shadow on the rule), the pose nearest the icon's.
- `feature-1024x500-dark.png`: ink and paper swapped. Play shows one graphic whatever the phone's theme, and the
  light one matches the screenshots, so the light one is the one to upload.

## Licence

The app's own art and its bundled typeface: the ghost is Ghost.md's mascot, and Inter is under the SIL Open Font
Licence, which allows this use.

## Checked

- Read back with pngjs: 1024 × 500, IHDR colour type 2, bit depth 8, 82 KB; the spares the same.
- `file`: "PNG image data, 1024 x 500, 8-bit/color RGB, non-interlaced".
- `document.fonts.check('700 96px "Inter Variable"')` was true before the screenshot, so the wordmark is Inter and not
  a fallback face.
