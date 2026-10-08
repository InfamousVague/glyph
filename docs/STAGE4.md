# Stage 4, the editor: what was read in ../glyph (2026-10-07), and the plan

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
