import { useCallback, useEffect, useRef, useState } from 'react';
import { Check, CircleAlert, LoaderCircle } from '@glacier/icons';
import { prefersStill } from '../core/motion.ts';
import { meetingStateNow } from '../capture/meetingLive.ts';
import { claimAutoReload, type Updates } from '../core/ota.ts';
import type { SyncStatus } from '../core/sync/engine.ts';
import { isTauri } from '../core/tauri.ts';
import icon from './ghost-icon-eyeless.webp';
import { barAt, easeFor, EYE_RX, EYE_RY, EYES, LOOK_OUT_MS, lookAt, WINK_MS, WINKING_EYE } from './eyes.ts';
import styles from './LaunchScreen.module.css';

/**
 * What the app shows while it opens (Matt: "I want a loading screen with the logo and checking for updates and stuff
 * and show statuses for checking for updates etc"): the icon, the name, and a line for each thing opening does, each
 * turning to a tick as it's done. The lines are the real steps, not a show: the notes read from the library, the
 * update check (asked now, on the app, rather than after the usual settling pause), and the account's sync when
 * there is one.
 *
 * An update found while it is up is taken there and then (Matt: "If an update is found on the loading screen apply
 * and restart automatically"): the check has already downloaded and installed the build, so the line says so and the
 * page reloads into it, and the launch that follows is the new build's. Once for a build (core/ota.ts
 * `claimAutoReload`), so a build that will not come up cannot loop the launch; not while a recording runs or the side
 * key opened the app to start one (`holdUpdate`), since a reload would end it; and only while this screen is still
 * up, since past it someone is already in the app. A newer app (the APK) is not this: Android's installer asks first,
 * and no app can answer for the person.
 *
 * It goes when the notes are read and the update check has answered, or three seconds on, whichever is first, so a slow
 * network never holds anyone at the door; and it stays at least long enough to be read rather than flash.
 */

/** Long enough to read the lines; short enough not to be a wait. */
const SHORTEST_MS = 900;
/** The update check stops holding the door after this: it carries on, and says what it found in the usual places. */
const LONGEST_MS = 3000;
const FADE_MS = 260;
/** A check that hasn't started by now isn't going to: this build or this device doesn't check. */
const SKIP_AFTER_MS = 500;
/** How long "Updating" is shown before the reload: long enough to be read as the reason the launch starts again. */
const APPLY_BEAT_MS = 450;

interface LaunchScreenProps {
  loading: boolean;
  notes: number;
  updates: Updates;
  sync: SyncStatus;
  /** Leave an update for later: the app was opened to record, which a reload would end. */
  holdUpdate?: boolean;
  onDone: () => void;
}

type Line = { key: string; state: 'working' | 'done' | 'note'; words: string };

/**
 * A squircle's outline as an SVG path: a superellipse, |x|^n + |y|^n = 1, the shape of an app icon's corners rather
 * than a rounded rectangle's, centred at (c, c) with half-width r.
 */
function squircle(c: number, r: number, n = 5, steps = 96): string {
  const points: string[] = [];
  for (let i = 0; i < steps; i += 1) {
    const t = (i / steps) * Math.PI * 2;
    const cos = Math.cos(t);
    const sin = Math.sin(t);
    const x = c + r * Math.sign(cos) * Math.abs(cos) ** (2 / n);
    const y = c + r * Math.sign(sin) * Math.abs(sin) ** (2 / n);
    points.push(`${x.toFixed(2)} ${y.toFixed(2)}`);
  }
  return `M${points.join('L')}Z`;
}

/** The drawing's box, the icon's squircle inside it, and the ring the bar runs round, a little outside the icon. */
const BOX = 128;
const ICON_PATH = squircle(BOX / 2, 48);
const RING_PATH = squircle(BOX / 2, 58);

/**
 * The app's icon in a squircle, and a short bar chasing round a ring outside it while the app opens (Matt: "put the app
 * logo in a squircle with a black bar that chases around the outside of the squircle"). The bar is the page's ink:
 * black on the light page, and white on the dark one, where black would be invisible. It runs on a faint track of the
 * same ring.
 *
 * And the ghost watches it (launch/eyes.ts): the picture's eyes are painted out and drawn again over it, and each frame
 * both turn toward the bar's middle, catching up with it as eyes do. The bar and the eyes run off one clock, so the bar
 * is moved from here too rather than by a CSS animation that would drift from them.
 *
 * When the app is open (`finishing`), the bar fades and the ghost turns to look out of the screen, at whoever is
 * holding it, and winks (Matt: "Remove the blink, when it's done loading have the ghost look at the camera and wink
 * before the loading screen goes away"); `onFinished` says the wink is over, for the screen to fade. Asked for less
 * motion, the bar stands still at the top, the eyes look ahead, and there is no wink to wait for.
 */
function IconChase({ finishing, onFinished }: { finishing: boolean; onFinished: () => void }) {
  const bar = useRef<SVGPathElement>(null);
  const eyes = useRef<(SVGEllipseElement | null)[]>([]);
  // Read each frame, so the loop that is already running turns the eyes out without starting again.
  const out = useRef(false);
  out.current = finishing;
  // Whether the eyes are moving at all: a still ghost has no look or wink to give.
  const [moving, setMoving] = useState(false);
  const [winking, setWinking] = useState(false);
  const finished = useRef(onFinished);
  finished.current = onFinished;
  useEffect(() => {
    const path = bar.current;
    // A page with no geometry (a test's DOM) keeps the bar where it starts and the eyes ahead.
    if (!path || typeof path.getTotalLength !== 'function' || typeof path.getPointAtLength !== 'function') return undefined;
    if (prefersStill()) return undefined;
    const length = path.getTotalLength();
    const looking = EYES.map(() => ({ x: 0, y: 0 }));
    const start = performance.now();
    let last = start;
    let frame = 0;
    path.dataset.driven = '';
    setMoving(true);
    const tick = (now: number) => {
      const { middle, offset } = barAt(now - start);
      path.style.strokeDashoffset = String(offset);
      const target = path.getPointAtLength(middle * length);
      const ease = easeFor(Math.min(64, now - last));
      last = now;
      EYES.forEach((eye, i) => {
        // Looking out of the screen is looking at no point on it: both eyes back to the middle of where they were.
        const to = out.current ? { x: 0, y: 0 } : lookAt(eye, target);
        const at = looking[i]!;
        at.x += (to.x - at.x) * ease;
        at.y += (to.y - at.y) * ease;
        eyes.current[i]?.setAttribute('transform', `translate(${at.x.toFixed(2)} ${at.y.toFixed(2)})`);
      });
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  // The look out, then the wink, then done; at once for a ghost that isn't moving.
  useEffect(() => {
    if (!finishing) return undefined;
    if (!moving) {
      finished.current();
      return undefined;
    }
    const wink = window.setTimeout(() => setWinking(true), LOOK_OUT_MS);
    const done = window.setTimeout(() => finished.current(), LOOK_OUT_MS + WINK_MS);
    return () => {
      window.clearTimeout(wink);
      window.clearTimeout(done);
    };
  }, [finishing, moving]);

  return (
    <svg className={styles.chase} viewBox={`0 0 ${BOX} ${BOX}`} width={BOX} height={BOX} aria-hidden="true" data-finishing={finishing || undefined}>
      <defs>
        <clipPath id="launch-squircle">
          <path d={ICON_PATH} />
        </clipPath>
      </defs>
      <image href={icon} x={BOX / 2 - 48} y={BOX / 2 - 48} width={96} height={96} clipPath="url(#launch-squircle)" preserveAspectRatio="xMidYMid slice" />
      {EYES.map((eye, i) => (
        // Each eye in a group of its own: the frame loop moves the eye, and the wink squeezes the group round it.
        <g key={i} className={i === WINKING_EYE && winking ? styles.wink : undefined}>
          <ellipse
            ref={(el) => {
              eyes.current[i] = el;
            }}
            className={styles.eye}
            cx={eye.x}
            cy={eye.y}
            rx={EYE_RX}
            ry={EYE_RY}
          />
        </g>
      ))}
      <path className={styles.track} d={RING_PATH} pathLength={100} />
      <path ref={bar} className={styles.bar} d={RING_PATH} pathLength={100} />
    </svg>
  );
}

export function LaunchScreen({ loading, notes, updates, sync, holdUpdate = false, onDone }: LaunchScreenProps) {
  const native = isTauri();
  const started = useRef(Date.now());
  const [now, setNow] = useState(() => Date.now());
  const [leaving, setLeaving] = useState(false);
  const asked = useRef(false);

  // The update check, now: the app's own first check waits a few seconds for the list to settle, and this screen is
  // the moment the answer is worth having.
  useEffect(() => {
    if (!native || asked.current) return;
    asked.current = true;
    updates.check();
  }, [native, updates]);

  useEffect(() => {
    const beat = window.setInterval(() => setNow(Date.now()), 150);
    return () => window.clearInterval(beat);
  }, []);

  // Whether a check really ran: a staging build, local-only mode and the dev server never check (core/ota.ts), and
  // then there is no answer to wait for and no line to show.
  const begun = useRef(false);
  if (updates.checking) begun.current = true;
  const [skipped, setSkipped] = useState(!native);
  useEffect(() => {
    if (!native) return undefined;
    const timer = window.setTimeout(() => {
      if (!begun.current) setSkipped(true);
    }, SKIP_AFTER_MS);
    return () => window.clearTimeout(timer);
  }, [native]);

  // An update found while this screen is up: loaded now, after a beat for its line to be read (the header).
  const [applying, setApplying] = useState(false);
  const readyBuild = updates.ready?.build ?? null;
  const reload = useRef(updates.reload);
  reload.current = updates.reload;
  useEffect(() => {
    if (!readyBuild || applying || leaving || holdUpdate) return;
    if (meetingStateNow()?.recording) return;
    if (claimAutoReload(readyBuild)) setApplying(true);
  }, [readyBuild, applying, leaving, holdUpdate]);
  useEffect(() => {
    if (!applying) return undefined;
    const timer = window.setTimeout(() => reload.current(), APPLY_BEAT_MS);
    return () => window.clearTimeout(timer);
  }, [applying]);

  const elapsed = now - started.current;
  const checked = skipped || (begun.current && !updates.checking);
  // Ready once, and ready from then on: a second check starting mid-fade can't hold the screen up again.
  const latched = useRef(false);
  // Not while an update is being taken: the page is about to start again, and the ghost's wink is the new build's to give.
  if (!applying && !loading && elapsed >= SHORTEST_MS && (checked || elapsed >= LONGEST_MS)) latched.current = true;
  const ready = latched.current;

  // Once ready it stays ready: the ghost looks out and winks (IconChase), then the screen fades and hands over. The
  // callback is read from a ref so a new one each render can't restart the fade and lose the hand-over.
  const done = useRef(onDone);
  done.current = onDone;
  const [winked, setWinked] = useState(false);
  const onWinked = useCallback(() => setWinked(true), []);
  useEffect(() => {
    if (!winked) return undefined;
    setLeaving(true);
    const timer = window.setTimeout(() => done.current(), FADE_MS);
    return () => window.clearTimeout(timer);
  }, [winked]);

  const lines: Line[] = [
    loading
      ? { key: 'notes', state: 'working', words: 'Opening your notes' }
      : { key: 'notes', state: 'done', words: notes === 1 ? '1 note' : `${notes} notes` },
  ];
  if (!skipped) {
    lines.push(
      applying
        ? { key: 'updates', state: 'working', words: 'Updating Ghost.md' }
        : !checked
        ? { key: 'updates', state: 'working', words: 'Checking for updates' }
        : updates.ready
          ? { key: 'updates', state: 'done', words: 'An update is ready for next time' }
          : updates.apk.kind === 'available'
            ? { key: 'updates', state: 'note', words: `Ghost.md ${updates.apk.info.version} is out` }
            : updates.lastError
              ? { key: 'updates', state: 'note', words: 'Couldn’t check for updates' }
              : { key: 'updates', state: 'done', words: 'Up to date' },
    );
  }
  if (sync.phase !== 'off') {
    lines.push(
      sync.phase === 'syncing'
        ? { key: 'sync', state: 'working', words: 'Syncing your devices' }
        : sync.phase === 'error'
          ? { key: 'sync', state: 'note', words: 'Sync will try again' }
          : { key: 'sync', state: 'done', words: 'In sync' },
    );
  }

  return (
    <div className={styles.launch} data-leaving={leaving || undefined} role="status" aria-live="polite" aria-label="Opening Ghost.md">
      <IconChase finishing={ready} onFinished={onWinked} />
      <h1 className={styles.name}>Ghost.md</h1>
      <ul className={styles.lines}>
        {lines.map((line) => (
          <li key={line.key} className={styles.line} data-state={line.state}>
            <span className={styles.mark} aria-hidden="true">
              {line.state === 'working' ? <LoaderCircle size={14} strokeWidth={2.4} /> : line.state === 'done' ? <Check size={14} strokeWidth={2.6} /> : <CircleAlert size={14} strokeWidth={2.4} />}
            </span>
            {line.words}
          </li>
        ))}
      </ul>
    </div>
  );
}
