# The ghosts

Prompts for generating Glyph's empty-state characters. Matt (2026-09-20): "default vector character graphics of
ghosts for the notes for things like empty pages and new notes etc etc like bear notes does".

A ghost is the right character for this app rather than a borrowed one: Glyph's own motif is already smoke. Words
arrive as wisps and gather into letters (`art/WispText.tsx`), a page going under the header turns to smoke rather
than sliding under a line (`art/wispEdge.ts`), and the tab row dissolves at its ends. The ghost is that smoke with a
face on it.

## What the app needs them to be

Anything generated has to survive `art/Shapes.tsx`, where the app's pictures live today, and its rules are not
negotiable - they are why the existing set works on both themes at every size:

- **One ink, no colour.** Every shape is drawn on `currentColor`, so a page sets its weight (`--app-ink` for a
  picture that leads, `--app-ink-3` for one that sits under the words) and it inverts with the theme. A generated
  image that is grey-on-white, or that relies on white fills, breaks the moment the page is dark.
- **Flat.** No gradients, no shading, no texture, no outline-plus-fill-in-two-tones.
- **Square**, drawn at about 120px (`7.5rem` on the home page's empty state). Detail below ~4px of that square is
  mud: no eyelashes, no cross-hatching, no thin whiskers.
- **Holes are holes**, cut with an even-odd path rather than painted white, so they stay holes on any ground.
- **Decoration only** - every one is `aria-hidden`, and the words beside it carry the meaning.

So the target is a **one-colour silhouette with cut-out holes**: solid black shapes on white, clean closed curves,
nothing thinner than about 3% of the square. That is what traces cleanly into an SVG path and what reads at 120px.

## The style block

Paste this into **every** prompt, unchanged. Consistency across the set comes from repeating it word for word.

```
Flat vector illustration, pure solid black shapes on a plain white background. No colour, no grey,
no gradients, no shading, no texture, no outlines around the shapes. Single continuous silhouette
with details cut out as holes. Thick, confident forms; nothing thinner than a pen stroke. Centred
in a square frame with generous empty margin. Simple and geometric enough to read clearly at 120
pixels. No text, no letters, no words, no watermark, no border.
```

## The character

Generate this one **first**, and feed the result back as a reference image to every prompt after it, so the ghost is
the same ghost each time.

```
A small friendly ghost character. Its body is a soft rounded dome that tapers into two or three
gentle wisps of smoke where feet would be, as if it is a curl of smoke rising. Two simple oval
eyes cut out of the silhouette, set wide and low. No mouth, no arms unless the scene needs them,
no eyebrows. Calm and quiet rather than spooky or cute-cartoonish.
```

**Character sheet (prompt 1).** Ask for the same ghost three times in one square - facing forward, three-quarter,
and drifting sideways - so later prompts have a reference for how it turns.

## The fifteen

Each gives the moment in the app, the subject line to append to the style block and the character, and what it has
to say at a glance. Where the app already draws something, the file is named: those are replacements, and the rest
are new places that have only words today.

| # | Where | Subject |
| --- | --- | --- |
| 1 | character sheet, not shipped | the three views above |
| 2 | no notes yet (`home/HomeScreen.tsx`, replaces `Blank`) | below |
| 3 | nothing in this workspace | below |
| 4 | a new, empty note | below |
| 5 | search found nothing | below |
| 6 | the trash, empty (`core/trash.ts`) | below |
| 7 | the archive, empty | below |
| 8 | listening (`capture/`) | below |
| 9 | the model working | below |
| 10 | an empty canvas (`canvas/`) | below |
| 11 | every to-do ticked | below |
| 12 | signed out / not syncing | below |
| 13 | something went wrong | below |
| 14 | welcome, first run (replaces `Welcome`) | below |
| 15 | an update is ready (replaces `Update`) | below |

**2. No notes yet.** The one people meet most; it sits over "A blank page."

```
The ghost curled up asleep on a single blank sheet of paper, as if the paper were a bed. The sheet
is a plain rectangle tilted slightly. Nothing is written on it.
```

**3. Nothing in this workspace.** Over "Nothing in {workspace} yet."

```
The ghost peering into an open, empty folder that is bigger than it is, holding the front flap
down with both hands to look inside. The folder is a simple geometric shape.
```

**4. A new note.** For a note with no words in it yet.

```
The ghost holding an oversized fountain pen with both hands, hovering the nib just above a blank
sheet, about to make the first mark. One small dot of ink sits where the nib will land.
```

**5. Search found nothing.** Over "No note by that name."

```
The ghost holding a large round magnifying glass up to one eye, its body seen small and distorted
through the lens. The lens is a clean circle cut out of the silhouette.
```

**6. The trash, empty.**

```
The ghost sitting inside an empty waste basket with its wisps hanging over the rim, perfectly at
home. The basket is a simple tapered shape with two straight bands across it.
```

**7. The archive, empty.**

```
The ghost floating beside a closed archive box with a lid, resting one hand on the lid. The box is
a plain rectangle with a lip; one label area on the front is left blank.
```

**8. Listening.** While the recorder is open and hearing nothing yet.

```
The ghost with its head tilted, one hand cupped at where an ear would be, three concentric arcs
travelling toward it from the side as sound. The arcs are thick and evenly spaced.
```

**9. The model working.** While the on-device model is formatting.

```
The ghost sitting cross-legged in mid-air with its eyes closed, three small dots orbiting above
its head in an arc, as if thinking. The dots are solid circles of increasing size.
```

**10. An empty canvas.**

```
The ghost floating in the middle of three empty rectangular cards arranged around it, holding a
line that connects two of them, about to join the third. The cards are plain rounded rectangles.
```

**11. Every to-do ticked.**

```
The ghost leaning proudly against a single large checkbox with a thick tick in it, one arm resting
on its top edge. The box is a rounded square; the tick is cut out of the solid box as a hole.
```

**12. Signed out, not syncing.**

```
Two identical ghosts drifting apart, facing each other, with a broken dashed line between them
where a connection would be. The dashes are thick and evenly spaced.
```

**13. Something went wrong.**

```
The ghost tangled up in a single long looping ribbon that wraps around its body twice, looking
down at the knot with its eyes. The ribbon is one continuous thick band.
```

**14. Welcome, first run.**

```
The ghost drifting upward with one hand raised in a small wave, its wisps trailing longer than
usual beneath it, as if it has just arrived.
```

**15. An update is ready.**

```
The ghost carrying a wrapped parcel almost as big as itself, with a simple cross of ribbon over
the front. It peers over the top of the parcel.
```

## After they come back

1. **Trace to SVG.** Any tracer that outputs paths (Illustrator's Image Trace at Black and White Logo, or SVGcode)
   works; the flat black silhouette is chosen so that it traces without cleanup.
2. **Strip the colour.** Remove every `fill` from the paths, set the root `fill="currentColor"`, and delete the
   white background rectangle a tracer usually adds. Holes become `fill-rule="evenodd"` on the path that owns them.
3. **Square the box.** `viewBox="0 0 120 120"`, which is what every shape in `art/Shapes.tsx` uses, so they can be
   swapped in and out without touching a stylesheet.
4. **Check both themes at 120px**, and check them at `--app-ink-3`, which is where most of them sit: a shape that
   reads in full ink can vanish at a third of it.
5. **Give it its thing to do.** Every existing shape moves, slowly and on a loop with long rests
   (`art/Shapes.module.css`), and holds still under reduced motion. A ghost has an obvious one: drift up an eighth
   of the square and back, with its wisps lagging behind. That is a transform and an opacity, so nothing lays out
   again.

## Not asked, so not chosen

How many of these actually ship, whether the ghost replaces the abstract shapes everywhere or lives only in the
empty states beside them, and whether it ever speaks. The 2026-09-13 direction was "abstract shapes, no ink
inspiration" for the guide's pictures; a character is a change of mind about that, and it may be one Matt wants
only where a page is empty.
