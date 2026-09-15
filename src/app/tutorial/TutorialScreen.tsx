import { Check } from '@glacier/icons';
import { useEffect, useMemo, useState } from 'react';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { renderNote } from '../capture/markdown.ts';
import { LESSONS, readProgress, writeProgress } from './lessons.ts';
import { useListening } from './useListening.ts';
import styles from './TutorialScreen.module.css';

/**
 * The voice tutorial: a few minutes, a lesson at a time, open whenever it's wanted from Settings (Matt: "take a
 * tutorial at any time for the commands you can say in the app, walk the user through each of the things and mark
 * off lesson by lesson what we've learned so far").
 *
 * Each lesson is one cue (tutorial/lessons.ts): what it does, words to try, and the microphone listening. What is
 * heard is written the way the recorder writes it, right there, and the moment it shows the cue worked the lesson is
 * ticked off and the next begins. Try again clears what was heard; Skip moves on without the tick. Progress is kept,
 * so closing halfway picks up at the first lesson not done. Nothing said here is saved.
 */

/** A passed lesson stays on screen this long, ticked, before the next one starts. */
const PASSED_MS = 1500;

export function TutorialScreen({ onDone, onAllMarks }: { onDone: () => void; onAllMarks: () => void }) {
  const [done, setDone] = useState<Set<string>>(readProgress);
  const [skipped, setSkipped] = useState<Set<string>>(() => new Set());
  const [passed, setPassed] = useState<string | null>(null);
  const ear = useListening();
  useBack(true, onDone);

  const lesson = passed ? (LESSONS.find((l) => l.id === passed) ?? null) : (LESSONS.find((l) => !done.has(l.id) && !skipped.has(l.id)) ?? null);
  const finished = !lesson;

  const heard = [...ear.segments.map((s) => s.text), ear.partial].join(' ').trim();
  const written = useMemo(() => renderNote(ear.segments, ear.partial, { titled: false }).markdown, [ear.segments, ear.partial]);

  // A lesson passes on what was committed, not on a guess still changing.
  useEffect(() => {
    if (!lesson || passed || !ear.segments.length) return;
    const committed = renderNote(ear.segments, '', { titled: false }).markdown;
    if (!lesson.passes(committed, ear.segments.map((s) => s.text).join(' '))) return;
    fireNativeHaptic('success');
    setPassed(lesson.id);
    setDone((was) => {
      const next = new Set(was).add(lesson.id);
      writeProgress(next);
      return next;
    });
  }, [ear.segments, lesson, passed]);

  // Ticked, a breath, then the next lesson with nothing heard yet.
  const { clear } = ear;
  useEffect(() => {
    if (!passed) return undefined;
    const timer = window.setTimeout(() => {
      setPassed(null);
      clear();
    }, PASSED_MS);
    return () => window.clearTimeout(timer);
  }, [passed, clear]);

  const skip = () => {
    if (!lesson) return;
    fireNativeHaptic('selection');
    setSkipped((was) => new Set(was).add(lesson.id));
    ear.clear();
  };

  const startOver = () => {
    const none = new Set<string>();
    writeProgress(none);
    setDone(none);
    setSkipped(new Set());
    ear.clear();
    fireNativeHaptic('selection');
  };

  const index = lesson ? LESSONS.indexOf(lesson) : LESSONS.length;
  const status = ear.state === 'failed' ? (ear.error ?? 'The microphone didn’t start.') : ear.download ? `Getting the voice model, ${Math.round(ear.download.received / 1e6)} of ${Math.round(ear.download.total / 1e6)} MB` : ear.state === 'starting' ? 'Starting the microphone…' : null;

  return (
    <div className={styles.screen}>
      <header className={styles.top}>
        <span className={styles.heading}>Voice tutorial</span>
        <button type="button" className="app-word" onClick={onDone}>
          Close
        </button>
      </header>

      {/* Every lesson, in order: ticked when learned, the current one ringed. */}
      <ol className={styles.lessons} aria-label="Lessons">
        {LESSONS.map((l, i) => (
          <li key={l.id} className={styles.lessonDot} data-done={done.has(l.id) || undefined} data-current={i === index || undefined} aria-label={`${l.title}${done.has(l.id) ? ', learned' : ''}`}>
            {done.has(l.id) ? <Check size={12} strokeWidth={3} aria-hidden="true" /> : null}
          </li>
        ))}
      </ol>
      <p className={styles.count}>
        {done.size} of {LESSONS.length} learned
      </p>

      <main className={styles.body}>
        {lesson ? (
          <section className={styles.card} data-passed={passed ? '' : undefined} aria-live="polite">
            <p className={styles.step}>
              Lesson {index + 1} of {LESSONS.length}
            </p>
            <h1 className={styles.title}>{lesson.title}</h1>
            <p className={styles.teach}>{lesson.teach}</p>
            <p className={styles.tryLabel}>Try saying</p>
            <blockquote className={styles.say}>
              {lesson.say.map((line, i) => (
                <span key={i}>“{line}”</span>
              ))}
            </blockquote>

            <div className={styles.heard} data-empty={!heard || undefined}>
              {passed ? (
                <p className={styles.praise}>
                  <Check size={20} strokeWidth={3} aria-hidden="true" /> {lesson.praise}
                </p>
              ) : status ? (
                <p className={styles.listening}>{status}</p>
              ) : heard ? (
                <pre className={styles.written}>{written}</pre>
              ) : (
                <p className={styles.listening}>
                  <span className={styles.pulse} aria-hidden="true" /> Listening
                </p>
              )}
            </div>
          </section>
        ) : (
          <section className={styles.card}>
            <h1 className={styles.title}>{done.size === LESSONS.length ? 'That’s all of them.' : 'That’s the tutorial.'}</h1>
            <p className={styles.teach}>
              {done.size === LESSONS.length
                ? 'You know every cue. Hold the side key, or tap Speak, and talk.'
                : `${LESSONS.length - done.size} skipped. Start over any time to try them again.`}
            </p>
            <ul className={styles.summary}>
              {LESSONS.map((l) => (
                <li key={l.id} data-done={done.has(l.id) || undefined}>
                  <span className={styles.tick} aria-hidden="true">
                    {done.has(l.id) ? <Check size={14} strokeWidth={3} /> : null}
                  </span>
                  {l.title}
                </li>
              ))}
            </ul>
            <button type="button" className={`app-word ${styles.marks}`} onClick={onAllMarks}>
              See every mark and cue
            </button>
          </section>
        )}
      </main>

      <footer className={styles.footer}>
        {finished ? (
          <>
            <button type="button" className="app-word" onClick={startOver}>
              Start over
            </button>
            <button type="button" className="app-pill" onClick={onDone}>
              Done
            </button>
          </>
        ) : (
          <>
            <button type="button" className="app-word" onClick={skip} disabled={Boolean(passed)}>
              Skip
            </button>
            <button type="button" className="app-pill" onClick={ear.clear} disabled={Boolean(passed) || !heard}>
              Try again
            </button>
          </>
        )}
      </footer>
    </div>
  );
}

