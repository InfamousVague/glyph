# Stage 4, the editor: what was read in tauri/ (2026-10-07), and the plan

## Findings
- The web editor is CodeMirror 6 over the Markdown string; 12 extensions hide or replace text (`Decoration.replace`) and
  every one steps aside on the caret's line. There is no formatting toolbar and no slash palette: formatting is the
  press-and-hold band's Style page, `/` on an empty line opens the + list, and the note's tools sit in the top bar.
- `src/app/format` is the AI rewrite pipeline (stage 8), not editor formatting.
- The editor is mounted on nine surfaces (note screen, card previews, canvas cards, academy, guide, live page, template
  picker, book view, reader), so the renderer must work read-only without input. It replaces `lib/home/note_peek.dart`.
- About 17k of the 32.7k lines are stage 4; boards/queries/tickets (5), canvas frames (6), live/comments (7),
  blanks/AI/wisp arrivals (8), plugins (9) are later. KaTeX and Mermaid: maths stays as code and a mermaid fence a code
  card for now; code fences are plain cards in the theme's colours (no highlighter yet).

## Architecture: a line-virtualised custom editor
- `EditorState` immutable: `Doc` (lines + prefix sums), selection, fields, facets. Offsets are UTF-16 units, as
  CodeMirror's, so the web tests' offsets port unchanged.
- CodeMirror's vocabulary kept by name: `Transaction` (with the 32 `userEvent` names), `ChangeSet`/`mapPos`,
  `StateField`, `StateEffect`, `Annotation`, `Facet`, `Compartment`, `ViewPlugin`, `Decoration.mark/line/replace/widget`,
  `WidgetType` → `EditorWidget`, `syntaxTree`, keymaps → Shortcuts/Actions + an IME hook. An extension file ports one
  to one (`counters.ts` → `counters.dart`).
- Projection per line: decorations compile to segments (shown text + style, hidden range, inline widget, atomic) with
  doc↔display offset maps.
- `RenderEditorLine`: one or two TextPainters (marker + words on the hang), paints its own background/bar/corners,
  selection and caret, answers `coordsAtPos`/`posAtCoords`. `RenderSliverEditor` in the page's scroll view with a
  height map. `MarkdownView`: the same lines in a column, read-only.
- Input: one `DeltaTextInputClient` for the editor; the IME sees source text for a window (the caret's line or the
  selected lines); Enter and Backspace arrive as deltas and run the ports of `insertNewlineContinueMarkup` and
  `deleteMarkupBackward`; the active line's projection is frozen while composing. `SelectionOverlay` for handles;
  never the system toolbar (the port of `ContextMenu.tsx` instead).
- Tokenizer: port `@lezer/markdown` (`markdown.ts` 1,966 lines, `extension.ts` 301) by structure, configured as
  `language.ts` does (no Setext headings; one inline delimiter parser per plugin format: the 12 marks). Everything
  else (tags, people, fields, counters, sums, blanks, emoji names, callouts...) is a regex over line text gated by
  `inQuietText`. Conformance: lezer's 657 + 55 cases, a fixture dumped from the web's own configured parser over
  docs/MARKDOWN.md, settings/specification.ts, guide/marks.ts and the guidebook, and the editor's own tests.

## Pieces (folders under lib/editor/, the screen in lib/note/)
0 IME spike · A state core (`state/`) · B tokenizer (`syntax/`) · C view and rendering (`view/`) · D input and
selection (`input/`) · E marks and effects (`marks/`) · F inline items (`items/`) · G tables · H links, pictures, media
(`media/`) · I commands and the band (`commands/`) · J the + (`plus/`) · K find (`find/`) · L the note screen.
Order: 0; A and B together with the Decoration/EditorWidget interfaces frozen; C read-only; D; then E–I and K in
parallel; J after I; L's frame once C reads, finished after D.

## Measuring
`tool/editor_reference.mjs` (to write, after `tool/wisp_reference.mjs`): mounts the web `Editor` at 390 x 844 with a
fixture note per feature, writes each `.cm-line` rectangle, chosen ranges' client rects and widgets' rectangles, plus a
picture; Dart tests assert line boxes and `coordsAtPos` to half a pixel.

## Piece 0, the keyboard (run on the emulator, Gboard 15.1, 2026-10-07; lib/spike/ime_spike.dart, removed 2026-10-10 and in git's history)
A windowed delta client works for typing, suggestions, glide, Enter, Backspace across the window's start, caret moves
and cross-line selections. Composing and autocorrect could not be exercised (the emulator's Gboard never composes):
still to see on the Fold, with Samsung Keyboard and a CJK keyboard.
Rules for the input layer:
1. The IME's value is always a real contiguous range of the document (window start + offset). Never push what the
   keyboard already holds.
2. Backspace arrives as a KEY EVENT (`KEYCODE_DEL`), not a delta, and the engine no longer applies it: the editor
   deletes (or joins lines at offset 0) itself, then pushes. A deletion delta (with a selection) is accepted too.
3. Enter arrives as an inserted "\n" delta, never `performAction`.
4. A window swap whose selection and composing offsets come out identical is invisible to the keyboard (stale
   suggestions corrupt the line): re-attach, or nudge the caret by one and back.
5. Window = the caret's line plus a neighbour each side, kept lazily: re-window only when the caret reaches its first
   or last line or it passes about a dozen lines; not mid-composition if avoidable.
6. Apply every delta of a batch, then re-sync once; check each delta's `oldText` against what the keyboard is believed
   to hold.
7. A push that changes the composing text restarts the input; clear composing on an editor-made caret move.
8. Send `setEditableSizeAndTransform`, `setCaretRect`, `setComposingRect`.
Why a window: pushing a 169 kB document costs ~47 ms on Android's main thread per editor-made change against ~0.5 ms.

## Simple mode's Format bar (2026-10-18)

The finding above still holds for advanced mode: there is no formatting toolbar, formatting is the press-and-hold
band's Style page. Simple mode (GHST-103, lib/core/preferences.dart `Preferences.simple`) is the one exception, and it
is Matt's: "allow selecting between simple and advanced mode where simple mode has a much more approachable UI with
fancy features hidden behind more and work on making formatting and stuff easier to understand", and for it "A small
Format bar in the editor". Someone new to Markdown looks for Bold where every other editor keeps it, and a band that
only comes on a press-and-hold is not where they look first.

- **The bar** (lib/note/format_bar.dart): Bold, Italic, Heading, List, To-do, Link, six of the Style page's rows
  pressed from outside the band (`formatBarTools`, lib/editor/band/style_items.dart): the same edits, lit from the
  same reading of the editor's state. A press never takes the editor's focus. Where it stands
  (lib/note/note_screen.dart): on a phone a strip in the page's paper just above the soft keyboard while it is up,
  the page ending above it; on an iPhone the keyboard bar's own row, beside Done (lib/app/iphone_page.dart
  `KeyboardBarOffer`); on a desktop or a wide window with the keyboard down, a pill in the dock's hand across the
  page's foot to the dock's start (docs/DOCK.md), which is "in the dock" without making its column twice as tall.
  Advanced mode draws none of it.
- **The Style page, both modes**: every row has a hint in plain words (Bold "Strong words", Quote "Someone else's
  words", Rule "A line across the page"), said to a screen reader and shown on a desktop while the pointer rests on
  the row. In simple mode the hint is drawn under the word, Style stands first in the band before Cut and Copy, and
  the plugins' decorative marks (Spoiler … Haunt) wait behind a More row at the page's end. In advanced the band
  keeps the geometry the web page was measured at (test/editor/band/band_reference_test.dart), so the hints are not
  drawn there.
- Tests: test/editor/band/format_bar_test.dart, test/note/note_format_bar_test.dart, and "simple mode" in
  test/editor/band/context_band_test.dart.
