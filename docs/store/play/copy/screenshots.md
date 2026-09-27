# The screenshots

Every picture in `screenshots/` is one real screen of the web build of the app at main (1.8.0-20), taken in headless
Chromium over an invented library. Nobody in it is real: Sam, Ana and Ali are first names and nothing more, the call
and the standup never happened, and every number is made up. The seeded notes are Weekend trip, House TODOs,
Groceries, Flat, Reading list, Planning call with Sam, Monday standup, Ideas on the walk, Launch week, the Portugal
book with its three pages, and the Cabin weekend canvas.

Above each screen sits a kicker in the app's eyebrow style and one caption in the app's interface face (Inter, with
the app's own cv11 and ss01), in the app's ink on the app's paper: gray-12 on gray-1 from `src/app/ink.css`, the
third ink for the kicker. No device frame. The band is 380 px of the phone's 1920 (19.8 percent) and 280 of the
tablet's 1440 (19.4 percent), under the fifth Play allows for a tagline. Seven words at most, in the app's own words.

Every file is a 24-bit PNG with no alpha, which is what Play's preview assets page asks for, and `../shots/verify.mjs`
reads each one back with pngjs and prints its pixels and whether it carries alpha.

## Phone, to upload

`screenshots/phone/`, 1080 × 1920 (9:16), the dark theme. Play shows the first two or three in a search result, so
the recorder is first and Hey Ghost second, and the order follows the listing's sections.

| # | File | The screen | What the seed puts on it | Caption |
|---|---|---|---|---|
| 1 | `01-speak.png` | The recorder sixteen seconds into a new note, the words laid out as they were said, a tip on the foot | "Saturday at the market" as the title, "Before we go" as a heading, a to-do with its box, two bullets and a plain line, said with the cues (heading, remember to, bullet point, next point) and the cues taken out | Say it. It lands as Markdown. |
| 2 | `02-hey-ghost.png` | The recorder after "Hey Ghost, add a note to House TODOs": the top line reads Adding to "House TODOs" with Not this note beside it, and the two sentences said next sit under Electrical as to-dos | House TODOs with its headed lists (Electrical, Kitchen, Garden); the words "Call an electrician about the light sockets" and "And check the fuse box while they are here" landed as two boxes | Name the note. The words go there. |
| 3 | `03-tapes.png` | A spoken note open: the tape at the top with its counter, Play, Add and Remove, the Work chip, then the title and the Summary section | Planning call with Sam, a 25:10 tape, a one-line Summary, two items, a Decided line | Every recording keeps its tape. |
| 4 | `04-the-review.png` | After Done: the note with the review's strip across the top (Reviewed, Keep all, Undo) and one marked change, the old line struck through and the new one tinted, with Keep and Revert under it | Notes from the bug bash, a 0:13 tape; "seat bar" heard again as "seek bar" | After Done, the phone reads it through. |
| 5 | `05-a-meeting.png` | A meeting written up: a long tape at the top, the title, the Summary with who has what and what was decided | Monday standup, a 12:40 tape, its Summary (Ana's post by Wednesday, Ali's form, the beta closing on the 28th) | Screen off. Written up when it ends. |
| 6 | `06-the-marks.png` | A typed note scrolled to its marks: a counted list, a highlight, a spoiler in smoke, the ## mark dimmed on a heading, a table and a quote | Weekend trip: Bottles of water [3/8], ==cabin key== highlighted, ||under the third stone|| hidden, the Who brings what table, the quote | Plain Markdown, with marks of its own. |
| 7 | `07-a-board.png` | A board: columns drawn from the fence, cards with their boxes, the first column full | Launch week: This week with three cards, Waiting on Sam beside it | A list can be a board. |
| 8 | `08-home.png` | The home page: the date, the count of to-dos open, the workspace chips, Pinned with its card, the To do list starting under it, the dock | The whole seed, the Weekend trip pinned | Your day on one page. |

**Picture 4** is the app's real review screen. In a browser the two models are played by a script (`?review`,
`src/app/ai/reviewSimulation.ts`): the slower speech model "hears" seat bar as seek bar, and the language model's
thought is fixed text. On a phone with the models installed the same screen shows what those models found. Nothing
on the picture says a word about the script, and nothing on it is drawn that the app would not draw.

**Picture 5** is 1.9.0's, since meetings that record with the screen off are that release's. The screen itself is
1.8.0's spoken note with a summary, which is what a written-up meeting looks like. For a 1.8.0 build, put
`spares/09-the-tapes-shelf.png` in its place and keep the order.

### Spares

`screenshots/phone/spares/`, the same size. Swaps, not additions, since Play takes eight.

| # | File | The screen | Caption |
|---|---|---|---|
| 9 | `09-the-tapes-shelf.png` | The home page scrolled to the Tapes shelf: two cassettes with their titles and first lines, then the Library with the Portugal book and its three pages | Your recordings, on a shelf. |
| 10 | `10-a-canvas.png` | The Cabin weekend canvas fitted to the phone's screen: the group, six cards, lines with words on them, the minimap | Cards on a canvas, lines between them. |
| 11 | `11-things-to-say.png` | The recorder before the first word: Start talking, the listening ghost, and the Things to say card | Things to say, before the first word. |
| 12 | `12-a-spoken-note.png` | Ideas on the walk: a 3:05 tape, a highlight, a to-do and a bullet said with the cues | Said on a walk. The tape stays. |

### The light theme

`screenshots/phone-light/` and `phone-light/spares/` are the same twelve pictures in the light theme, the same names
and sizes, the caption in dark ink on white paper. Play takes one set per slot; the dark one is the app's default and
the one to upload unless the listing should read light.

## Tablet, to upload

Play's preview assets page, read on 2026-09-27, asks for tablet screenshots in "16:9 aspect ratio for landscape and
a 9:16 aspect ratio for portrait", with sides between 1080 and 7680 px. `screenshots/tablet-16x9/` is that shape:
2560 × 1440, a landscape screen of 2400 × 1350 (a 1200 × 675 viewport at a scale of 2, the sidebar docked, the same
library) under the band. The same four files go into both tablet slots, the 7-inch and the 10-inch.

| # | File | The screen | Caption |
|---|---|---|---|
| 1 | `01-home.png` | The home page beside the docked sidebar: the date, the chips, Pinned, the sidebar's Work and Home notes | Your day, with the sidebar docked. |
| 2 | `02-a-tape.png` | Planning call with Sam beside the sidebar: the tape, Play, the title, the Summary | The note, the tape, the summary. |
| 3 | `03-a-canvas.png` | Cabin weekend, laid out: the group, the cards, the lines with words on them | Cards on a canvas, lines between them. |
| 4 | `04-a-book.png` | Portugal in Read, its Index and page chips, the Book index aside on the right | A book, read straight through. |

`tablet-16x9/spares/` holds `05-a-board.png` (Launch week as a board) and `06-a-meeting.png` (Monday standup with its
tape and Summary), swaps and not additions. `tablet-16x9-light/` is the same six in the light theme.

### The Fold opened out

`screenshots/tablet/` and `tablet-light/` are the same six screens at the Fold's inner shape, 1812 × 2176 (a 906 ×
1088 viewport at a scale of 2, the sidebar docked). That is near square, not 9:16, so the tablet slots may refuse
it; it is kept because it is what the app looks like on Matt's own phone, for the landing page or a post, and for the
day Play's slots take a squarer shape.

## The plain set, with no caption

Play's rule also reads that a picture should show "only the app interface". The captioned sets keep the band under
the fifth the same page allows for a tagline, so they are within the rule as written. Should a reviewer read it the
strict way and turn a captioned picture down, `screenshots/plain/` (dark) and `plain-light/` hold every picture with
no caption and no frame: `phone/` and `phone/spares/` at 1080 × 1920, `tablet/` and `tablet/spares/` at 2400 × 1350,
under the same names and numbers, so a plain picture swaps for its captioned one by name.

## How they were made

Everything is under `../shots/`, beside the pack, and runs against `vite preview` of a build of main (the port is in
`../preview.port`).

- `seed.mjs` is the invented library, written into localStorage before the page's scripts run, the way the app's tests
  seed a store: the notes, the gists under the cards, two workspaces, the theme, and the flags that say the walkthrough,
  the sample note and the Academy's card have been seen.
- `shoot.mjs` takes the raw screens into `screenshots/raw/` as `phone-<scene>-<theme>.png` (a 412 × 733 viewport at
  1080/412, cropped to 1080 × 1920) and `fold-<scene>-<theme>.png` (906 × 1088 at 2). The recorder scenes use the
  app's simulated engine (`?simulate=say&say=...`, `src/app/capture/simulated.ts`) so the words arrive as they would
  from a microphone; the review scene adds `&review` and taps Done. Each scene waits for the home page's dock, then
  for the words to settle before the shot.
- `shoot-tablet.mjs` is the same for the landscape tablet, `tablet-<scene>-<theme>.png` at 2400 × 1350.
- `compose.mjs` and `compose-tablet.mjs` draw each raw screen under its caption through `../dist/compose/frame.html`
  and write the finals as 24-bit PNG with no alpha. `plain.mjs` writes the uncaptioned twins.
- `verify.mjs` reads every final back and prints its pixels, its alpha and its size on disk.

To shoot again after the app changes: build main into `../dist`, serve it with `vite preview`, then `node shoot.mjs`,
`node shoot-tablet.mjs`, `node compose.mjs` (once with `--theme=light`), `node compose-tablet.mjs`, `node plain.mjs`
and `node verify.mjs`.

## Not pictured, on purpose

Settings, which a caption could not improve; sync and sharing, which are a sign-in form and a link; the notification
a meeting sends, which the web build cannot show and which would have to be staged; and the Academy and the Guide,
which are the app teaching itself and read better in the app than in a store.
