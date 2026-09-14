import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ArrowRight } from '../art/Icons.tsx';
import { useBack } from '../core/back.ts';
import { useSwipeNav } from '../core/swipe.ts';
import { Markdown as MarkdownArt, SideKey as SideKeyArt, Theme as ThemeArt, Tips as TipsArt, Welcome as WelcomeArt } from '../art/Shapes.tsx';
import { isAndroid } from '../core/platform.ts';
import { setPreferences, usePreferences, type ThemePref } from '../core/preferences.ts';
import { gb, MODELS, modelName, useModels } from '../core/ai.ts';
import { isTauri } from '../core/tauri.ts';
import { GUIDE_PAGES as PAGES, type GuidePage as Page } from './pages.ts';
import { PHRASES, renderExample } from './phrases.ts';
import styles from './Guide.module.css';

/**
 * The walkthrough: set up the side key, then learn to talk in markdown.
 *
 * Shown once on first launch and any time from Settings. Four pages set as
 * type, like the rest of the app, with Back and Next where the thumb is.
 *
 * The side-key page is the one that matters most and the one Glyph can do the
 * least about: Android will not let an app make itself the assistant (the role
 * is marked not requestable), and the side key's own setting belongs to the
 * phone maker. So the page does the three things it can - opens the right
 * settings screen, tells the person exactly which rows to tap on THEIR phone,
 * and checks the result when they come back - and is honest that this replaces
 * Gemini or Bixby.
 *
 * The markdown page renders every example through the real speech rules (see
 * phrases.ts), so what it shows is what a capture writes.
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
}

/*
 * The activity's assistant helpers (MainActivity.GlyphHost). Every one is
 * optional: they arrive in native 0.3.1, and an over-the-air page can be
 * running on an older APK that has none of them.
 */
function bridge() {
  return window.GlyphHost;
}

function isAssistantNow(): boolean | null {
  try {
    const host = bridge();
    return host?.isAssistant ? host.isAssistant() : null;
  } catch {
    return null;
  }
}

/** 'samsung', 'pixel', or 'other' - the side key lives in a different place on each. */
function phoneKind(): 'samsung' | 'pixel' | 'other' {
  let maker: string;
  try {
    maker = bridge()?.deviceMaker?.() ?? '';
  } catch {
    maker = '';
  }
  const ua = typeof navigator === 'undefined' ? '' : navigator.userAgent;
  if (/samsung/i.test(maker) || /\bSM-[A-Z0-9]/.test(ua)) return 'samsung';
  if (/google/i.test(maker) || /\bPixel\b/.test(ua)) return 'pixel';
  return 'other';
}


export function Guide({ index, onIndex: setIndex, onClose, onTry }: GuideProps) {
  const page: Page = PAGES[index] ?? 'welcome';
  const last = index === PAGES.length - 1;

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
      if (!last) setIndex(index + 1);
    },
  });

  return (
    <div ref={root} className={styles.guide} role="dialog" aria-modal="true" aria-label="How to use Glyph">
      <header className={styles.top}>
        <span className={styles.progress}>
          {index + 1} of {PAGES.length}
        </span>
        <button type="button" className={`app-word ${styles.skip}`} onClick={onClose}>
          {last ? 'Close' : 'Skip'}
        </button>
      </header>

      <div className={styles.page} key={page}>
        {page === 'welcome' ? <Welcome /> : null}
        {page === 'theme' ? <Theme /> : null}
        {page === 'model' ? <Model /> : null}
        {page === 'sidekey' ? <SideKey /> : null}
        {page === 'markdown' ? <Markdown /> : null}
        {page === 'tips' ? <Tips /> : null}
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
        {last ? (
          <button
            type="button"
            className={`app-pill ${styles.primary}`}
            onClick={() => {
              onClose();
              onTry();
            }}
          >
            <span className={styles.dot} aria-hidden="true" />
            Try it
          </button>
        ) : (
          <button type="button" className={`app-pill ${styles.primary}`} onClick={() => setIndex(index + 1)}>
            Next
          </button>
        )}
      </nav>
    </div>
  );
}

function Welcome() {
  return (
    <>
      <WelcomeArt className={styles.hero} />
      <h1 className={styles.display}>
        Hold.
        <br />
        Talk.
        <br />
        Done.
      </h1>
      <p className={styles.lead}>
        Glyph turns what you say into a formatted note. Headings, lists and to-dos, all on the phone, no connection needed.
      </p>
      <p className={styles.body}>Two things to set up. The side key, and a few words that shape the note.</p>
    </>
  );
}

const THEME_CHOICES: Array<{ value: ThemePref; label: string; hint: string }> = [
  { value: 'dark', label: 'Dark', hint: 'Light words on black. Easier on the eyes at night.' },
  { value: 'light', label: 'Light', hint: 'Dark words on white, like paper.' },
  { value: 'system', label: 'Match the phone', hint: 'Follows your phone’s dark mode.' },
];

/**
 * Light or dark, asked up front, because in an app that is almost all type the
 * ground behind the words is most of the look. Each choice applies the moment
 * it is tapped - the guide itself changes colour under the thumb - so the
 * person decides by seeing, not by imagining. Changeable any time in Settings.
 */
function Theme() {
  const { theme } = usePreferences();
  return (
    <>
      <ThemeArt className={styles.art} />
      <h1 className={styles.title}>Light or dark?</h1>
      <p className={styles.lead}>Pick the page you want to write on. You can change it later in Settings.</p>
      <div className={styles.choices} role="radiogroup" aria-label="Theme">
        {THEME_CHOICES.map((choice) => (
          <button
            key={choice.value}
            type="button"
            role="radio"
            aria-checked={theme === choice.value}
            className={`${styles.choice} ${theme === choice.value ? 'app-inverse' : ''}`}
            data-selected={theme === choice.value ? '' : undefined}
            onClick={() => setPreferences({ theme: choice.value })}
          >
            <span className={styles.swatch} data-swatch={choice.value} aria-hidden="true">
              Aa
            </span>
            <span className={styles.choiceText}>
              <span className={styles.stepTitle}>{choice.label}</span>
              <span className={styles.note}>{choice.hint}</span>
            </span>
          </button>
        ))}
      </div>
    </>
  );
}

/**
 * Which model formats notes, asked up front like the theme: the choice is a
 * row per model with its size, the chosen one printed in reverse. Choosing
 * only sets the preference; the bytes come when Formatted is first opened,
 * or now, from the word under the list, so a phone on wifi tonight is ready
 * tomorrow. Changeable any time in Settings > Formatting.
 */
function Model() {
  const { formatModel } = usePreferences();
  const { models, download, problem, fetch } = useModels();
  const here = models.find((m) => m.id === formatModel)?.present ?? false;
  const chosen = MODELS.find((m) => m.id === formatModel);
  return (
    <>
      <MarkdownArt className={styles.art} />
      <h1 className={styles.title}>Choose your model</h1>
      <p className={styles.lead}>It rewrites your notes on the phone. Bigger is more careful, and slower. Nothing leaves the phone.</p>
      <div className={styles.choices} role="radiogroup" aria-label="Model">
        {MODELS.map((model) => (
          <button
            key={model.id}
            type="button"
            role="radio"
            aria-checked={formatModel === model.id}
            className={`${styles.choice} ${formatModel === model.id ? 'app-inverse' : ''}`}
            data-selected={formatModel === model.id ? '' : undefined}
            onClick={() => setPreferences({ formatModel: model.id })}
          >
            <span className={`${styles.swatch} ${styles.size}`} aria-hidden="true">
              {gb(model.bytes)}
            </span>
            <span className={styles.choiceText}>
              <span className={styles.stepTitle}>{model.name}</span>
              <span className={styles.note}>{model.about}</span>
            </span>
          </button>
        ))}
      </div>
      {isTauri() && chosen ? (
        <p className={styles.fine}>
          {download?.id === formatModel
            ? `Getting ${modelName(formatModel)}, ${gb(download.received)} of ${gb(download.total)}. Keep Glyph open.`
            : here
              ? `${chosen.name} is on the phone.`
              : problem
                ? problem
                : `${chosen.name} downloads the first time you ask the robot on a note, or `}
          {!here && download === null ? (
            <button type="button" className={`app-word ${styles.action}`} onClick={() => void fetch(formatModel)}>
              get it now
            </button>
          ) : null}
        </p>
      ) : null}
    </>
  );
}

function SideKey() {
  const [held, setHeld] = useState<boolean | null>(() => isAssistantNow());
  const kind = useMemo(phoneKind, []);
  const canOpen = Boolean(bridge()?.openAssistantSettings);

  // The person leaves for Settings and comes back; look again when they do.
  useEffect(() => {
    const recheck = () => {
      if (document.visibilityState === 'visible') setHeld(isAssistantNow());
    };
    document.addEventListener('visibilitychange', recheck);
    return () => document.removeEventListener('visibilitychange', recheck);
  }, []);

  const open = useCallback(() => {
    try {
      bridge()?.openAssistantSettings?.();
    } catch {
      // Nothing to open on this build; the written steps still stand.
    }
  }, []);

  if (!isAndroid) {
    return (
      <>
        <SideKeyArt className={styles.art} />
        <h1 className={styles.title}>The side key is an Android thing.</h1>
        <p className={styles.lead}>Here, tap Speak at the bottom of your notes to start a voice note.</p>
      </>
    );
  }

  const assistantPath =
    kind === 'samsung'
      ? ['Settings', 'Apps', 'Choose default apps', 'Digital assistant app', 'Device assistance app', 'Glyph']
      : ['Settings', 'Apps', 'Default apps', 'Digital assistant app', 'Default digital assistant app', 'Glyph'];
  const keyPath =
    kind === 'samsung'
      ? ['Settings', 'Advanced features', 'Side button', 'Press and hold', 'Digital assistant']
      : kind === 'pixel'
        ? ['Settings', 'System', 'Gestures', 'Press and hold power button', 'Digital assistant']
        : ['Settings', 'search “press and hold”', 'Digital assistant'];

  return (
    <>
      <SideKeyArt className={styles.art} />
      <h1 className={styles.title}>Make the side key record.</h1>
      {held ? (
        <p className={styles.done} role="status">
          <span aria-hidden="true">✓</span> Glyph is your assistant.
        </p>
      ) : null}

      <ol className={styles.steps}>
        <li>
          <h2 className={styles.stepTitle}>Make Glyph your digital assistant.</h2>
          <Path parts={assistantPath} />
          {canOpen && !held ? (
            <button type="button" className={`app-word ${styles.action}`} onClick={open}>
              Open assistant settings <ArrowRight />
            </button>
          ) : null}
        </li>
        <li>
          <h2 className={styles.stepTitle}>Point the side key at it.</h2>
          <Path parts={keyPath} />
          {kind === 'samsung' ? (
            <p className={styles.note}>
              Choose Digital assistant, not Bixby. On a Fold this is the key under your thumb when the phone is open.
            </p>
          ) : null}
        </li>
        <li>
          <h2 className={styles.stepTitle}>Hold the key and talk.</h2>
          <p className={styles.note}>
            Glyph opens already listening, even on the lock screen. Let go and talk. If the phone is locked, the note is
            there once you unlock it.
          </p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Hold the side key again to stop.</h2>
          <p className={styles.note}>That saves the note. Tapping Done does the same.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Recording keeps adding to your last note.</h2>
          <p className={styles.note}>
            Tap New note on the recorder to start a fresh one. Turn off Memo mode in Settings to get a new note every
            time.
          </p>
        </li>
      </ol>

      <p className={styles.fine}>
        This replaces {kind === 'samsung' ? 'Bixby or Gemini' : 'Gemini'} as your assistant. Switch back in the same place any
        time.
      </p>
    </>
  );
}

function Path({ parts }: { parts: string[] }) {
  return (
    <p className={styles.path}>
      {parts.map((part, i) => (
        <span key={part}>
          {i > 0 ? <span className={styles.sep} aria-hidden="true"> › </span> : null}
          <span className={i === parts.length - 1 ? styles.target : undefined}>{part}</span>
        </span>
      ))}
    </p>
  );
}

function Markdown() {
  // Rendered once per mount: the rules are pure, and these never change mid-guide.
  const rendered = useMemo(() => PHRASES.map((group) => ({ group, markdown: renderExample(group.example) })), []);
  return (
    <>
      <MarkdownArt className={styles.art} />
      <h1 className={styles.title}>Talk in markdown.</h1>
      <p className={styles.lead}>Say these words and the note formats itself as you talk. Everything else stays exactly as you said it.</p>
      <ul className={styles.phrases}>
        {rendered.map(({ group, markdown }) => (
          <li key={group.title} className={styles.phrase}>
            <h2 className={styles.stepTitle}>{group.title}</h2>
            <p className={styles.cues}>
              {group.cues.map((cue) => (
                <span key={cue} className={styles.cue}>
                  {cue}
                </span>
              ))}
            </p>
            <p className={styles.note}>{group.lead}</p>
            <div className={styles.example}>
              <p className={styles.said}>
                {group.example.say.map((line) => (
                  <span key={line}>“{line}” </span>
                ))}
              </p>
              <pre className={styles.result}>{markdown}</pre>
            </div>
          </li>
        ))}
      </ul>
    </>
  );
}

function Tips() {
  return (
    <>
      <TipsArt className={styles.art} />
      <h1 className={styles.title}>A few habits.</h1>
      <ol className={styles.steps}>
        <li>
          <h2 className={styles.stepTitle}>Pause before a cue word.</h2>
          <p className={styles.note}>A short pause before “heading” or “bullet point” starts a new sentence. That’s where Glyph listens for cues.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Or say the cue on its own.</h2>
          <p className={styles.note}>“Bullet point.” Pause. “Oat milk.” The cue waits for the next thing you say.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Stop for two seconds to start a paragraph.</h2>
          <p className={styles.note}>You don’t have to say it. The pause does it.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Talk normally.</h2>
          <p className={styles.note}>Glyph picks lists and to-dos out of normal speech. It never changes your words, only how they’re laid out.</p>
        </li>
        <li>
          <h2 className={styles.stepTitle}>Fix it after.</h2>
          <p className={styles.note}>A voice note lands at the top of your notes. Open it to fix anything. The markdown is all there.</p>
        </li>
      </ol>
    </>
  );
}
