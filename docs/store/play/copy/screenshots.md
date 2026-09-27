# The screenshots

Eight phone screenshots, in the order Play shows them, then the tablet set from the Fold opened out. Each is one
real screen of the app over the invented library (the notes named here are seeded: Weekend trip, House TODOs,
Groceries, Planning call with Sam, Monday standup, Launch week, the Portugal book and the Cabin weekend canvas; Sam,
Ana and Ali are names and nothing more). The caption is drawn on the picture, in the app's interface type on the
app's paper, above the screen. Seven words at most, in the app's own words.

Phone pictures are 1242 × 2208 (9:16, a 414 × 736 viewport at a scale of 3), 24-bit PNG with no alpha. Play
shows the first two or three in a search result, so the recorder is first and Hey Ghost second.

## Phone

| # | File | The screen | What the seed puts on it | Caption |
|---|---|---|---|---|
| 1 | `phone-01-speak.png` | The recorder fourteen seconds into a new note, the top line New note, the words laid out as they were said, the last phrase still being guessed | The simulated engine says "Title: weekend trip. Heading: before we go. Remember to book the cabin. For the drive we need snacks, water, a charger and the good playlist." The page shows the title, the heading, the to-do with its box, the lead line and four bullets | Say it. It lands as Markdown. |
| 2 | `phone-02-hey-ghost.png` | The recorder after "Hey Ghost, add a note to House TODOs": the top line reads Adding to "House TODOs", the page shows that note, and the sentence said next sits under Electrical as a to-do | House TODOs with its three headed lists (Electrical, Kitchen, Garden); the engine says "Hey Ghost, add a note to House TODOs. Call an electrician about the light sockets." | Name the note. The words go there. |
| 3 | `phone-03-tapes.png` | A spoken note open: the tape at the top with Play, Add and Remove and its counter, then the title and the Summary section, its to-dos as boxes | Planning call with Sam, a 12:40 tape, a Summary of one line, two items, a Decided line and a to-do | Every recording keeps its tape. |
| 4 | `phone-04-the-review.png` | After Done: the note with its marked changes, added words tinted and removed words struck through, Keep and Revert on each. Or, when no model can be run for the shot, the phone at work over the note: the step list (Listening again, Loading the model, Reading the note, Thinking it through, Writing what it found), Heat, CPU and Pace, and the line "It carries on behind the note. Nothing leaves the phone." | The real review, with a model on the phone, over the Planning call note. It is the truer picture, so shoot it if it can be shot. Failing that, the app's own scene played from a script, ?scene=heat in a browser (docs/DESIGN.md §128), over the same note. The note on picture 4 under this table says what the shot may not carry | After Done, the phone reads it through. |
| 5 | `phone-05-a-meeting.png` | A meeting written up: a long tape at the top, the title, the Summary with what was decided and the to-dos | Monday standup, a 47:12 tape, its Summary (Ana's post by Wednesday, Ali's form, the beta closing on the 28th, one to-do) | Screen off. Written up when it ends. |
| 6 | `phone-06-the-marks.png` | A typed note in the editor: the #, ** and - [ ] marks dimmed on the page, a highlight, a spoiler in smoke, a heated line with the line above it wavering, a table and a quote | Weekend trip, with ==the cabin key== highlighted, ||under the third stone|| as a spoiler, one heated line, the Who brings what table and the quote | Plain Markdown, with marks of its own. |
| 7 | `phone-07-a-board.png` | A board: three columns drawn from the fence, cards with their boxes, one in Done ticked | Launch week: This week, Waiting on Sam, Done | A list can be a board. |
| 8 | `phone-08-home.png` | The home page: the date, To do with its boxes, the Tapes shelf with two cassettes and their captions, the Library with the Portugal book, Recent | The whole seed, the Weekend trip pinned | Your day on one page. |

**Picture 4.** The scripted scene is the app's real screen (scene/AtWork.tsx), but its Heat, CPU and Pace readings are
the script's (scene/scripted.ts), not a phone's. The shot must carry no bench bar, so no "The phone at work" title, no
Play again and no close across the top, and no word from Settings › Developer. In the pack, `phone-screenshots/04-the-review.png`
is clean. `phone-04-review.png` in the pack's root was shot with the bar across the top and is not the one to upload.

Spares, if one above cannot be shot on the day: the Tapes shelf close up ("Your recordings, on a shelf."), a canvas
("Cards on a canvas, lines between them."), and the recorder before the first word with the Things to say card
("Things to say, before the first word.").

Picture 5 is 1.9.0's. For a 1.8.0 build, put the Tapes shelf spare in its place and keep the order.

## Tablet: the Fold opened out

Four screens at the Fold's inner size, 2184 × 1968, wide enough for the sidebar to dock. The same files fit both of
Play's tablet slots (the 7-inch takes sides of 320 to 3840 px, the 10-inch 1080 to 7680, each with the long side under
twice the short), so upload the set to both.

| # | File | The screen | What the seed puts on it | Caption |
|---|---|---|---|---|
| 1 | `tablet-01-home.png` | The home page with the sidebar docked beside it: To do, the Tapes shelf with three cassettes, the Library | The whole seed | Your day, with the sidebar docked. |
| 2 | `tablet-02-a-tape.png` | A spoken note beside the docked sidebar: the tape, the title, the Summary | Planning call with Sam | The note, the tape, the summary. |
| 3 | `tablet-03-a-canvas.png` | A canvas: a group, six cards, lines with words on them, the minimap | Cabin weekend, laid out: Book the cabin, Ask Sam about the dog, Packing, The weekend | Cards on a canvas, lines between them. |
| 4 | `tablet-04-a-book.png` | A book open in Read, the Book index aside, Previous and Next at the foot | Portugal, on Lisbon, the first three days | A book, read straight through. |

## Not pictured, on purpose

Settings, which a caption could not improve; sync and sharing, which are a sign-in form and a link; the notification
a meeting sends, which the web build cannot show and which would have to be staged.

## The tablet slots take 16:9 or 9:16 only

Read again on 2026-09-27 from Play's preview assets page: the 7-inch and 10-inch tablet slots take pictures with
sides between 1080 and 7680 px and, in the page's words, "16:9 aspect ratio for landscape and a 9:16 aspect ratio for
portrait". The Fold opened out is near square (1812 × 2176 as shot in a browser, 2184 × 1968 on the phone), so that
set cannot go up as it is. Its raws stay in `screenshots/raw/` under `fold-*` as a reference for the day the slots
take a squarer shape, and nothing else uses them.

The set to upload is `screenshots/tablet-16x9/` (the dark theme) or `screenshots/tablet-16x9-light/` (the light
one), made by `../shots/shoot-tablet.mjs` and `../shots/compose-tablet.mjs`. Each is 2560 × 1440, a 24-bit PNG with
no alpha: a landscape screen of 2400 × 1350 (a 1200 × 675 viewport at a scale of 2, the sidebar docked, the same
invented library) under a band of 280 px for the kicker and the caption, which is 19.4 percent of the picture, under
the fifth Play allows for a tagline. The same four files go into both tablet slots.

| # | File | The screen | Caption |
|---|---|---|---|
| 1 | `tablet-16x9/01-home.png` | The home page beside the docked sidebar: the date, To do, Pinned, the Library | Your day, with the sidebar docked. |
| 2 | `tablet-16x9/02-a-tape.png` | Planning call with Sam beside the sidebar: the tape, the title, the Summary | The note, the tape, the summary. |
| 3 | `tablet-16x9/03-a-canvas.png` | Cabin weekend, laid out: the group, the cards, the lines with words on them, the minimap | Cards on a canvas, lines between them. |
| 4 | `tablet-16x9/04-a-book.png` | Portugal in Read, the Book index aside | A book, read straight through. |
| 5 | `tablet-16x9/spares/05-a-board.png` | Launch week as a board, three columns | A list can be a board. |
| 6 | `tablet-16x9/spares/06-a-meeting.png` | Monday standup with its long tape and its Summary | Screen off. Written up when it ends. |

The two spares are swaps, not additions, and picture 6 is 1.9.0's.

## The plain set, with no caption

Play's screenshot rule also reads that a picture should show "only the app interface", with a tagline allowed on at
most a fifth of it. The captioned sets keep their band under the fifth (the phone's 380 px of 1920 is 19.8 percent,
the tablet's 280 of 1440 is 19.4), so they are within the rule as written. Should a reviewer read it the strict way
and turn a captioned picture down, `screenshots/plain/` (dark) and `screenshots/plain-light/` hold the same
pictures with no caption and no frame: `phone/` at 1080 × 1920 and `tablet/` at 2400 × 1350, both 16:9 or 9:16,
24-bit PNG with no alpha, under the same names and numbers, so a plain picture swaps for its captioned one by name.
`../shots/plain.mjs` writes them from the raws.
