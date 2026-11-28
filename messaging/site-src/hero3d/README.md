# The hero's phone

The landing page's hero (site/index.html) is a foldable phone turning slowly in space with the app on its screens.
Now and then a screen is lifted apart into its layers and drawn back in: the conversation on the outer screen,
then, opened, the Marketplace and a plugin's page, then the list beside a voice space. It shuts with its screen
lit and turns once round. The phone is the pale finish on the dark page and the dark one on the light page.

Two pictures share one camera:

- **The phone** is WebGL (three.js). Where the site has `/model/duo.bin` it is that model (`duo.js`); where it has
  not, a plain foldable made in code (`phone.js`). `studio.js` is the light it is seen by.
- **What is on its screens** is the app, in HTML, drawn by the kit in `site/mock`. Each screen is a pane at the
  app's own size and each piece of the app a layer of it (`site/mock/hero3d.css` says how they are written).
  `main.js` gives each screen the phone's own matrix as a CSS transform and lifts the layers along it.

Everything that moves is a function of one clock: `TRACK` and `SCENES` at the top of `main.js` are the whole score
(the fold, which screen is lit, where the camera is, when each view lifts and lands).

## Changing it

- A view: edit `views/<name>.html` (and its styles in `site/mock/`), then `node tool/build-hero3d.mjs`, which
  writes the views into `site/index.html` between its `H3` marks and bundles the script to `site/hero3d.js`.
  `--check` fails if either is stale.
- The motion: `TRACK` and `SCENES` in `main.js`, then build.
- To look at one moment, open the page with `?h3=<seconds>` (0 to 35); `window.__h3.seek(t)` and `.play()` do the
  same from the console. `?h3plain` draws the plain phone, `?h3flat` what a browser with no WebGL gets.

The conversation on the outer screen plays before it is lifted apart (the reply typed and sent under what it
answers, then the next message, then the reactions): `site/mock/hero.js` does the playing, told when by `CUE` in
`main.js`.

The phone shuts with its inner screen still lit. HTML cannot be folded or hidden behind the phone, so for that
moment the page becomes a picture of itself on the phone's own display: `site/art/hero/space-dark.webp` and
`-light.webp`, which `tool/hero3d-screens.mjs` draws from the view (it needs Playwright and cwebp; `--check` says
when they are stale, and needs neither). Run it after changing the `space` view, its styles or the kit's.

`node tool/serve-site.mjs` serves `site/` on this computer, for looking at it in a browser (or the iOS simulator's
Safari) before it ships.

A callout is a `.h3-tag` in the page: `data-view` and `data-for` name the layer its line runs to, `data-at` its
place on the stage in percent (`data-at-s` on a narrow stage; without one it is not shown there).

## The model

`/model/duo.bin` is not in this repository and must never be: it is a real phone's model, which Uplink may show
but not pass on. `tool/hero3d-model.py` packs it from the prepared files (kept outside the repository) into
`~/.config/mattssoftware/uplink-site-private/model/duo.bin`; `tool/deploy-site.mjs` lays that folder over the site
as it ships, and `site/model/` is ignored by git, so a copy there for looking at the page on this computer is never
committed. Anyone building the site from the public source gets the plain phone.
