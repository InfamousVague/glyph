import { prefersStill } from '../core/motion.ts';
import { usePreferences } from '../core/preferences.ts';
import { useEffect, useState, type RefObject } from 'react';
import { installWispMasks, type WispDraw, wispDraw, wispHead } from './wispMask.ts';

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
 * A header that sits over the scroller (the guide's, a note's) is a pane of
 * glass, the page's paper at two thirds over a blur of what runs under it
 * (app.css `.app-headerPane`), with the wisp a little way under its edge,
 * short and tight (Matt, when it was glass the first time: "do a solid black
 * background, just make the wisp effect move down a bit further and condense
 * it vertically a bit"; the solid pane then went back to glass, "it's not
 * like a dark glass, it's solid black"). Pass the header as `under`, and the band
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
 * attribute, styled in art/wisp.css), so a still, unscrolled view pays nothing.
 *
 * A column that scrolls beside a page, both smoking at their tops at the same moment, wears a top band of its own
 * (`band: 'column'`): Settings' sections in the split view, under the search field, beside the section's page (Matt:
 * "on the settings page when scrolling on the left sidebar we should see the wisp fade effect under the search bar
 * covering the overflowing content like we see with the header on the main page"). Every attribute on a filter is
 * global, so one band worn by two views under headers of different heights sits under whichever was placed last, and
 * its drift moves both while only one is scrolled. The column's is the page's band again, the same strength, under its
 * own ids, placed and drifted apart. Its region is the column's own width rather than the window's, and it is held to
 * the budget together with a page's beside it (`placeRegion`). Its lip eases down to its place over the first px of a
 * scroll (`WISP_EDGE_EASE`), since the column's first row starts right at the field's edge.
 *
 * Like the page's it is placed in user space, which WebKit starts from the document's corner rather than the view's
 * (docs/DESIGN.md §54), so in WebKit a view below the window's top has its band that far too high: the column's, 69px
 * on the Fold's size, lands at the column's own top, where the rows under the field's glass are bent and smoke is
 * thrown up over the bottom of Settings' head and the field's padding above its pill, while the rows at the field's
 * edge stay crisp. Nothing that ships draws that: the Mac draws the blur strip (`wispHead`) and Android is Chromium.
 * An iPad build would (the Apple target has the iPad in it, and a touch screen takes the filter); placing the bands in
 * their views' own boxes, as §54 describes, settles it for the column and for Settings' page beside it alike.
 */

export const WISP_EDGE_FILTER_ID = 'wispEdge';
/** The foot's band, a filter of its own so a view that wants only its foot never draws another view's header band. */
export const WISP_EDGE_FOOT_FILTER_ID = 'wispEdgeFoot';
export const WISP_EDGE_NOISE_ID = 'wispEdgeNoise';
export const WISP_EDGE_DRIFT_ID = 'wispEdgeDrift';
export const WISP_EDGE_STRIP_ID = 'wispEdgeStrip';
export const WISP_EDGE_BENT_ID = 'wispEdgeBent';
export const WISP_EDGE_SOFT_ID = 'wispEdgeSoft';
export const WISP_EDGE_NEAR_ID = 'wispEdgeNear';
export const WISP_EDGE_FOOT_NOISE_ID = 'wispEdgeFootNoise';
export const WISP_EDGE_FOOT_DRIFT_ID = 'wispEdgeFootDrift';
export const WISP_EDGE_FOOT_STRIP_ID = 'wispEdgeFootStrip';
export const WISP_EDGE_FOOT_BENT_ID = 'wispEdgeFootBent';
export const WISP_EDGE_FOOT_NEAR_ID = 'wispEdgeFootNear';
export const WISP_EDGE_FOOT_SOFT_ID = 'wispEdgeFootSoft';
/** The column's top band, beside the page's (above): the same filter again under ids of its own. */
export const WISP_EDGE_COLUMN_FILTER_ID = 'wispEdgeColumn';
export const WISP_EDGE_COLUMN_NOISE_ID = 'wispEdgeColumnNoise';
export const WISP_EDGE_COLUMN_DRIFT_ID = 'wispEdgeColumnDrift';
export const WISP_EDGE_COLUMN_STRIP_ID = 'wispEdgeColumnStrip';
export const WISP_EDGE_COLUMN_BENT_ID = 'wispEdgeColumnBent';
export const WISP_EDGE_COLUMN_SOFT_ID = 'wispEdgeColumnSoft';
export const WISP_EDGE_COLUMN_NEAR_ID = 'wispEdgeColumnNear';

/**
 * Which top band a view wears: the page's, which every view under a header shares, or the column's, for a column
 * scrolling beside a page (above). The foot has one band only, the page's.
 */
export type WispBand = 'page' | 'column';

/** A top band's filter by the ids of the parts the hook places and the drift moves (art/WispEdgeFilter.tsx draws each). */
export interface WispBandIds {
  filter: string;
  noise: string;
  drift: string;
  strip: string;
  bent: string;
  soft: string;
  near: string;
}

export const WISP_EDGE_BANDS: Record<WispBand, WispBandIds> = {
  page: {
    filter: WISP_EDGE_FILTER_ID,
    noise: WISP_EDGE_NOISE_ID,
    drift: WISP_EDGE_DRIFT_ID,
    strip: WISP_EDGE_STRIP_ID,
    bent: WISP_EDGE_BENT_ID,
    soft: WISP_EDGE_SOFT_ID,
    near: WISP_EDGE_NEAR_ID,
  },
  column: {
    filter: WISP_EDGE_COLUMN_FILTER_ID,
    noise: WISP_EDGE_COLUMN_NOISE_ID,
    drift: WISP_EDGE_COLUMN_DRIFT_ID,
    strip: WISP_EDGE_COLUMN_STRIP_ID,
    bent: WISP_EDGE_COLUMN_BENT_ID,
    soft: WISP_EDGE_COLUMN_SOFT_ID,
    near: WISP_EDGE_COLUMN_NEAR_ID,
  },
};

/**
 * How far under the header's edge the smoke still bends a little (the strip's
 * blur, a long ramp: Matt found a short one "quite abrupt", and a 40px one
 * "way too subtle"), and its full-strength lip (Matt, of a 10px one under a
 * bend of 24: "can still be stronger on the header").
 *
 * Every measure of how far the smoke reaches - these two, the drop under the header, and the foot's three - came
 * down by a third on 2026-09-22 (Matt: "The wisp effect travels a bit too far below the header and above the
 * bottom part of the page, reduce how much room this animation / effect has by 33%"). The proportions between them
 * are the ones the rounds above settled on; only the distance is shorter.
 */
export const WISP_EDGE_SOFT = 15;
export const WISP_EDGE_BAND = 7;
/** How far below a header's edge the band's lip sits: the smoke happens under the header's glass, not hidden behind it. */
const WISP_EDGE_DROP = 12;
/**
 * How far the column's lip comes down as its scroll begins (`band: 'column'`): from this far above its place, one px for
 * each px scrolled, to where the page's would be. A band's whole depth - the drop, the lip, and one ramp of its blur -
 * so the ramp starts under the field's glass. The home page's first line stands 46px under its header, and its lip
 * reaches it over the first 27px of a scroll; the column's first row starts at the field's edge with its words 15px
 * under it, inside the lip, so a band laid at its place when the scroll began took them from crisp to full smoke on
 * the first 5px. Eased, the first row goes to smoke over about the first 20px, as the home page's first line does,
 * and past it the column's smoke is the home page's exactly.
 */
export const WISP_EDGE_EASE = WISP_EDGE_DROP + WISP_EDGE_BAND + WISP_EDGE_SOFT;
/** The strip starts this far above the view, so its blur never opens the top. */
export const WISP_EDGE_ABOVE = 200;
/**
 * The filter's region: the view, with room around it for the bend to throw pixels into and for the strip above.
 *
 * It used to be one guess big enough for any view - 4000 by 60000 - and that is what took the effect off Apple's
 * engine for a while (Matt, on the Mac: "the whole page is going black when I scroll down"). A filter region has a
 * budget of 2^24 device pixels, and over it WebKit draws nothing and the element paints solid black: measured in
 * WebKit, 4096 x 4096 draws and 4200 x 4000 is black, and at two device pixels to the CSS pixel the boundary moves
 * to 2048 x 2048 exactly. The old region was forty times over it. Sized to the view it is nowhere near - the app's
 * own window is 430 x 860 - so `placeRegion` sets it from the view, and a window too large even for that keeps the
 * plain fade rather than risking the black.
 */
export const WISP_EDGE_SIDE = 40;
const WISP_EDGE_CROWN = WISP_EDGE_ABOVE + 40;
const WISP_EDGE_BELOW = 40;
const WISP_EDGE_BUDGET = 2 ** 24;

/**
 * Whether a filter region `across` × `down` CSS pixels fits the budget above, counted in the screen's own pixels: a
 * sharp screen spends two or three for each one here. Every wisp filter asks before it is worn - the page's
 * (`placeRegion`), a lane's foot (art/wispFoot.ts) and the tab row's (art/wispSides.ts) - and one that does not fit
 * keeps its plain fade.
 */
export function withinWispBudget(across: number, down: number): boolean {
  const dots = typeof devicePixelRatio === 'number' && devicePixelRatio > 0 ? devicePixelRatio : 1;
  return Math.ceil(across * dots) * Math.ceil(down * dots) <= WISP_EDGE_BUDGET;
}
/** The foot's full-strength lip at the view's bottom edge, and how far the band is computed above it. */
export const WISP_EDGE_FOOT_BAND = 11;
/**
 * The foot's own ramp, and how far above the edge its lip sits: taller than the top's (Matt: "Make the bottom
 * distortion taller"), so words start to smoke well before the edge and go on smoking down to it, where the top's
 * band is a lip just under the header.
 */
export const WISP_EDGE_FOOT_SOFT = 29;
export const WISP_EDGE_FOOT_LIFT = 24;
/**
 * How far above a view's bottom edge the foot's smoke reaches words: its lip, lifted off the edge, and two widths of
 * its ramp's blur, past which the bend is too faint to see. A line typed lower than this comes out of the smoke
 * already bent (Matt: "when I'm typing and the text is affected by the wisp at the bottom of the page it should scroll
 * the page up"), so the note's editor keeps its caret this far clear of the edge (editor/Editor.tsx `footClear`), where
 * the foot smokes at all (`footSmokes`).
 */
export const WISP_EDGE_FOOT_CLEAR = WISP_EDGE_FOOT_LIFT + WISP_EDGE_FOOT_BAND + 2 * WISP_EDGE_FOOT_SOFT;

/**
 * Which drawing a view's edges get: the filter or the mask, or on a desktop neither - a blur strip at the top and a
 * short fade at the foot. `draw` is what the view asked for; left out, the platform decides. One answer for the hook
 * below and for anyone asking whether the edges smoke (`footSmokes`), so the two cannot come to disagree.
 */
export function wispModeFor(draw?: WispDraw): WispDraw | 'fade' {
  if (!draw && wispHead() === 'blur') return 'fade';
  return draw ?? wispDraw();
}

/**
 * Whether a page's foot bends the words under it here: its smoke is wanted (Settings › Appearance › Motion), drawn as
 * smoke rather than a desktop's plain fade, and motion is not asked to be reduced, which takes the filter away
 * (art/wisp.css). Where it does not, nothing needs lifting out of it.
 */
export function footSmokes(wanted: boolean, draw?: WispDraw): boolean {
  if (!wanted) return false;
  const mode = wispModeFor(draw);
  if (mode === 'fade') return false;
  return !(mode === 'filter' && prefersStill());
}
/** How far below the band's lip the bend and blur are computed at all: past the strip's soft edge, with room for the drift. */
export const WISP_EDGE_REACH = WISP_EDGE_BAND + WISP_EDGE_SOFT * 4 + 48;

/** Steps no closer than this: about 35 a second, smooth to the eye, a third of the frames on a 120Hz phone. */
const DRIFT_STEP_MS = 28;
const BASE_X = 0.018;
const BASE_Y = 0.06;
/** The noise slides this far, down and up, over its cycle: never past the view's top. Quiet: Matt found more "too intense". */
const SLIDE_PX = 20;

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
 * Each band's drift: how many of its views are being scrolled, and the smoke's own time, advanced only while they are.
 * A band apiece, so the column's smoke holds still while only the page beside it scrolls, and the page's while only
 * the column does: "only animate when we're actively scrolling" (Matt), which one clock for both would break.
 */
const lanes: Record<WispBand, { moving: number; clock: number }> = {
  page: { moving: 0, clock: 0 },
  column: { moving: 0, clock: 0 },
};
const BANDS = Object.keys(lanes) as WispBand[];

/** The last frame's time, to measure each step by. */
let lastFrameAt = 0;

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
  for (const band of BANDS) if (lanes[band].moving > 0) lanes[band].clock += gap;
  if (now - lastStep < DRIFT_STEP_MS) return;
  lastStep = now;
  for (const band of BANDS) if (lanes[band].moving > 0) stepBand(band, lanes[band].clock);
}

/** One band's step, at `t` on its own clock. */
function stepBand(band: WispBand, t: number): void {
  const ids = WISP_EDGE_BANDS[band];
  const noise = document.getElementById(ids.noise);
  const slide = document.getElementById(ids.drift);
  if (!noise || !slide) return;
  const x = BASE_X + 0.003 * Math.sin(t / 2600);
  const y = BASE_Y + 0.01 * Math.sin(t / 3400 + 1.3);
  const dx = (4 * Math.sin(t / 2300 + 0.7)).toFixed(2);
  const dy = (SLIDE_PX / 2 + (SLIDE_PX / 2) * Math.sin(t / 3100)).toFixed(2);
  noise.setAttribute('baseFrequency', `${x.toFixed(4)} ${y.toFixed(4)}`);
  slide.setAttribute('dx', dx);
  slide.setAttribute('dy', dy);
  // A view drawn as a mask (art/wispMask.ts) slides its smoke by the same amounts. Written on the views wearing it,
  // never on the root: a custom property set on the root thirty-five times a second invalidates style for everything
  // that inherits it, which is the whole document, whatever the mask itself costs (the lanes session's point).
  for (const view of masked(band)) {
    view.style.setProperty('--wisp-noise-x', `${dx}px`);
    view.style.setProperty('--wisp-noise-y', `${dy}px`);
  }
  if (band !== 'page') return;
  // The foot's own noise drifts with the top's, so both ends of a view move as one smoke.
  document.getElementById(WISP_EDGE_FOOT_NOISE_ID)?.setAttribute('baseFrequency', `${x.toFixed(4)} ${y.toFixed(4)}`);
  const footSlide = document.getElementById(WISP_EDGE_FOOT_DRIFT_ID);
  footSlide?.setAttribute('dx', dx);
  footSlide?.setAttribute('dy', dy);
}

/**
 * The views drawn as a mask right now, and the band each wears: the drift slides their smoke by writing on them
 * (art/wisp.css `--wisp-noise-x/y`). Each hook says its own view in and out, so a view is its band's from the start,
 * whether or not its top is smoking yet.
 */
const maskViews = new Map<HTMLElement, WispBand>();

function masked(band: WispBand): HTMLElement[] {
  return [...maskViews].filter(([, worn]) => worn === band).map(([view]) => view);
}

/** After the last scroll event, this long and the smoke holds still. */
const SCROLL_IDLE_MS = 160;

/** Counts each band's views scrolling; the one animation loop runs while any is. */
function drift(band: WispBand, on: boolean, reset = true): void {
  const lane = lanes[band];
  lane.moving = Math.max(0, lane.moving + (on ? 1 : -1));
  const drifting = BANDS.reduce((sum, one) => sum + lanes[one].moving, 0);
  if (on && drifting === 1) {
    lastFrameAt = 0;
    driftFrame = requestAnimationFrame(driftStep);
  }
  if (drifting === 0) cancelAnimationFrame(driftFrame);
  // A scroll that stopped leaves the smoke as it was; only a view back at its top puts its band back to rest.
  if (!on && lane.moving === 0 && reset) rest(band);
}

/** A band at rest: its noise at the base frequency and not slid, and the foot's with the page's. */
function rest(band: WispBand): void {
  const ids = WISP_EDGE_BANDS[band];
  const noises = band === 'page' ? [ids.noise, WISP_EDGE_FOOT_NOISE_ID] : [ids.noise];
  for (const id of noises) document.getElementById(id)?.setAttribute('baseFrequency', `${BASE_X} ${BASE_Y}`);
  for (const id of band === 'page' ? [ids.drift, WISP_EDGE_FOOT_DRIFT_ID] : [ids.drift]) {
    const slide = document.getElementById(id);
    slide?.setAttribute('dx', '0');
    slide?.setAttribute('dy', '0');
  }
  for (const view of masked(band)) {
    view.style.setProperty('--wisp-noise-x', '0px');
    view.style.setProperty('--wisp-noise-y', '0px');
  }
}

/** How far above the view's bottom edge the foot's bend and blur are computed: its lip, its ramp, and room for the drift. */
const WISP_EDGE_FOOT_REACH = WISP_EDGE_FOOT_BAND + WISP_EDGE_FOOT_SOFT * 4 + 48;

/**
 * Puts the foot band at the view's bottom edge, or takes it away: the same smoke as the top, so words scrolling off
 * the end dissolve instead of meeting a flat fade (Matt: "replace the areas where it's just a black fade and blur to
 * use the wisp fade effect"). `height` is the view's own height, since the filter's coordinates start at its top-left.
 */
function placeFoot(height: number, on: boolean): void {
  const strip = document.getElementById(WISP_EDGE_FOOT_STRIP_ID);
  const reach = WISP_EDGE_FOOT_REACH + 40 + WISP_EDGE_FOOT_LIFT;
  const top = height - WISP_EDGE_FOOT_LIFT - WISP_EDGE_FOOT_REACH;
  /*
   * The lip sits above the edge (`WISP_EDGE_FOOT_LIFT`), as the top band's sits below its header: where the words are still
   * there to bend. At the edge itself, where the lip used to be, the view's own fade (art/wisp.css `--wisp-foot-fade`) had
   * already taken them, so the strongest bend happened to nothing and what showed was the fade - a black gradient
   * where the header has smoke (Matt: "it's just a black gradient not the cool effect").
   */
  // Off: the strip is parked far below anything drawn, and nothing is computed for it.
  strip?.setAttribute('y', String(on ? height - WISP_EDGE_FOOT_LIFT - WISP_EDGE_FOOT_BAND : 1e6));
  strip?.setAttribute('height', String(WISP_EDGE_ABOVE + WISP_EDGE_FOOT_BAND));
  for (const id of [WISP_EDGE_FOOT_NOISE_ID, WISP_EDGE_FOOT_BENT_ID, WISP_EDGE_FOOT_NEAR_ID, WISP_EDGE_FOOT_SOFT_ID]) {
    const part = document.getElementById(id);
    part?.setAttribute('y', String(on ? top : 1e6));
    part?.setAttribute('height', String(on ? reach : 0));
  }
}

/**
 * Sizes the filter's region to the view about to wear it, and answers whether it fits the budget above.
 *
 * The page's is the window's size rather than the view's own: two views can be wearing the one filter at a time (a
 * page with a sheet over it), and a region cut to the smaller would clip the larger - what falls outside a filter's
 * region is not drawn at all, so the miss would be a page with its edges missing rather than a page without smoke.
 * The page's top and its foot are held to the budget each on its own, as they always were.
 *
 * The column's is its own: only the column wears its filter, so its region is cut to the column's width, out to its
 * right-hand edge in the window since WebKit counts user space from the document's corner (and the window's height,
 * for the same reason). And it is held to the budget together with a page's region beside it, because in WebKit two
 * filters worn at once drew from one budget between them: with the page's band and the column's both on at 1800 x
 * 1100 and two device pixels to the CSS pixel, each region 0.62 of the budget alone and drawn alone, WebKit gave back
 * an empty frame every time, with the break between 1.00 and 1.08 of the budget together; the column's region cut to
 * its width (0.13) brought the frame back with both drawn (the review of 2026-09-28, headless). A column the pair would
 * not fit keeps its plain edge while the page smokes. The foot's region is the page's to place, and is left alone here.
 */
function placeRegion(el: HTMLElement, band: WispBand): boolean {
  const wide = typeof innerWidth === 'number' ? innerWidth : 0;
  const down = Math.max(el.offsetHeight, typeof innerHeight === 'number' ? innerHeight : 0) + WISP_EDGE_CROWN + WISP_EDGE_BELOW;
  if (band === 'column') {
    const across = Math.ceil(Math.max(el.offsetWidth, el.getBoundingClientRect().right)) + WISP_EDGE_SIDE * 2;
    if (!withinWispBudget(across + wide + WISP_EDGE_SIDE * 2, down)) return false;
    region(WISP_EDGE_COLUMN_FILTER_ID, across, down);
    return true;
  }
  const across = Math.max(el.offsetWidth, wide) + WISP_EDGE_SIDE * 2;
  if (!withinWispBudget(across, down)) return false;
  for (const id of [WISP_EDGE_FILTER_ID, WISP_EDGE_FOOT_FILTER_ID]) region(id, across, down);
  return true;
}

/** One filter's region, `across` × `down` from the room the bend and the strip need above and beside the view. */
function region(id: string, across: number, down: number): void {
  const filter = document.getElementById(id);
  filter?.setAttribute('x', String(-WISP_EDGE_SIDE));
  filter?.setAttribute('y', String(-WISP_EDGE_CROWN));
  filter?.setAttribute('width', String(across));
  filter?.setAttribute('height', String(down));
}

/** The phone's status bar, in px: the app sets it on the root as `--app-safe-top` (app.css). */
function safeTop(): number {
  if (typeof getComputedStyle === 'undefined') return 0;
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--app-safe-top')) || 0;
}

/**
 * Moves the band down to sit under a header `under` px tall (0: at the view's top), and the bend's reach with it; its
 * lip `lift` px above that while it eases in (`WISP_EDGE_EASE`). Off, the strip has no height at all, so a view
 * wearing the filter for its foot alone has nothing at its top: a page at rest under the header was smoking because
 * the strip is always there while the filter is (Matt: "when scrolled to top of page content under topbar shouldn't
 * have ghostly effect").
 */
function placeBand(ids: WispBandIds, under: number, on = true, lift = 0): void {
  const drop = under > 0 ? WISP_EDGE_DROP : 0;
  document.getElementById(ids.strip)?.setAttribute('height', String(on ? WISP_EDGE_ABOVE + under + drop + WISP_EDGE_BAND - lift : 0));
  const reach = String(on ? 40 + under + drop + WISP_EDGE_REACH : 0);
  for (const id of [ids.noise, ids.bent, ids.near, ids.soft]) document.getElementById(id)?.setAttribute('height', reach);
}

/**
 * Wears the wisp edge on `scroller` while it is scrolled off its top; answers
 * whether it is. `key` re-reads it when the content changes; `under` is a
 * header the scroller runs beneath.
 */
export function useWispEdge(
  scroller: RefObject<HTMLElement | null>,
  key?: unknown,
  under?: RefObject<HTMLElement | null>,
  options: {
    foot?: boolean;
    /**
     * What stands over the view's foot, a dock of buttons: the foot's smoke happens at its top edge rather than the
     * view's, and the view is gone below it (Matt: "The bottom bar doesn't give the wisp effect when content goes
     * behind it it shouldn't have the glass background just the wisp effect subtly"). At the view's own edge the
     * smoke was behind the buttons, where nobody could see it.
     */
    footOver?: RefObject<HTMLElement | null>;
    /**
     * How the smoke is drawn: the filter that bends the words, or the mask that tears them (art/wispMask.ts). Left
     * out, the platform decides - the mask in the Mac app, where the filter costs seconds a frame, the filter
     * elsewhere. A page comparing the two says which it wants.
     */
    draw?: WispDraw;
    /**
     * Which top band: the page's, left out, or the column's, for a column scrolling beside a page that smokes at its
     * own top at the same moment (Settings' sections, beside the section's page). Said on the view as
     * `data-wisp-edge="column"` while it smokes, for the stylesheet to give it its own filter (art/wisp.css). A top
     * only: the column's band has no foot, and `foot` is not heard with it - art/wisp.css chains a view's two ends as
     * the page's top and the foot, so a column smoking at both would have worn the page's band under its field.
     */
    band?: WispBand;
  } = {},
): boolean {
  const band = options.band ?? 'page';
  const foot = (options.foot ?? false) && band === 'page';
  const footOver = options.footOver;
  const draw = options.draw;
  const [on, setOn] = useState(false);
  // Switched off under Settings › Appearance › Motion, a page slips under its header with a clean edge (core/preferences.ts).
  const wanted = usePreferences().wispEdge;
  useEffect(() => {
    const el = scroller.current;
    if (!el || !wanted) return undefined;
    // Both refs are set by the time the effect runs; the header is read once so the cleanup sees the same node.
    const header = under?.current ?? null;
    const still = prefersStill();
    // Which drawing this view wears, said on the element for the stylesheet (art/wisp.css) and for anyone measuring.
    // On a desktop neither end smokes: the top is a blur strip under the header, the foot a short fade at the very edge,
    // so the page runs down to the window's bottom (Matt: "the desktop UI on the home page isn't reaching to the bottom
    // of the screen"). The mask's foot hid the last 104px, which a dock row across the bottom used to stand over.
    // `fade`: neither drawing, a desktop's plain edges - the blur strip at the top, a short fade at the foot.
    const mode = wispModeFor(draw);
    const plain = mode === 'fade';
    const masked = mode === 'mask';
    /** Whether this view wears the SVG filter, and so has its bands placed in the filter's coordinates. */
    const filtered = mode === 'filter';
    // On a desktop the top is a blurred strip hung under the header's glass, not smoke (art/wispMask.ts `wispHead`,
    // art/wisp.css `.app-headerBlur`). Only with a header to hang it from; the foot smokes as it always did.
    const blurHead = !!header && plain;
    // The strip is the header's sibling, laid just under it: a child of the header would blur only the header's own
    // contents, since an element wearing a backdrop filter is where its children's backdrops stop.
    const strip = blurHead ? document.createElement('div') : null;
    if (strip && header) {
      strip.className = 'app-headerBlur';
      strip.setAttribute('aria-hidden', 'true');
      header.insertAdjacentElement('afterend', strip);
    }
    if (masked) {
      installWispMasks();
      maskViews.set(el, band);
    }
    el.dataset.wispDraw = mode;
    const ids = WISP_EDGE_BANDS[band];
    let worn = false;
    /** Whether the foot band is on this view right now. */
    let footWorn = false;
    /** Whether this view's scrolling is moving the smoke right now, and the wait for the scrolling to stop. */
    let moving = false;
    let idle = 0;
    const holdStill = (reset: boolean) => {
      window.clearTimeout(idle);
      if (!moving) return;
      moving = false;
      drift(band, false, reset);
    };
    let fitted = -1;
    /** What the band sits under: a header, or the phone's status bar on a view that has none. */
    let beneath = 0;
    /** How far above its place the top band's lip is at this scroll: the page's never; the column's while it eases in. */
    const liftNow = () => (band === 'column' ? Math.max(0, WISP_EDGE_EASE - Math.round(el.scrollTop)) : 0);
    let lifted = liftNow();
    /** Lays the top band where it goes now, lifted as it is: the mask's lip always, the filter's strip while worn. */
    const layTop = () => {
      lifted = liftNow();
      // The mask's lip, where the filter's strip would end: the stylesheet lays the band from it.
      if (masked) el.style.setProperty('--wisp-lip', `${beneath + (beneath > 0 ? WISP_EDGE_DROP : 0) - lifted}px`);
      if (worn && filtered) placeBand(ids, beneath, true, lifted);
    };
    /** Whether the filter's region can cover this view at all: a window past the budget goes without (`placeRegion`). */
    let roomy = false;
    const fit = () => {
      // A mask has no region and no budget: only the filter is held to one.
      roomy = !filtered || placeRegion(el, band);
      const height = header?.offsetHeight ?? 0;
      // With no header the status bar plays the part of one: the smoke's lip sits at its edge, so a page dissolves
      // as it reaches the clock instead of sliding under a flat scrim (app.css .app-statusScrim).
      beneath = height || safeTop();
      // Only when it really changed: these set the scroller's own top padding, and writing them from a size observer
      // that then sees a new size would feed itself.
      if (height !== fitted) {
        fitted = height;
        el.style.setProperty('--wisp-under', `${height}px`);
        // Said on the view, for its scrollbar to start where the header ends (app.css `[data-under-header]`).
        el.toggleAttribute('data-under-header', height > 0);
        // Under a header the header hides the top; with no header the view dissolves into the status bar's own
        // ground, so what passes the clock is smoke rather than a flat fade (app.css .app-statusScrim).
        // Short, so the smoke has words to bend before they are gone: the lip sits a drop under the status bar, and a
        // fade that ran past it hid the bend and read as a black gradient (Matt: "not the cool effect").
        el.style.setProperty('--wisp-top-fade', height ? '0px' : 'calc(var(--app-safe-top, 0px) + 8px)');
      }
      layTop();
      if (strip && header) {
        strip.style.top = `${header.offsetTop + header.offsetHeight}px`;
        strip.style.left = `${header.offsetLeft}px`;
        strip.style.width = `${header.offsetWidth}px`;
      }
    };
    /** How much of the view's foot the dock covers: where the foot band sits, measured up from the view's bottom. */
    let covered = -1;
    const footAt = () => {
      const over = footOver?.current?.offsetHeight ?? 0;
      if (over !== covered) {
        covered = over;
        el.style.setProperty('--wisp-foot-inset', `${over}px`);
      }
      return el.offsetHeight - over;
    };
    const check = () => {
      // Scrolled off its top AND able to scroll: a view that stops scrolling (a note's page while the robot shows its
      // own card over it) keeps its scrollTop, and the band would go on smoking over whatever is under the header
      // (Matt: "when on the page where the AI is analyzing everything the top text looks distorted unexpectedly").
      const more = el.scrollHeight - el.clientHeight > 4;
      const scrolled = el.scrollTop > 4 && more && roomy;
      // The foot smokes while there is still something below the view's bottom edge to scroll to.
      const ending = foot && more && roomy && el.scrollTop < el.scrollHeight - el.clientHeight - 4;
      if (ending !== footWorn) {
        footWorn = ending;
        el.toggleAttribute('data-wisp-foot', ending);
        if (filtered) {
          placeFoot(footAt(), ending);
          // Wearing the filter for the foot alone: the top band stays off until this view is scrolled.
          if (ending && !worn) placeBand(ids, beneath, false);
        } else {
          footAt();
        }
      } else if (ending) {
        if (!filtered) footAt();
        else placeFoot(footAt(), true);
      }
      setOn(scrolled);
      if (scrolled === worn) {
        // Smoking already: the column's lip may still be on its way down.
        if (scrolled && liftNow() !== lifted) layTop();
        return;
      }
      worn = scrolled;
      if (blurHead) {
        strip?.toggleAttribute('data-on', scrolled);
        return;
      }
      if (scrolled) {
        el.setAttribute('data-wisp-edge', band === 'page' ? '' : band);
        layTop();
      } else {
        el.removeAttribute('data-wisp-edge');
        // The top band goes with it: a view still wearing the filter for its foot must be crisp at its top.
        if (filtered) placeBand(ids, beneath, false);
        holdStill(true);
      }
    };
    // Scrolling moves the smoke; a pause in it holds the smoke where it is. A desktop's plain edges have no smoke to
    // move (the blur strip, the short fade: art/wisp.css takes the filter off them), so their scrolling starts no loop;
    // it did, and wrote seventy-odd attributes a second to a filter nothing wore.
    const onScroll = () => {
      check();
      if ((!worn && !footWorn) || still || mode === 'fade') return;
      if (!moving) {
        moving = true;
        drift(band, true);
      }
      window.clearTimeout(idle);
      idle = window.setTimeout(() => holdStill(false), SCROLL_IDLE_MS);
    };
    fit();
    check();
    el.addEventListener('scroll', onScroll, { passive: true });
    // The header's height, and the view's own: content that comes or goes can stop it scrolling without a scroll event.
    const resized = new ResizeObserver(() => {
      fit();
      check();
    });
    resized.observe(el);
    /*
     * The header by its border box, not the default content box. A header here is mostly padding - the list's is
     * `padding-block: calc(var(--app-safe-top) + ...)` around a title only a screen reader sees - so when the bar
     * above it changes height (the app stamping its height after the first paint, the Mac's title bar, the bar going
     * from one row to two) only the padding grows. The content box stays put, a content-box observer never fires,
     * and `--wisp-under` kept whatever the first `fit()` happened to catch: 16px on one load, 125 on the next, and
     * the workspace pills either under the bar or crowded against it. Measured: the same padding change fired a
     * content-box observer 0 times and a border-box one once. `fit()` reads `offsetHeight`, which is the border box,
     * so what is watched and what is measured now agree.
     */
    if (header) resized.observe(header, { box: 'border-box' });
    const dock = footOver?.current ?? null;
    if (dock) resized.observe(dock, { box: 'border-box' });
    return () => {
      el.removeEventListener('scroll', onScroll);
      resized.disconnect();
      el.removeAttribute('data-wisp-edge');
      el.removeAttribute('data-under-header');
      strip?.remove();
      delete el.dataset.wispDraw;
      maskViews.delete(el);
      if (footWorn) {
        el.removeAttribute('data-wisp-foot');
        if (filtered) placeFoot(0, false);
      }
      holdStill(true);
    };
  }, [wanted, scroller, key, under, foot, footOver, draw, band]);
  return on;
}
