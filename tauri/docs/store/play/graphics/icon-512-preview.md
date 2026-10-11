# The app icon, 512 × 512

Play Console › Main store listing › App icon. `icon-512.png` in this folder: 512 × 512, 32-bit PNG (8-bit RGBA),
every pixel opaque, 594 KB (Play's limit is 1024 KB). Play rounds the corners itself, so the file is the full square.

## What it is

The app's own dotwork ghost, waving on lined paper, cropped close: the ghost's rounded head with its folded corner,
the two oval eyes, the raised hand at the left edge and the curl of smoke at the top. It is the icon the app already
wears on Android, the Mac and the web pages (DESIGN.md §93, "The mascot is the app icon", 2026-09-23), so the listing
shows the same picture the phone does.

## Where it came from

- `src-tauri/icons/icon.png` in the repo, the 512 × 512 square that `npx tauri icon design/icon.json` makes from
  `design/app-icon.png` (the picture at 1024). Its pixels are used as they are; the file was only re-encoded so the
  alpha channel is present and fully opaque. The source had no transparent pixels, so nothing was flattened; had there
  been any, they would have gone onto the paper's own colour, `#f3f3f0`, which `design/icon.json` names as the
  adaptive icon's background.
- The picture is Matt's `ghost.md-mascot.png`, the same character as the fourteen scenes in `src/app/art/ghosts/`
  (docs/GHOSTS.md): a sheet of writing paper with a dog-eared corner, solid oval eyes, no mouth, a thin curl of smoke.

## Licence

The app's own art, made for Ghost.md by its author. No third-party artwork, stock or fonts are in the file.

## Checked

- Size and depth read back with pngjs: 512 × 512, IHDR colour type 6, bit depth 8, 0 pixels with alpha under 255.
- `file`: "PNG image data, 512 x 512, 8-bit/color RGBA, non-interlaced".
