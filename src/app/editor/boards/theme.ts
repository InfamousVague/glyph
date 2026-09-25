import { EditorView } from '@codemirror/view';

/**
 * How a board looks: its columns, cards, controls, the + field, the card's menu, the line under it, and the anchors
 * and pointers in the note's own lines. Written under the editor's classes (`EditorView.baseTheme`), which is why a
 * card lifted off the board is drawn in a layer carrying them (editor/boards/drag.ts `pickUp`).
 */

/** A board's type, against the note's. */
export const BOARD_TYPE = 0.86;
/** Room under a lane's last card, in the lane's ems; the set-height lanes keep more, for the smoke. */
export const LANE_FOOT = 0.25;

export const boardTheme = EditorView.baseTheme({
  '.cm-board': {
    display: 'flex',
    gap: '0.7em',
    // As wide as the note is, never as wide as its columns: the columns scroll inside it (editor/boards.ts `boardRoom`).
    inlineSize: 'var(--cm-board-room, 100%)',
    // A block widget sits outside the note's own indent, so the indent is put back as padding: the first column
    // lines up with the words, and a column scrolled along runs to the edge of the screen.
    paddingInline: 'var(--cm-board-bleed, 0px)',
    scrollPaddingInline: 'var(--cm-board-bleed, 0px)',
    overflowX: 'auto',
    // Sideways only. With the columns scrolling, the board is a scroller both ways, and a finger moving up it was
    // the board's to scroll wherever it overflowed by a pixel, not the note's.
    overflowY: 'hidden',
    overscrollBehaviorX: 'contain',
    // One column at a time on a phone: a swipe settles on a column rather than between two.
    scrollSnapType: 'x mandatory',
    paddingBlock: '0.1em 0.5em',
    scrollbarWidth: 'none',
    fontSize: `${BOARD_TYPE}em`,
    textIndent: '0',
  },
  '.cm-board[data-holding]': { scrollSnapType: 'none', cursor: 'grabbing' },
  '.cm-boardColumn': {
    flex: '0 0 auto',
    inlineSize: 'min(78vw, 16rem)',
    scrollSnapAlign: 'start',
    display: 'flex',
    flexDirection: 'column',
    gap: '0.4em',
    padding: '0.5em 0.45em 0.2em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
  },
  '.cm-boardName': {
    display: 'flex',
    alignItems: 'center',
    gap: '0.45em',
    margin: '0',
    padding: '0 0.15em',
    minBlockSize: '1.9em',
    fontSize: '0.78em',
    fontWeight: '700',
    letterSpacing: '0.07em',
    textTransform: 'uppercase',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  '.cm-boardNameWords': { overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
  '.cm-boardCount': {
    flex: 'none',
    minInlineSize: '1.6em',
    padding: '0.05em 0.45em',
    borderRadius: '999px',
    background: 'color-mix(in oklch, currentColor 10%, transparent)',
    textAlign: 'center',
    letterSpacing: '0',
    fontWeight: '600',
  },
  '.cm-boardAdd': {
    flex: 'none',
    display: 'grid',
    placeItems: 'center',
    marginInlineStart: 'auto',
    inlineSize: '2em',
    blockSize: '2em',
    padding: '0',
    border: 'none',
    borderRadius: '999px',
    background: 'color-mix(in oklch, currentColor 8%, transparent)',
    color: 'var(--app-ink-2, inherit)',
    cursor: 'pointer',
  },
  /* The field a new card is typed into, under the column's name. */
  /*
   * The field a new card is typed into is drawn as the card it is about to be (Matt: "Add task input and button
   * dont match up"): the card's corners, ground and ring, an empty tick box where the card's box goes so the words
   * start where a card's do, and an Add whose corners sit inside the field's. The ring is a little stronger than a
   * card's, which is how the one being written is told from the rest.
   */
  '.cm-boardCompose': {
    display: 'grid',
    gridTemplateColumns: 'auto 1fr auto',
    alignItems: 'center',
    columnGap: '0.55em',
    padding: '0.3em 0.3em 0.3em 0.65em',
    borderRadius: '0.7em',
    background: 'var(--app-paper, var(--glacier-bg))',
    boxShadow: 'inset 0 0 0 1.5px color-mix(in oklch, currentColor 30%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)',
  },
  '.cm-boardComposeTick': {
    inlineSize: '1.15em',
    blockSize: '1.15em',
    borderRadius: '0.32em',
    border: '1.5px solid color-mix(in oklch, var(--app-ink, var(--glacier-text)) 30%, transparent)',
  },
  '.cm-boardComposeField': {
    minInlineSize: '0',
    blockSize: '2.1em',
    padding: '0',
    border: 'none',
    background: 'none',
    color: 'inherit',
    font: 'inherit',
    lineHeight: '2.1em',
    outline: 'none',
  },
  '.cm-boardComposeField::placeholder': { color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardComposeAdd': {
    blockSize: '2.1em',
    padding: '0 0.85em',
    border: 'none',
    // The field's corner less its padding: the button's curve runs alongside the field's.
    borderRadius: 'calc(0.7em - 0.3em)',
    background: 'var(--app-ink, currentColor)',
    color: 'var(--app-paper, var(--glacier-bg))',
    // The field's own size, so its height and its corner are measured in the same em as the field's.
    font: 'inherit',
    fontWeight: '600',
    lineHeight: '1',
    cursor: 'pointer',
    transition: 'background-color 120ms ease, color 120ms ease',
  },
  // Nothing typed yet, nothing to add: the button waits, quiet, in the field's own ink.
  '.cm-boardComposeAdd:disabled': {
    background: 'color-mix(in oklch, currentColor 10%, transparent)',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    cursor: 'default',
  },
  /*
   * Set by the line under the board: the lanes are that tall, cards or not (heightSplit), and one with more cards
   * scrolls inside itself. At either end of it the finger goes on to the note (no `overscroll-behavior`: a lane that
   * kept the scroll to itself stopped the note dead under a finger that landed on it).
   */
  '.cm-board[data-sized] .cm-boardStack': {
    blockSize: 'var(--cm-lane-height)',
    overflowY: 'auto',
    scrollbarWidth: 'none',
    paddingBlockEnd: '0.9em',
  },
  /* The same, for a board holding the height it was drawn at rather than one the fence set (height.ts `pin`). */
  '.cm-board[data-pinned]:not([data-sized]) .cm-boardStack': {
    blockSize: 'var(--cm-board-pin)',
    overflowY: 'auto',
    scrollbarWidth: 'none',
    paddingBlockEnd: '0.9em',
  },
  // More cards below than the lane shows: its foot fades, and goes to smoke where the app's wisp is on (laneFoot).
  // With smoke the length comes from the band's own lip (`--cm-lane-fade`, art/wispFoot.ts `WISP_FOOT_FADE`); the
  // em here is the plain fade, for a lane with no smoke to agree with.
  '.cm-boardStack[data-more]': {
    WebkitMaskImage: 'linear-gradient(to bottom, #000 calc(100% - var(--cm-lane-fade, 1.2em)), transparent)',
    maskImage: 'linear-gradient(to bottom, #000 calc(100% - var(--cm-lane-fade, 1.2em)), transparent)',
  },
  // Padding, not margin, above and below: the editor measures a block by its border box, and a margin - the board's
  // own at the top went straight through this box - put every line under the board that far from where the editor
  // thought it was. The room above is the board's 0.4em, in the note's type.
  '.cm-boardWrap': { paddingBlock: `calc(0.4em * ${BOARD_TYPE}) 0.5em` },
  /*
   * Glacier's split-pane divider (@glacier/react ResizableSplitPane): a hairline in the subtle border, a grip pill,
   * the accent when it is being moved or has the focus. Its touch reaches above and below the hairline.
   */
  '.cm-boardSplit': {
    position: 'relative',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    blockSize: 'var(--glacier-hairline, 1px)',
    marginInline: 'var(--cm-board-bleed, 0px)',
    marginBlock: '0.3em 1em',
    background: 'var(--glacier-border-subtle, color-mix(in oklch, currentColor 14%, transparent))',
    cursor: 'row-resize',
    touchAction: 'none',
    transition: 'background-color var(--glacier-duration-fast, 120ms) var(--glacier-ease-out, ease-out)',
  },
  // A finger's width of touch: down to the next line, and up into the board's own padding but not onto its cards.
  '.cm-boardSplit::before': { content: '""', position: 'absolute', insetInline: '0', insetBlock: '-0.7em -1em' },
  '.cm-boardSplit:focus-visible, .cm-boardSplit[data-dragging]': {
    outline: 'none',
    background: 'var(--glacier-accent-solid, currentColor)',
  },
  // The grip, at the middle of the line and always there, since a phone has no hover: a small pill, white while it is
  // held or has the focus.
  '.cm-boardGrip': {
    position: 'relative',
    zIndex: '1',
    inlineSize: 'var(--glacier-space-6, 1.5rem)',
    blockSize: '6px',
    borderRadius: 'var(--glacier-radius-full, 999px)',
    background: 'color-mix(in oklch, currentColor 45%, transparent)',
    transition: 'background-color var(--glacier-duration-fast, 120ms) var(--glacier-ease-out, ease-out)',
  },
  '.cm-boardSplit:hover .cm-boardGrip': { background: 'color-mix(in oklch, currentColor 70%, transparent)' },
  '.cm-boardSplit:focus-visible .cm-boardGrip, .cm-boardSplit[data-dragging] .cm-boardGrip': { background: '#fff' },
  /*
   * A lane. Left to itself it shows every card and never scrolls: a note is scrolled past a board in one sweep (Matt:
   * "scrolling past boards is glitchy and stops scroll momentum"), where a lane with a cap of its own took the finger
   * and kept it. It runs to the foot of its column, which is as tall as the board's tallest, so an empty lane has a
   * middle.
   */
  '.cm-boardStack': {
    display: 'flex',
    flexDirection: 'column',
    flex: '1 1 auto',
    gap: '0.4em',
    minBlockSize: '2.5em',
    paddingBlockEnd: `${LANE_FOOT}em`,
  },
  /*
   * A card is a small grid (Matt: "the cards themselves can have the text go full width and we can move the notion icon
   * to the right more"): the tick and the words on the first row, the words taking every bit of width the card has,
   * and under them a footer that sits right - the plugin's mark, then the two arrows.
   */
  '.cm-boardCard': {
    display: 'grid',
    gridTemplateColumns: 'auto 1fr auto auto',
    gridTemplateAreas: '"tick words words words" ". . linked moves"',
    alignItems: 'start',
    columnGap: '0.55em',
    rowGap: '0.15em',
    flex: 'none',
    minBlockSize: '2.6em',
    padding: '0.6em 0.4em 0.3em 0.65em',
    borderRadius: '0.7em',
    background: 'var(--app-paper, var(--glacier-bg))',
    boxShadow: 'inset 0 0 0 1px color-mix(in oklch, currentColor 9%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)',
    // The finger scrolls until the card is picked up, and then the drag takes over.
    touchAction: 'pan-x pan-y',
    userSelect: 'none',
    WebkitUserSelect: 'none',
    WebkitTapHighlightColor: 'transparent',
    transition: 'opacity 120ms ease',
  },
  '.cm-boardCard[data-done]': { opacity: '0.62' },
  /* The card where it would land: its own shape, emptied out, so the column opens exactly the space it takes. */
  '.cm-boardCard[data-lifted]': {
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
    borderStyle: 'dashed',
    overflow: 'hidden',
  },
  '.cm-boardCard[data-lifted] > *': { visibility: 'hidden' },
  '.cm-boardCard[data-done] .cm-boardWords': { textDecoration: 'line-through', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardCard[data-gone] .cm-boardWords': { fontStyle: 'italic', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardCard[data-empty] .cm-boardWords': { fontStyle: 'italic', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  /* The card in the air, under the finger: the same card, lifted off the page. */
  '.cm-boardGhost': {
    position: 'fixed',
    insetBlockStart: '0',
    insetInlineStart: '0',
    zIndex: '40',
    margin: '0',
    pointerEvents: 'none',
    boxShadow: '0 10px 24px rgba(0, 0, 0, 0.28)',
    transform: 'translate(0, 0)',
    opacity: '0.96',
  },
  '.cm-boardEmpty': {
    display: 'none',
    margin: '0',
    padding: '0.8em 0.6em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    border: '1px dashed transparent',
    textAlign: 'center',
    fontSize: '0.9em',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  // At rest, only an empty column shows it: the picture and the words, no outline.
  // It fills its lane, and the picture and words sit in the middle of it (Matt: "vertically center the icons in the
  // swimlanes"): a lane beside a full one is as tall as that one, and a board with a set height has tall lanes.
  // It reaches into the lane's own space at the foot, so the middle is the whole lane's: its type is 0.9 of the lane's,
  // so the lane's room is this element's room over 0.9.
  '.cm-boardEmpty[data-none]': {
    display: 'grid',
    flex: '1 1 auto',
    alignContent: 'center',
    paddingBlock: '1.1em',
    marginBlockEnd: `calc(${-LANE_FOOT}em / 0.9)`,
  },
  '.cm-board[data-sized] .cm-boardEmpty[data-none], .cm-board[data-pinned] .cm-boardEmpty[data-none]': { marginBlockEnd: 'calc(-0.9em / 0.9)' },
  '.cm-boardEmptyRest': { display: 'grid', justifyItems: 'center', gap: '0.45em' },
  '.cm-boardEmptyIcon': { opacity: '0.55' },
  '.cm-boardEmptyDrop': { display: 'none' },
  // A card held: every column is a target, outlined, and says so instead.
  '.cm-board[data-holding] .cm-boardEmpty': {
    display: 'block',
    paddingBlock: '0.8em',
    borderColor: 'var(--app-rule, var(--glacier-border-subtle))',
  },
  '.cm-board[data-holding] .cm-boardEmptyRest': { display: 'none' },
  '.cm-board[data-holding] .cm-boardEmptyDrop': { display: 'block' },
  '.cm-boardStack[data-over] .cm-boardEmpty': { borderStyle: 'solid' },
  // Sized from the card's own text rather than a button's default font, and set on the first line's centre, so every
  // box sits level with the words beside it (Matt: "the checkboxes also dont look like they line up nice").
  '.cm-boardTick': {
    gridArea: 'tick',
    position: 'relative',
    display: 'grid',
    placeItems: 'center',
    fontSize: 'inherit',
    lineHeight: '1',
    inlineSize: '1.15em',
    blockSize: '1.15em',
    marginBlockStart: 'calc((1.35em - 1.15em) / 2)',
    padding: '0',
    borderRadius: '0.32em',
    // The box's edge is named in ink, not `currentColor`: the tick's own colour is paper, for the check drawn on ink.
    border: '1.5px solid color-mix(in oklch, var(--app-ink, var(--glacier-text)) 45%, transparent)',
    background: 'none',
    color: 'var(--app-paper, var(--glacier-bg))',
    cursor: 'pointer',
  },
  '.cm-boardTick svg': { visibility: 'hidden' },
  // The box is small; the place to tap it is not. An invisible margin around it takes a finger that lands a little off,
  // which otherwise hit the words beside it and went to the line.
  '.cm-boardTick::before': { content: '""', position: 'absolute', inset: '-0.6em -0.45em -0.6em -0.6em' },
  // A card that has just arrived in its lane, lit for a moment so the eye finds it.
  '.cm-boardCard[data-arrived]': {
    boxShadow: 'inset 0 0 0 1.5px color-mix(in oklch, var(--app-ink, currentColor) 55%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)',
  },
  '.cm-boardCard[data-done] .cm-boardTick': {
    background: 'var(--app-ink, currentColor)',
    borderColor: 'var(--app-ink, currentColor)',
  },
  '.cm-boardCard[data-done] .cm-boardTick svg': { visibility: 'visible' },
  '.cm-boardTick:disabled': { opacity: '0.4', cursor: 'default' },
  /* An item with no box: a bullet, kept so every card's words start in the same place. */
  '.cm-boardDot': {
    gridArea: 'tick',
    justifySelf: 'center',
    flex: 'none',
    inlineSize: '0.4em',
    blockSize: '0.4em',
    marginBlockStart: '0.55em',
    marginInline: '0.45em',
    borderRadius: '50%',
    background: 'var(--app-ink-3, currentColor)',
  },
  '.cm-boardWords': {
    gridArea: 'words',
    minInlineSize: '0',
    // Three lines at most: one long item must not take the whole board. The words are whole in the note below.
    display: '-webkit-box',
    WebkitLineClamp: '3',
    WebkitBoxOrient: 'vertical',
    overflow: 'hidden',
    padding: '0',
    border: 'none',
    background: 'none',
    font: 'inherit',
    lineHeight: '1.35',
    textAlign: 'start',
    color: 'inherit',
    cursor: 'pointer',
  },
  // The plugin a card's item is linked to, as its mark: quiet, beside the words, never read as one of them.
  '.cm-boardLinked': {
    gridArea: 'linked',
    alignSelf: 'center',
    display: 'grid',
    placeItems: 'center',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    opacity: '0.8',
  },
  '.cm-boardMoves': { gridArea: 'moves', display: 'flex', gap: '0', marginInlineEnd: '-0.1em' },
  '.cm-boardMove': {
    display: 'grid',
    placeItems: 'center',
    inlineSize: '1.7em',
    blockSize: '1.7em',
    padding: '0',
    border: 'none',
    borderRadius: '999px',
    background: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    opacity: '0.7',
    cursor: 'pointer',
  },
  '.cm-boardMove:disabled': { opacity: '0.25', cursor: 'default' },
  /* The card's menu button, the same size and weight as the chevrons beside it. */
  '.cm-boardMore': {
    display: 'grid',
    placeItems: 'center',
    inlineSize: '1.7em',
    blockSize: '1.7em',
    padding: '0',
    border: 'none',
    borderRadius: '999px',
    background: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    opacity: '0.7',
    cursor: 'pointer',
  },
  /*
   * The card's menu: in the lane, right under its card, the way the + field sits at the top of a column. A panel of
   * the board's own ground with a hairline, and rows a thumb can hit.
   */
  '.cm-boardMenu': {
    display: 'grid',
    flex: 'none',
    gap: '1px',
    margin: '0.1em 0 0.2em',
    padding: '0.25em',
    borderRadius: '0.7em',
    background: 'var(--app-paper, var(--glacier-bg))',
    boxShadow: 'inset 0 0 0 1px color-mix(in oklch, currentColor 14%, transparent), 0 2px 6px rgba(0, 0, 0, 0.18)',
  },
  '.cm-boardMenuRow': {
    display: 'flex',
    alignItems: 'center',
    gap: '0.55em',
    minBlockSize: '2.4em',
    padding: '0 0.55em',
    border: 'none',
    borderRadius: '0.5em',
    background: 'none',
    color: 'var(--app-ink, currentColor)',
    font: 'inherit',
    fontSize: '0.95em',
    textAlign: 'start',
    cursor: 'pointer',
  },
  '.cm-boardMenuRow:hover': { background: 'color-mix(in oklch, currentColor 7%, transparent)' },
  '.cm-boardMenuRow svg': { flex: 'none', opacity: '0.75' },
  /* The anchor on the line, and a pointer at one from the words. */
  '.cm-itemAnchor': { fontSize: '0.82em', opacity: '0.45' },
  '.cm-itemRef': {
    textDecoration: 'underline',
    textUnderlineOffset: '0.2em',
    textDecorationThickness: '0.06em',
    textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)',
    cursor: 'pointer',
  },
  '.cm-itemRefGone': { opacity: '0.55', textDecorationStyle: 'dotted' },
});
