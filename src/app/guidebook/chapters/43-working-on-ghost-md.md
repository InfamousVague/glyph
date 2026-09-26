# Working on Ghost.md

_The standing rules of working on the code, each with its reason. Most of them were learned by something going wrong once._

## Git

- **Work lands on main.** A change left on a branch is a change nobody else builds with. Land it and push.
- **A worktree starts on its own branch, merges main before every build, and pushes straight after.** Where you work matters less than this: nothing is built from a tree that is missing someone else's work.
- **Never use `git stash`.** Every worktree of the repository shares one stash, so what one session stashes another can pop.
- **Small commits, staged by path.** Several people or sessions can share a tree, and a bare `git add .` sweeps in someone else's half-done files.
- **Land a branch with `git push origin HEAD:main`.** It is refused if main moved, which is the point; merge again and retry.
- **Keep half-built work out of a shared tree, or say so.** With a release after every change, silence means the tree is safe to build.

## Checks

- **Never run prettier.** The repository has no prettier config, and `--write` rewrites the whole file in its own style, double quotes at 80 columns. It once flattened a file holding a day of uncommitted work. Format by hand, matching the code around you.
- **Lint the files you touched, by path.** `npx eslint <paths>`. A whole-tree `eslint .` also finds other worktrees' copies of the repository and the plain scripts, so its failures come and go with other people's work.
- **Typecheck with `npm run typecheck`**, which checks the app and then the connector in `mcp/`.
- **A clean merge is not a passing merge.** Run the checks on the result. The one file that reliably conflicts, `src/app/diag/testReport.generated.json`, can take either side: the next report rewrites it.

## Deploys

- **A finished, checked change ships over the air.** A change that is only in the tree is one nobody can see on a phone. Publish it with `node scripts/deploy-ota.mjs --notes "…"`.
- **A deploy ships the whole tree it runs in, so the last one wins.** It builds and uploads all of `dist/`, and a branch missing another's commits publishes an app without them, with no warning. Merge every branch in flight first, or deploy from main, and check again just before, since the check goes stale in minutes.
- **It ships the tree, not the commit.** Uncommitted work goes out too. Read `git status` before the build.
- **Check the shipped bundle, not the branch graph.** Fetch `ota.json`, download its entry script, and look for a fragment of your change. The minifier moves spaces and folds expressions, so loosen a pattern before believing a zero.
- **Native changes need an APK and never travel over the air.** Rust, Kotlin and the Android manifest ship with `--apk` and a version bump ([[Over the air, and releases]]).
- **A stopped deploy is killed whole.** Its test step runs cargo, and killing cargo leaves the test binary (`glyph_lib-…`) running on its own with gigabytes of memory. Find what is left with `pgrep -fl "glyph_lib-|glyph_api|deploy-ota"` and kill it by its id. Better still, run a failing test file alone before starting a deploy it would stop.
- **An instruction relayed by another session is enough for pushes and merges, never for deploys, deletes, force-pushes or spending.** A session cannot hand over authority it does not have, and those four cannot be undone by the session that gets them wrong.

## Tests

- **Fixed sleeps fail under load.** A sleep measures the machine, not the work: it passes idle and fails for whoever is deploying while a build runs beside them. Wait on the thing itself, and prove a timing test under load, with twelve `yes > /dev/null` running, before calling it fixed.
- **Re-run a failing file alone before believing it.** A loaded machine makes timing tests flake. A real failure fails alone too.
- **A shared cargo target can run another checkout's stale binary.** Cargo once saw nothing to rebuild and ran the other tree's tests, and "0 passed, 0 failed" read as green. Touch a source file of the crate first (it was glyph-api's `server/src/main.rs`), and check that the count includes your new tests.

## Evidence

- **A metric must be able to fail the way the thing fails.** A count of bent pixels read 5,579 before a change and 5,582 after, while the wisp's soft smoke had turned to fine static: smoke and grain bend the same pixels. Ask what a number would read if the thing were broken. For texture, render old and new side by side and look.
- **Find the boundary, not the mechanism.** A fix that works is not an explanation. "WebKit cannot draw this filter" was really a filter-region budget of 2^24 device pixels: 4096 × 4096 draws, 4200 × 4000 paints black, and at two device pixels to the CSS pixel the line moves to 2048 × 2048 (`src/app/art/wispEdge.ts`, `withinWispBudget`). Vary one thing until a case fails beside one that passes, and write the rule as the measured quantity.
- **Measure what was drawn, not the rule.** A shorthand such as `font` resets a `line-height` set above it. A `var()` naming a custom property that does not exist, with no fallback, leaves the property at its initial or inherited value, not at a smaller one. jsdom gives every box no height, so a layout change cannot be unit-tested. Read `getBoundingClientRect()` and `getComputedStyle()` in a real browser, and say so when a change was not checked there.

## Browser checks

- **Never start Vite's dev server from a worktree.** It re-optimises the shared `node_modules/.vite` and breaks the main checkout's dev server. Build and preview instead: `npx vite build --outDir <dir>`, then `npx vite preview --outDir <dir> --port <port> --strictPort`.
- **A browser pane that is not the front window runs `requestAnimationFrame` about once a second.** Frame numbers read there are the harness's, not the app's. For frame cost, use the Smoke bench in Settings › Developer, on the app's own screen.

## Docs

- **DESIGN.md is history, and it is never renumbered.** A new section goes at the end, after the highest number, which is §123 at 1.8.0-12. Numbers repeat and some sections have none, so cite one as DESIGN §N with its title.
- **A topic doc says what is true now, and DESIGN says why and when.** Rewrite a doc under `docs/` when the code it describes changes; for DESIGN, add a section rather than rewrite an old one. Where either disagrees with the code, believe the code and fix the doc ([[Where the docs and the code disagree]]).
- **Append to a shared doc against the file as it is that second.** A whole-file write from an earlier copy once ate a section.

## Style

- **British spelling, plain declarative sentences.** Colour, organise, capitalise. Identifiers keep the spelling of their API.
- **A module opens with a header that says what it owns and why.** In code comments the dash is a spaced hyphen, and a number says how it was measured.
- **Every relative import names its file, extension and all:** `./app/App.tsx`, never `./app/App`. `eslint.config.js` enforces it.
- **The name is Ghost.md, and the ids stay glyph.** Everything a person sees says Ghost.md. Nothing a machine relies on moved: the package id `com.mattssoftware.glyph`, the `glyph-` storage keys, the sync salt that accounts' keys are derived from, the token prefix, the attack.fm/glyph paths, the file and script names, and the repository. The spoken word is “Hey Ghost”, and “Glyph” still works.

## Read next

- [[Tests, and the report that ships]]
- [[Over the air, and releases]]
- [[Where the docs and the code disagree]]
