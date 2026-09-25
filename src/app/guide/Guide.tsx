import { useRef, type ComponentType } from 'react';
import { ArrowDown } from '@glacier/icons';
import { WispText } from '../art/WispText.tsx';
import { useWispEdge } from '../art/wispEdge.ts';
import { useBack } from '../core/back.ts';
import { useSwipeNav } from '../core/swipe.ts';
import { GUIDE_PAGES as PAGES, type GuidePage as Page } from './pages.ts';
import { Marks } from './pages/Marks.tsx';
import { Model } from './pages/Model.tsx';
import { SideKey } from './pages/SideKey.tsx';
import { Theme } from './pages/Theme.tsx';
import { Tips } from './pages/Tips.tsx';
import { Welcome } from './pages/Welcome.tsx';
import { SideKeyWaves } from './SideKeyWaves.tsx';
import { useBottomNudge } from './useBottomNudge.ts';
import styles from './Guide.module.css';

/**
 * The walkthrough: what Ghost.md is, how it looks, which model it runs, the side key, every mark, and how to talk.
 *
 * Shown once on first launch and any time from Settings. Six pages set as type, like the rest of the app, with Back
 * and Next where the thumb is. This is the frame they share - the dots saying where the reader is, Skip, the dock,
 * the back gesture and the swipes - and each page is its own component in guide/pages/, in the order guide/pages.ts
 * names them. The side-key page is the one that matters most (guide/pages/SideKey.tsx); the marks page draws every
 * example with the note's own editor (guide/MarksTable.tsx), so what it shows is what a note does.
 */

interface GuideProps {
  /**
   * The page showing, held by the caller: the guide unmounts while a capture is
   * on screen (see App), and a person who went off to test the side key from
   * page 2 should come back to page 2.
   */
  index: number;
  onIndex: (index: number) => void;
  onClose: () => void;
  /** Start a voice note from the last page. */
  onTry: () => void;
  /** The reader held the side key before the guide got to it (tooSoon.ts): one line says so, at the top of the page. */
  tooSoon?: boolean;
}

/** Each page's words, by its name. */
const VIEWS: Record<Page, ComponentType> = { welcome: Welcome, theme: Theme, model: Model, sidekey: SideKey, marks: Marks, tips: Tips };

export function Guide({ index, onIndex: setIndex, onClose, onTry, tooSoon }: GuideProps) {
  const page: Page = PAGES[index] ?? 'welcome';
  const last = index === PAGES.length - 1;
  const View = VIEWS[page];

  const pageRef = useRef<HTMLDivElement>(null);
  const { atBottom, due: nudgeReady, words: nudge } = useBottomNudge(pageRef, page);
  // Content slipping behind the top bar goes to smoke: the app's wisp edge (art/wispEdge.ts).
  const topRef = useRef<HTMLElement>(null);
  // And into the fade over its buttons at the foot (Matt: "anywhere we use the dark gradient color overlay we should
  // include a slight wisp effect").
  useWispEdge(pageRef, page, topRef, { foot: true });
  const toBottom = () => pageRef.current?.scrollTo({ top: pageRef.current.scrollHeight, behavior: 'smooth' });

  // The phone's back gesture (and Escape) steps back through the guide before
  // it closes it; a swipe right does the same, and a swipe left is Next.
  const stepBack = () => {
    if (index > 0) setIndex(index - 1);
    else onClose();
  };
  useBack(true, stepBack);
  const root = useRef<HTMLDivElement>(null);
  useSwipeNav(root, {
    onBack: stepBack,
    onForward: () => {
      if (!last && atBottom) setIndex(index + 1);
    },
  });

  return (
    <div ref={root} className={styles.guide} role="dialog" aria-modal="true" aria-label="How to use Ghost.md">
      <header ref={topRef} className={`app-headerPane ${styles.top}`}>
        {/* Where the reader is, as a row of dots, the one on show filled: "1 of 6" as words was a count to read. */}
        <span className={styles.progress} role="img" aria-label={`Page ${index + 1} of ${PAGES.length}`}>
          {PAGES.map((name, at) => (
            <span key={name} className={styles.progressDot} data-on={at === index || undefined} data-done={at < index || undefined} />
          ))}
        </span>
        <button type="button" className={`app-word ${styles.skip}`} onClick={onClose}>
          {last ? 'Close' : 'Skip'}
        </button>
      </header>

      {/*
        The rings from the side key wait for its page, where the key is the subject (Matt: "remove the animation … until we
        get to that step"). Drawn here, outside the scrolling page, so they stay put while it scrolls (Matt: "the ripples
        should stay where they are and not scroll with the page"); inside it, the page's wisp edge (a filter) would make
        their fixed position scroll along.
      */}
      {page === 'sidekey' ? <SideKeyWaves /> : null}
      <div ref={pageRef} className={styles.page} key={page}>
        {/* The reader held the side key before the guide got to it (tooSoon.ts): one line, out of smoke like the rest. */}
        {tooSoon ? (
          <p className={styles.tooSoon} role="status">
            <WispText text="Not yet, finish reading." pace={18} />
          </p>
        ) : null}
        <View />
      </div>

      <nav className={styles.dock} aria-label="Guide">
        <button
          type="button"
          className={`app-word ${styles.nav}`}
          onClick={() => setIndex(index - 1)}
          disabled={index === 0}
          data-hidden={index === 0 ? '' : undefined}
        >
          Back
        </button>
        <span className={styles.nextSlot}>
          <button
            type="button"
            className={`app-pill ${styles.primary} ${styles.nudge}`}
            data-shown={(!atBottom && nudgeReady) || undefined}
            aria-hidden={atBottom || !nudgeReady}
            tabIndex={atBottom || !nudgeReady ? -1 : 0}
            onClick={toBottom}
          >
            <ArrowDown size={18} strokeWidth={2.6} aria-hidden="true" />
            {nudge}
          </button>
          {last ? (
            <button
              type="button"
              className={`app-pill ${styles.primary} ${styles.next}`}
              data-shown={atBottom || undefined}
              aria-hidden={!atBottom}
              tabIndex={atBottom ? 0 : -1}
              onClick={() => {
                onClose();
                onTry();
              }}
            >
              <span className={styles.dot} aria-hidden="true" />
              Try it
            </button>
          ) : (
            <button
              type="button"
              className={`app-pill ${styles.primary} ${styles.next}`}
              data-shown={atBottom || undefined}
              aria-hidden={!atBottom}
              tabIndex={atBottom ? 0 : -1}
              onClick={() => setIndex(index + 1)}
            >
              Next
            </button>
          )}
        </span>
      </nav>
    </div>
  );
}
