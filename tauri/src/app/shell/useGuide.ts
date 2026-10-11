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
 * on page one - can tell it came too soon: the guide comes up again with its "Not yet" line, and the key's recording
 * does not start.
 *
 * That was lost for a while (1.6, when the side key's capture moved into an effect): too soon was asked only of a
 * launch by the key, and the guide opened only on a launch that was not, so a key held on page one opened the app on
 * the home page with neither, and a plain relaunch reopened the guide without its line.
 */

/** No storage: showing it every launch would be worse than never. */
const seenFlag = storedFlag('glyph-guide-seen', { value: '1', unreadable: true });

export interface GuideState {
  open: boolean;
  page: number;
  /** "Not yet, finish reading.": a relaunch, or the side key, while the guide was still on a reading page. */
  tooSoon: boolean;
  /** This launch came while the guide was left on a reading page: it is the guide's, and a side key's recording waits. */
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
  const [tooSoonAtBoot] = useState(() => launchedTooSoon(seenFlag.is()));
  const [open, setOpen] = useState(() => !seenFlag.is() && (!launchedByKey || tooSoonAtBoot));
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
