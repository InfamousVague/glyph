import { shortenUrls } from '../core/shortUrl.ts';
import { layout, tailStart } from './tail.ts';
import styles from './CaptureScreen.module.css';

/**
 * The note as it is being spoken, laid out and set large: the recorder's
 * whole view.
 *
 * Held to the side of the head and glanced at, a phone needs to show one thing:
 * that it is hearing you, in words big enough to read at arm's length, shaped
 * the way the note will be. So each line is formatted as its spoken cue made
 * it - a heading set larger, a to-do and a bullet hanging off their marks, a
 * quote set in - with the markdown mark kept, dimmed, in a gutter. Bottom
 * aligned so the newest words sit just above the buttons, older lines fading
 * out at the top; the phrase still being guessed is lighter.
 *
 * Only the tail is rendered: a long dictation would otherwise lay out a page of
 * text nobody can see behind the fade.
 */

interface TailProps {
  markdown: string;
  pendingFrom: number | null;
}

/** Characters kept: comfortably more than the lines the view shows at display size. */
const TAIL_CHARS = 400;

export function Tail({ markdown, pendingFrom }: TailProps) {
  const start = tailStart(markdown, TAIL_CHARS);
  const lines = layout(markdown, pendingFrom, start);
  return (
    <div className={styles.tail} aria-live="polite">
      {start > 0 ? <p className={styles.more}>…</p> : null}
      {lines.map((line, i) =>
        line.kind === 'blank' ? (
          <div key={i} className={styles.gap} />
        ) : (
          <p key={i} className={styles.line} data-kind={line.kind} data-level={line.level} data-pending={line.pending ? '' : undefined}>
            {line.mark ? <span className={styles.gutter}>{line.mark}</span> : null}
            <span className={styles.words}>
              {line.runs.map((run, j) =>
                run.kind === 'text' ? shortenUrls(run.text) : (
                  <span key={j} className={run.kind === 'mark' ? styles.mark : styles.pending}>
                    {shortenUrls(run.text)}
                  </span>
                ),
              )}
            </span>
          </p>
        ),
      )}
    </div>
  );
}
