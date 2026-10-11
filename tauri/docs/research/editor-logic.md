# Glacier rich-text logic: what Glyph inherits

Reference notes for the Glyph design panel. Everything below was read from the kit source on 2026-09-11; kit HEAD is `6d6c2b6` (2026-09-06). Paths are absolute.

## 1. Where the pieces live

| Piece | Path |
|---|---|
| Pure logic (no DOM, no React) | `/Users/matt/Development/UIUX/GlacierUI/packages/logic/src/rich-text.ts` (574 lines, zero imports) |
| Barrel that re-exports it | `/Users/matt/Development/UIUX/GlacierUI/packages/logic/src/index.ts` |
| Logic tests | `/Users/matt/Development/UIUX/GlacierUI/packages/logic/test/rich-text.test.ts` |
| DOM editor | `/Users/matt/Development/UIUX/GlacierUI/packages/react/src/organisms/RichTextEditor/RichTextEditor.tsx` + `RichTextEditor.module.css` |
| Native editor (parity reference) | `/Users/matt/Development/UIUX/GlacierUI/packages/native/src/molecules/RichTextEditor.tsx` |
| Spec | `/Users/matt/Development/UIUX/GlacierUI/packages/spec/src/components/rich-text-editor.ts` (`richTextEditorSpec`, `richTextMarks`, `richTextBlocks`; `status: 'draft'`) |
| Docs page | `/Users/matt/Development/UIUX/GlacierUI/apps/docs/src/pages/organisms/RichTextEditorPage.tsx`; copy in `apps/docs/src/i18n/en/*.ts` under `rte*` keys |
| CodeBlock | `/Users/matt/Development/UIUX/GlacierUI/packages/react/src/atoms/display/CodeBlock/CodeBlock.tsx` + `.module.css`; spec `packages/spec/src/components/code-block.ts` |
| Shiki wiring (docs app only) | `/Users/matt/Development/UIUX/GlacierUI/apps/docs/src/docs-ui.tsx` (`useHighlighted`, `HighlightedCode`), vars in `apps/docs/src/docs.css` lines 309-319 |

History: `a2cb285` 2026-07-27 introduced the module (renamed `commons` to `logic`), `27eaa29` 2026-07-28 added in-place highlighting and fenced code, `464c416` 2026-08-03 house-style dash pass.

### Vendoring reality (matters for Glyph's `vendor/@glacier`)

AttackFM's `/Users/matt/Development/Apps/AttackFM/vendor/@glacier` holds only `icons`, `react`, `tokens`. `react` is a `dist/` build (`index.js` 1.3 MB, `index.d.ts`, `styles.css`; built 2026-09-06). The kit's `packages/react/vite.config.ts` bundles `@glacier/spec`, `@glacier/tokens`, `@glacier/motion` and (by omission from `external`) `@glacier/logic` into that file; only `react`, `react-dom`, `motion` stay external. Consequences:

- The vendored `dist/index.d.ts` exports `RichTextEditor`, `RichTextEditorProps`, `MarkdownMark`, `MarkdownBlock`. It does **not** export `toggleMark`, `toggleBlock`, `activeMarks`, `activeBlock`, `tokenizeMarkdown`, `insertLink`, `markForShortcut`, `MARK_DELIMITERS`, `BLOCK_PREFIXES`, `MarkdownToken`, or `useControlled`. The tokenizer code is inside `index.js` (strings `code-keyword`, `link-url` are present) but unreachable.
- `packages/react/src/index.ts` re-exports from `@glacier/logic` only `useBeat`, `useLiveLevels`, `volumeAmplitude`, `volumeGain`.
- So Glyph must either (a) vendor `packages/logic` as `vendor/@glacier/logic` (it depends on `@glacier/spec` for `spec.ts` only; `rich-text.ts` itself has no imports), or (b) copy `rich-text.ts` alone, or (c) add re-exports to the kit barrel and rebuild. Option (b) is 574 self-contained lines.

## 2. Exported API (from `rich-text.ts`)

```ts
export type MarkdownMark = 'bold' | 'italic' | 'code' | 'strike';
export type MarkdownBlock = 'heading' | 'quote' | 'bullet' | 'number';
export interface TextSelection { start: number; end: number }
export interface EditResult { text: string; selection: TextSelection }
export const MARK_DELIMITERS: Record<MarkdownMark, string> = { bold: '**', italic: '_', code: '`', strike: '~~' };
export const BLOCK_PREFIXES: Record<MarkdownBlock, string> = { heading: '# ', quote: '> ', bullet: '- ', number: '1. ' };

export function toggleMark(text: string, selection: TextSelection, mark: MarkdownMark): EditResult;
export function activeMarks(text: string, selection: TextSelection): MarkdownMark[];
export function activeBlock(text: string, selection: TextSelection): MarkdownBlock | null;
export function toggleBlock(text: string, selection: TextSelection, block: MarkdownBlock): EditResult;
export function insertLink(text: string, selection: TextSelection, url: string): EditResult;
export interface MarkShortcutEvent { key: string; metaKey?: boolean; ctrlKey?: boolean }
export function markForShortcut(event: MarkShortcutEvent): MarkdownMark | null;
export type MarkdownTokenKind = 'text' | 'marker' | MarkdownMark | MarkdownBlock | 'link-text' | 'link-url'
  | 'code-lang' | 'code-block' | 'code-keyword' | 'code-string' | 'code-number' | 'code-comment';
export interface MarkdownToken { kind: MarkdownTokenKind; start: number; end: number /* exclusive */; marks: MarkdownMark[]; block?: MarkdownBlock }
export function tokenizeMarkdown(text: string): MarkdownToken[];
```

Semantics, verified against tests and by running the module in Node:

- **`toggleMark`**: selection is normalised (backwards and out-of-range clamped). Unwraps if delimiters sit immediately outside the selection, or if the selection itself starts and ends with them (min length `2*d.length`). Otherwise wraps and keeps the same words selected (`selection` shifts by `d.length`). Empty selection inserts `dd` and puts the caret between (`'' -> '****'`, caret 2). Caret-only inside an existing `**x**` does **not** unwrap; it inserts another empty pair (`'**x**' caret 3 -> '**x******'`).
- **`activeMarks`**: tokenizes the whole text, takes the tokens the selection covers (a caret counts a token it sits at the end of and the one it sits at the start of), drops `marker` tokens when any content token is touched, and returns the marks every considered token carries. A mark covering only part of a selection is not reported.
- **`activeBlock`**: same touch test; returns the single block all touched tokens share, else `null` (a selection across a quote and a plain line is `null`). Reported from inside the prefix too (`'> quoted'` caret 1 -> `'quote'`).
- **`toggleBlock`**: expands to whole lines. Removes the prefix only if every non-blank touched line has it; otherwise prefixes the rest (a mixed selection completes rather than undoes). Blank lines are skipped, except a single empty line gets the prefix inserted with the caret after it. Numbered lists renumber `1.`, `2.`, ... and un-toggle matches `/^\d+\. /`. Result selection is the whole affected block. Heading has one level: pressing it on `# Title` removes it; no `##` cycling.
- **`insertLink`**: `[label](url)`, label = selection or the url; selects the label.
- **`markForShortcut`**: meta or ctrl + `b` -> bold, `i` -> italic, `e` -> code; case-insensitive; no shortcut for strike.

## 3. What `tokenizeMarkdown` produces

Invariant: a complete, ordered, non-overlapping cover of the source (concatenating slices reproduces the input byte-for-byte). Adjacent runs with identical `kind`, `block`, `marks` merge, so a 2000-word plain line is one token. `marks` is outermost-first (`**a _b_**` gives `b` `['bold','italic']`). Block prefixes become a `marker` token carrying `block`; the newline ending a line is a `text` token carrying the line's block.

Recognised:
- Inline, within one line only, longest-first order `bold, strike, code, italic`: `**`, `~~`, `` ` ``, italic `_` **or** `*`. Code is terminal (`` `**x**` `` is code). A mark cannot nest in itself. Unclosed delimiters stay `text`. Empty pairs (`****`) stay text.
- Blocks: `/^#{1,6} /` (all levels map to `'heading'`; level is only recoverable as marker length), `/^> /`, `/^[-*] /`, `/^\d+\. /`.
- Links `[text](url)` on one line -> `marker '[' , link-text, marker ']( ', link-url, marker ')'`.
- Fences `` ``` `` or `~~~` (3+, leading whitespace allowed): opening line -> `marker` + `code-lang`; body lines scanned by `scanCode` into `code-block`/`code-keyword`/`code-string`/`code-number`/`code-comment` (one shared C-family keyword set, `//`/`#` line comments, `/* */` clipped per line, quotes with escapes, numbers at boundaries); closing must match the fence char; an unclosed fence runs to EOF.

Not recognised (measured): `#NoSpace` (plain), task lists `- [ ]` (bullet only), `***both***` (bold with a stray `*`), images (`!` is text then a link), `---` rules, indented code, `1)` lists, tables, footnotes, marks spanning a line break, and there is **no flanking/word-boundary rule**: `snake_case_name` italicises `case`, `a * b * c` italicises ` b `.

## 4. How the kit's DOM editor works (the contract Glyph should match)

Two stacked layers inside `.editorStack`: an `aria-hidden` `div.highlight` that renders one `<span class="run" data-kind data-marks data-block>` per token, and a real `<textarea class="editorText editor">` on top with `color: transparent; caret-color: var(--glacier-text)`. Both share `.editorText`, which fixes every wrapping metric: `padding: var(--glacier-space-3)`, `font-family: var(--glacier-font-mono)`, `font-size: var(--glacier-font-size-sm)`, `line-height: 1.5`, `letter-spacing: normal`, `tab-size: 4`, `white-space: pre-wrap`, `overflow-wrap: break-word`. The highlight layer follows textarea scroll via `onScroll` copying `scrollTop/scrollLeft`.

Selection: `onSelect`, `onKeyUp`, `onClick` all call `readSelection()` (`selectionStart/End` into state). Shortcuts: `onKeyDown` -> `markForShortcut` -> `event.preventDefault()` -> `apply(toggleMark(...))`. Toolbar buttons use `onMouseDown` + `preventDefault` so the textarea keeps focus and selection. `apply()` refuses results over `maxLength`, then writes via `document.execCommand('insertText')` over only the changed span (common prefix/suffix diff) so the edit joins the native undo stack; falls back to `setValue`. The new selection is restored in a `useLayoutEffect` keyed on `value`. Tab is not trapped. There is no Enter handling (no list continuation), no auto-pairing, no heading sizing.

Per render the component calls `activeMarks`, `activeBlock`, and `tokenizeMarkdown` on the full value: three full tokenizations per keystroke, plus a React re-render of every span (`key={i}`).

Styling rules in the CSS module (all tokens): `.run[data-kind='marker'] { color: var(--glacier-text-subtle) }`; `[data-marks~='bold']` -> `font-weight: var(--glacier-font-weight-bold)`; `italic` -> `font-style: italic`; `strike` -> `line-through`; `code` -> `color: var(--glacier-accent-text)`; `[data-block='heading']:not([data-kind='marker'])` -> bold only (same size); quote -> `--glacier-text-muted` + italic; `link-text` -> accent + underline; `link-url` -> muted; fence kinds -> `code-block` muted, `code-lang`/`code-keyword` accent (keyword `--glacier-font-weight-medium`), `code-string` `--glacier-success-text`, `code-number` `--glacier-warning-text`, `code-comment` subtle italic. Toolbar: `.control[aria-pressed='true']` -> `--glacier-accent-soft` / `--glacier-accent-text`; `.control:hover` uses `var(--glacier-surface-hover)`, which **no tokens file defines** (the real token is `--glacier-hover`; `accent-soft-hover` etc. exist). The `.control` font-weight has a `600` fallback but `--glacier-font-weight-semibold` does exist (`regular/medium/semibold/bold` = 400/500/600/700 from `packages/tokens/src/type.ts`).

Labels (`kitMessages` in `packages/react/src/i18n/messages.ts`): `editorToolbar` "Formatting", `editorBold`, `editorItalic`, `editorCode` "Inline code", `editorStrike` "Strikethrough", `editorHeading`, `editorQuote`, `editorBullet` "Bulleted list", `editorNumber` "Numbered list". Glyphs: `B`, `I`, `</>`, `S`, `H`, `❝`, `•`, `1.`.

The native binding mirrors this with `TextInput` `onSelectionChange` and a controlled `selection` prop; `LINE_HEIGHT = 21`.

## 5. Performance (Node v25.9, desktop; expect 3-5x slower in a phone WebView)

50,015-word / 350 KB / 4,111-line synthetic note: `tokenizeMarkdown` median **13.6 ms**, producing **74,475 tokens** (= 74k `<span>`s if rendered the kit's way). `activeMarks` and `activeBlock` each cost the same again because they re-tokenize. A 2,010-word note: 0.49 ms, 2,988 tokens. One 15-word line: ~3.5 µs. The tokenizer is per-line and stateless except for the fence flag, so incremental re-tokenization of only the edited line(s) is trivial to add; the kit does not do it.

## 6. Reusable for Glyph vs not

Reusable as-is (copy or vendor `rich-text.ts`):
- `MARK_DELIMITERS`, `BLOCK_PREFIXES`, `toggleMark`, `toggleBlock`, `insertLink`, `markForShortcut`, `activeMarks`, `activeBlock` for the formatting bar and hardware-keyboard shortcuts. Same delimiters guarantee what the bar writes is what the highlighter reads.
- `tokenizeMarkdown` as the per-line syntax model: token kinds map one-to-one onto the `data-kind`/`data-marks`/`data-block` CSS contract, so Glyph's editor can reuse the kit's run styling rules verbatim (with `--glacier-*` tokens) even under a different rendering engine. Wrap it per line for incremental work.
- CSS run rules and the toolbar pressed-state tokens.

Not reusable for Glyph's requirements:
- The transparent-textarea overlay only aligns because the font is monospace (bold/italic keep advance widths). A proportional prose font with bold runs, or larger headings, desynchronises caret and glyphs, which is why the kit renders headings at body size. Requirement 2 (headings larger, markers visible) therefore needs the styled text to be the editable surface itself (contenteditable via CodeMirror 6 decorations / ProseMirror / Lexical) rather than this overlay.
- Full-document re-tokenize x3 and 74k spans per keystroke at 50k words fails requirement 1.
- `activeMarks` cannot detect "closing `**` just typed": at that instant it returns `['bold']` only when the caret is at end-of-document; with any following character it returns `[]`. Detect mark completion by diffing the edited line's token list before and after the input (a new non-`marker` `bold`/`italic`/`code`/`strike` token, or a new `marker` with `block`, appeared), then fire the haptic through a floor like AttackFM's `fireFelt` (28 ms) / `makeRatchet`.
- No list continuation on Enter, no heading levels, no task lists, no word-boundary rule for `_` (bad for notes containing identifiers). Glyph would extend the grammar.

## 7. Code highlighting in the kit

The kit ships no highlighter. `CodeBlock` takes `code: string` plus optional pre-highlighted `children`; `.pre :global(pre)` resets Shiki's `<pre>`, `.numbered :global(.line)::before` draws CSS-counter line numbers off `<span class="line">`. The docs app creates Shiki (`^4.3.1`) with `createCssVariablesTheme({ name: 'glacier', variablePrefix: '--shiki-', fontStyle: true })`, `langs: ['tsx']`, and maps `--shiki-token-keyword: var(--glacier-purple-11)`, `-string: var(--glacier-green-11)`, `-constant/-link: var(--glacier-blue-11)`, `-function: var(--glacier-accent-11)`, `-parameter: var(--glacier-amber-11)`, `-comment: var(--glacier-text-subtle)`, `-punctuation: var(--glacier-text-muted)`, `--shiki-foreground: var(--glacier-text)`. Native uses `codeToTokens` (`packages/native/src/highlight.ts`, `useHighlightedLines`). Inside the editor, fenced code uses the tokenizer's own tiny `scanCode`, not Shiki. For Glyph a fence inside a note can keep the `scanCode` kinds; Shiki is only worth loading for a read-only preview.

## 8. Haptics hooks the editor would call

Glacier: `HapticsProvider({ enabled, impl })` and `useHaptics(): (kind?: HapticKind) => void` with `HapticKind = 'selection' | 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error'` (`packages/react/src/haptics/haptics.ts`). AttackFM's impl: `fireNativeHaptic(kind)` maps to `@tauri-apps/plugin-haptics` `selectionFeedback` / `impactFeedback('light'|'medium'|'heavy')` / `notificationFeedback`; `fireMicroTick()` is `impactFeedback('soft')`; `fireFelt(kind, at)` enforces a 28 ms floor; `makeRatchet()` in `src/app/ux/ratchet.ts` gives `feel/arrive/reset` (`TICK_FLOOR_MS = 28`). The kit's delegated pointerdown tick is disabled in AttackFM (`enabled={false}`) in favour of `installTapHaptics()` firing `'selection'` on pointerup.
