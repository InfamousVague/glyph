import { Switch } from '@glacier/react';
import { ArrowLeft, ArrowRight, Check, GraduationCap, ListChecks, RotateCcw, Wand2 } from '@glacier/icons';
import { useEffect, useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { usePlugins } from '../plugins/hooks.ts';
import {
  CHAPTER_ABOUT,
  CHAPTERS,
  lessonsIn,
  lessonsNow,
  readProgress,
  readSkipStandard,
  writeProgress,
  writeSkipStandard,
  type Chapter,
  type Lesson,
} from './lessons.ts';
import { Playground } from './Playground.tsx';
import styles from './AcademyScreen.module.css';

/**
 * Glyph Academy: markdown taught a mark at a time, by typing it (Matt: "we need a Glyph Academy section that teaches
 * you markdown then teaches you the extra stuff we have. Build the academy section start with just the markdown
 * basics set it up as a live code type thing where it teaches you then you type it and see it format below").
 *
 * A lesson says what a mark does and shows one line using it; then the person writes their own, in a field with the
 * note's own drawing of it underneath, changing as they type (academy/Playground.tsx). The moment what they typed
 * has the mark in it the lesson is ticked and Next appears - but nothing is taken away, so they can carry on playing
 * with it. **Show me** writes the example into the field for anyone who would rather start from something that works,
 * and a lesson can always be skipped.
 *
 * It opens on its contents (Matt: "Rework the ghost.md academy so that there is the option to skip default markdown
 * if the user doesn't want to learn that ... Make chapters in the lesson as well"): the chapters, each with what it
 * covers and how much of it is learned, a way to carry on where you left off, and a switch for a person who knows
 * Markdown already, which leaves out every lesson any Markdown app reads (academy/lessons.ts `standard`) and keeps
 * Ghost.md's own. A chapter can be started from the contents, and its end is a page of its own: what it taught, any
 * lesson to take again, and the next chapter. Nothing typed here is saved as a note: it is a page to play on.
 *
 * A lesson for a plugin's mark is on offer only while that mark is switched on, so the Academy never teaches what
 * the note would not draw. The bars along the top are the chapter being taken, and the count beside the title is all
 * of it.
 */

/** Where the Academy is: its contents, a lesson, or the end of a chapter. */
type Place = { at: 'contents' } | { at: 'lesson'; id: string } | { at: 'chapterEnd'; chapter: Chapter };

export function AcademyScreen({ onDone, onCheatSheet }: { onDone: () => void; onCheatSheet: () => void }) {
  // Drawn again when a plugin is switched, so its lessons come and go with its marks. The lessons themselves are the
  // same objects every time, so the one in hand stays the one in hand.
  usePlugins();
  const [skipStandard, setSkipStandard] = useState(readSkipStandard);
  const lessons = lessonsNow(skipStandard);
  const [done, setDone] = useState<Set<string>>(readProgress);
  /**
   * Where the Academy is, held until Next is pressed. A lesson cannot be worked out from what has been learned:
   * passing it would then move the page on the instant the mark was typed, and the whole point is to stay and watch
   * it format.
   */
  const [place, setPlace] = useState<Place>({ at: 'contents' });
  const [typed, setTyped] = useState('');
  const [hinting, setHinting] = useState(false);

  const lesson = place.at === 'lesson' ? (lessons.find((one) => one.id === place.id) ?? null) : null;

  // Back from a lesson or a chapter's end is the contents; from the contents, out of the Academy.
  useBack(true, () => (place.at === 'contents' ? onDone() : setPlace({ at: 'contents' })));

  // A new lesson starts on a clean page, with its hint put away.
  const showing = lesson?.id ?? '';
  const was = useRef(showing);
  useEffect(() => {
    if (was.current === showing) return;
    was.current = showing;
    setTyped('');
    setHinting(false);
  }, [showing]);

  const passed = Boolean(lesson && lesson.passes(typed));
  // Ticked the moment the mark appears, and only once: the tick is a fact about the person, not about the field.
  useEffect(() => {
    if (!lesson || !passed || done.has(lesson.id)) return;
    fireNativeHaptic('success');
    setDone((before) => {
      const next = new Set(before).add(lesson.id);
      writeProgress(next);
      return next;
    });
  }, [lesson, passed, done]);

  const learned = lessons.filter((one) => done.has(one.id)).length;
  const chapter = lesson?.chapter ?? (place.at === 'chapterEnd' ? place.chapter : null);
  const bars = chapter ? lessonsIn(chapter, lessons) : [];

  /** The lesson after this one; at the end of its chapter, that chapter's end page. */
  const next = (from: Lesson) => {
    const following = lessons[lessons.indexOf(from) + 1];
    setPlace(following && following.chapter === from.chapter ? { at: 'lesson', id: following.id } : { at: 'chapterEnd', chapter: from.chapter });
  };
  /** A chapter, from its first lesson not learned yet, or its first if all are. */
  const startChapter = (name: Chapter) => {
    const its = lessonsIn(name, lessons);
    const first = its.find((one) => !done.has(one.id)) ?? its[0];
    if (first) setPlace({ at: 'lesson', id: first.id });
  };

  return (
    <div className={styles.screen}>
      <header className={styles.top}>
        <button
          type="button"
          className={styles.back}
          onClick={place.at === 'contents' ? onDone : () => setPlace({ at: 'contents' })}
          aria-label={place.at === 'contents' ? 'Close the Academy' : 'The Academy’s chapters'}
        >
          <ArrowLeft size={20} />
        </button>
        <h1 className={styles.heading}>
          <GraduationCap size={18} aria-hidden="true" /> Ghost.md Academy
        </h1>
        <p className={styles.count} aria-label={`${learned} of ${lessons.length} learned`}>
          {learned}/{lessons.length}
        </p>
      </header>

      {/* A bar for every lesson of the chapter: faint to come, ink for learned, lit for the one being taken. */}
      {bars.length ? (
        <ol className={styles.bars} aria-hidden="true">
          {bars.map((one) => (
            <li
              key={one.id}
              className={styles.bar}
              {...(done.has(one.id) ? { 'data-done': '' } : {})}
              {...(one.id === lesson?.id ? { 'data-now': '' } : {})}
            />
          ))}
        </ol>
      ) : null}

      <main className={styles.page}>
        {lesson ? (
          <LessonCard
            lesson={lesson}
            chapter={lessonsIn(lesson.chapter, lessons)}
            typed={typed}
            onTyped={setTyped}
            passed={passed}
            hinting={hinting}
            onHint={() => setHinting(true)}
            onShowMe={() => setTyped(lesson.example)}
            onNext={() => next(lesson)}
          />
        ) : place.at === 'chapterEnd' ? (
          <ChapterEnd
            chapter={place.chapter}
            lessons={lessons}
            done={done}
            onAgain={(id) => setPlace({ at: 'lesson', id })}
            onNextChapter={startChapter}
            onContents={() => setPlace({ at: 'contents' })}
          />
        ) : (
          <Contents
            lessons={lessons}
            done={done}
            skipStandard={skipStandard}
            onSkipStandard={(skip) => {
              setSkipStandard(skip);
              writeSkipStandard(skip);
            }}
            onLesson={(id) => setPlace({ at: 'lesson', id })}
            onChapter={startChapter}
            onStartOver={() => {
              setDone(new Set());
              writeProgress(new Set());
              const first = lessons[0];
              if (first) setPlace({ at: 'lesson', id: first.id });
            }}
            onCheatSheet={onCheatSheet}
          />
        )}
      </main>
    </div>
  );
}

/** One lesson: what the mark does, a line using it, and the live page to write your own on. */
function LessonCard({
  lesson,
  chapter,
  typed,
  onTyped,
  passed,
  hinting,
  onHint,
  onShowMe,
  onNext,
}: {
  lesson: Lesson;
  /** The lessons of its chapter, for where it is among them. */
  chapter: readonly Lesson[];
  typed: string;
  onTyped: (text: string) => void;
  passed: boolean;
  hinting: boolean;
  onHint: () => void;
  onShowMe: () => void;
  onNext: () => void;
}) {
  const at = chapter.indexOf(lesson) + 1;
  return (
    <article className={styles.card}>
      <p className={styles.chapter}>
        Chapter {CHAPTERS.indexOf(lesson.chapter) + 1} · {lesson.chapter} · {at} of {chapter.length}
      </p>
      <h2 className={styles.title}>{lesson.title}</h2>
      <p className={styles.teach}>{lesson.teach}</p>

      <div className={styles.example}>
        <pre className={styles.exampleText}>{lesson.example}</pre>
        <button type="button" className={`app-word ${styles.wordRow}`} onClick={onShowMe}>
          <Wand2 size={16} aria-hidden="true" /> Show me
        </button>
      </div>

      <p className={styles.task}>{lesson.task}</p>

      <Playground value={typed} onChange={onTyped} placeholder={lesson.example} />

      <div className={styles.foot}>
        {passed ? (
          <p className={styles.praise}>
            <Check size={18} aria-hidden="true" /> {lesson.praise}
          </p>
        ) : hinting ? (
          <p className={styles.hint}>{lesson.hint}</p>
        ) : (
          <button type="button" className="app-word" onClick={onHint}>
            Show me a hint
          </button>
        )}
        <button type="button" className={passed ? 'app-pill' : 'app-word'} onClick={onNext}>
          {passed ? 'Next' : 'Skip'}
        </button>
      </div>
    </article>
  );
}

/**
 * The contents, where the Academy opens: a way on from where it was left, the switch for a person who knows Markdown
 * already, and the chapters, each with what it covers and how much of it is learned. Once everything is learned it is
 * also the summary, with every chapter to take again.
 */
function Contents({
  lessons,
  done,
  skipStandard,
  onSkipStandard,
  onLesson,
  onChapter,
  onStartOver,
  onCheatSheet,
}: {
  lessons: readonly Lesson[];
  done: ReadonlySet<string>;
  skipStandard: boolean;
  onSkipStandard: (skip: boolean) => void;
  onLesson: (id: string) => void;
  onChapter: (chapter: Chapter) => void;
  onStartOver: () => void;
  onCheatSheet: () => void;
}) {
  const left = lessons.find((lesson) => !done.has(lesson.id)) ?? null;
  const begun = lessons.some((lesson) => done.has(lesson.id));
  return (
    <article className={styles.card}>
      <h2 className={styles.title}>{left ? (begun ? 'Carry on learning' : 'Learn what a note can hold') : 'That is every mark.'}</h2>
      <p className={styles.teach}>
        {left
          ? 'A mark at a time: what it does, an example, and a line of your own to write, drawn as the note draws it while you type.'
          : 'Every mark a note can carry is one you can now write by hand. The Markdown ones read the same in any app that knows Markdown, and Ghost.md’s own read as plain words there. Take any chapter again below.'}
      </p>
      {left ? (
        <button type="button" className={`app-pill ${styles.go}`} onClick={() => onLesson(left.id)}>
          {begun ? `Continue: ${left.title}` : 'Start'} <ArrowRight size={16} aria-hidden="true" />
        </button>
      ) : null}

      <label className={styles.skip}>
        <span className={styles.skipWords}>
          <span className={styles.skipName}>I know Markdown already</span>
          <span className={styles.skipSaid}>Skip what any Markdown app reads: headings, bold, lists, links, tables, pictures. Ghost.md’s own marks are still taught.</span>
        </span>
        <Switch aria-label="I know Markdown already" checked={skipStandard} onCheckedChange={onSkipStandard} />
      </label>

      <ol className={styles.chapters} aria-label="Chapters">
        {CHAPTERS.map((chapter, index) => {
          const its = lessonsIn(chapter, lessons);
          const learned = its.filter((lesson) => done.has(lesson.id)).length;
          const skipped = its.length === 0;
          return (
            <li key={chapter}>
              <button type="button" className={styles.chapterRow} onClick={() => onChapter(chapter)} disabled={skipped} aria-label={`Chapter ${index + 1}, ${chapter}`}>
                <span className={styles.chapterNumber} {...(its.length && learned === its.length ? { 'data-done': '' } : {})} aria-hidden="true">
                  {its.length && learned === its.length ? <Check size={14} /> : index + 1}
                </span>
                <span className={styles.chapterWords}>
                  <span className={styles.chapterTitle}>{chapter}</span>
                  <span className={styles.chapterAbout}>{CHAPTER_ABOUT[chapter]}</span>
                </span>
                <span className={styles.chapterCount}>{skipped ? 'Skipped' : `${learned}/${its.length}`}</span>
              </button>
            </li>
          );
        })}
      </ol>

      <p className={styles.teach}>Every mark is in the cheat sheet as well, to look up while you write.</p>
      <div className={styles.foot}>
        <button type="button" className="app-word" onClick={onStartOver}>
          <RotateCcw size={16} aria-hidden="true" /> Start again
        </button>
        <button type="button" className="app-pill" onClick={onCheatSheet}>
          <ListChecks size={16} aria-hidden="true" /> Cheat sheet
        </button>
      </div>
    </article>
  );
}

/** The end of a chapter: what it taught, any lesson to take again, and the chapter after it. */
function ChapterEnd({
  chapter,
  lessons,
  done,
  onAgain,
  onNextChapter,
  onContents,
}: {
  chapter: Chapter;
  lessons: readonly Lesson[];
  done: ReadonlySet<string>;
  onAgain: (id: string) => void;
  onNextChapter: (chapter: Chapter) => void;
  onContents: () => void;
}) {
  const its = lessonsIn(chapter, lessons);
  const all = its.every((lesson) => done.has(lesson.id));
  const following = CHAPTERS.slice(CHAPTERS.indexOf(chapter) + 1).find((name) => lessonsIn(name, lessons).length) ?? null;
  return (
    <article className={styles.card}>
      <p className={styles.chapter}>
        Chapter {CHAPTERS.indexOf(chapter) + 1} · {chapter}
      </p>
      <h2 className={styles.title}>{all ? 'Chapter learned.' : 'The end of the chapter.'}</h2>
      <p className={styles.teach}>{all ? `Every mark in ${chapter} is one you can write by hand now.` : 'You can come back to the ones you skipped whenever you like: tap one to take it.'}</p>
      <ul className={styles.list}>
        {its.map((lesson) => (
          <li key={lesson.id}>
            <button type="button" className={styles.again} onClick={() => onAgain(lesson.id)}>
              <span className={styles.againTick} {...(done.has(lesson.id) ? { 'data-done': '' } : {})} aria-hidden="true">
                <Check size={14} />
              </span>
              <span className={styles.againName}>{lesson.title}</span>
              <span className={styles.againMark}>{lesson.symbol}</span>
            </button>
          </li>
        ))}
      </ul>
      <div className={styles.foot}>
        <button type="button" className="app-word" onClick={onContents}>
          All chapters
        </button>
        {following ? (
          <button type="button" className="app-pill" onClick={() => onNextChapter(following)}>
            Next: {following} <ArrowRight size={16} aria-hidden="true" />
          </button>
        ) : (
          <button type="button" className="app-pill" onClick={onContents}>
            Done
          </button>
        )}
      </div>
    </article>
  );
}
