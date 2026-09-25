import { EditorView } from '@codemirror/view';

/**
 * A few words shown under what was tapped, over the note: a footnote's text (editor/footnotes.ts) and the note on a
 * mark (editor/markNotes.ts). One at a time for each, closed by a tap elsewhere, a change to the note, or a scroll.
 *
 * Both built the same panel the same way - under the tapped words, then measured once it is on the page and held
 * inside the editor's width, since a panel as wide as its words would otherwise run off the edge it opened near - and
 * each keeps its own class, so closing one never closes the other.
 */

/** Shows `text` in a panel of class `className` under the position `at`, in place of any it already shows. */
export function showTextPanel(view: EditorView, at: number, text: string, { className, label }: { className: string; label: string }): void {
  closeTextPanel(view, className);
  const coords = view.coordsAtPos(at);
  if (!coords) return;
  const panel = document.createElement('div');
  panel.className = className;
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', label);
  panel.textContent = text;
  const box = view.dom.getBoundingClientRect();
  panel.style.left = '0px';
  panel.style.top = `${coords.bottom - box.top + 6}px`;
  view.dom.appendChild(panel);
  const width = panel.getBoundingClientRect().width;
  panel.style.left = `${Math.max(8, Math.min(coords.left - box.left, box.width - width - 8))}px`;
}

/** Takes away the panel of class `className`, if one is showing. */
export function closeTextPanel(view: EditorView, className: string): void {
  view.dom.querySelector(`.${className}`)?.remove();
}

/** The panel's look, for the class `className`: a small card in the paper's second tone. */
export function textPanelTheme(className: string) {
  return EditorView.baseTheme({
    [`.${className}`]: {
      position: 'absolute',
      zIndex: '30',
      maxInlineSize: 'min(20rem, 76vw)',
      padding: '0.5em 0.7em',
      borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
      background: 'var(--app-paper-2, var(--glacier-surface))',
      border: '1px solid var(--app-rule, var(--glacier-border-subtle))',
      boxShadow: '0 6px 20px rgb(0 0 0 / 0.18)',
      font: 'inherit',
      fontSize: '0.86em',
      lineHeight: '1.4',
    },
  });
}

/** Closes the panel of class `className` when the note scrolls: it is placed against the words, and would drift. */
export function closeTextPanelOnScroll(className: string) {
  return EditorView.domEventHandlers({ scroll: (_event, view) => void closeTextPanel(view, className) });
}
