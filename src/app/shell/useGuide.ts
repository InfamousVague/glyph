import { useEffect, useState } from 'react';
import { storedFlag } from '../core/stored.ts';
import { clearGuideProgress, isReadingPage, launchedTooSoon, markGuideStarted, rememberGuidePage } from '../guide/tooSoon.ts';

/**
 * The walkthrough (guide/Guide.tsx): whether it is up, the page it is on, and whether it is saying "Not yet, finish
 * reading." - the Shell's half of it, which decides when it opens by itself and what a launch in the middle of it
 * means.
 *
 * It opens by itself once, on the first launch that is not a side-key capture: a person who held the key is already
 * mid-sentence. After that it is opened from Settings, the palette, or the Academy, and seen for good when it is
 * closed. While it is up, the page it is on is kept (guide/tooSoon.ts), so a relaunch - someone who held the side key
 * on page one - can tell it came too soon.
 */

/** No storage: showing it every launch would be worse than never. */
const seenFlag = storedFlag('glyph-guide-seen', { value: '1', unreadable: true });

export interface GuideState {
  open: boolean;
  page: number;
  /** "Not yet, finish reading.": a relaunch, or the side key, while the guide was still on a reading page. */
  tooSoon: boolean;
  /** The side key launched the app while the guide was on a reading page: the launch is the guide's, not a recording's. */
  tooSoonAtBoot: boolean;
  /** Up, at `page`. */
  show: (page?: number) => void;
  /** To `page`, from the guide's own arrows: the too-soon line has been read. */
  turn: (page: number) => void;
  /** Closed and seen: it will not open by itself again, and its progress goes. */
  close: () => void;
  /** Closed without being seen: the side key clearing the stage for a recording. */
  hide: () => void;
  /** The side key pressed now would be too soon: the guide is up on a page still to be read. */
  onReadingPage: () => boolean;
  /** Say "Not yet" at the top of the guide. */
  sayTooSoon: () => void;
}

/** `launchedByKey`: the side key launched this run of the app (core/host.ts `takeCaptureLaunch`). */
export function useGuide(launchedByKey: boolean): GuideState {
  const [tooSoonAtBoot] = useState(() => Boolean(launchedByKey && launchedTooSoon(seenFlag.is())));
  const [open, setOpen] = useState(() => !launchedByKey && !seenFlag.is());
  const [tooSoon, setTooSoon] = useState(tooSoonAtBoot);
  const [page, setPage] = useState(0);
  // Where the guide is, kept for a relaunch (guide/tooSoon.ts); gone once it is finished.
  useEffect(() => {
    if (open) {
      markGuideStarted();
      rememberGuidePage(page);
    }
  }, [open, page]);
  return {
    open,
    page,
    tooSoon,
    tooSoonAtBoot,
    show: (at = 0) => {
      setPage(at);
      setOpen(true);
    },
    turn: (at) => {
      setPage(at);
      setTooSoon(false);
    },
    close: () => {
      // Not kept: seen for this run, at least.
      seenFlag.mark();
      clearGuideProgress();
      setOpen(false);
    },
    hide: () => setOpen(false),
    onReadingPage: () => open && isReadingPage(page),
    sayTooSoon: () => setTooSoon(true),
  };
}
