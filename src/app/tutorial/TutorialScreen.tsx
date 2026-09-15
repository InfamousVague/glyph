import { Check } from '@glacier/icons';
import { Fragment, useEffect, useMemo, useState } from 'react';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { renderNote, setSpokenFormats } from '../capture/markdown.ts';
import { plugins } from '../plugins/registry.ts';
import { CHAPTERS, lessonsFor, readProgress, writeProgress } from './lessons.ts';
import { useListening } from './useListening.ts';
import styles from './TutorialScreen.module.css';

/**
 * The voice tutorial: a few minutes, a lesson at a time, open whenever it's wanted from Settings (Matt: "take a
 * tutorial at any time for the commands you can say in the app, walk the user through each of the things and mark
 * off lesson by lesson what we've learned so far", and then "just learning the voice to markdown commands and tips
 * and tricks").
 *
 * Every cue and command is a lesson (tutorial/lessons.ts), in chapters: what it does, words to try, and the microphone
 * listening. What is heard is written the way the recorder writes it, right there, and the moment it shows the cue
 * worked the lesson is ticked off and the next begins. Try again clears what was heard; Skip moves on without the
 * tick. The last chapter is tips, read and ticked with Got it. Progress is kept, so closing halfway picks up at the
 * first lesson not done, and any lesson can be taken again from the summary at the end. Nothing said here is saved.
 */

/** A passed lesson stays on screen this long, ticked, before the next one starts. */
const PASSED_MS = 1500;

export function TutorialScreen({ onDone, onAllMarks }: { onDone: () => void; onAllMarks: () => void }) {
  // The plugins' spoken marks, as the recorder sets them, so "highlight … end highlight" works here too.
  const lessons = useMemo(() => {
    const formats = plugins.formats();
    setSpokenFormats(formats.flatMap((format) => (format.cue ? [{ word: format.cue, delimiter: format.delimiter }] : [])));
    return lessonsFor(formats);
  }, []);
  const [done, setDone] = useState<Set<string>>(readProgress);
  const [skipped, setSkipped] = useState<Set<string>>(() => new Set());
  const [passed, setPassed] = useState<string | null>(null);
  /** A lesson picked from the summary to take again. */
  const [again, setAgain] = useState<string | null>(null);
  const ear = useListening();
  useBack(true, onDone);

  const pick = passed ?? again;
  const lesson = pick ? (lessons.find((l) => l.id === pick) ?? null) : (lessons.find((l) => !done.has(l.id) && !skipped.has(l.id)) ?? null);
  const finished = !lesson;

  const heard = [...ear.segments.map((s) => s.text), ear.partial].join(' ').trim();
  const written = useMemo(() => renderNote(ear.segments, ear.partial, { titled: false }).markdown, [ear.segments, ear.partial]);

  const tick = (id: string) =>
    setDone((was) => {
      const next = new Set(was).add(id);
      writeProgress(next);
      return next;
    });

  // A lesson passes on what was committed, not on a guess still changing.
  useEffect(() => {
    if (!lesson || lesson.kind !== 'practice' || passed || !ear.segments.length) return;
    const committed = renderNote(ear.segments, '', { titled: false }).markdown;
    if (!lesson.passes(committed, ear.segments.map((s) => s.text).join(' '))) return;
    fireNativeHaptic('success');
    setPassed(lesson.id);
    tick(lesson.id);
  }, [ear.segments, lesson, passed]);

  // Ticked, a breath, then the next lesson with nothing heard yet.
  const { clear } = ear;
  useEffect(() => {
    if (!passed) return undefined;
    const timer = window.setTimeout(() => {
      setPassed(null);
      setAgain(null);
      clear();
    }, PASSED_MS);
    return () => window.clearTimeout(timer);
  }, [passed, clear]);

  const skip = () => {
    if (!lesson) return;
    fireNativeHaptic('selection');
    if (again) setAgain(null);
    else setSkipped((was) => new Set(was).add(lesson.id));
    ear.clear();
  };

  const gotIt = () => {
    if (!lesson) return;
    fireNativeHaptic('selection');
    tick(lesson.id);
    setAgain(null);
    ear.clear();
  };

  const takeAgain = (id: string) => {
    fireNativeHaptic('selection');
    setAgain(id);
    ear.clear();
  };

  const startOver = () => {
    const none = new Set<string>();
    writeProgress(none);
    setDone(none);
    setSkipped(new Set());
    setAgain(null);
    ear.clear();
    fireNativeHaptic('selection');
  };

  const inChapter = lesson ? lessons.filter((l) => l.chapter === lesson.chapter) : [];
  const status =
    ear.state === 'failed'
      ? (ear.error ?? 'The microphone didn’t start.')
      : ear.download
        ? `Getting the voice model, ${Math.round(ear.download.received / 1e6)} of ${Math.round(ear.download.total / 1e6)} MB`
        : ear.state === 'starting'
          ? 'Starting the microphone…'
          : null;

  return (
    <div className={styles.screen}>
      <header className={styles.top}>
        <span className={styles.heading}>Voice tutorial</span>
        <button type="button" className="app-word" onClick={onDone}>
          Close
        </button>
      </header>

      {/* A bar for every lesson, a gap between chapters: filled when learned, lit for the one now. */}
      <ol className={styles.lessons} aria-label="Lessons">
        {CHAPTERS.map((chapter) => (
          <li key={chapter} className={styles.chapterBar}>
            <ol className={styles.chapterLessons} aria-label={chapter}>
              {lessons
                .filter((l) => l.chapter === chapter)
                .map((l) => (
                  <li
                    key={l.id}
                    className={styles.lessonBar}
                    data-done={done.has(l.id) || undefined}
                    data-current={l.id === lesson?.id || undefined}
                    aria-label={`${l.title}${done.has(l.id) ? ', learned' : ''}`}
                  />
                ))}
            </ol>
          </li>
        ))}
      </ol>
      <p className={styles.count}>
        {done.size} of {lessons.length} learned
      </p>

      <main className={styles.body}>
        {lesson ? (
          <section key={lesson.id} className={styles.card} data-passed={passed ? '' : undefined} aria-live="polite">
            <p className={styles.step}>
              {lesson.chapter} · {inChapter.indexOf(lesson) + 1} of {inChapter.length}
            </p>
            <h1 className={styles.title}>{lesson.title}</h1>
            <p className={styles.teach}>{lesson.teach}</p>
            {lesson.kind === 'practice' ? (
              <>
                {lesson.asks ? (
                  <div className={styles.asks}>
                    <span className={styles.asksLabel}>Glyph asks</span>
                    {lesson.asks}
                  </div>
                ) : null}
                <p className={styles.tryLabel}>{lesson.asks ? 'Try answering' : 'Try saying'}</p>
                <blockquote className={styles.say}>
                  {lesson.say.map((line, i) => (
                    <Fragment key={i}>
                      {lesson.pause && i > 0 ? <span className={styles.wait}>wait two seconds</span> : null}
                      <span>“{line}”</span>
                    </Fragment>
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
                    <pre className={styles.written}>{lesson.asks ? heard : written}</pre>
                  ) : (
                    <p className={styles.listening}>
                      <span className={styles.pulse} aria-hidden="true" /> Listening
                    </p>
                  )}
                </div>
              </>
            ) : null}
          </section>
        ) : (
          <section className={styles.card}>
            <h1 className={styles.title}>{done.size === lessons.length ? 'That’s all of them.' : 'That’s the tutorial.'}</h1>
            <p className={styles.teach}>
              {done.size === lessons.length
                ? 'You know every cue. Hold the side key, or tap Speak, and talk.'
                : `${lessons.length - done.size} skipped. Tap one to try it, or start over.`}
            </p>
            {CHAPTERS.map((chapter) => (
              <Fragment key={chapter}>
                <h2 className={styles.chapter}>{chapter}</h2>
                <ul className={styles.summary}>
                  {lessons
                    .filter((l) => l.chapter === chapter)
                    .map((l) => (
                      <li key={l.id}>
                        <button type="button" className={styles.summaryRow} data-done={done.has(l.id) || undefined} onClick={() => takeAgain(l.id)}>
                          <span className={styles.tick} aria-hidden="true">
                            {done.has(l.id) ? <Check size={14} strokeWidth={3} /> : null}
                          </span>
                          {l.title}
                        </button>
                      </li>
                    ))}
                </ul>
              </Fragment>
            ))}
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
        ) : lesson.kind === 'tip' ? (
          <>
            <button type="button" className="app-word" onClick={skip}>
              {again ? 'Back' : 'Skip'}
            </button>
            <button type="button" className="app-pill" onClick={gotIt}>
              Got it
            </button>
          </>
        ) : (
          <>
            <button type="button" className="app-word" onClick={skip} disabled={Boolean(passed)}>
              {again ? 'Back' : 'Skip'}
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
