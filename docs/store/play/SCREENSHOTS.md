# The pictures

What each picture in the pack shows, the caption drawn over it, and how the set was made, so the next release can
remake it in an hour. The PNGs are not in the repo: they were delivered beside this folder's markdown, in the
scratchpad's `store/play/` folder, and are uploaded straight from there.

## The set

Each phone and tablet screenshot is one real screen of the web build of 1.8.0-20's tree, over an invented library,
set in a frame: the app's paper, one short caption in the app's interface font (Inter), and the screen as a rounded
card running off the foot. Nothing else is drawn on them. The captions are the app's own words for the things they
name.

| File | Size | Screen | Caption |
| --- | --- | --- | --- |
| `phone-screenshot-01.png` | 1242 × 2208 | The recorder fourteen seconds into a take, the words laid out as they were said: a title, a heading, two to-dos, and a list said in one breath | Say it. It lands as Markdown. |
| `phone-screenshot-02.png` | 1242 × 2208 | The recorder after "Hey Ghost, add a note to House TODOs": the top line reads Adding to "House TODOs", and the two sentences said next sit in the Electrical list | "Hey Ghost, add a note to House TODOs." |
| `phone-screenshot-03.png` | 1242 × 2208 | A spoken note, Planning call with Sam: the tape at the top with Play, Add and Remove, then the title and the Summary section with its to-dos | Every recording is kept. The summary is written on the phone. |
| `phone-screenshot-04.png` | 1242 × 2208 | The home page: the date, the digest, To do with five rows, and the Tapes heading with the row's top edge | Your day on one page. |
| `phone-screenshot-05.png` | 1242 × 2208 | The home page scrolled to Tapes: two cassette cards with their summaries and counters, then the Library with the Portugal book | Your recordings, on a shelf. |
| `phone-screenshot-06.png` | 1242 × 2208 | A typed note, Weekend trip, in the editor: the `#` and `**` marks dimmed on the page, a to-do list, a heading | Plain Markdown, with the marks on the page. |
| `phone-screenshot-07.png` | 1242 × 2208 | A board note, Launch week: the columns drawn from the fence with their cards | A board is a list with names on it. |
| `phone-screenshot-08.png` | 1242 × 2208 | The same spoken note as 03, on the dark page, in a dark frame | Light or dark. |
| `tablet-7-inch-screenshot-01.png` | 1080 × 1920 | The home page at a 7-inch width: Pinned, To do and the Tapes row with three cassettes | Your day on one page. |
| `tablet-7-inch-screenshot-02.png` | 1080 × 1920 | The recorder mid-take, as 01 | Say it. It lands as Markdown. |
| `tablet-7-inch-screenshot-03.png` | 1080 × 1920 | The spoken note with its tape, as 03 | Every recording is kept. The summary is written on the phone. |
| `tablet-10-inch-screenshot-01.png` | 2560 × 1440 | The home page with the sidebar docked, the way the opened Fold has it | Your day on one page. |
| `tablet-10-inch-screenshot-02.png` | 2560 × 1440 | The spoken note beside the docked sidebar | Every recording is kept. The summary is written on the phone. |
| `tablet-10-inch-screenshot-03.png` | 2560 × 1440 | A canvas, Cabin weekend, laid out: a group, cards, a table, a Mermaid chart and lines with words on them | Cards on a canvas, kept as a file Obsidian opens too. |
| `feature-graphic.png` | 1024 × 500 | The mascot from the app icon on lined paper, the name, and one line: Notes you type or say. | |
| `app-icon.png` | 512 × 512 | The Tauri icon set's 512, `src-tauri/icons/icon.png`, unchanged: the dotwork ghost on lined paper, every pixel opaque | |

The order is the store's. A search result shows the first two, so the recorder comes first and Hey Ghost second.
The phone set is eight, the store's most; each tablet set is three, enough to show the app is laid out for the width.

Not pictured, on purpose: meetings, which 1.9.0 is building; the AI runs and the review, which need a model the web
build has no way to run, so a screenshot would have to be staged; Settings, which says nothing a caption could not.

## The library in the pictures

`seed.mjs` beside the script writes fourteen notes into the web build's localStorage before the page loads: three
spoken notes with tapes (a planning call with a summary, a standup with a summary, a voice note from a walk), a pinned
trip note, House TODOs with three headed lists, a groceries list, a board, a three-chapter book, a reading list, a
note about a flat, and a canvas. Sam, Ana and Ali are names and nothing more; the meeting never happened; the
numbers are made up. The gists under the cards and the summaries are seeded as the phone's models would write them,
because the web build has no model to write them with. Nothing in the seed is a secret, a token or a real person's.

## How it was made

From the branch's tree, with the box left alone:

1. `npx vite build --outDir <scratch>/store/dist` in the worktree. The OTA manifest step at the end fails on an
   absolute `--outDir` (vite.config.ts joins it to the root), after the page is built; the page is whole.
2. `npx vite preview --outDir <scratch>/store/dist --port <free> --strictPort`.
3. `node shots.mjs http://localhost:<port>/`: Playwright 1.59 from the npx cache, headless Chromium, one context
   per screen. A phone is a 414 × 736 viewport at a device scale factor of 3, so the PNG is 1242 × 2208, which is
   9:16; the 7-inch tablet is 675 × 1200 at 1.6 (1080 × 1920); the 10-inch is 1280 × 720 at 2 (2560 × 1440).
   Each context runs the seed as an init script, waits for the dock, acts (opens a note by its title, or taps
   Speak), settles, and screenshots. The recorder is driven by the app's own `?simulate=say&say=a|b` engine
   (capture/simulated.ts), which speaks the phrases given at a word every 180 ms with no microphone, so the words on
   the page are what the app draws from them.
4. The same script then composes each raw screen into `dist/compose/frame.html`, at the same viewport and scale,
   and screenshots that: the caption, the card, the paper. The feature graphic is the same page with `?feature=1`
   at 1024 × 500 and a scale of 1. The icon is copied.

`shots.mjs --only=<name>` retakes one raw screen and recomposes the set; `--compose-only` recomposes without
retaking. The script, the seed and the frame live with the pictures in the scratchpad, not in the repo.

## Before uploading

- Every phone and tablet PNG is RGB with no alpha channel, as Play asks; the icon keeps its alpha channel, as Play
  asks of it.
- The date on the home page is the day the shots were taken. Retake the set on the day of the upload if that
  matters; it takes about four minutes.
- A frame with a caption is allowed; a device frame is not needed. If Play's featuring guidance is wanted to the
  letter, the raw screens in `dist/compose/raw/` are the same pictures with no caption at all.
