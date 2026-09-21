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
- **Flat ink.** No gradients, no grey washes, no painted shading; tone comes only from lines - hatching - so it
  stays one colour and inverts with the theme.
- **Square**, and drawn larger than the abstract shapes: about 200px where a picture leads a page (the home page's
  empty state, welcome), 120px where it sits under the words. An illustration wants the room (Matt, 2026-09-21: "I
  want them to have an illustrated look"), and the abstract shapes' `7.5rem` is a line in `art/Shapes.module.css`,
  not a law. Detail below ~2px of the drawn square is still mud: hatching is sparse and bold, a few strokes for a
  shadow, never a fine mesh; no stippling, no whiskers.
- **Lines, not fills** (Matt, of the first set: "I want them to be outlines not solid fill"). Varied line weight -
  a heavier outline, lighter interior and hatching lines - round caps and joins; the inside of a shape is the paper,
  so nothing is painted white and nothing needs a hole cut.
- **Decoration only** - every one is `aria-hidden`, and the words beside it carry the meaning.

So the target is a **one-colour pen-and-ink illustration**: black line on white, weight in the line, shadow in
sparse hatching, a figure with a little ground and a little scene, no fill. That traces to stroked SVG paths and
reads at 200px, and at 120px if the hatching is kept coarse.

## The style block

Paste this into **every** prompt, unchanged. Consistency across the set comes from repeating it word for word.

```
Pen-and-ink illustration, black ink on plain white paper, drawn with a brush pen or a flexible
nib: strong contrast between thick and thin. The outer outline is bold and heavy, the lines inside
it are fine, and each stroke swells and tapers along its length - thick where it turns or carries
weight, thin where it trails off. Sparse, bold hatching where a shadow falls - a few decisive
strokes, never a fine mesh, never scribble. No fill inside the shapes, no colour, no grey wash, no
gradients, no painted shading, no stippling, no texture other than the hatching. A touch of
cartoon in the drawing: shapes a little simplified and exaggerated, a clear pose, an expression in
the eyes, the warmth of a good comic - but with the craft of an illustrator, not a sticker, not an
emoji, not a mascot, not a children's picture book. A small sense of place: a ground line low in
the frame, and only the objects the scene names. Every shape deliberate; no stray marks, no
sketch lines, no construction lines. Atmospheric, wry, quietly melancholy, with a little humour.
Centred in a square frame with generous empty margin, and legible at 200 pixels. No text, no
letters, no words, no watermark, no border, no frame around the drawing.
```

## The character

Generate this one **first**, and feed the result back as a reference image to every prompt after it, so the ghost is
the same ghost each time.

```
A ghost: a hollow sheet of old linen floating in the air with nothing inside it. It hangs from a
softly rounded crown and falls in loose folds, as wide at the bottom as at the top, ending in an
uneven hem of soft waves that hangs free and ripples a little in the air; it never narrows to a
point or a tail, and it never touches the ground. There is no body under the cloth: no shoulders,
no waist, no hips, no legs, no feet - only the folds of an empty sheet. The whole figure tilts a
few degrees and the hem trails slightly to one side, as if it is drifting slowly. Two small, calm
almond-shaped eyes, set wide and a little low on the crown; no mouth, no eyebrows, no cheeks. No
arms unless the scene needs them, and then only as a fold of the cloth lifting. Long, soft
interior lines follow the folds, with a few bold hatching strokes in the deepest of them. Far
below the hem, a small soft shadow on the ground, clearly separate from the ghost, shows how high
it floats. Melancholy, composed, a little wry; never spooky, never cute.
```

**Character sheet (prompt 1).** Ask for the same ghost three times in one square - facing forward, three-quarter,
and drifting sideways - so later prompts have a reference for how it turns.

Why the shape changed: the first set asked for a dome "tapering into wisps", and what came back was a teardrop with a
tail (Matt: "they look a bit sperm-like"). A ghost reads as a ghost from its hem, not from a tail: the width held all
the way down and the wave along the bottom are the two things to keep in every prompt.

Why it changed again: the second set, a bare outline of a "small friendly ghost", came back flat and childish (Matt:
"these are better but lack detail and feel a bit childish"). Three things were doing that - the words "small",
"friendly" and "simple", which a model reads as a sticker; one even line with nothing inside it; and round, wide
proportions with big eyes. So the style block is now an editorial ink drawing with lighter interior contour lines,
the character is cloth with folds and weight rather than a blob with a face, the eyes are small and calm, and the
words "cute" and "friendly" are gone.

And a third time, before the third set was even judged: "I want them to have an illustrated look." An icon and an
illustration are different asks - an illustration has weight in its line, shadow, a ground, a scene - so the style
block is now a pen-and-ink book illustration, hatching is allowed where it is sparse and bold, the ghost casts a
shadow and stands over a ground line, and the pictures get more room on the page than the abstract shapes had. The
rule that survives every pass is the same: whatever is drawn must be one ink on the paper, so it inverts with the
theme, and nothing finer than a couple of pixels at the size it is shown.

Then the illustrated set came back "too humanoid now and not floating". The prompt had said "hanging over an unseen
figure", "unseen shoulders and arms", "figure study" and "stands above a ground line", and the model drew exactly that:
a person under a sheet, standing. So the character is now a hollow sheet with nothing inside it - no shoulders, no
waist, no legs, said outright - tilted with its drift, its hem hanging free and never touching the ground, and its
shadow a small separate mark far below, which is the one thing in a still drawing that says it floats. In the
scenes, anything that has the ghost sitting, leaning or holding is a fold of the cloth doing it, not a limb.

Then two dials at once: "a bit more thick lines and thin lines mixed, and bring a touch of cartoon into it." The
line is now a brush pen's - a bold outer outline, fine lines inside, strokes that swell and taper - and the block
asks for a touch of cartoon by name: simplified, a little exaggerated, a clear pose, an expression in the eyes, the
warmth of a good comic. The guard against sliding back to the sticker of the second set is kept in the same
sentence: the craft of an illustrator, not a mascot. "Literary rather than cartoonish" is gone, since it argued
with the ask.

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
2. **Strip the colour.** Every path `fill="none"`, the root `stroke="currentColor"`, two `stroke-width`s for the
   whole set (about 5 for the outline and 3.5 for the interior lines in a 120 box, on a group each),
   `stroke-linecap="round"` and `stroke-linejoin="round"`; delete the white background rectangle a tracer usually
   adds. Nothing is painted white and nothing is a hole.
3. **Square the box.** `viewBox="0 0 120 120"`, which is what every shape in `art/Shapes.tsx` uses, so they can be
   swapped in and out without touching a stylesheet.
4. **Check both themes at 120px**, and check them at `--app-ink-3`, which is where most of them sit: a shape that
   reads in full ink can vanish at a third of it.
5. **Give it its thing to do.** Every existing shape moves, slowly and on a loop with long rests
   (`art/Shapes.module.css`), and holds still under reduced motion. A ghost has an obvious one: drift up an eighth
   of the square and back, with its hem lagging behind and its shadow staying put. That is a transform and an
   opacity, so nothing lays out again.
6. **Give it its room.** Where a picture leads a page, size it at about 200px rather than the shapes' `7.5rem`
   (one rule in `art/Shapes.module.css`, keyed on the ghost's own class); under the words it stays at 120px, where
   the hatching must still read as strokes - check it there before shipping that one.

## Not asked, so not chosen

How many of these actually ship, whether the ghost replaces the abstract shapes everywhere or lives only in the
empty states beside them, and whether it ever speaks. The 2026-09-13 direction was "abstract shapes, no ink
inspiration" for the guide's pictures; a character is a change of mind about that, and it may be one Matt wants
only where a page is empty.
