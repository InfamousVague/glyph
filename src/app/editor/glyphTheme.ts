import { EditorView } from '@codemirror/view';

/**
 * CodeMirror's own styling layer, expressed entirely in Glacier tokens.
 *
 * Everything that can live in `Editor.module.css` does; this file exists only
 * for the handful of selectors CodeMirror generates and owns (`.cm-scroller`,
 * `.cm-content`, `.cm-line`, `.cm-cursor`), which no stylesheet of ours can
 * reach first because the editor's base theme is injected at a precedence a
 * plain class cannot beat.
 *
 * style-mod writes values through verbatim, so `var(--glacier-surface)` is
 * passed as a string and resolved by the browser at paint time. That is what
 * lets Glacier's `data-theme` flip on `<html>` retune the editor with no
 * rebuild, no re-render, and no theme object in JavaScript - one attribute
 * changes and the whole editor follows, including mid-composition.
 *
 * The `dark` flag is still reconfigured through a Compartment on every theme
 * change, because CodeMirror's own base theme has `&dark` rules of its own and
 * it should agree with the app about which one is in force.
 */
export const glyphTheme = (dark: boolean) =>
  EditorView.theme(
    {
      '&': {
        backgroundColor: 'var(--glacier-bg)',
        color: 'var(--glacier-text)',
        height: '100%',
      },
      // The prose face. The kit's own RichTextEditor is monospace, which is
      // right for a chat composer that must align a highlight layer under a
      // textarea; Glyph paints the styled text itself, so it can use the
      // reading face and vary the size per heading.
      '.cm-scroller': {
        fontFamily: 'var(--glacier-font-sans)',
        // A full kit step above reading size, scaled by the text-size setting
        // (app.css). The leading is a little looser than the kit's 1.5, which
        // is tuned for UI text rather than paragraphs a person reads.
        fontSize: 'var(--app-body)',
        lineHeight: '1.6',
        // Momentum scrolling inside the editor rather than the page, so the
        // header stays put and the keyboard does not fight the document.
        overflowY: 'auto',
        overscrollBehavior: 'contain',
      },
      '.cm-content': {
        // Room to tap past the last line, and to keep the final paragraph off
        // the formatting bar.
        padding: 'var(--glacier-space-5) 0 var(--glacier-space-24)',
        caretColor: 'var(--glacier-accent-solid)',
      },
      /*
       * The line's inline padding is deliberately NOT set here, and this is a
       * specificity note rather than a preference. style-mod scopes every rule
       * in this object under a generated class, so `.cm-line` here is really
       * `.ͼ1 .cm-line` - two classes - and it silently beat the single-class
       * `.lineItem` / `.lineQuote` rules that need to change the same property.
       * The visible symptom was a list's dash and a quote's bar sitting flat
       * against the left edge of the screen. All line padding lives in
       * Editor.module.css, where the base rule and the per-block rules can be
       * written at specificities that order correctly against each other.
       */
      // A full-bleed editor has nothing to draw a ring around.
      '&.cm-focused': {
        outline: 'none',
      },
      // The native selection, coloured. Glyph deliberately does not install
      // `drawSelection`, so these are real browser selections with real grab
      // handles, a real magnifier, and the real callout menu.
      '.cm-line ::selection': { backgroundColor: 'var(--glacier-selection)' },
      '.cm-line::selection': { backgroundColor: 'var(--glacier-selection)' },
      '.cm-placeholder': { color: 'var(--glacier-text-subtle)' },
    },
    { dark },
  );
