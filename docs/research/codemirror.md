# CodeMirror 6 as a token-preserving live markdown editor on mobile

Reference notes for the Glyph design panel. Researched 2026-09-11 against the packages actually installed that day (`npm i` into a scratch project, sizes measured with esbuild + gzip -9 on this Mac). Web content and package sources were read as data. File paths in the AttackFM and GlacierUI sections are real.

## 1. Verdict

CodeMirror 6 is the right engine for Glyph. It is the only mature option whose document model IS the markdown text: decorations style ranges of the real string, so `**bold**` renders bold with the asterisks still in the document, still selectable, still deletable. Lexical, ProseMirror and Tiptap all consume the markers (their input rules delete `**` and set a bold attribute), so "tokens never disappear" would mean fighting the engine. Monaco's own FAQ answers "Is the editor supported in mobile browsers or mobile web app frameworks?" with "No." A textarea overlay cannot do variable line heights at all. CodeMirror renders only the viewport, parses incrementally (a 56k-word note reparses in about 1 ms after a keystroke), ships at about 175 kB gzipped for the whole markdown stack, and has had a steady stream of iOS/Android fixes through 2025-2026.

## 2. Versions and where the project lives now

Installed on 2026-09-11: `@codemirror/state` 6.7.4, `@codemirror/view` 6.43.11 (2026-09-03), `@codemirror/language` 6.12.4, `@codemirror/commands` 6.11.0, `@codemirror/lang-markdown` 6.5.2, `@lezer/markdown` 1.7.2, `@lezer/highlight` 1.2.3, `@lezer/common` 1.5.2. Transitive: `@codemirror/lang-html` 6.4.12, `@codemirror/autocomplete` 6.20.3, `style-mod` 4.1.3, `w3c-keyname` 2.2.8, `crelt` 1.0.7.

The GitHub bug tracker `codemirror/dev` was archived on 2026-04-15; its README says "This repository has moved to https://code.haverbeke.berlin/codemirror/dev". File and search issues at `https://code.haverbeke.berlin/codemirror/dev/issues` (Forgejo API: `https://code.haverbeke.berlin/api/v1/repos/codemirror/dev/issues?state=open&q=ios`). The lang-markdown typings already link to `https://code.haverbeke.berlin/lezer/markdown#user-content-markdownextension`. npm packages are unchanged.

## 3. Bundle sizes (measured)

Method: `esbuild --bundle --minify --format=esm --target=es2020`, then `gzip -9` / `brotli -q 11`.

| Entry | min | gz | br |
| --- | --- | --- | --- |
| `@codemirror/state` + `@codemirror/view` only | 200.7 kB | 65.4 kB | 57.2 kB |
| + `history()`, `defaultKeymap`, `historyKeymap`, `syntaxTree` (no markdown) | 269.4 kB | 88.5 kB | 76.9 kB |
| + `markdown({base: markdownLanguage})`, `addKeymap:false`, `completeHTMLTags:false` | 477.7 kB | 166.4 kB | 141.9 kB |
| Full: the above + `defaultKeymap` + `syntaxHighlighting(HighlightStyle)` + `lineWrapping` | 502.5 kB | 174.5 kB | 148.6 kB |

Per-package minified bytes in the full build: `@codemirror/view` 151.2 kB, `@lezer/javascript` 77.9 kB, `@codemirror/state` 47.1 kB, `@lezer/markdown` 35.7 kB, `@lezer/common` 27.8 kB, `@lezer/lr` 26.6 kB, `@codemirror/commands` 23.4 kB, `@codemirror/language` 18.7 kB, `@lezer/css` 17.3 kB, `@lezer/html` 14.5 kB, `@codemirror/lang-html` 14.1 kB, `@codemirror/lang-css` 11.0 kB, `@codemirror/autocomplete` 8.6 kB, `@codemirror/lang-markdown` 8.3 kB, `@lezer/highlight` 7.2 kB.

The surprise is the HTML chain (`lang-html` -> `lang-css`, `lang-javascript`, `@lezer/javascript`, `@lezer/css`, `@lezer/html`, `autocomplete`), roughly 175 kB minified / about 55-60 kB gz. `@codemirror/lang-markdown` lists `@codemirror/lang-html` as a hard dependency and its `index.js` evaluates `const htmlNoMatch = html({ matchClosingTags: false })` at module top, so neither `completeHTMLTags: false` nor `htmlTagLanguage` removes it. Options: accept it (HTML-in-markdown then highlights correctly), or build the language directly from `@lezer/markdown` with `new Language(...)` from `@codemirror/language` and skip `lang-markdown` entirely, giving up `insertNewlineContinueMarkup` / `deleteMarkupBackward` (or copying them). Estimated full stack without the HTML chain: about 325 kB min / 110-115 kB gz.

For scale: the shipped AttackFM `app.js` is about 8.8 MB (comment in `/Users/matt/Development/Apps/AttackFM/vite.config.ts`), so 175 kB gz is not the constraint; parse and layout cost is.

Competitors measured the same way: Lexical 0.50.0 (`lexical` + `@lexical/rich-text` + `@lexical/markdown` + `@lexical/history` + list/code/link) 472.9 kB / 155.9 kB gz. ProseMirror (state, view, model, `prosemirror-markdown` incl. markdown-it, history, keymap, commands) 370.6 kB / 121.9 kB gz. Tiptap 3.31.3 (`@tiptap/core` + `@tiptap/starter-kit`) 382.3 kB / 121.5 kB gz. Monaco 0.56.0 via the package entry: 4,436.8 kB / 1,153.6 kB gz JS plus 157 kB CSS, before workers (`editor.worker` 272.8 kB / 81.7 kB gz; `ts.worker` 7.0 MB).

## 4. Minimal setup

```ts
import {EditorState, Compartment} from "@codemirror/state";
import {EditorView, keymap} from "@codemirror/view";
import {history, historyKeymap, defaultKeymap} from "@codemirror/commands";
import {markdown, markdownLanguage} from "@codemirror/lang-markdown";
import {syntaxHighlighting} from "@codemirror/language";

const themeSlot = new Compartment();

const state = EditorState.create({
  doc: note.body,                         // string | Text
  selection: {anchor: 0},
  extensions: [
    history(),                            // HistoryConfig: minDepth 100, newGroupDelay 500 ms, joinToEvent
    keymap.of([...historyKeymap, ...defaultKeymap]),
    markdown({
      base: markdownLanguage,             // "GFM plus subscript, superscript, and emoji"; the DEFAULT base is commonmarkLanguage (no ~~ or [ ])
      addKeymap: true,                    // installs markdownKeymap: Enter -> insertNewlineContinueMarkup, Backspace -> deleteMarkupBackward
      completeHTMLTags: false,            // no "<" autocompletion popup on a phone
      pasteURLAsLink: true,               // 6.4.0: pasting a URL over a selection makes [sel](url)
    }),
    syntaxHighlighting(glyphHighlight),   // section 6a
    glyphLinePlugin,                      // section 6b
    EditorView.lineWrapping,              // sets white-space: pre-wrap on .cm-content
    EditorView.contentAttributes.of(proseAttrs), // section 8
    themeSlot.of(glyphTheme(isDark)),     // section 7; themeSlot.reconfigure(glyphTheme(next)) on theme flip
    EditorView.updateListener.of(onUpdate), // section 11
  ],
});
const view = new EditorView({state, parent: hostEl}); // {state, parent?, dispatch?}
```

`markdownKeymap` is exactly `[{key: "Enter", run: insertNewlineContinueMarkup}, {key: "Backspace", run: deleteMarkupBackward}]`. `insertNewlineContinueMarkupCommand({nonTightLists: false})` (6.5.0) is the configurable variant. The doc comment warns the command "does nothing in non-Markdown context, so it should not be used as the only binding for Enter", hence `defaultKeymap` after it. `historyKeymap` binds `Mod-z`, `Mod-y`/`Mod-Shift-z`, `Mod-u`, `Alt-u`.

Other `markdown()` options: `defaultCodeLanguage`, `codeLanguages` (array of `LanguageDescription` or `(info) => Language | LanguageDescription | null`), `extensions: MarkdownExtension`, `htmlTagLanguage: LanguageSupport`.

## 5. Lezer markdown node names (ground truth)

Printed from `parser.configure([GFM]).parse(doc)` with `@lezer/markdown` 1.7.2. Marks are children of the node they delimit.

```
ATXHeading1 > HeaderMark "#"            (ATXHeading1..ATXHeading6, SetextHeading1..2)
Paragraph
  StrongEmphasis > EmphasisMark "**" ... EmphasisMark "**"
  Emphasis       > EmphasisMark "*"  ... EmphasisMark "*"
  Strikethrough  > StrikethroughMark "~~" ... StrikethroughMark "~~"   (GFM)
  InlineCode     > CodeMark "`" ... CodeMark "`"
  Link > LinkMark "[" , LinkMark "]" , LinkMark "(" , URL , LinkTitle , LinkMark ")"
  URL                                     (bare autolink, GFM Autolink)
Blockquote > QuoteMark ">" , Paragraph
BulletList > ListItem > ListMark "-" , Paragraph
                       ListMark "-" , Task > TaskMarker "[ ]"          (GFM TaskList; Task replaces the Paragraph)
OrderedList > ListItem > ListMark "1." , Paragraph
HorizontalRule "---"
FencedCode > CodeMark "```" , CodeInfo "js" , CodeText , CodeMark "```"
CodeBlock (indented), HTMLBlock, HTMLTag, Image, Escape, Entity, HardBreak, LinkReference, LinkLabel, Comment, CommentBlock, ProcessingInstruction(Block)
Table > TableHeader / TableRow > TableCell, TableDelimiter ; Subscript > SubscriptMark ; Superscript > SuperscriptMark ; Emoji
```

`GFM` = `[Table, TaskList, Strikethrough, Autolink]`. The `styleTags` block in `@lezer/markdown` `markdown.ts` (verbatim):

```ts
"Blockquote/...": t.quote, HorizontalRule: t.contentSeparator,
"ATXHeading1/... SetextHeading1/...": t.heading1, "ATXHeading2/... SetextHeading2/...": t.heading2,
"ATXHeading3/...": t.heading3, "ATXHeading4/...": t.heading4, "ATXHeading5/...": t.heading5, "ATXHeading6/...": t.heading6,
"Comment CommentBlock": t.comment, Escape: t.escape, Entity: t.character,
"Emphasis/...": t.emphasis, "StrongEmphasis/...": t.strong, "Link/... Image/...": t.link,
"OrderedList/... BulletList/...": t.list, "InlineCode CodeText": t.monospace, "URL Autolink": t.url,
"HeaderMark HardBreak QuoteMark ListMark LinkMark EmphasisMark CodeMark": t.processingInstruction,
"CodeInfo LinkLabel": t.labelName, LinkTitle: t.string, Paragraph: t.content
```

Extensions: `StrikethroughMark: t.processingInstruction`, `"Strikethrough/...": t.strikethrough`, `Task: t.list`, `TaskMarker: t.atom`, `TableDelimiter: t.processingInstruction`, `"TableHeader/...": t.heading`, `TableCell: t.content`, `Emoji: t.character`, `SubscriptMark`/`SuperscriptMark: t.processingInstruction`.

## 6. Styling: two layers

### 6a. Inline: `HighlightStyle` + `syntaxHighlighting` (no plugin code)

`highlightTree` emits one span per run with the union of classes, and `/...` rules are inherited, so with the stock tags a `**` gets both `strong` and `processingInstruction` while `bold` gets only `strong` (verified with `classHighlighter`: `"**" -> tok-strong tok-meta`, `"bold" -> tok-strong`). That is exactly the iA Writer look: one rule for the content, one rule that dims every token.

```ts
import {HighlightStyle} from "@codemirror/language";
import {tags} from "@lezer/highlight";
import styles from "./Editor.module.css";      // Glacier: CSS Modules over --glacier-* tokens only

export const glyphHighlight = HighlightStyle.define([
  {tag: tags.heading1, class: styles.h1}, {tag: tags.heading2, class: styles.h2}, {tag: tags.heading3, class: styles.h3},
  {tag: [tags.heading4, tags.heading5, tags.heading6], class: styles.h4},
  {tag: tags.strong, class: styles.strong}, {tag: tags.emphasis, class: styles.em},
  {tag: tags.strikethrough, class: styles.strike}, {tag: tags.monospace, class: styles.code},
  {tag: tags.link, class: styles.link}, {tag: tags.url, class: styles.url},
  {tag: tags.quote, class: styles.quote}, {tag: tags.list, class: styles.list},
  {tag: tags.contentSeparator, class: styles.hr}, {tag: tags.labelName, class: styles.codeInfo},
  {tag: tags.atom, class: styles.taskMarker},                 // [ ] and [x]
  {tag: tags.processingInstruction, class: styles.mark},      // # > - ** * ~~ ` [ ] ( ) ```  -- keep LAST in the CSS file
]);
```

`TagStyle` is `{tag: Tag | readonly Tag[], class?: string, ...StyleSpec}`; `HighlightStyle.define(specs, {scope?, all?, themeType?: "dark"|"light"})`; `syntaxHighlighting(highlighter, {fallback?})`. Using `class:` keeps the styles in the module CSS (tokens, dark mode via `data-theme`) instead of CM-generated rules. `.mark` must win over `.strong`/`.h1` for weight and colour: same specificity, so order it last (`.mark { color: var(--glacier-text-subtle); font-weight: var(--glacier-font-weight-regular); }`). An inline `.h1 { font-size: var(--glacier-font-size-2xl) }` span already makes its line taller; CM measures the real line height.

Internally `syntaxHighlighting` is a `ViewPlugin` (`TreeHighlighter`) that rebuilds only over `view.visibleRanges` when the tree, viewport or highlighters change and otherwise maps decorations through changes, so it is viewport-only for free.

### 6b. Block: a small `ViewPlugin` with `Decoration.line`

Padding above a heading, the quote bar, list hanging indent, fenced-code background and the `---` rule need the line element, which inline spans cannot reach.

```ts
import {ViewPlugin, Decoration, EditorView, type DecorationSet, type ViewUpdate} from "@codemirror/view";
import {RangeSetBuilder} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

const LINE_CLASS: Record<string, string> = {
  ATXHeading1: styles.lineH1, SetextHeading1: styles.lineH1, ATXHeading2: styles.lineH2, SetextHeading2: styles.lineH2,
  ATXHeading3: styles.lineH3, ATXHeading4: styles.lineH4, ATXHeading5: styles.lineH4, ATXHeading6: styles.lineH4,
  Blockquote: styles.lineQuote, ListItem: styles.lineItem, FencedCode: styles.lineCode, CodeBlock: styles.lineCode,
  HorizontalRule: styles.lineHr,
};

function buildLines(view: EditorView): DecorationSet {
  const doc = view.state.doc;
  const perLine = new Map<number, string[]>();               // line.from -> classes (a quote can hold a heading)
  for (const {from, to} of view.visibleRanges) {
    syntaxTree(view.state).iterate({from, to, enter: (node) => {
      const cls = LINE_CLASS[node.name];
      if (!cls) return;
      const first = doc.lineAt(node.from).number, last = doc.lineAt(Math.max(node.from, node.to - 1)).number;
      for (let n = first; n <= last; n++) {
        const at = doc.line(n).from;
        perLine.set(at, [...(perLine.get(at) ?? []), cls]);
      }
    }});
  }
  const builder = new RangeSetBuilder<Decoration>();         // add() must be sorted by from, then startSide
  for (const at of [...perLine.keys()].sort((a, b) => a - b))
    builder.add(at, at, Decoration.line({class: perLine.get(at)!.join(" ")}));
  return builder.finish();
}

export const glyphLinePlugin = ViewPlugin.fromClass(class {
  decorations: DecorationSet;
  constructor(view: EditorView) { this.decorations = buildLines(view); }
  update(u: ViewUpdate) {
    if (u.docChanged || u.viewportChanged || syntaxTree(u.startState) != syntaxTree(u.state)) this.decorations = buildLines(u.view);
  }
}, {decorations: (v) => v.decorations});
```

Rules that bite: `Decoration.line` ranges must be zero-length (`RangeError("Line decoration ranges must be zero-length")`) and sit at `line.from`; `line.startSide` is `-200000000` versus `500000000` for a non-inclusive mark, so at the same position a line decoration is added before marks. `EditorView.decorations` doc: sets "provided as functions are called after the new viewport has been computed, and thus must not introduce block widgets or replacing decorations that cover line breaks"; plain line/mark decorations from a plugin are fine, and variable line heights are supported (the view keeps a height map, "initially estimated, measured accurately when content is drawn"). `Decoration.mark` spec: `inclusive`, `inclusiveStart`, `inclusiveEnd`, `attributes`, `class`, `tagName`, `bidiIsolate`. `Decoration.set(ranges, sort?)` sorts for you if `sort` is true.

## 7. Theme: `EditorView.theme` with Glacier tokens

`EditorView.theme(spec, {dark?})` scopes selectors under a generated class; `&` is the editor wrapper (`.cm-editor`); `EditorView.baseTheme` accepts `&light`/`&dark`; `dark: true` sets the `EditorView.darkTheme` facet. style-mod writes values verbatim (`prop + ": " + value`), so `var(--glacier-*)` passes straight through and Glacier's `data-theme` flip retunes the editor without a rebuild. Still reconfigure `dark` through a `Compartment` so `&dark` base rules (caret, selection fallbacks) agree.

The base theme sets `.cm-scroller { fontFamily: "monospace", lineHeight: 1.4 }`, `.cm-content { whiteSpace: "pre" }` (lineWrapping overrides), `.cm-line { padding: "0 2px 0 6px" }`, `&light .cm-content { caretColor: black }`, `&dark ... white`. Override:

```ts
export const glyphTheme = (dark: boolean) => EditorView.theme({
  "&": {backgroundColor: "var(--glacier-surface)", color: "var(--glacier-text)"},
  ".cm-scroller": {fontFamily: "var(--glacier-font-sans)", fontSize: "var(--glacier-font-size-md)", lineHeight: "var(--glacier-leading-md)"},
  ".cm-content": {padding: "var(--glacier-space-4) 0", caretColor: "var(--glacier-accent-solid)"},
  ".cm-line": {padding: "0 var(--glacier-space-4)"},
  "&.cm-focused": {outline: "none"},
  ".cm-line ::selection, .cm-line::selection": {backgroundColor: "var(--glacier-selection)"},
}, {dark});
```

Token names that exist in `/Users/matt/Development/UIUX/GlacierUI/packages/tokens/css/tokens.css`: `--glacier-font-sans`, `--glacier-font-mono`, `--glacier-font-weight-regular|medium|semibold|bold`, `--glacier-font-size-xs|sm|md|lg|xl|2xl|3xl|4xl|5xl` (fluid `clamp()`), `--glacier-leading-*` (same steps), `--glacier-tracking-*`, `--glacier-space-0|1|2|3|4|5|6|8|10|12|16|20|24|px` (multiplied by `--glacier-density-scale`), `--glacier-radius-xs|sm|md|lg|xl|2xl|full`, `--glacier-duration-instant|fast|normal|slow|slower`, `--glacier-ease-out|in-out|spring|exit`, `--glacier-surface`, `--glacier-surface-raised`, `--glacier-surface-sunken`, `--glacier-text`, `--glacier-text-muted`, `--glacier-text-subtle`, `--glacier-text-disabled`, `--glacier-border-subtle|border|border-strong`, `--glacier-accent-solid|solid-hover|soft|soft-hover|border|text|contrast`, `--glacier-selection`, `--glacier-focus-ring`, `--glacier-overlay`, glass: `--glacier-glass-thin|regular|thick|border|highlight`. Theme flips on `data-theme="light"|"dark"` on `<html>`, density on `data-density="compact"`.

## 8. Mobile: content attributes, keyboard, selection

The view sets these defaults on `.cm-content` (6.43.11 source): `spellcheck: "false"`, `autocorrect: "off"`, `autocapitalize: "off"`, `writingsuggestions: "false"` (6.35.1, "to opt out of Safari's new intelligence completions"), `translate: "no"`, `role: "textbox"`, `aria-multiline: "true"`, `contenteditable` from `EditorView.editable`. Facet values are merged with `combineAttrs` (`class`/`style` concatenate, anything else overwrites), so prose settings win:

```ts
const proseAttrs = {autocorrect: "on", autocapitalize: "sentences", spellcheck: "true", inputmode: "text", enterkeyhint: "enter"};
EditorView.contentAttributes.of(proseAttrs)
```

Autocorrect-on is a real choice: iOS replaces the composed word with a `input.type` change that lands as one transaction; the 6.43.2 entry "On iOS when autocapitalize is enabled, ignore the shift modifier on virtual keyboard Enter or Backspace presses" shows the team tests that path. Wire it to the Settings pane so it can be turned off.

Selection handles: `drawSelection()` hides the native caret (`caretColor: transparent !important`), which on iOS also hides the native grabbers (issue 1538, marijnh: Mobile Safari "appears to only query this style once, when the selection is made"). Since view 6.39.16/6.39.17 `drawSelection({iosSelectionHandles: true})` (default) draws `.cm-selectionHandle`, `.cm-selectionHandle-start/-end` itself; `SelectionConfig` also has `cursorBlinkRate` (1200) and `drawRangeCursor`. The doc comment notes drawSelection "requires an extra DOM layout cycle for many updates". Recommendation for phones: do not install `drawSelection` at all; keep the native caret, native grabbers, magnifier and callout, and colour them with `caret-color` and `::selection` in the theme. Issue 1675 "Android selection drag handle gets stuck" (open, 2026-02) is a native-handle report.

Other mobile-relevant view API: `view.composing`, `view.hasFocus`, `view.inView`, `view.viewport`, `view.visibleRanges`, `view.requestMeasure()`, `view.posAtCoords({x, y})`, `view.coordsAtPos(pos)`, `EditorView.scrollIntoView(pos, {y: "nearest"})` (a `StateEffect`), `EditorView.scrollHandler`, `EditorView.focusChangeEffect`, `EditorView.EDIT_CONTEXT` (EditContext is used only when `window.EditContext && browser.android && EDIT_CONTEXT !== false` and Chrome >= 126), `EditorView.domEventHandlers({touchstart, ...})`, `EditorView.inputHandler` (`(view, from, to, text, insert: () => Transaction) => boolean`).

## 9. IME / composition safety

`view.composing` is true "while the user is currently composing text via IME, and at least one change has been made in the current composition"; such transactions carry `Transaction.userEvent` `"input.type.compose"`. Decoration churn under a composition has been the classic mobile bug class (closed: 1654 "IME composition problem in decoration", 1650 "IME composition at the boundary of syntax highlight nodes garbles content", 1504 "Samsung Keyboard Predictive text breaks editor state", 1210 Android backspace composition; 6.38.4 worked around Chrome Android not firing `compositionend`; 6.43.1/6.43.10 still tune composition). Practical rules: in `glyphLinePlugin.update`, when `u.view.composing` map the previous set instead of rebuilding (`this.decorations = this.decorations.map(u.changes)`); never `dispatch` document changes from the update listener while composing; fire haptics on `input.type` but not `input.type.compose`; keep the composed line's DOM stable (no widgets on the current line). Android IME is where 6.28-6.43 fixes concentrate; test Gboard and Samsung Keyboard explicitly.

## 10. History and keymaps

`history({minDepth?, newGroupDelay?, joinToEvent?})`, `undo`, `redo`, `undoDepth`, `historyKeymap`, `defaultKeymap` from `@codemirror/commands`; `keymap.of(bindings)` from `@codemirror/view`. Precedence: earlier in the extension array wins within the same `Prec`; use `Prec.high(keymap.of(...))` for the formatting bar's Mod-B/Mod-I if a hardware keyboard is attached. The formatting bar itself should dispatch `view.dispatch(view.state.changeByRange(range => ({changes: [...], range: ...})))` with `annotations: Transaction.userEvent.of("input.format")` so the haptic layer can tell bar taps from typed marks.

## 11. Haptics: detecting a just-completed mark

All the signal is in the transaction. Use `EditorView.updateListener` and compare the syntax tree before and after; `@codemirror/language` does up to `Work.Apply = 20` ms of synchronous parsing on a doc change (the `Work` enum: `Apply 20, MinSlice 25, Slice 100, MinPause 100, MaxPause 500, ChunkBudget 3000, ChunkTime 30000, ChangeBonus 50, MaxParseAhead 1e5, InitViewport 3000`), so `syntaxTree(tr.state)` at the cursor is current by the time the listener runs (guard with `syntaxTreeAvailable(state, pos)` or `ensureSyntaxTree(state, pos, 5)`).

```ts
import {syntaxTree, syntaxTreeAvailable} from "@codemirror/language";
import type {EditorState, Transaction} from "@codemirror/state";
import type {ViewUpdate} from "@codemirror/view";
import type {SyntaxNode} from "@lezer/common";
import type {HapticFn} from "@glacier/react";

const INLINE = new Set(["StrongEmphasis", "Emphasis", "Strikethrough", "InlineCode", "Link"]);
const BLOCK = /^(ATXHeading[1-6]|Blockquote|ListItem|FencedCode|HorizontalRule)$/;

function enclosing(state: EditorState, pos: number, test: (name: string) => boolean) {
  for (let n: SyntaxNode | null = syntaxTree(state).resolveInner(pos, -1); n; n = n.parent) if (test(n.name)) return n;
  return null;
}

export function feelTransaction(tr: Transaction, haptic: HapticFn) {
  if (!tr.docChanged || !tr.isUserEvent("input.type") || tr.isUserEvent("input.type.compose")) return;
  let typed = "";
  tr.changes.iterChanges((_fa, _ta, _fb, _tb, inserted) => { typed += inserted.toString(); });
  const head = tr.state.selection.main.head;
  if (!syntaxTreeAvailable(tr.state, head)) return;
  if (/[*_~`)\]]$/.test(typed)) {                              // closing token typed
    const after = enclosing(tr.state, head, (n) => INLINE.has(n));
    const before = after && enclosing(tr.startState, tr.changes.mapPos(head, -1), (n) => n === after.name);
    if (after && after.to === head && !before) haptic("selection");          // the tick: ** closed
  } else if (/[ \n-]$/.test(typed)) {                          // "# ", "> ", "- ", "---", "```"
    const line = tr.state.doc.lineAt(head);
    const after = enclosing(tr.state, line.from + 1, (n) => BLOCK.test(n));
    const before = enclosing(tr.startState, tr.changes.mapPos(line.from + 1, 1), (n) => BLOCK.test(n));
    if (after && (!before || before.name !== after.name)) haptic(after.name.startsWith("ATXHeading") ? "medium" : "light");
  }
}
export const onUpdate = (u: ViewUpdate) => { for (const tr of u.transactions) feelTransaction(tr, haptic); };
```

`Transaction` API used: `docChanged`, `changes.iterChanges((fromA, toA, fromB, toB, inserted: Text) => void)`, `changes.mapPos(pos, assoc)`, `startState`, `state`, `isUserEvent(event)` ("equal to or more specific than", so `"input"` matches `"input.type"`), `annotation(Transaction.userEvent)`. User events used by the core: `input`, `input.type`, `input.type.compose`, `input.paste`, `input.drop`, `input.complete`, `delete`, `delete.selection`, `delete.forward`, `delete.backward`, `delete.cut`, `move`, `move.drop`, `select`, `select.pointer`, `undo`, `redo`. A regex on `tr.state.doc.lineAt(head).text` is an acceptable cheaper first pass for headings, but the tree check avoids false positives inside code fences.

Rate limiting: reuse the AttackFM shape. `/Users/matt/Development/Apps/AttackFM/src/app/ux/ratchet.ts` exports `makeRatchet(): Ratchet` (`feel(travel, from, to, nowMs)`, `arrive(weight?: 'medium' | 'heavy')`, `reset()`), `notchWeight(p)`, `notchSpacing(p)`, `nextNotch(...)`, with `TICK_FLOOR_MS = 28`, `NOTCH_FAR = 24`, `NOTCH_NEAR = 9`. `/Users/matt/Development/Apps/AttackFM/src/app/core/haptics.ts` exports `fireNativeHaptic(kind)`, `fireFelt(kind, at = performance.now())` (`FLOOR_MS = 28`), `fireMicroTick()` (`impactFeedback('soft')`), `hapticsImpl`, `hapticsAvailable()`, `installTapHaptics()`, `hapticsPref()`/`setHapticsPref()`/`useHapticsPref()` (`PREF_KEY = 'attackfm-haptics'`). Mapping to `@tauri-apps/plugin-haptics`: `selectionFeedback()`, `impactFeedback('light'|'medium'|'heavy'|'soft')`, `notificationFeedback('success'|'warning'|'error')`. Glacier side (`/Users/matt/Development/UIUX/GlacierUI/packages/react/src/haptics/`): `HapticsProvider({enabled = false, impl, children})`, `useHaptics(): HapticFn`, `HapticKind = 'selection' | 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error'`, `haptic()`, `setHapticsEnabled()`. AttackFM mounts `<HapticsProvider enabled={false} impl={hapticsImpl}>` in `src/app/nav/AppProviders.tsx` and runs its own tap tick on pointerup. Suggested editor budget: `fireFelt('selection')` for closed inline marks, `fireFelt('medium')` for a new heading, `fireMicroTick()` for list continuation on Enter, `notificationFeedback('success')` once per save, and nothing on ordinary characters.

## 12. Performance

- Viewport rendering: the view draws only the viewport plus a margin; `visibleRanges` excludes folded/hidden parts. Decorate only `visibleRanges`; never iterate the whole tree per keystroke.
- Parsing: incremental via `TreeFragment`. Measured in Node on a 380 kB / 55,817-word / 3,178-line note: full parse 27-32 ms, reparse after inserting `**` mid-document 1.1 ms. The parse worker runs in `requestIdleCallback` slices and stops when `navigator.scheduling.isInputPending()` says input is waiting; `MaxParseAhead` is 100,000 characters beyond the viewport.
- Tree identity: `syntaxTree(u.startState) != syntaxTree(u.state)` is the cheap "tree changed" check; `syntaxTreeAvailable`, `syntaxParserRunning(view)`, `forceParsing(view, upto, timeout)` exist for a "prepare whole note" pass on open.
- Keep `.cm-line` CSS cheap: no `transition` on `font-size` (the live-markdown design doc animates `fontSize: 0.01em -> 1em` on marks; skip that on phones), no `backdrop-filter` under the scroller, no per-line box-shadow. `Decoration.mark` with `class` only; nested marks create nested spans, split at line and lower-precedence boundaries.
- `drawSelection` costs a layout pass per update (doc comment); omit on mobile.
- Scroll: 6.43.5 "Don't abort momentum scrolling on iOS by stabilizing the scroll position", 6.43.8 fixed horizontal drift on Android/iOS scrollIntoView, 6.36.6 fixed wrong scrolls near the bottom with line wrapping. Atomic-editor's README reports 500-page documents scrolling smoothly on iOS after fixing "momentum-scroll halts (image remount jank, heightmap drift, anchor conflicts)".
- Avoid `StateField` decorations rebuilt on every transaction across the whole doc; a `StateField` is only needed for block widgets / multi-line replacements, which Glyph does not use.

## 13. Known mobile bugs, 2025-2026

Fixed (from `@codemirror/view/CHANGELOG.md`): 6.36.2 mobile spacebar-drag selection in EditContext mode; 6.36.3 Chrome EditContext + Samsung keyboard + autocompletion; 6.38.3 Mobile Safari rendering bug (empty layers); 6.38.4 Chrome Android missing `compositionend`; 6.38.5 Safari 26 scroll-on-focus, Android spurious text changes; 6.38.6 Safari 26 stale selection fragments; 6.38.7 IME at multiple cursors; 6.39.15 Chrome Android scroll-into-view; 6.39.17 iOS selection handles, touch tap-selection at wrap boundaries, Safari `posAtCoords`; 6.40.0 iOS Shift-Enter/Backspace modifier; 6.41.0 WebKit stale-selection workaround on non-Safari WebKit; 6.43.2 Chrome Android select-all, iOS autocapitalize shift on Enter/Backspace, Chrome Android scroll-up on tapping an empty line; 6.43.5 iOS momentum scrolling; 6.43.8 Android/iOS horizontal scroll drift; 6.43.11 (2026-09-03) "Speed up handling of Enter/Backspace on iOS in cases where the browser's native behavior is to do nothing."

Open at `code.haverbeke.berlin/codemirror/dev` (2026-09-11): 1748 "iOS and Korean Input: Part of the input disappears" (2026-09-06); 1739 "iOS: Return/Enter is delayed on the last blank line" (2026-08-17); 1675 "Android selection drag handle gets stuck" (2026-02-15); 1556 "Android: Screen reader navigation by lines doesn't work" (2025-04-28); 1538 iOS grabbers (mitigated by `iosSelectionHandles`, still open); 1499 "Scrollbar position jumps when selecting closing bracket on mobile"; 1403 "Safari: Pressing Enter after Korean text inserts duplicate line break" (2024); 1278 "iOS/Safari: Vertical scrollbar broken with wrapped lines" (2023, updated 2025-04); 467 "Android (Boox): Autocorrect appends instead of replacing" (2021). Korean/CJK on iOS is the live risk; add a CJK IME pass to device testing.

## 14. Comparison

| Engine | Tokens stay visible? | Mobile stance | Size (gz, measured) | Notes |
| --- | --- | --- | --- | --- |
| CodeMirror 6 | Yes by construction: plain-text doc + mark/line decorations | Explicit iOS/Android work every release; contenteditable with own DOM sync | 174.5 kB full stack (65 kB core) | Viewport-only, incremental Lezer parse, `lineWrapping`, per-line classes; own selection drawing optional |
| Monaco 0.56.0 | Could (plain text + decorations) | FAQ: mobile browsers / mobile web frameworks "No"; iOS external keyboards lose arrow keys (#293) | 1,153 kB JS + 157 kB CSS + workers | Renders the whole viewport with absolute-positioned lines, needs workers; not viable in WKWebView |
| Lexical 0.50.0 | No: `registerMarkdownShortcuts` "Clean text from opening and closing tags" (`closeNode.setTextContent(...)`), markers removed | contenteditable; iOS autocorrect issues tracked (#7614, 2025) | 155.9 kB (rich-text + markdown + history + list/code/link) | Would need a custom plain-text node tree to keep tokens; fights the model |
| ProseMirror / Tiptap 3.31.3 | No: `prosemirror-markdown` parses to a schema doc via markdown-it; Tiptap `starInputRegex` `/(?:^|\s)(\*\*(?!\s+\*\*)((?:[^*]+))\*\*(?!\s+\*\*))$/` turns `**x**` into a bold mark; `@tiptap/markdown` (2025-10-15) is bidirectional import/export, "early release" | contenteditable; mature, but no phone-specific selection/IME layer beyond the browser | 121.9 kB PM / 121.5 kB Tiptap StarterKit | Token-preserving would mean a one-node plain-text schema plus `Decoration.inline`, i.e. rebuilding CM's job |
| Roll-your-own textarea overlay | Yes (transparent `<textarea>` over a styled `<pre>`) | Native keyboard, autocorrect, handles for free | ~0 kB | react-simple-code-editor: "The syntax highlighted code cannot have different font family, font weight, font style, line height etc." (must align with the textarea), custom undo stack, "large documents may slow typing"; kills the heading-size requirement outright |
| Roll-your-own contenteditable | Yes | You own every composition/autocorrect/Android bug CM fixed in section 13 | small | Only sensible if the feature set stays at colour-only |

## 15. Prior art: Obsidian-style live preview on CM6

- `blueberrycongee/codemirror-live-markdown` (design doc): decorates `EmphasisMark`, `StrikethroughMark`, `CodeMark`, `HeaderMark`, `ListMark`, `QuoteMark`, `StrongEmphasis`, `Emphasis`, `Strikethrough`, `ATXHeading1-6`, `InlineCode`, `Link`; mixes a `StateField` (cached widget decorations for math/tables/code, `provide: f => EditorView.decorations.from(f)`) with a `ViewPlugin.fromClass` for live marks; `shouldShowSource` reveals marks when any `state.selection.ranges` overlaps `[from, to]`; classes `cm-formatting-inline`, `cm-formatting-block`, `cm-heading-line`; a `setMouseSelecting` `StateEffect` freezes rebuilds during drags.
- `kenforthewin/atomic-editor`: "all decorations are view-only", "raw markdown is the source of truth", narrow invalidation so a paragraph edit costs O(change size), a "mouse-freeze guard", and iOS momentum-scroll fixes.

Glyph never hides tokens, so it needs none of the reveal/replace machinery, none of the widget remount jank, and no cursor-position edge cases; sections 6a/6b are the whole renderer.

## 16. Open questions

1. Accept the ~55-60 kB gz `lang-html` chain, or build the `Language` directly from `@lezer/markdown` and vendor the two markdown commands?
2. Autocorrect/autocapitalize default on for prose (iOS-native feel) versus off (CM default, fewer surprises with `*` and `#`)? Needs a device test with Korean/Japanese keyboards given issue 1748.
3. Native selection versus `drawSelection({iosSelectionHandles: true})`: native is cheaper and gives the magnifier; confirm the `::selection` colour can carry `--glacier-selection` in WKWebView.
4. Heading size purely via inline `HighlightStyle` spans, or line classes too (needed for top spacing and the quote bar)? Both is the recommendation; confirm it does not double-apply.
5. Haptic budget per keystroke class and whether `Task` toggles (tap on `[ ]`) get a `selectionFeedback` too.
6. Keep `pasteURLAsLink` (on by default in `markdown()`) and the `Enter`/`Backspace` markdown keymap when the input is a virtual keyboard? Both look right for notes, but `deleteMarkupBackward` changes what Backspace does after `- `, which a phone user cannot see coming.
