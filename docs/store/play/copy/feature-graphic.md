# The feature graphic

Play Console › Main store listing › Feature graphic. 1024 × 500, JPEG or 24-bit PNG with no alpha, under 15 MB.
Play shows it at the top of the listing on some surfaces and behind the play button when there is a video, and
crops the edges on others, so everything that matters sits inside the middle 80 percent.

## What it shows

The app's own ink on paper, and nothing else.

- **The page.** The app's paper, the light one the listing's screenshots use, with the icon's faint ruled lines
  across it at the icon's spacing. No gradient, no photograph, no device frame, no badge, no "new".
- **The ghost mark.** The dotwork ghost, the one on the app icon (`src-tauri/icons/icon.png`; `art/Ghost.tsx` draws it in the
  app), in ink, about 260 px tall, left of centre, its feet on a rule.
- **The wordmark.** Ghost.md, to the right of the ghost, in the app's bold grotesk with its tight letter-spacing,
  about 96 px, in ink.
- **One line of words**, under the wordmark, in the quieter ink the app uses for a gist, about 30 px:

  ```
  Notes you say or type.
  ```

  The site says "Notes you type or say." The store listing is about saying them first, so the order is turned
  round here. Use the site's order if the two should match to the letter.

Ink and paper are the app's own tokens, so the graphic reads as the app does. A dark version (ink page, paper
ghost and words) is a swap of the two tokens; Play shows one graphic whatever the phone's theme, and the light one
matches the screenshots, so it is the one to upload.

## Layout, in pixels

| Element | Box |
|---|---|
| Safe area | 102 to 922 across, 50 to 450 down |
| Ghost mark | 260 tall, its centre at x 300, y 250 |
| Wordmark | Baseline at y 245, starting at x 470 |
| The line | Baseline at y 310, starting at x 472 |

Rendered with the same headless Chromium as the screenshots (a 1024 × 500 page at a scale of 1), then written as
JPEG at quality 92, which drops the alpha channel Play refuses.
