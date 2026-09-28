# The feature graphic

Play Console › Main store listing › Feature graphic. 1024 × 500, JPEG or 24-bit PNG with no alpha, under 15 MB.
Play shows it at the top of the listing on some surfaces and behind the play button when there is a video, and
crops the edges on others, so everything that matters sits inside the middle 80 percent.

## What it shows

The app's own ink on paper, and nothing else.

- **The page.** The app's paper in the dark theme, the one the listing's screenshots are in (`#040404`, the same as
  the screenshots' own page), with the icon's faint ruled lines across it at the icon's spacing. No gradient, no photograph, no device frame, no badge, no "new".
- **The ghost mark.** The dotwork ghost, the same character as the app icon (`src-tauri/icons/icon.png`), in its
  listening scene from the set `art/Ghost.tsx` draws in the app, in ink, 300 px tall, left of centre, its hem on a
  rule.
- **The wordmark.** Ghost.md, to the right of the ghost, in the app's bold grotesk with its tight letter-spacing,
  about 96 px, in ink.
- **One line of words**, under the wordmark, in the quieter ink the app uses for a gist, about 30 px:

  ```
  Notes you say or type.
  ```

  The site says "Notes you type or say." The store listing is about saying them first, so the order is turned
  round here. Use the site's order if the two should match to the letter.

Ink and paper are the app's own tokens, so the graphic reads as the app does: the dark theme's gray-1 for the page
and gray-12 for the ink, and the light version the light theme's. Play shows one graphic whatever the phone's theme, and the listing is one theme throughout: the eight phone
screenshots and the four tablet ones to upload are the dark theme, so the dark graphic is the one to upload. Should
the listing be made light instead (the `phone-light` and `tablet-16x9-light` sets), upload
`graphics/spares/feature-1024x500-light.png` with them.

## Layout, in pixels

| Element | Box |
|---|---|
| Safe area | 102 to 922 across, 50 to 450 down |
| Ghost mark | 295 × 300, x 153 to 448, y 86 to 386, its hem on the rule at y 386 |
| Wordmark | Baseline at y 245, starting at x 470 |
| The line | Baseline at y 310, starting at x 472 |

Rendered with the same headless Chromium as the screenshots (a 1024 × 500 page at a scale of 1), then written by
pngjs as a 24-bit PNG with no alpha channel, which is what Play accepts (JPEG would do as well).
