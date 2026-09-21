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
- **Lines, not fills** (Matt, 2026-09-21, of the first set: "I want them to be outlines not solid fill"). One stroke
  weight for the whole set, about 4% of the square, round caps and joins; the inside of a shape is the paper, so
  nothing is painted white and nothing needs a hole cut.
- **Decoration only** - every one is `aria-hidden`, and the words beside it carry the meaning.

So the target is **one-colour line art**: a single clean black outline on white, one even stroke, closed shapes,
no fill inside them. That is what traces to stroked SVG paths and what reads at 120px without turning to mud.

## The style block

Paste this into **every** prompt, unchanged. Consistency across the set comes from repeating it word for word.

```
Minimal line-art icon, a single clean black outline on a plain white background. Line drawing
only: no fill inside the shapes, no colour, no grey, no gradients, no shading, no hatching, no
texture. One even stroke weight throughout, medium-thick, with rounded ends and rounded corners.
Closed, simple shapes; nothing thinner than the main line. Centred in a square frame with
generous empty margin. Simple and geometric enough to read clearly at 120 pixels. No text, no
letters, no words, no watermark, no border, no frame around the drawing.
```

## The character

Generate this one **first**, and feed the result back as a reference image to every prompt after it, so the ghost is
the same ghost each time.

```
A small friendly ghost character, the classic sheet ghost: a wide rounded head that flows
straight down into a body about as wide as the head, ending in a soft scalloped hem of three or
four gentle waves along the bottom. The body stays broad all the way down; it never narrows to a
point or a tail. Two small oval eyes drawn as outlines, set wide and low. Two short rounded arm
bumps at the sides. No mouth, no eyebrows, no legs. Calm and quiet rather than spooky or
cute-cartoonish.
```

**Character sheet (prompt 1).** Ask for the same ghost three times in one square - facing forward, three-quarter,
and drifting sideways - so later prompts have a reference for how it turns.

Why the shape changed: the first set asked for a dome "tapering into wisps", and what came back was a teardrop with a
tail (Matt: "they look a bit sperm-like"). A ghost reads as a ghost from its hem, not from a tail: the width held all
the way down and the wave along the bottom are the two things to keep in every prompt.

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
through the lens. The lens is a clean outlined circle, and the ghost's eye shows inside it.
```

**6. The trash, empty.**

```
The ghost sitting inside an empty waste basket with its scalloped hem draped over the rim,
perfectly at home. The basket is a simple tapered shape with two straight bands across it.
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
its head in an arc, as if thinking. The dots are outlined circles of increasing size.
```

**10. An empty canvas.**

```
The ghost floating in the middle of three empty rectangular cards arranged around it, holding a
line that connects two of them, about to join the third. The cards are plain rounded rectangles.
```

**11. Every to-do ticked.**

```
The ghost leaning proudly against a single large checkbox with a thick tick in it, one arm resting
on its top edge. The box is an outlined rounded square with the tick drawn inside it.
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
The ghost drifting upward with one hand raised in a small wave, its hem rippling a little more than
usual beneath it, as if it has just arrived.
```

**15. An update is ready.**

```
The ghost carrying a wrapped parcel almost as big as itself, with a simple cross of ribbon over
the front. It peers over the top of the parcel.
```

## After they come back

1. **Trace to SVG as strokes.** A centreline tracer (Illustrator's Image Trace with Strokes on and Fills off, or
   Inkscape's Trace Bitmap in centerline mode) turns each line into one path; an outline tracer would give every
   line two edges and a fill between them, which is twice the geometry and a stroke that cannot be retuned.
2. **Strip the colour.** Every path `fill="none"`, the root `stroke="currentColor"`, one `stroke-width` for the whole
   drawing (about 5 in a 120 box), `stroke-linecap="round"` and `stroke-linejoin="round"`; delete the white
   background rectangle a tracer usually adds. Nothing is painted white and nothing is a hole.
3. **Square the box.** `viewBox="0 0 120 120"`, which is what every shape in `art/Shapes.tsx` uses, so they can be
   swapped in and out without touching a stylesheet.
4. **Check both themes at 120px**, and check them at `--app-ink-3`, which is where most of them sit: a shape that
   reads in full ink can vanish at a third of it.
5. **Give it its thing to do.** Every existing shape moves, slowly and on a loop with long rests
   (`art/Shapes.module.css`), and holds still under reduced motion. A ghost has an obvious one: drift up an eighth
   of the square and back, with its hem lagging behind. That is a transform and an opacity, so nothing lays out
   again.

## Not asked, so not chosen

How many of these actually ship, whether the ghost replaces the abstract shapes everywhere or lives only in the
empty states beside them, and whether it ever speaks. The 2026-09-13 direction was "abstract shapes, no ink
inspiration" for the guide's pictures; a character is a change of mind about that, and it may be one Matt wants
only where a page is empty.
