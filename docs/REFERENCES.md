# References: what holds each drawn thing to Ghost.md's own page

Begun 2026-10-11. docs/PARITY.md says what the port has; this says what proves a thing is drawn as the page draws
it, and what does not yet. It follows PARITY.md's sections, area by area.

## How a thing is held

A **reference** is three things kept together: a tool that draws the thing in the ORIGINAL's page in Chromium
(`tauri/` on a Vite dev server of its own port, read-only; Playwright from the npx cache), the fixtures it writes
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
| 10 | **Maths**: in a line, set apart, alone on its line, numbered rows, a tag, the source with the caret in it, one that cannot be read | **R P** the same (`maths*`: 14 cases held, and two in a phone's pixels); heights by KaTeX `test/editor/maths/katex_test.dart` (130 pieces) | L, D | 390, 704 | `maths-overwide`: not copied, see below. A long press's panel. |
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
| A formula in a line that does not fit what is left of the line went to the next line whole. The page ends the line between two pieces of it (after a relation or an operator). | `## Energy, $E = mc^2$` at the larger size: the formula on the second line | `E =` on the first, `mc²` on the second, to 0.10px (`maths-larger`, `phone/maths`) | `lib/editor/maths/maths.dart` `MathsWidget.piece` (second batch) |
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
  `tauri/` worth mending there.
- **Mermaid's own error picture.** A diagram written wrong leaves Mermaid's "Syntax error" element at the foot of
  the page's `body` (mermaid.ts asks `mermaid.render` without `suppressErrorRendering`). The tool cuts its picture
  above it. Also `tauri/`'s to mend.

## In a phone's own pixels (2026-10-11, the second batch)

Every reference was Chromium told two device pixels to one by Playwright, which only PAINTS at that scale: the page
is laid out in whole CSS pixels (a border of 0.35em at 10.8px is 3px at any factor). A phone's page is laid out in
the phone's pixels: `border: 1px` is two of them at 2.625 (0.762px), a line's leading a sixty-fourth of one, a
face's ascent a whole one. Chromium LAUNCHED at a scale lays out that way:

| Chromium | `border-top: 0.35em` at 10.8px | a line of 14.9385px at 1.6 |
| --- | --- | --- |
| Playwright's `deviceScaleFactor: 2` or `2.625` | 3px | 23.890625 |
| launched with `--force-device-scale-factor=2.625 --window-size=475,…`, `viewport: null` | 3.42857px (nine device pixels) | 23.904762 (4016 sixty-fourths of a device pixel) |

Five tools take it (`GLYPH_RATIO=2.625 node <tool>`: a window of 475, the Fold's cover screen, 1248 across at
2.625) and write to `fixtures/phone/`; their tests draw those at 2.625 (`measuredAt`, test/support/render.dart).
The Fold unfolded is 1848 across at the same 2.625 (704), so the ratio is one; only the width differs.

| Tool | Cases in `phone/` | Before | After |
| --- | --- | --- | --- |
| `test/editor/tables/fixtures/reference.mjs` | 18 | 0.88 to 1.58px out; a table of four rows 1.13px tall | worst 0.079px |
| `test/editor/queries/fixtures/reference.mjs` (queries) | 15 | a list card 0.60px tall, a table card 0.96; pieces 1.16 to 1.97px out | both cards to 0.01px; worst piece 0.40px |
| the same (tickets) | 3 | within half a pixel already (0.48) | the same |
| `test/editor/boards/fixtures/reference.mjs` | 9 | a card's and a lane's words 0.55 to 0.87px out | worst 0.025px |
| `tool/blocks_reference.mjs` | 7, 5 held | code and short formulas held as they stood | boxes to 0.40px, carets to 0.10 |

What was wrong was the same in each: a rule one CSS pixel wide, lengths to a sixty-fourth of a CSS pixel, and a
face's ascent and half-leading in whole CSS pixels (`WordsFace`, `blinkLineHeight`, `pageLine`, `glyphBox`, each
look's own lengths). They are the pixels the page is laid out in now (the tokens' `css.lineDpr`).

**What the instrument is not.** It is a Mac's Chromium. A phone's (Android's, and Linux's) rounds a face's
ascent and descent another way where subpixel text is on: a descent rounded down gets a pixel from the ascent
(`lib/editor/looks/look.dart` `_box`, measured beside the emulator); a Mac's rounds each to the nearest. A line
made of two boxes of different sizes (a heading's tight box in the line's own, wrapped onto several visual lines)
can be a device pixel a visual line different between the two: `phone/long-words` is measured and not held for
that, and says so. Where the two disagree, only the phone can say; the port keeps the phone's rule.

## Measured beside the page on a phone, and where each stands

| Measured on the phone (1248 x 1972 at 2.625) | Stands |
| --- | --- |
| A table of three rows 3 device px taller | **Fixed, held** (`tables/fixtures/phone/three`: 0.019px). |
| A query's list rows +1 to +3, its table +3 to +6 down four queries | **Fixed, held** (`queries/fixtures/phone/`: the cards' heights to 0.01px). |
| A board's cards 3 or 4 px high against the text above | **Fixed, held** (`boards/fixtures/phone/`: 0.025px). |
| `$$ E = mc^2 $$` 105 against 108.37, everything under it 4 or 5 px high | **Fixed, held** at two to one and in the phone's pixels (`maths-rows`, `phone/maths-rows`). |
| Code: the letters a pixel short by column 40 | **Not this engine's advances.** In the phone's pixels a line of code's last letter is where the page's is to a tenth of a pixel (`phone/code-places`, the caret at every position). What was seen is the phone's own drawing of the face (Android's WebView against Flutter's on the same glyphs: hinting, or where a glyph's pixels are put), and wants measuring on the phone. |
| A home card of a note with maths in a line: its first line 2 or 3 px low | **Probably fixed** (a formula kept the size it was first drawn at: batch 1); no reference draws a card with maths in it yet. |

## Still unheld, most seen first

0. **The phone's own pixels for the rest of the editor.** Tables, queries, tickets, boards and a note's blocks
   are drawn that way; the base editor's own cases (`tool/editor_reference.mjs`), the marks, the items, the media
   (whose words in a box are still set in whole CSS pixels: `lib/editor/media/inline_box.dart`, and with them a
   diagram's words, `phone/mermaid-missing`), the +, the band and the find bar are not. Each tool takes the same
   dozen lines.
1. **The Fold's width for everything but the note's blocks and the aside.** Each editor reference would take the
   Fold as `tool/blocks_reference.mjs` takes it: a second window of 704, the same notes. The `-inter` and `-larger`
   cases show the tools already carry such variants.
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
10. **Words placed by what a paragraph says of its baseline, outside the editor.** A paragraph inks a line's
    baseline on the whole pixel nearest the line's ascent; it says something else twice over (`LineMetrics.baseline`
    is the rounded height less the descent, a painter's distance to its baseline is the ascent unrounded), and
    words set on the page's baseline by either stand up to three quarters of a logical pixel off it, with their
    boxes right. The editor's own places are put right (`lib/editor/looks/look.dart` `inkBaseline`: a line's words,
    its marker, raised runs, a table's cell, a chip's words, an effect's letter; held by
    test/editor/view/ink_rows_test.dart and test/editor/tables/ink_rows_test.dart against the page's pictures).
    The same error is still in `packages/glacier/lib/src/tokens/exact_lines.dart` and `line_height.dart` (every
    label the kit sets on the page's line), `lib/sheet/css.dart`, the queries' `PageWords`
    (`lib/editor/queries/query_layout.dart`, which says itself it is a fraction of a pixel off),
    `lib/canvas/minimap.dart` and `lib/tapes/tape_art.dart`. None has been measured against a page's picture.
11. **Inter and a block of code at a phone's density, by ink.** test/editor/view/fixtures/device is the page drawn
    by a desktop's browser truly at 2.625 (`GLYPH_DSF=2.625 node tool/editor_reference.mjs`), and holds Maple
    Mono's lines to within 0.27 of a device pixel. Where a face's descent rounds down, Android gives it a pixel of
    the ascent and a desktop's browser does not, so a line in Inter, or in the code face at its size, stands a
    pixel higher on the phone than in that picture: the test leaves such a line out and counts it. Only the
    phone's own WebView can say they are right (the side-by-side walk, with the note's face set to Inter).
12. **The rule under a link.** It is drawn a device row from where the page draws it (the three `inline-*` cases'
    link line: the letters on the page's rows, the ink's centre 0.8 off).
13. **The pictures only drawn when asked.** `EDITOR_SHOTS` and `FIND_SHOTS` gate the pictures of the view's, the
    tables', the queries', the boards', the tickets' and the find bar's reference tests; no ordinary run holds
    them, and 26 were not what main drew on 2026-10-11 (the caret cases, the find bar's). They are recorded again
    as of the baseline's fix and will drift the same way until a run holds them.
14. **A table's baseline on a logical pixel.** `lib/editor/tables/table_layout.dart` `paint` rounds a line's
    baseline to a whole logical pixel where a phone's page puts it on a device pixel.
