import { useEffect, useState, type RefObject } from 'react';

/**
 * The wisp edge: the app's standard soft top for anything that scrolls under
 * a header. Content slipping up behind the header goes to smoke, with the
 * headline's own effect (art/WispText.tsx: fractal noise bending the picture,
 * a blur softening it), and the bend grows the higher the content goes
 * (Matt: "the wisp effect should get stronger the higher up it goes"), from
 * nothing about 40px under the header's edge to its full strength at it.
 * Matt: "use this blur animation wisp effect behind every header on the app,
 * save it as a standard mask effect we'll use quite frequently".
 *
 * A header that sits over the scroller (the guide's, a note's) is a solid
 * pane of the page's paper (app.css `.app-headerPane`), with the wisp a
 * little way under its edge, short and tight (Matt, after glass: "do a solid
 * black background, just make the wisp effect move down a bit further and
 * condense it vertically a bit"). Pass the header as `under`, and the band
 * moves down below its bottom edge, with `--wisp-under` set on the scroller
 * for its own padding; the top fade (`--wisp-top-fade`) is only for a
 * scroller with no header.
 *
 * While a view is being scrolled, the smoke drifts, and when the scrolling
 * stops it holds where it is (Matt: "only animate when we're actively
 * scrolling"; it used to drift the whole time a view sat scrolled). The noise
 * slides up and down and its frequency breathes, on the
 * animation clock at about 35 steps a second (eight a second "makes it look
 * choppy"), each step redrawing the band only: the filter computes the noise,
 * the bend and the blur over the band's reach and leaves the rest of the view
 * alone. Still while nothing is scrolled, while the page is hidden, with
 * reduced motion, and while a recording holds it (`holdWispDrift`). Matt
 * tried a stiller, gentler band and asked for this one back: "Go back to the
 * one I said was too intense".
 *
 * To use it: mount `<WispEdgeFilter />` once (App.tsx does), and call
 * `useWispEdge(scrollerRef)` for the element that scrolls. The effect is only
 * worn once the element has been scrolled off its top (the `data-wisp-edge`
 * attribute, styled in app.css), so a still, unscrolled view pays nothing.
 */

export const WISP_EDGE_FILTER_ID = 'wispEdge';
export const WISP_EDGE_NOISE_ID = 'wispEdgeNoise';
export const WISP_EDGE_DRIFT_ID = 'wispEdgeDrift';
export const WISP_EDGE_STRIP_ID = 'wispEdgeStrip';
export const WISP_EDGE_BENT_ID = 'wispEdgeBent';
export const WISP_EDGE_SOFT_ID = 'wispEdgeSoft';
export const WISP_EDGE_NEAR_ID = 'wispEdgeNear';

/**
 * How far under the header's edge the smoke still bends a little (the strip's
 * blur, a long ramp: Matt found a short one "quite abrupt", and a 40px one
 * "way too subtle"), and its full-strength lip (Matt, of a 10px one under a
 * bend of 24: "can still be stronger on the header").
 */
export const WISP_EDGE_SOFT = 22;
export const WISP_EDGE_BAND = 10;
/** How far below a header's edge the band's lip sits: the smoke happens under a solid header, not hidden behind it. */
export const WISP_EDGE_DROP = 18;
/** The strip starts this far above the view, so its blur never opens the top. */
export const WISP_EDGE_ABOVE = 200;
/** How far below the band's lip the bend and blur are computed at all: past the strip's soft edge, with room for the drift. */
export const WISP_EDGE_REACH = WISP_EDGE_BAND + WISP_EDGE_SOFT * 4 + 48;

/** Steps no closer than this: about 35 a second, smooth to the eye, a third of the frames on a 120Hz phone. */
const DRIFT_STEP_MS = 28;
const BASE_X = 0.018;
const BASE_Y = 0.06;
/** The noise slides this far, down and up, over its cycle: never past the view's top. Quiet: Matt found more "too intense". */
const SLIDE_PX = 20;

let drifting = 0;
let driftFrame = 0;
let lastStep = 0;
let held = 0;

/**
 * Holds the drift still (the smoke stays where it is) until the answer is
 * called: each step re-renders the filtered view, main-thread work a
 * recording can do without. The capture engine holds it while the phone
 * listens.
 */
export function holdWispDrift(): () => void {
  held += 1;
  let released = false;
  return () => {
    if (released) return;
    released = true;
    held -= 1;
  };
}

/**
 * One frame of the drift, on the animation clock so it never ticks (Matt, of
 * eight steps a second: "too slow, it makes it look choppy"): the noise slides
 * over a few seconds and its frequency breathes a little slower.
 */
function driftStep(now: number): void {
  driftFrame = requestAnimationFrame(driftStep);
  // The smoke's own clock only runs while it moves, so a scroll picks it up where the last one left it, not with a jump.
  const gap = lastFrameAt ? Math.min(now - lastFrameAt, 50) : 0;
  lastFrameAt = now;
  if (held > 0 || document.visibilityState !== 'visible') return;
  smokeClock += gap;
  if (now - lastStep < DRIFT_STEP_MS) return;
  lastStep = now;
  const noise = document.getElementById(WISP_EDGE_NOISE_ID);
  const slide = document.getElementById(WISP_EDGE_DRIFT_ID);
  if (!noise || !slide) return;
  const t = smokeClock;
  const x = BASE_X + 0.003 * Math.sin(t / 2600);
  const y = BASE_Y + 0.01 * Math.sin(t / 3400 + 1.3);
  noise.setAttribute('baseFrequency', `${x.toFixed(4)} ${y.toFixed(4)}`);
  slide.setAttribute('dx', (4 * Math.sin(t / 2300 + 0.7)).toFixed(2));
  slide.setAttribute('dy', (SLIDE_PX / 2 + (SLIDE_PX / 2) * Math.sin(t / 3100)).toFixed(2));
}

/** The drift's own time, advanced only while it runs; and the last frame's, to measure each step by. */
let smokeClock = 0;
let lastFrameAt = 0;

/** After the last scroll event, this long and the smoke holds still. */
const SCROLL_IDLE_MS = 160;

/** Counts the views drifting; the one animation loop runs while any is. */
function drift(on: boolean, reset = true): void {
  drifting += on ? 1 : -1;
  if (drifting === 1 && on) {
    lastFrameAt = 0;
    driftFrame = requestAnimationFrame(driftStep);
  }
  if (drifting <= 0) {
    drifting = 0;
    cancelAnimationFrame(driftFrame);
    // A scroll that stopped leaves the smoke as it was; only a view back at its top puts it back to rest.
    if (!reset) return;
    document.getElementById(WISP_EDGE_NOISE_ID)?.setAttribute('baseFrequency', `${BASE_X} ${BASE_Y}`);
    const slide = document.getElementById(WISP_EDGE_DRIFT_ID);
    slide?.setAttribute('dx', '0');
    slide?.setAttribute('dy', '0');
  }
}

/** Moves the band down to sit under a header `under` px tall (0: at the view's top), and the bend's reach with it. */
function placeBand(under: number): void {
  const drop = under > 0 ? WISP_EDGE_DROP : 0;
  document.getElementById(WISP_EDGE_STRIP_ID)?.setAttribute('height', String(WISP_EDGE_ABOVE + under + drop + WISP_EDGE_BAND));
  const reach = String(40 + under + drop + WISP_EDGE_REACH);
  document.getElementById(WISP_EDGE_NOISE_ID)?.setAttribute('height', reach);
  document.getElementById(WISP_EDGE_BENT_ID)?.setAttribute('height', reach);
  document.getElementById(WISP_EDGE_NEAR_ID)?.setAttribute('height', reach);
  document.getElementById(WISP_EDGE_SOFT_ID)?.setAttribute('height', reach);
}

/**
 * Wears the wisp edge on `scroller` while it is scrolled off its top; answers
 * whether it is. `key` re-reads it when the content changes; `under` is a
 * header the scroller runs beneath.
 */
export function useWispEdge(scroller: RefObject<HTMLElement | null>, key?: unknown, under?: RefObject<HTMLElement | null>): boolean {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const el = scroller.current;
    if (!el) return undefined;
    // Both refs are set by the time the effect runs; the header is read once so the cleanup sees the same node.
    const header = under?.current ?? null;
    const still = typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
    let worn = false;
    /** Whether this view's scrolling is moving the smoke right now, and the wait for the scrolling to stop. */
    let moving = false;
    let idle = 0;
    const holdStill = (reset: boolean) => {
      window.clearTimeout(idle);
      if (!moving) return;
      moving = false;
      drift(false, reset);
    };
    const fit = () => {
      const height = header?.offsetHeight ?? 0;
      el.style.setProperty('--wisp-under', `${height}px`);
      // Under a header the header hides the top; with no header, the very top dissolves.
      el.style.setProperty('--wisp-top-fade', height ? '0px' : '29px');
      if (worn) placeBand(height);
    };
    const check = () => {
      const scrolled = el.scrollTop > 4;
      setOn(scrolled);
      if (scrolled === worn) return;
      worn = scrolled;
      if (scrolled) {
        el.setAttribute('data-wisp-edge', '');
        placeBand(header?.offsetHeight ?? 0);
      } else {
        el.removeAttribute('data-wisp-edge');
        holdStill(true);
      }
    };
    // Scrolling moves the smoke; a pause in it holds the smoke where it is.
    const onScroll = () => {
      check();
      if (!worn || still) return;
      if (!moving) {
        moving = true;
        drift(true);
      }
      window.clearTimeout(idle);
      idle = window.setTimeout(() => holdStill(false), SCROLL_IDLE_MS);
    };
    fit();
    check();
    el.addEventListener('scroll', onScroll, { passive: true });
    const resized = new ResizeObserver(fit);
    if (header) resized.observe(header);
    return () => {
      el.removeEventListener('scroll', onScroll);
      resized.disconnect();
      el.removeAttribute('data-wisp-edge');
      holdStill(true);
    };
  }, [scroller, key, under]);
  return on;
}
