import { useEffect, useMemo, useRef, useState, type RefObject } from 'react';
import { EditorView } from '@codemirror/view';
import { Editor } from '../editor/Editor.tsx';
import { commonEnds, wisp } from '../editor/wispArrivals.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { holdWispDrift, useWispEdge } from '../art/wispEdge.ts';
import { END, placeTake, type Placing } from './place.ts';
import { onVoiceLevel } from './voiceLevel.ts';
import styles from './CaptureScreen.module.css';

/**
 * The note being spoken, as its page: the same editor the note opens in, the
 * note's older text above, and what is being said written onto its end.
 *
 * Matt: "as the text is understood from the transcriptions it should render
 * into the active note showing the old notes above instead of always going to
 * this new UI. The memo mode will always just be voice writing with formatting
 * keywords on a normal page. As we understand and rewrite the text I speak I
 * want the text to appear and disappear with the wisp effect."
 *
 * Set as it will read, not as it is written: the page is in the formatted view (editor/viewMode.ts), so a heading is
 * a heading and a bullet a bullet as it is said, without the marks around them (Matt: "show actual stuff being
 * written out and formatted as i talk"). The marks are all there in the note it saves.
 *
 * The page is read-only while it is being written. Each change of what was
 * heard is written into the editor as the smallest edit that gets there (the
 * shared start and end kept), marked `wisp` (editor/wispArrivals.ts): new
 * letters come in out of smoke, and a guess being corrected loses its old
 * letters into it (Matt: "the memo page should real time fade words in with
 * the wisp effect"; it was off a while, when the arriving letters were boxes
 * that shifted the line, and came back once they weren't). The page follows the newest words down unless the person
 * has scrolled up to read.
 *
 * Words for a note's list are written into the list, where they will be saved (place.ts `placeTake`, the same the
 * recorder's Done writes with), so the page follows the words where they arrive rather than the bottom: Matt, "open
 * the note, and start live writing to that note".
 */

interface LivePageProps {
  /** The continued note's text before this capture, or '' for a new note. */
  base: string;
  /** This capture's markdown so far, the phrase still being guessed included. */
  markdown: string;
  /** Shown on an empty page. */
  placeholder: string;
  /** The recorder's top line, which the page runs under: the wisp sits below it, and the page pads by its height. */
  under?: RefObject<HTMLElement | null>;
  /** Where the words go in the note: its end (the default), or its lists. */
  placing?: Placing;
  /** The document to start from, when the page was just switched to this note: the words then arrive through the wisp. */
  from?: string;
}

/** Within this far of the bottom, the page keeps following the newest words. */
const FOLLOW_PX = 160;

export function LivePage({ base, markdown, placeholder, under, placing = END, from }: LivePageProps) {
  const { theme, wisp: ghosting, ripples: rippling } = usePreferences();
  const page = useRef<HTMLDivElement>(null);
  // The older text goes to smoke under the recorder's top line, like any page (art/wispEdge.ts): the line is a pane
  // the page runs under, so nothing shows fading against the black above the words (Matt: "the header on the new
  // note section isn't dark enough and shows the slight white glow").
  useWispEdge(page, undefined, under);
  // While the phone listens, the smoke holds still: each drift step redraws the filtered page on the main thread, next
  // to the microphone and the voice model.
  useEffect(() => holdWispDrift(), []);
  const [view, setView] = useState<EditorView | null>(null);
  // The voice moves the newest lines: ripples through the words as the microphone hears (editor/wispRipples.ts; Matt:
  // "show the voice recording ripples giving the text weird wisp ripples").
  const ripples = useMemo(() => ({ subscribe: onVoiceLevel }), []);
  // The document the editor starts with; everything after is written in as edits.
  const [first] = useState(() => from ?? placeTake(base, markdown, placing).body);
  /** Where the page last followed the words to, for telling whether the person has scrolled away to read. */
  const followed = useRef<number | null>(null);

  useEffect(() => {
    if (!view) return;
    const next = placeTake(base, markdown, placing).body;
    const now = view.state.doc.toString();
    if (now === next) return;
    const { prefix, suffix } = commonEnds(now, next);
    const scroller = page.current;
    const removed = now.length - prefix - suffix;
    const inside = placing.kind !== 'end';
    // At the end, the bottom is where the words are; in a list, where they went in is, and the page follows that
    // while the person has stayed within reach of where it last followed to.
    const following = scroller
      ? inside
        ? followed.current === null || Math.abs(scroller.scrollTop - followed.current) < FOLLOW_PX
        : scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < FOLLOW_PX
      : false;
    const at = next.length - suffix;
    view.dispatch({
      changes: { from: prefix, to: now.length - suffix, insert: next.slice(prefix, at) },
      annotations: wisp.of({ kind: removed > 0 ? 'rewrite' : 'heard' }),
      ...(inside && following ? { effects: EditorView.scrollIntoView(Math.min(at, next.length), { y: 'center' }) } : {}),
    });
    if (inside) {
      if (following && scroller) window.requestAnimationFrame(() => (followed.current = scroller.scrollTop));
    } else if (following && scroller) {
      window.requestAnimationFrame(() => scroller.scrollTo({ top: scroller.scrollHeight, behavior: 'smooth' }));
    }
  }, [view, base, markdown, placing]);

  // Opened on a long note: start at its end, where the words will go, or at the list they will go into.
  useEffect(() => {
    if (!view || !page.current) return;
    if (placing.kind === 'end') {
      page.current.scrollTop = page.current.scrollHeight;
      return;
    }
    // Where a word said now would go in: the first place the note with one more item differs from it.
    const { prefix } = commonEnds(base, placeTake(base, 'Here.', placing).body);
    view.dispatch({ effects: EditorView.scrollIntoView(Math.min(prefix, view.state.doc.length), { y: 'center' }) });
    // Only as the page opens: after that it follows the words.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view]);

  return (
    <div ref={page} className={styles.livePage}>
      <Editor
        value={first}
        onChange={noop}
        dark={isDarkNow(theme)}
        assist={false}
        placeholder={placeholder}
        onView={setView}
        readOnly
        grow
        arrivals={ghosting}
        ripples={rippling ? ripples : undefined}
        display="formatted"
      />
    </div>
  );
}

function noop(): void {
  // Read-only: the recorder writes the page, nothing typed comes back.
}
