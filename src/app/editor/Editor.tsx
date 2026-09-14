import { useEffect, useRef } from 'react';
import { Compartment, EditorState } from '@codemirror/state';
import { EditorView, keymap, placeholder as cmPlaceholder } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { syntaxHighlighting } from '@codemirror/language';
import { glyphHighlight } from './glyphHighlight.ts';
import { glyphLines } from './glyphLines.ts';
import { glyphTheme } from './glyphTheme.ts';
import { feelTransaction } from './feel.ts';
import { inlineImages } from './images.ts';
import { shortLinks } from './links.ts';
import { drawnTables } from './tables.ts';
import { swipeItemAction, swipeItemTheme, type SwipeAction } from './swipeItems.ts';
import { glyphMarkdown } from './language.ts';
import styles from './Editor.module.css';

/**
 * The editing surface: one CodeMirror view, held outside React.
 *
 * React renders the host element and nothing inside it. That division is not
 * stylistic - the editor's DOM is CodeMirror's, it is reconciled against a
 * document model React knows nothing about, and a re-render that touched it
 * would destroy a selection or a live IME composition. So the view is created
 * once in an effect with an empty dependency list, the `onChange` and `value`
 * props are read through refs, and this component re-renders as often as its
 * parent likes without the editor noticing.
 *
 * `value` is treated as an INITIAL value plus a resync signal: when it differs
 * from what the view holds, the document is replaced (a different note was
 * opened). It is deliberately not a controlled prop in the React sense, because
 * round-tripping every keystroke through a parent's state is exactly the
 * latency this app exists to avoid.
 */

interface EditorProps {
  /** The note's markdown. Changing it to something the view does not hold loads a new document. */
  value: string;
  onChange: (value: string) => void;
  dark: boolean;
  /** Prose input aids: autocorrect, autocapitalisation, spellcheck. */
  assist: boolean;
  placeholder?: string;
  /** A pasted picture could not be kept: the sentence to show. */
  onImageError?: (message: string) => void;
  /** Handed the view once it exists, so a toolbar can dispatch into it. */
  onView?: (view: EditorView | null) => void;
  /** No typing: the document is being written by something else, as during a capture. */
  readOnly?: boolean;
  /**
   * Swiping a list item left runs a plugin's action on it (editor/swipeItems.ts):
   * the action on offer right now, or null. Read at swipe time, through a ref.
   */
  swipeAction?: () => SwipeAction | null;
}

/**
 * The prose overrides.
 *
 * CodeMirror defaults `.cm-content` to `spellcheck: false`, `autocorrect: off`,
 * `autocapitalize: off` and `writingsuggestions: false`, which is right for
 * code and wrong for a notes app: on a phone those four settings are most of
 * what makes typing bearable. `contentAttributes` values overwrite the
 * defaults, so this simply wins.
 */
const PROSE_ATTRS = {
  autocorrect: 'on',
  autocapitalize: 'sentences',
  spellcheck: 'true',
  inputmode: 'text',
  enterkeyhint: 'enter',
};

const PLAIN_ATTRS = {
  autocorrect: 'off',
  autocapitalize: 'off',
  spellcheck: 'false',
  inputmode: 'text',
  enterkeyhint: 'enter',
};

export function Editor({
  value,
  onChange,
  dark,
  assist,
  placeholder,
  onImageError,
  onView,
  readOnly = false,
  swipeAction,
}: EditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  // Props the view needs at dispatch time, read through refs so changing them
  // never rebuilds the editor.
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const onImageErrorRef = useRef(onImageError);
  onImageErrorRef.current = onImageError;
  const swipeActionRef = useRef(swipeAction);
  swipeActionRef.current = swipeAction;

  const themeSlot = useRef(new Compartment());
  const assistSlot = useRef(new Compartment());
  const readOnlySlot = useRef(new Compartment());

  useEffect(() => {
    if (!host.current) return undefined;

    const state = EditorState.create({
      doc: value,
      extensions: [
        history(),
        keymap.of([...historyKeymap, ...defaultKeymap]),
        glyphMarkdown(),
        syntaxHighlighting(glyphHighlight),
        glyphLines,
        inlineImages((message) => onImageErrorRef.current?.(message)),
        shortLinks(),
        drawnTables(),
        swipeItemAction({ action: () => swipeActionRef.current?.() ?? null }),
        swipeItemTheme,
        EditorView.lineWrapping,
        assistSlot.current.of(EditorView.contentAttributes.of(assist ? PROSE_ATTRS : PLAIN_ATTRS)),
        themeSlot.current.of(glyphTheme(dark)),
        readOnlySlot.current.of(readOnlyExtensions(readOnly)),
        placeholder ? cmPlaceholder(placeholder) : [],
        EditorView.updateListener.of((update) => {
          if (update.docChanged) onChangeRef.current(update.state.doc.toString());
          for (const tr of update.transactions) feelTransaction(tr);
        }),
      ],
    });

    const created = new EditorView({ state, parent: host.current });
    view.current = created;
    onView?.(created);

    return () => {
      onView?.(null);
      created.destroy();
      view.current = null;
    };
    // Built once. Every prop that can change is reconfigured below instead.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Theme and input aids flip through Compartments, which swap one extension
  // in place: no new state, no lost selection, no interrupted composition.
  useEffect(() => {
    view.current?.dispatch({ effects: themeSlot.current.reconfigure(glyphTheme(dark)) });
  }, [dark]);

  useEffect(() => {
    view.current?.dispatch({
      effects: assistSlot.current.reconfigure(EditorView.contentAttributes.of(assist ? PROSE_ATTRS : PLAIN_ATTRS)),
    });
  }, [assist]);

  useEffect(() => {
    view.current?.dispatch({ effects: readOnlySlot.current.reconfigure(readOnlyExtensions(readOnly)) });
  }, [readOnly]);

  // A different note was opened. Compared against the view's own document
  // rather than a previous prop, so the echo of our own `onChange` is ignored.
  useEffect(() => {
    const current = view.current;
    if (!current || current.state.doc.toString() === value) return;
    current.dispatch({
      changes: { from: 0, to: current.state.doc.length, insert: value },
      selection: { anchor: Math.min(current.state.selection.main.anchor, value.length) },
    });
  }, [value]);

  return <div className={styles.editor} ref={host} />;
}

/**
 * Read-only in both of CodeMirror's senses. `readOnly` stops transactions from
 * editing; `editable` stops the content element being contenteditable at all,
 * which is what keeps a phone's keyboard from rising over a note that is being
 * dictated rather than typed.
 */
function readOnlyExtensions(readOnly: boolean) {
  return [EditorState.readOnly.of(readOnly), EditorView.editable.of(!readOnly)];
}
