# The editor and its language

_How a Markdown string becomes the page you type on: one CodeMirror view held outside React, a parser that is GFM less one rule, and two layers of drawing that never take a character out of the file._

## One view, held outside React

`src/app/editor/Editor.tsx` renders one `div` and hands it to CodeMirror 6 in an effect with an empty dependency list. React never touches what is inside. A re-render that did would break a selection or a live IME composition.

`value` is not a controlled prop. It is the first document, plus a resync: when it differs from what the view holds, the document is replaced, which is what opening another note does. It is compared with the view's own document, so the echo of `onChange` is ignored and no keystroke round-trips through a parent's state.

A prop reaches the view in one of three ways, and a caller has to know which.

| How it arrives | Props | A change costs |
|---|---|---|
| A ref, read when used | `onChange`, `onImageError`, `swipeAction`, `suggest`, `linkMenus`, `wiki`, `onAiMarks` | Nothing |
| A `Compartment`, swapped in place | `dark`, `assist`, `readOnly`, `tape` and `tapeId`, `display` | One transaction; selection and composition survive |
| Read once, when the view is made | `grow`, `arrivals`, `wispTyping`, `ripples`, `peek`, `diagrams`, `placeholder`, whether `wiki` or `linkMenus` was given, the plugins' formats | A remount with a new `key` |

`src/app/App.tsx` keys the note screen by note id, so every note opens in a fresh editor. A new `wiki` object tells the editor the notes changed and it rescans for framed canvases, so `NoteScreen.tsx` keeps one in a `useMemo`. Undo sits in a compartment of its own, `undoSlot` (`editor/undoSlot.ts`), so a live note can swap in Yjs's.

CodeMirror turns `spellcheck`, `autocorrect` and `autocapitalize` off on `.cm-content`, which is right for code and wrong for notes. `PROSE_ATTRS` turns them back on through `EditorView.contentAttributes`. The note screen passes `prefs.assist`, which is on by default and synced; at HEAD no row in Settings changes it. Read-only editors and the recorder's live page pass `assist={false}`. There is no `drawSelection`: a selection is the browser's own, with real handles and a magnifier.

## The language

`editor/language.ts` starts from `markdownLanguage`, GFM with subscript, superscript and emoji, and takes one rule out: `{ remove: ['SetextHeading'] }`. On a phone, a `-` typed under a line to start a list promoted that line to a heading. Here `#` is the only way to make one, a lone `-` is an empty item, and `---` is a rule.

A fence whose info string names a language, such as `js`, is parsed by that language from `@codemirror/language-data`, loaded the first time it is met. A fence with no language, or one the pack does not know, is plain monospace.

A plugin's inline format (`InlineFormat`, `plugins/types.ts`) becomes a node the way GFM's `~~` does, with the same flanking rules: the spoiler makes a `Spoiler` node holding two `SpoilerMark`s and the words. `delimiterUnit` finds the piece a delimiter repeats, and a longer run of the piece is not the format, so three flames are three flames. `🔥🔥` is a run of `🔥`, two UTF-16 code units; `❄️❄️` is a run of a character and its variation selector. The parser counts in code units, as CodeMirror's positions do.

`editor/syntax.ts` asks the parse what a position is inside; `inQuietText` says whether text is code, an address, front matter, HTML, a comment or maths, where a tag or a counter is never drawn.

## Two layers of drawing

Nothing in either layer changes the document. Decorations style ranges of the real text.

**Inline, by tag.** `glyphHighlight.ts` is one `HighlightStyle`. Lezer tags every delimiter `processingInstruction`, and each run carries the union of the tags covering it, so inside `**bold**` the asterisks carry `strong` and `processingInstruction` and the word only `strong`. One rule styles the words; `.mark` dims the markers. `.mark` and `.strong` have the same specificity, so the marker comes last in the highlight list and last among the inline rules of `Editor.module.css`, or the asterisks draw bold.

**Per line.** `glyphLines.ts` is one `ViewPlugin` for what a span cannot reach: space above a heading, a quote's bar, a code block's card, a list's hanging indent. The indent is measured with a hidden ruler in the editor's own face, cached per face, size and kind of marker, and set as `--hang`. While an IME is composing, the plugin maps its decorations through the change rather than rebuilding them: replacing a line's DOM under a composition is the surest way to lose characters on a phone.

**CodeMirror's own selectors.** `glyphTheme.ts` holds only what CodeMirror generates: the scroller, the content, the selection, the placeholder. Most of its values are `var(--…)` strings resolved at paint time, so a change of palette needs no rebuild. The selection is the exception: it is literal ink and paper, because some WebViews resolve a custom property in a selection late or not at all, so the `dark` compartment swaps it. The theme sets no line padding, because style-mod scopes its `.cm-line` under a generated class and that silently beat `.lineItem`.

**The rule book.** `Editor.module.css` is named for the host, but only `.editor` is the host's. The rest is the renderer's: inline classes for spans, line classes for lines, every line rule written `.editor :global(.cm-line).lineX` so the specificities order themselves in one file.

## Widgets drawn in place

Some things are drawn as what they are, and each keeps its Markdown.

| Written | Drawn by | The Markdown shows |
|---|---|---|
| A GFM table | `editor/tables.ts` | With the caret in it |
| A `board` fence | `editor/boards.ts`, `editor/boards/` | With the caret in the fence |
| A `mermaid` fence | `editor/mermaid.ts`, loaded on first use | With the caret in the fence |
| `![[Cabin weekend, laid out]]` alone on a line | `editor/canvasFrames.ts` | With the caret on the line |
| A picture reference | `editor/images.ts`, under the line | Always, dimmed |
| A line that is only a link | `editor/linkCards.ts`, under the line | Always |
| A voice memo | `editor/clips.ts`, a small player | With the caret on the line |

Block widgets must come from a state field, and a field cannot ask the view about focus, so `editor/drawnBlock.ts` keeps focus in a field every drawn block shares. A widget that holds React uses `editor/reactMount.ts`: `mountReact(host, element)` makes a root and takes it down in a microtask, since CodeMirror may destroy a widget while React is drawing. It is the only `createRoot` in `src/app`.

## The Formatted view

`editor/viewMode.ts` has two views. The round switch among the note's tools changes between them: it wears a code icon while the marks are on the page and an open book while the note is formatted. On a narrow screen the More sheet offers it too: a Show row under Reading it, with Markdown and Formatted. Markdown (`mixed`) is the default and adds nothing. Formatted hides the marks that only say how words look (emphasis, strikethrough, `#`, `>`, inline code's backticks, a plugin's delimiters, an escape's backslash) with `Decoration.replace` and `atomicRanges`, so the arrow keys step over them. While the note has focus, the lines the selection touches keep their marks. A list's dash and a to-do's box always stay.

## Effects and smoke

- `editor/wispFormat.ts` draws the spoiler: every letter under one of twelve shared SVG filters, moved about thirty times a second while smoke is on screen. The caret in it clears it; a read-only view never does.
- `editor/textEffects.ts` draws `TEXT_EFFECTS`. Heat is `'rising'`, a haze over the text above, found by measuring after each draw. Frost is `'filter'`, one field over the words. Wave, shimmer and haunt are `'letters'`, a CSS animation per letter with negative delays, so a line drawn fresh is already moving. An effect lifts while the caret is in its words.
- `editor/wispArrivals.ts` draws Ghostly typing (Settings > Animations): letters typed, and letters from a transaction carrying the `wisp` annotation, arrive out of smoke, from a pool of at most 32 filters. `editor/wispMotion.ts` decides what moves. The recorder (`capture/LivePage.tsx`), the AI's lander (`ai/land.ts`) and the review (`ai/review.ts`) write with the annotation.

Every look is a plain inline mark, never an inline-block, so kerning and wrapping stay exactly as they are without it. `art/wisp.ts` plans the same kind of arrival, word by word, for words outside the editor (`art/WispText.tsx`, such as the welcome page's headline).

## The 2^24 budget

The smoke where a page slips under its header is `art/wispEdge.ts`; the note screen wears it with `useWispEdge`. A filter region has a budget of 2^24 device pixels. Over it, WebKit draws nothing and the element paints solid black: measured, 4096 by 4096 draws and 4200 by 4000 is black, and at two device pixels to the CSS pixel the boundary is 2048 by 2048. The region was once one fixed size big enough for any view, which is why the Mac went black on scroll. Now `placeRegion` sizes it to the window, and every wisp filter asks `withinWispBudget(across, down)` first: the page's, a board lane's foot (`art/wispFoot.ts`) and the tab row's (`art/wispSides.ts`). One that does not fit keeps a plain fade.

==The boundary, not the engine, decided whether it drew.==

## The note screen around it

`editor/NoteScreen.tsx` composes one open note: the AI's strip under the header, the tape, the link marks, a book's bar, the byline, the editor. For a canvas or a book the drawn view takes the editor's place, and the editor stays mounted under it, hidden.

Saving is `editor/useNoteSaving.ts`. The live words are a ref, `body`, and only `onChange` writes it. A save runs 400 ms after the last keystroke; a flush runs on `visibilitychange` to hidden, `pagehide`, unmount, and every way off the note, because a phone kills a background WebView with no `beforeunload`. Anything else that must change the open note asks the screen, as a rename from a tab does through the `rename` prop. A failed save stops the screen saving, so a queued write never brings a deleted note back.

`editor/aiChanges.ts` tracks the AI's changes. The model's lines land in the note as they finish, and the marks are decorations over that text, mapped through every edit: added words tinted, removed words struck through where they were, Keep and Revert at the end of each run. Typing on a changed line makes it yours. Revert is one edit, so one Undo takes it back. `ai/marks.ts` keeps a note's marks with a hash of its body.

`editor/liveBinding.ts` binds a live note: the view is brought to the shared text, then `undoSlot` is swapped for `yCollab` and Yjs's undo keys, so undo takes back only this device's typing. `editor/useLiveNote.ts` loads it on demand, only when live is on.

## Where the comments have fallen behind

- `glyphLines.ts` says the editor never hides anything, and `links.ts` repeats it. The Formatted view hides marks, and the drawn blocks replace their Markdown while the caret is elsewhere.
- `language.ts` and `wispFormat.ts` speak of "the Spoiler plugin". The spoiler is one of the Marks plugin's eleven formats.
- `tables.ts` and `drawnBlock.ts` call the Formatted view one that cannot be edited, where a drawn block stays drawn, and `links.ts` calls the Formatted note read-only. On the note screen the Formatted view is editable, and a table steps aside for the caret there as it does in Markdown.

## Read next

- [[Formats that stay Markdown]]
- [[The plugin seam]]
- [[Live typing over a relay]]
