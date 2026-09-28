import { Fragment, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Check, Hourglass } from '@glacier/icons';
import { cancelRun, ended, runFor, useRun, type RunState } from '../ai/runs.ts';
import { useSummaries } from '../ai/summaries.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { clock, paceNumber } from '../ai/words.ts';
import { withinWispBudget } from '../art/wispEdge.ts';
import { useRefining } from '../capture/refine.ts';
import { cpuShare, heatShare } from '../core/ai.ts';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { prefersStill } from '../core/motion.ts';
import { usePreferences } from '../core/preferences.ts';
import { useWideScreen } from '../core/useWideScreen.ts';
import { HEAT_NOISE } from '../editor/textEffects.ts';
import { feedOf, paneWindow, type Feed, type FeedRun } from './feed.ts';
import { HotPhone } from './HotPhone.tsx';
import { STEP_ICONS } from './icons.ts';
import {
  GRACE_MS,
  HAZE_HZ,
  HAZE_OWN,
  HOLD_MS,
  LEAVE_MS,
  OPEN_GRACE_MS,
  glowOf,
  glowStepOf,
  litPinsOf,
  liveWords,
  pinsOf,
  sceneDetail,
  sceneTitle,
  stepsOf,
  titlePieces,
  warmthOf,
  workingStep,
  type SceneInput,
  type StepId,
  type Warmth,
} from './steps.ts';
import styles from './AtWork.module.css';

/**
 * The phone at work: a full-screen scene over the note while the models work
 * on a recording, until they are done or it is sent behind.
 *
 * Matt: "make the analyzing steps of the AI full screen high contrast SVG
 * iconography with cool effects like a piping hot phone CPU scrolling through
 * the thoughts and transcriptions of the AI etc." After Done on a recording
 * the note opens and the review runs in it (ai/useNoteReview.ts): listening
 * again, comparing, then a thinking run of the engine (ai/runs.ts). That was
 * a strip under the header; this is the same work drawn large. The phone
 * (scene/HotPhone.tsx) over a pane of what is being read and thought
 * (scene/feed.ts), the steps in the order they happen, a title in the strip's
 * own words (scene/steps.ts), four counters, and two words: Stop, which is
 * the strip's own control, and Back to the note, which drops to the strip.
 *
 * It never blocks anything. The strip and the note are under it, the review
 * carries on whether it is up or not, and the moment the run ends it begins
 * to leave, so the findings and the toast are seen landing. One exception:
 * while the summary queue holds a job for this note (ai/summaries.ts), a
 * summary run may follow the review's, and the scene waits the grace for it
 * after an end instead of the settle alone, then follows it as "Reading the
 * recording" and "Writing the summary" (docs/DESIGN.md §127 section 2). It is a child of
 * the note screen on purpose and never navigates: leaving the note mid-review
 * drops the findings (useNoteReview's cleanup), so nothing here does. Back
 * closes it, armed one commit after the note's own handler so the first swipe
 * takes the scene and the second the note.
 *
 * The one looped motion is the haze on the words: the app's heat filter idea
 * (editor/textEffects.ts `heat`) at the words' own share, stepped in the
 * same commit as each report rather than animated on its own clock, so the
 * model keeps its cores. It is worn only with Settings › Feel's smoke at
 * the edges on, the switch that already means "SVG turbulence costs frames
 * here", and never under reduced motion.
 */

export interface AtWorkProps {
  noteId: string;
  /** The review's key while one is on this note; null with none. A new key opens the scene. */
  opening: number | null;
  /** Every phrase the fast model heard, in order. */
  heard: string;
  /** The note as the prompt read it. */
  body: string;
  /** Whether a listen will happen: the recorder kept a recording. */
  hasJob: boolean;
  /** The review's own stage before its run (editor/useNoteAi.ts `reviewStage`). */
  stage: ReviewStage | null;
  /** In the bench: absolute in its host under the bench's bar rather than fixed over the app, with no inset padding. */
  inline?: boolean;
}

/** What the scene has seen of this opening. Replaced whole when a new key opens it. */
interface Seen {
  key: number | null;
  shown: boolean;
  leaving: boolean;
  openedAt: number;
  /** An ENDED run the note already had at opening, which is not this review's: ignored. A live one is never ignored. */
  ignoreId: string | null;
  /** What Comparing said, kept after the stage clears. */
  compared: string | null;
  sawStage: boolean;
  /** The review is over with no run (no thinking model): "Done." */
  ended: boolean;
  /** Reduced motion, read at opening. */
  still: boolean;
}

function opened(noteId: string, key: number | null): Seen {
  const had = runFor(noteId);
  return { key, shown: key !== null, leaving: false, openedAt: Date.now(), ignoreId: had && ended(had) ? had.id : null, compared: null, sawStage: false, ended: false, still: prefersStill() };
}

/** Whether a report past loading has come: loading's one sample is a new sampler's, and reads nothing true. */
function pastLoading(run: RunState): boolean {
  if (run.phase === 'prefill' || run.phase === 'generating') return true;
  return ended(run) && (run.promptTokensDone > 0 || run.outputTokens > 0);
}

/*
 * The haze's numbers: the heat filter's (editor/textEffects.ts `HEAT_NOISE`) for 14 px type, the words' own share of
 * the bend, and the noise breathing between its low and high frequencies on `baseFrequency` alone - the seed stays 7,
 * so no letter jumps.
 */
const K = 14 / 16;
const LOW = [HEAT_NOISE.low[0] / K, HEAT_NOISE.low[1] / K] as const;
const HIGH = [HEAT_NOISE.high[0] / K, HEAT_NOISE.high[1] / K] as const;
const LOW_FREQUENCY = `${LOW[0].toFixed(4)} ${LOW[1].toFixed(4)}`;
const BEND = HEAT_NOISE.bend * K * HAZE_OWN;
const BREATH_MS = 2500;
const SHARE: Record<Warmth, number> = { cold: 0, warm: 0.5, hot: 1 };

/*
 * Where the current line is kept, as a share of the pane's height: under the die and its pins (the die's bottom pins
 * end at 0.66 of the drawing), in clear paper. The lines already read or thought pass up behind the die and the mark,
 * which hide them; the one being read or written never is. (It was 0.6, which is the die itself, and the review found
 * the head line and each finding cut through by it on the cover screen.) `.list`'s top padding in AtWork.module.css
 * is the same share, so the first line can sit there too.
 */
const ANCHOR = 0.72;
const NO_LINES: string[] = [];

/** One counter tile: a label, a value (or a blank of the same height), and a bar, a unit, or nothing under it. */
function Tile({ label, value, share, unit }: { label: string; value: string; share?: number | null; unit?: string }) {
  const words = value !== '' && !/\d/.test(value);
  return (
    <div className={styles.tile}>
      <dt className={styles.tileLabel}>{label}</dt>
      <dd className={styles.tileValue} data-words={words || undefined} data-blank={value === '' || undefined}>
        {value}
      </dd>
      {share !== undefined ? (
        <dd className={styles.tileBar} aria-hidden="true">
          <span style={{ inlineSize: share === null ? 0 : `${Math.round(share * 100)}%` }} />
        </dd>
      ) : (
        <dd className={styles.tileUnit}>{unit ?? ''}</dd>
      )}
    </div>
  );
}

export function AtWork({ noteId, opening, heard, body, hasJob, stage, inline = false }: AtWorkProps) {
  const [seen, setSeen] = useState(() => opened(noteId, opening));
  // Adjusted during render, so the first render with a key already has the scene, and what a stage says is kept.
  let current = seen;
  if (opening !== seen.key) current = opened(noteId, opening);
  if (stage && !current.sawStage) current = { ...current, sawStage: true };
  if (stage?.what === 'Comparing' && current.compared !== stage.detail) current = { ...current, compared: stage.detail };
  if (current !== seen) setSeen(current);
  const { shown, still, openedAt, key } = current;

  const run = useRun(noteId);
  const live = run && run.id !== current.ignoreId ? run : null;
  const refining = useRefining();
  // A summary run may follow this one on the note: after an end, wait the grace for it rather than the settle alone.
  const summaryDue = useSummaries().pending.has(noteId);
  const prefs = usePreferences();
  const wide = useWideScreen();

  // Hidden: the clock and the haze stop, and the feed and the picture hold their last values.
  const [hidden, setHidden] = useState(() => typeof document !== 'undefined' && document.visibilityState === 'hidden');
  useEffect(() => {
    if (!shown) return undefined;
    const read = () => setHidden(document.visibilityState === 'hidden');
    read();
    document.addEventListener('visibilitychange', read);
    return () => document.removeEventListener('visibilitychange', read);
  }, [shown]);

  const input: SceneInput = { stage, download: stage ? refining.download : null, run: live, hasJob, compared: current.compared, ended: current.ended && !live };

  // The part of the run the feed reads, keyed on those fields alone: a report that moves only the clock or the readings
  // (every 120 ms while the model loads) must not split the transcript and the thought again.
  const kind = live?.kind ?? null;
  const phase = live?.phase ?? null;
  const thought = live?.thought ?? '';
  const runLines = live?.lines ?? NO_LINES;
  const partial = live?.partial ?? '';
  const promptTokens = live?.promptTokens ?? 0;
  const promptTokensDone = live?.promptTokensDone ?? 0;
  const outputTokens = live?.outputTokens ?? 0;
  const maxTokens = live?.maxTokens ?? 0;
  const feedRun = useMemo<FeedRun | null>(
    () => (kind === null || phase === null ? null : { kind, phase, thought, lines: runLines, partial, promptTokens, promptTokensDone, outputTokens, maxTokens }),
    [kind, phase, thought, runLines, partial, promptTokens, promptTokensDone, outputTokens, maxTokens],
  );
  const heldFeed = useRef<Feed | null>(null);
  // Split again only when the run's words or the stage change, never on the note's own redraws; and not while hidden.
  const feed = useMemo(() => {
    if (hidden && heldFeed.current) return heldFeed.current;
    return feedOf({ stage, run: feedRun, heard, body });
  }, [stage, feedRun, heard, body, hidden]);
  heldFeed.current = feed;
  const lines = useMemo(() => paneWindow(feed), [feed]);
  const currentAt = feed.current !== null ? (feed.lines[feed.current]?.at ?? null) : null;

  const heldPicture = useRef<{ warmth: Warmth; glowStep: number; pins: number; litPins: number; step: StepId | null } | null>(null);
  const pins = pinsOf(live?.hardware?.cores);
  // The pins go out with the rings at an end: an ended run keeps its last sample, but the cores are no longer its.
  const drawn = { warmth: warmthOf(input), glowStep: glowStepOf(glowOf(live)), pins, litPins: live?.hardware && pastLoading(live) && !ended(live) ? litPinsOf(live.hardware.cpuPercent, pins) : 0, step: workingStep(input) };
  const picture = hidden && heldPicture.current ? heldPicture.current : drawn;
  heldPicture.current = picture;

  // Back: armed one commit late, so the note's own handler (registered in the first commit, parent effects after the
  // child's) is under this one and the first swipe takes the scene.
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    setArmed(true);
  }, []);
  const carryOn = () => {
    setSeen((was) => ({ ...was, shown: false, leaving: false }));
    fireNativeHaptic('selection');
  };
  useBack(shown && armed, carryOn);

  const stop = () => {
    void cancelRun(noteId);
    fireNativeHaptic('warning');
  };

  // Leaving: after an end the settle plays, then the fade, then nothing; or the review is taken as over when no run
  // comes after the stage clears; or, having seen nothing at all, the scene leaves quietly. Not while the document is
  // hidden: what ended off screen is settled and left on return, so the findings are still seen landing.
  const liveId = live?.id ?? null;
  const liveEnded = live ? ended(live) : false;
  const staged = stage !== null;
  const { sawStage, ended: over } = current;
  // What the scene has seen, for a timer to ask at the moment it fires.
  const seenSoFar = useRef({ staged, liveId, sawStage });
  seenSoFar.current = { staged, liveId, sawStage };
  useEffect(() => {
    if (!shown || staged || hidden) return undefined;
    const timers: number[] = [];
    const later = (fn: () => void, ms: number) => timers.push(window.setTimeout(fn, ms));
    const leave = (hold: number, unless?: () => boolean) =>
      later(() => {
        if (unless?.()) return;
        setSeen((was) => ({ ...was, leaving: true }));
        later(() => setSeen((was) => ({ ...was, shown: false, leaving: false })), LEAVE_MS);
      }, hold);
    if (liveEnded || (over && !liveId)) leave(liveEnded && summaryDue ? Math.max(HOLD_MS, GRACE_MS) : HOLD_MS);
    else if (!liveId) {
      if (sawStage) later(() => setSeen((was) => ({ ...was, ended: true })), GRACE_MS);
      // The one leave that fires on nothing having happened, so it asks again as it fires. Seen once in the browser
      // pane and never again: a play after one that had run hidden left at eight seconds, mid-run. The cleanup below
      // clears this timer the moment a stage or a run is seen, and no path to a survivor was found; this makes sure.
      else leave(Math.max(0, openedAt + OPEN_GRACE_MS - Date.now()), () => seenSoFar.current.staged || seenSoFar.current.liveId !== null || seenSoFar.current.sawStage);
    }
    return () => timers.forEach((timer) => window.clearTimeout(timer));
  }, [shown, staged, hidden, liveId, liveEnded, over, sawStage, openedAt, key, summaryDue]);

  // Since Done: wall time from the opening, a second at a time, paused while hidden and true again on return.
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    if (!shown || hidden) return undefined;
    setNow(Date.now());
    const beat = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(beat);
  }, [shown, hidden, key]);

  // The haze: on the pane's list, within the filter budget (art/wispEdge.ts), asked again whenever the list's box
  // changes - the Fold's unfold changes it.
  const hazeId = useId().replace(/[^a-zA-Z0-9]/g, '');
  const list = useRef<HTMLOListElement>(null);
  const pane = useRef<HTMLDivElement>(null);
  const noise = useRef<SVGFETurbulenceElement>(null);
  const bend = useRef<SVGFEDisplacementMapElement>(null);
  const [fits, setFits] = useState(true);
  useEffect(() => {
    const el = list.current;
    if (!el || !shown || still || typeof ResizeObserver === 'undefined') return undefined;
    const measure = () => setFits(withinWispBudget(el.offsetWidth * 1.1, el.offsetHeight * 1.3));
    measure();
    const watched = new ResizeObserver(measure);
    watched.observe(el);
    return () => watched.disconnect();
  }, [shown, still]);
  const hazeOn = shown && !still && !hidden && fits && prefs.wispEdge && picture.warmth !== 'cold';
  // The bend, written only when the warmth changes.
  useLayoutEffect(() => {
    bend.current?.setAttribute('scale', (BEND * SHARE[picture.warmth]).toFixed(2));
  }, [picture.warmth, hazeOn]);
  // The breath, stepped with each report and no faster than HAZE_HZ: a filtered element repaints on any change, and
  // every report changes the text, so one repaint carries both. Nothing steps while nothing streams.
  const lastStep = useRef(-Infinity);
  const reported = live?.elapsedMs ?? 0;
  const percent = stage?.percent ?? null;
  useLayoutEffect(() => {
    const el = noise.current;
    if (!el || !hazeOn) return;
    const at = Date.now();
    if (at - lastStep.current < 1000 / HAZE_HZ) return;
    lastStep.current = at;
    const breath = 0.5 - 0.5 * Math.cos(((at % BREATH_MS) / BREATH_MS) * Math.PI * 2);
    el.setAttribute('baseFrequency', `${(LOW[0] + (HIGH[0] - LOW[0]) * breath).toFixed(4)} ${(LOW[1] + (HIGH[1] - LOW[1]) * breath).toFixed(4)}`);
  }, [reported, percent, hazeOn]);

  // The current line kept at the anchor, under the die.
  useLayoutEffect(() => {
    const host = pane.current;
    if (!host || currentAt === null) return;
    const el = host.querySelector<HTMLElement>(`[data-at="${currentAt}"]`);
    if (!el) return;
    host.scrollTop = Math.max(0, el.offsetTop - host.clientHeight * ANCHOR);
  }, [currentAt, shown]);

  if (!shown) return null;

  const steps = stepsOf(input);
  const title = sceneTitle(input);
  const detail = sceneDetail(input);
  const queued = live?.phase === 'queued';
  const past = live ? pastLoading(live) : false;
  const hardware = past ? (live?.hardware ?? null) : null;
  const tempC = hardware?.tempC ?? null;
  const streaming = feed.mode === 'thought' || feed.mode === 'findings' || feed.mode === 'prose';

  return (
    <section
      className={styles.scene}
      aria-label="The models at work on this note"
      data-leaving={current.leaving || undefined}
      data-ended={liveEnded || over || undefined}
      data-wide={wide || undefined}
      data-inline={inline || undefined}
      data-still={still || undefined}
      data-warmth={picture.warmth}
      data-mode={feed.mode}
    >
      {still ? null : (
        <svg width="0" height="0" className={styles.defs} aria-hidden="true" focusable="false">
          <filter id={hazeId} x="-0.05" y="-0.15" width="1.1" height="1.3" colorInterpolationFilters="sRGB">
            <feTurbulence ref={noise} type="fractalNoise" baseFrequency={LOW_FREQUENCY} numOctaves="2" seed="7" result="noise" />
            <feDisplacementMap ref={bend} in="SourceGraphic" in2="noise" scale="0" xChannelSelector="R" yChannelSelector="G" />
          </filter>
        </svg>
      )}

      <div className={styles.head}>
        <h2 className={styles.title}>
          {/* One block inside the heading, so the wide layout can hold it to the foot of a two-line box. */}
          <span className={styles.titleText}>
            {titlePieces(title).map((piece, i) =>
              piece.number ? (
                <span key={i} aria-hidden="true">
                  {piece.text}
                </span>
              ) : (
                <Fragment key={i}>{piece.text}</Fragment>
              ),
            )}
          </span>
        </h2>
        <p className={styles.detail}>{detail}</p>
        <p className={styles.unseen} aria-live="polite">
          {liveWords(input)}
        </p>
      </div>

      <div className={styles.picture}>
        <div ref={pane} className={styles.pane} aria-label="What is being read and thought" aria-live="off">
          <ol ref={list} className={styles.list} data-streaming={streaming || undefined} style={hazeOn ? { filter: `url(#${hazeId})` } : undefined}>
            {lines.map((line) => (
              <li key={line.at} className={styles.line} data-at={line.at} data-place={currentAt === null ? 'after' : line.at < currentAt ? 'before' : line.at === currentAt ? 'current' : 'after'} data-strong={line.strong || undefined}>
                {line.text}
              </li>
            ))}
          </ol>
        </div>
        <HotPhone warmth={picture.warmth} glowStep={picture.glowStep} litPins={picture.litPins} pins={picture.pins} step={picture.step} still={still} />
      </div>

      <div className={styles.side}>
        <ol className={styles.steps} aria-label="The steps">
          {steps.map((step) => {
            const working = step.state === 'working';
            const Icon = step.state === 'done' ? Check : step.id === 'load' && working && queued ? Hourglass : STEP_ICONS[step.id];
            return (
              <li key={step.id} className={styles.step} data-state={step.state}>
                <span className={styles.stepMark} data-turn={(step.id === 'load' && working && !queued) || undefined} aria-hidden="true">
                  <Icon size={15} strokeWidth={2.2} />
                </span>
                <span>
                  {step.words}
                  {step.detail ? <span className={styles.stepDetail}> {step.detail}</span> : null}
                </span>
              </li>
            );
          })}
        </ol>

        <dl className={styles.counters} aria-label="The phone's readings">
          <Tile label="Heat" value={!past ? '' : tempC !== null ? `${Math.round(tempC)} °C` : 'No reading'} share={tempC !== null ? heatShare(tempC) : null} />
          <Tile label="CPU" value={!past ? '' : hardware ? `${Math.round(hardware.cpuPercent)}%` : 'No reading'} share={hardware && hardware.cores ? cpuShare(hardware.cpuPercent, hardware.cores) : null} />
          <Tile label="Pace" value={live && past ? paceNumber(live.tokensPerSecond) : ''} unit="a second" />
          <Tile label="Since Done" value={clock(Math.max(0, now - openedAt))} />
        </dl>

        <p className={styles.foot}>It carries on behind the note. Nothing leaves the phone.</p>

        <div className={styles.words}>
          {live && !liveEnded && !staged ? (
            <button type="button" className={`app-word ${styles.word}`} onClick={stop}>
              Stop
            </button>
          ) : null}
          <button type="button" className={`app-word ${styles.word}`} onClick={carryOn}>
            Back to the note
          </button>
        </div>
      </div>
    </section>
  );
}
