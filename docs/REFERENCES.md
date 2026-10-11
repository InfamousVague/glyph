# References: what holds each drawn thing to Ghost.md's own page

Begun 2026-10-11. docs/PARITY.md says what the port has; this says what proves a thing is drawn as the page draws
it, and what does not yet. It follows PARITY.md's sections, area by area.

## How a thing is held

A **reference** is three things kept together: a tool that draws the thing in the ORIGINAL's page in Chromium
(`../glyph` on a Vite dev server of its own port, read-only; Playwright from the npx cache), the fixtures it writes
(every box's rectangle, the computed inks and types, and a picture), and a test that draws the same thing here and
compares. The tool's header says the command that remakes its fixtures.

How strongly a thing is held, weakest last:

| Mark | Means |
| --- | --- |
| **R** | Rectangles from a tool's fixtures, each within half a pixel (`tolerance`, the same in every reference test). |
| **P** | A picture laid over the page's own (`test/support/page_picture.dart`): the same size, the ground the same colour wherever either picture has ground, the ink within a limit, each limit proven by a drawing made wrong on purpose. Only `test/editor/blocks` and the smoke (`test/art`, `test/editor/marks/effects_parity_test.dart`) have this. |
| **N** | Numbers read off the page once and written into the test. They hold, but no tool remakes them, so nobody can tell when the page has moved. |
| **O** | The port's own pictures (`shots/`, `matchesGoldenFile`). They say when a drawing changes, not whether it is the page's. The page's picture is often beside it for the eye (`fixtures/*.png`, `fixtures/web/`), and nothing compares the two. |
| **—** | Nothing. |

Widths: **390** is the phone (390 x 844), **704** the Fold's inner screen (704 x 933). 840, 1200 and 1280 are a
desktop's window, which is another layout: they do not stand for the Fold. Sides: **L** light, **D** dark. A tool
that takes its numbers on the light page and a picture of the dark one holds the dark page's colours by nothing
(`L, D to look at`).

What a picture cannot tell, measured here (`test/editor/blocks/reference_test.dart`, "drawn wrong on purpose"): a
corner four pixels tighter, a word in bold among twenty lines, a sloped line of eleven letters. Those are held by
the look's own facts (the corner, each letter's weight and slope against the page's computed style). What it does
tell: a ground a shade off (484,581 pixels of ground, where the limit is 60), square corners (976), a seam between
two lines (6,156, in runs of 684), a bar that should not be there (336, in a run of 121), words four pixels along
(7,258), another code theme (ink 87.7 at its worst place, where the limit is 40).

## The map

| PARITY § | Area | Held by | Sides | Widths | Not held |
| --- | --- | --- | --- | --- | --- |
| 1 | Launch screen | N `test/launch/launch_screen_test.dart`; O | L (D: O) | 390 | No tool. The sync and update lines; the Fold. |
| 2 | Welcome guide (four pages, the table, too soon) | R `test/guide/measure_test.dart` over `test/guide/fixtures/*.json`; the page's pictures in `fixtures/web/` to look at | L, D to look at | 390 | The tool that made the fixtures is not in the repository (`fixtures/web` has only pictures). The Fold. |
| 3 | Home: search, filters, the four layouts, cards, rows, notices, organizations, the dock | N `test/home/home_screen_test.dart`, `home_parts_test.dart`; O | L (D: O) | 390 | No tool. Dark by rectangles; the Fold; an organization's events; a notice's states. |
| 4 | Top bar, tabs, groups | N `test/notes/note_tabs_test.dart`; the note's bar R `test/note/note_frame_test.dart` (`test/note/reference/note_reference.mjs`) | L, D to look at | 390, 840 | The four bar styles by a tool; a tab's menu; a group's chip and its menu; the Fold. |
| 5 | Sidebar | N `test/sidebar/notes_drawer_test.dart`; O | L (D: O) | 390 | No tool. Docked (a wide window); the Trash; names only. |
| 6 | All notes | N `test/allnotes/all_notes_screen_test.dart`; O | L (D: O) | 390 | No tool. The workspace pills' sheet; the Fold's two columns. |
| 7 | The + sheet | N `test/allnotes/new_sheet_test.dart`; a notebook's and a journal's sheets R `test/book_ui/reference_test.dart` (`sheet-*`) | L, D to look at | 390, 1280 | The sheet's own rows by a tool; Meeting's switch; From a shared link. |
| 8 | A blank page: names, template cards | the names R `test/editor/items/reference_test.dart` (`open-mixed`); cards N `test/allnotes/template_cards_test.dart` | L | 390 | The names as a block after line 1 in dark and at 704; the cards by a tool; "a second". |
| 9 | The note's screen: bar, header, byline, More | R `test/note/note_frame_test.dart` (`note_390.json`, `note_840.json`: the bar's tools, the header pane, the page, the byline, every block of More) | L, D to look at | 390, 840 | **More's pages**: Journal, Ticket key, AI, Reading it, Workspace, Version history. The picture that did not come in; the tape's transcript over the note; the Fold. |
| 10 | Editor: Markdown (headings, lists, quotes, callouts, front matter, definitions, inline marks) | R `test/editor/view/reference_test.dart` (`tool/editor_reference.mjs`, 53 cases: lines, runs, `coordsAtPos`, `posAtCoords`) | L; D for five notes | 390 | Pictures only to look at. 704. Four `-inter` cases wait on JetBrains Mono. |
| 10 | **Fenced code**: the card, its ground, corners, padding, lines, where it wraps, the seven themes on both sides | **R P** `test/editor/blocks/reference_test.dart` (`tool/blocks_reference.mjs`, `code-*`: 19 cases); tokens by the web's parsers `test/editor/code/conformance_test.dart` | L, D | 390, 704 | There is no language label on the page and no sideways scroll: a block wraps. Nothing left. |
| 10 | **A word too long for its line** (an address, a long string): where it wraps, where the caret stands | **R P** the same (`long-words*`, `code-places*`, with `coordsAtPos` at every position) | L | 390, 704 | Dark (nothing in it is a colour). |
| 10 | **Maths**: in a line, set apart, alone on its line, numbered rows, a tag, the source with the caret in it, one that cannot be read | **R P** the same (`maths*`: 13 cases held); heights by KaTeX `test/editor/maths/katex_test.dart` (130 pieces) | L, D | 390, 704 | `maths-larger`: a formula that does not fit what is left of its line (the page ends the line between two pieces of it; here it goes down whole). `maths-overwide`: not copied, see below. A long press's panel. |
| 10 | **A diagram's box**: its words before its picture, its mistake, nothing to draw it, its picture's place | **R P** the same (`mermaid-*`: 10 cases); the picture itself against the web's, by hand, `tool/diagram_reference.mjs` | L, D | 390, 704 | The picture's own pixels are compared by the tool when it is run, and by no test. |
| 10 | A table drawn | R `test/editor/tables/reference_test.dart` (26 cases) | L, D | 390 | 704; "+ Column", "+ Row" pressed. Pictures to look at. |
| 11 | The twelve marks, the five effects, the smoke | R `test/editor/marks/reference_test.dart`; P heat, haze and frost `effects_parity_test.dart`; the smoke `test/art/wisp_parity_test.dart` (`tool/wisp_reference.mjs`) | L, D | 390 | Wave, shimmer and haunt by picture (they are held at three moments by rectangles only); a mark's note panel; 704. |
| 12 | Small marks in a line: tags, people, dates, counters, sums, choices, footnotes, wiki links, anchors, the bookmark, progress | R `test/editor/items/reference_test.dart` (7 cases) | L | 390 | Dark. The pages a chip opens (date, priority, person): **the band's page for a chip** is held as the band's (`test/editor/band`), not by chip. 704. |
| 13 | Pictures, films, memos, places, link cards | R `test/editor/media/*_reference_test.dart` (31 cases) | L, D | 390 | A film playing; a memo playing; the map at the top beyond one case; 704. |
| 14 | The + and its list, More, the pickers | R `test/editor/plus/plus_reference_test.dart` (50 cases) | L, D | 390 | 704. |
| 14 | The band (press and hold), the style page | R `test/editor/band/band_reference_test.dart` (23 cases, three wide ones) | L, D | 390, a wide window | 704. |
| 14 | Find and replace | R `test/editor/find_bar/reference_test.dart` (16 cases) | L, D | 390, one wide | 704. |
| 15 | Comments: the round, the wash, the fence drawn as threads, a thread's card, the sheet | O (`test/comments`, `test/editor/comments`) | L, D | 390 | **No reference at all.** The fence's cards were set with their words a pixel and a quarter low (found by the diagram's reason line, which shares their face: `lib/editor/looks/note_face.dart`); nothing says whether they are right now. |
| 16 | Boards | R `test/editor/boards/reference_test.dart` (23 cases) | L, D | 390 | 704; a card held mid-air beyond two cases. |
| 17 | Tickets: the panel, its fields, `[[GHO-12]]` | R `test/editor/tickets/reference_test.dart` (10 cases) | L, D | 390 | A field's own page (status, people, dates); 704. |
| 18 | Queries: list, table, board, calendar, timeline, count; the builder | R `test/editor/queries/reference_test.dart` (40 cases) | L, D | 390 | The builder's sheet; the view switcher pressed; 704. |
| 19, 20 | Notebooks and journals: index, a page's bar and foot, reading straight through, the sheets | R `test/book_ui/reference_test.dart` (`tool/book_reference.mjs`, 27 fixtures) | L, D to look at | 390, 1280 | Dark by rectangles; 704; the read-through rail's states. |
| 21 | Canvas | R `test/canvas/reference_test.dart` (`tool/canvas_reference.mjs`) | L, D | 390, 1280 | One canvas, at rest. A card picked, a line being drawn, the minimap, a chart card's diagram; 704. |
| 22 | The recorder and its live page, the chip, confirm, landing | R `test/capture_ui/recorder_page_test.dart`, `meeting_page_test.dart` (`test/capture_ui/reference/capture_reference.mjs`, 16 fixtures) | L, D by colours | 390, 1200; rest at 704 x 933 and 933 x 704 | The live page's cards past the first; the review; a spoken command's card. |
| 25 | Meetings | R the same (`meeting-*`) | L, D | 390, 1200 | The write-up; the summary's card. |
| 26 | Tapes: the shelf, the player | O `test/tapes` | L | 390 | **No reference.** A voice memo in a note is held (§13). |
| 27 | AI: the strip, blanks, the review, the scene | O `test/ai`, `test/editor_ai`, `test/scene` | L, D | 390 | **No reference.** |
| 28, 29 | Account, organizations, the gate | R `test/account_ui/reference_test.dart` (`tool/account_reference.mjs`, 12 fixtures) | L, D to look at | 390, 1280 | Dark by rectangles; 704; an organization's settings beyond members. |
| 30 | Shared links and the reader | — | | | **No reference.** |
| 31 | The bell's drawer | N `test/sidebar/notifications_drawer_test.dart`; O | L (D: O) | 390 | No tool. |
| 32 | The palette | R `test/commands/command_bar_test.dart` over `test/commands/fixtures/web_palette.json` | L, D | 390, a wide window | The tool that made the fixture is not in the repository. 704. |
| 33 | Settings: every page | Appearance N `test/settings/appearance_pane_test.dart`; the others N in part `test/settings/panes/*`; the plugins' pages R `test/plugins/*/` (GitHub, Notion, Slack, Claude) and `test/plugins/plugins_pane_test.dart`; Developer's benches R `test/diag/benches_reference_test.dart` | L (D: O) | 390 | **No tool in the repository for any page** (the plugins' and the benches' fixtures are kept without the tool that made them). Recording, AI, Notifications, Sync, About, Developer, Library: numbers in part, dark by nothing. |
| 34 | Plugins in a note: pills, rows, the swipe | R `test/plugins/editor/reference_test.dart` (11 cases) | L, D | 390 | 704. |
| 35 | Academy, cheat sheet | R `test/academy/reference_test.dart` (6 fixtures, `fixtures/web_academy.mjs`) | L, D to look at | 390 | The specification; dark by rectangles. |
| 41 | A wide window and the Fold | R `test/aside/aside_panel_test.dart` (`aside_704.json`) | L | 704 | Everything else at 704: this is the largest gap. The tool that made the fixture is not in the repository. |
| 42 | Sheets (the app's own) | N `test/sheet/sheet_test.dart`, `kit_test.dart`; O | L | 390 | No tool. |

## What 2026-10-11 added

One tool, `tool/blocks_reference.mjs`, 46 fixtures in `test/editor/blocks/fixtures/`, and
`test/editor/blocks/reference_test.dart` (44 cases held, 2 said why not, 9 drawn wrong on purpose). It is the first
reference that holds a picture of a note to the page's by a test, and the first that holds anything of the editor at
the Fold's width. `test/support/page_picture.dart` is there for the next one.

What it found, each fixed from the page's own rule and not by its numbers:

| Found | Before | After | Where |
| --- | --- | --- | --- |
| A word too long for what is left of its line (an address after "See", a string after `const s =`) was cut where it stood. The page takes it to the next line first, and cuts it only if it is longer than a line. | `const unbroken = "aaa…` on the first line at 704, two visual lines | on its own lines, three, as the page; the caret within 0.5 px at every position, either side | `lib/editor/view/line.dart` `_lateBreak`, `projection.dart` `PaintText.forced` |
| A formula kept the size it was first drawn at: after the words were made larger, or drawn small on a card and then in the note. | the set-apart sum 152.7 px wide at the usual size and at the larger | 152.7 and 195.1, the page's 195.1 | `packages/flutter_math_fork` (README 21) |
| A root where the type is smaller (the quadratic formula in a line, a root in a script). | 1.35 em above the baseline, the line 3.7 px taller | 1.04 em, KaTeX's; fifteen such roots in `katex.json` | `packages/flutter_math_fork` (README 22) |
| `$$…$$` alone on its line has an empty line above and below it on the page (CodeMirror's buffers are line boxes of their own). | 83.7 px | 131.6, the page's 131.625 | `lib/editor/maths/maths.dart` `_BufferLines` |
| A formula that cannot be read: its lines at the note's leading, its dots as the page's engine draws them (a tenth of the type thick, a quarter of an em under the baseline, two pixels on and two off). | a block of three lines 76.9 px, hairline dots | 89.9 (the page 89.8), the page's dots | `maths.dart` `DottedUnderline` |
| A short formula set apart (`x`, `a = b`) is as tall as the two faces' boxes together. | 2 px short | the page's, to 0.03 px | `maths.dart`, `formula.dart` `letterInLine` |
| A block of code in a quote had the quote's bar down its card. | a bar 3 px wide | none (`background` is the shorthand) | `lib/editor/looks/markdown_look.dart` |
| A diagram's words stood on whole-pixel lines, and its reason a pixel and a quarter low. | four lines 92 px | 90, each line's letters where the page's are | `lib/editor/diagrams/diagrams.dart`, `looks/note_face.dart` |
| A line box's height: the type to the nearest sixty-fourth, times the leading, down. | a sixty-fourth out for two sizes in five (forty lines of code at 704: half a pixel) | Blink's rule, 836 sizes of 836 | `lib/editor/looks/look.dart` `lineBoxHeight` |
| The faces a formula is drawn in are KaTeX 0.16's, as the page's. | an earlier cut | the page's twenty files | `packages/flutter_math_fork` (README 23) |

And one thing about the tests themselves: a test's window is at three device pixels to one whatever the test says
of its view, so an edge "on a whole pixel" was on a third of one in a picture taken at two, and every block of code
in every picture had a seam between its lines that no phone draws. A reference says the picture's own ratio
(`debugPaintPixelRatio`). The pictures in `shots/` still have the seam: they were not drawn again, and are the
port against itself.

## Not copied from the page, on purpose

- **A formula wider than the screen** (`maths-overwide`). On the page the whole note grows as wide as the formula:
  `.cm-content` is a flex item no narrower than what is in it, so in a window of 390 every line is 834 px wide, the
  words run off the screen and the note scrolls sideways. mathsDrawn.ts says it means the formula to scroll ("rather
  than running off it"). Here the note keeps to the screen and the formula scrolls in its box. This is a mistake in
  `../glyph` worth mending there.
- **Mermaid's own error picture.** A diagram written wrong leaves Mermaid's "Syntax error" element at the foot of
  the page's `body` (mermaid.ts asks `mermaid.render` without `suppressErrorRendering`). The tool cuts its picture
  above it. Also `../glyph`'s to mend.

## Measured beside the page on a phone, and where each stands

The side-by-side walk (an emulator at 1248 x 1972, 2.625 device pixels to one) measured these inside a note. A
reference here is Chromium at two pixels to one with its layout in whole CSS pixels, so what is a matter of the
phone's own pixels is not held by any of them yet (see 1 below).

| Measured on the phone | Stands |
| --- | --- |
| `$$ E = mc^2 $$` set apart: 105 px here, 108.37 on the page, and everything under it 4 or 5 px high | **Fixed and held**: the line of a short formula is two faces' boxes (`maths-rows`, to 0.03 px at a phone's width and the Fold's). Not yet seen again on the phone. |
| A home card of a note with maths in a line: its first line 2 or 3 px low | **Probably the formula's size** (a tree first drawn at the note's size and then on the card, or the other way: fixed, held by `katex_test.dart`). No reference draws a card with maths in it. |
| A table of three rows 3 px taller | Not held. `test/editor/tables` agrees to half a CSS pixel at two to one; this is the phone's pixels. |
| A query's list rows +1 to +3 px, its table +3 to +6 down four queries; a board's cards 3 or 4 px high | Not held, the same. |
| Code: the lines' boxes right, the letters a pixel short by column 40 | Not held. Here a letter's advance is 0.009 px LONG a letter at two to one (a third of a pixel by column 40, `long-words-fold`), so this too is the phone's: an advance rounded there. |

## Still unheld, most seen first

0. **The phone's own pixels.** Every reference is drawn with Chromium told two device pixels to one by Playwright,
   which lays out in whole CSS pixels; a phone's page is laid out in its own (2.625 on the Fold's emulator: a
   border is a whole number of THEM, a line's leading a sixty-fourth of one). `lib/editor/looks/look.dart` has the
   arithmetic for it (`lineDpr`, measured beside the emulator), and nothing made by a tool holds it. The
   instrument is there, measured 2026-10-11 on one page (`font-size: 10.8px; border-top: 0.35em solid`, and a
   line of 14.9385 px at 1.6):

   | Chromium | the border | the line |
   | --- | --- | --- |
   | Playwright's `deviceScaleFactor: 2` | 3px | 23.890625 |
   | Playwright's `deviceScaleFactor: 2.625` | 3px | 23.890625 |
   | launched with `--force-device-scale-factor=2.625 --window-size=475,751`, `viewport: null` | 3.42857px (nine device pixels) | 23.904762 (4016 sixty-fourths of a device pixel) |

   The third is the phone's layout. A tool that takes a ratio that way, fixtures named for it, and a test that
   says `measuredAt: 2.625` (test/support/render.dart) and takes its picture at 2.625 would hold the rows above;
   `tool/blocks_reference.mjs` is the place to begin, then the tables', the queries' and the boards'.

1. **The Fold's width for everything but the note's blocks and the aside.** Each editor reference would take the
   Fold as `tool/blocks_reference.mjs` takes it: a second window of 704, the same notes. The `-inter` and `-larger`
   cases show the tools already carry such variants.
2. **A formula that does not fit what is left of its line.** It needs each piece of a formula to be a thing of its
   own in the line (`Formula.parts` are the pieces already), so the line can end between two.
3. **Comments.** No tool draws the fence's threads, a thread's card or the sheet.
4. **More's pages, a ticket's field pages, a chip's page in the band, a query's builder.** Each is a sheet over a
   note; `test/note/reference/note_reference.mjs` opens More and measures its first page, and is where the others
   would go.
5. **Settings.** Thirteen pages with numbers in tests and no tool; dark by nothing.
6. **The shell by a tool**: home, the sidebar, All notes, the sheets, the launch screen, the bell's drawer. Their
   numbers were read off the page by hand.
7. **Tapes, the AI's strip and review, shared links' reader.** Nothing.
8. **A word too long for its line outside the editor.** Every `Text` the app draws cuts such a word where it
   stands, as the editor's lines did: the guide's marks table shows `[Ghost.md](https://` / `attack.fm/glyph)` in
   its source column where the page has `[Ghost.md]` / `(https://attack.fm/g` / `lyph)`
   (test/guide/fixtures/web/table-light.png). The rule is in `lib/editor/view/line.dart` `_lateBreak` and wants a
   home any text can ask.
9. **Pictures as tests for the references that have them only to look at.** `test/support/page_picture.dart` and a
   repaint boundary round the host are all a reference test needs; the `fixtures/*.png` are there already.
