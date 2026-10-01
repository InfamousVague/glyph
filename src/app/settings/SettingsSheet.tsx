import { useCallback, useEffect, useState } from 'react';
import { BookOpen, CircleUser, FileCode, FlaskConical, Info, Mic, Puzzle, Shapes, SunMoon, Terminal } from '@glacier/icons';
import { useAccount } from '../core/account/account.ts';
import { syncSummary, useSyncStatus } from '../core/sync/engine.ts';
import { AccountPane } from './AccountPane.tsx';
import { findable as accountFindable } from './AccountPane.findable.ts';
import { gb, modelName, modelSpec, useModels } from '../core/ai.ts';
import { hapticsAvailable } from '../core/haptics.ts';
import { isAndroid, isMobile } from '../core/platform.ts';
import { storeOf, type Updates } from '../core/ota.ts';
import { DEFAULT_PREFERENCES, facesOf, usePreferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { useSidebar } from '../core/useWideScreen.ts';
import { useDeveloperMode } from './developerMode.ts';
import { CheatSheet } from '../guide/CheatSheet.tsx';
import { findable as cheatSheetFindable } from '../guide/CheatSheet.findable.ts';
import { PluginsPane } from '../plugins/PluginsPane.tsx';
import { findable as pluginsFindable } from '../plugins/PluginsPane.findable.ts';
import { usePlugins } from '../plugins/hooks.ts';
import { AboutPane } from './AboutPane.tsx';
import { findable as aboutFindable } from './AboutPane.findable.ts';
import { AppearancePane } from './AppearancePane.tsx';
import { findable as appearanceFindable } from './AppearancePane.findable.ts';
import { DeveloperPane } from './DeveloperPane.tsx';
import { findable as developerFindable } from './DeveloperPane.findable.ts';
import { ExamplesPane } from './ExamplesPane.tsx';
import { findable as examplesFindable } from './ExamplesPane.findable.ts';
import { RecordingPane } from './RecordingPane.tsx';
import { SpecPane } from './SpecPane.tsx';
import { findable as specFindable } from './SpecPane.findable.ts';
import { findable as recordingFindable } from './RecordingPane.findable.ts';
import { SettingsScreen, type SettingsSection, type SettingsTarget } from './SettingsScreen.tsx';
import { TestResultsPane } from './TestResultsPane.tsx';
import { updatesSummary } from './updateLines.ts';
import { ACCENT_WORDS, DENSITY_WORDS, FACE_WORDS, ROUNDING_WORDS, SIZE_WORDS, THEME_WORDS } from './words.ts';
import { reportSummary } from '../diag/testReport.ts';

/**
 * Settings: the sections and their live one-line readings, handed to the
 * screen that lists them (SettingsScreen). The readings come from the same
 * stores the panes edit, so a row can never disagree with its pane.
 *
 * Five rows on a phone since docs/DESIGN.md §138 (Matt: "also see if you can clean up / streamline settings a bit"),
 * on one screen with air under them, in four cards: who you are and what leaves the phone (Account); how it looks,
 * moves and feels (Appearance), what happens to a recording and the model that writes it up (Recording), and what
 * reaches beyond the phone (Plugins); the app itself (About); and the hidden pages (Developer, Test results). It was
 * twelve rows over two screens. Recording is listed on Android, where there is a side key, and on the Mac, which
 * records through Speak and runs the better words and the summaries (§127 section 2); the hidden pages only once
 * unlocked.
 *
 * Sub-pages are sections too, off the list (`listed: false`) and still searched, each stepping back to its parent:
 * a switched-on plugin's own page behind its Plugins card, and the cheat sheet and the examples behind About's Help.
 * What the search finds on each page is that page's `findable`, a `.ts` beside it (a plugin's is on its `settings`),
 * and SettingsSheet.test.tsx renders every page and fails on a name it does not draw. The words for a preference's
 * values are words.ts, shared with the panes, so a reading here says what the pane's control says.
 */

interface SettingsSheetProps {
  open: boolean;
  onClose: () => void;
  updates: Updates;
  /** Opens the welcome walkthrough on its first page (About › Help). */
  onGuide: () => void;
  /** Make the sample note, the one with every mark in it (core/seed.ts), and open it. */
  onSample: () => void;
  /** Adds Ghost.md: The Guide (guidebook/guidebook.ts), once, and opens its index. */
  onGuideBook: () => void;
  /** Adds the example board (core/boardNote.ts). */
  onBoard: () => void;
  /** Adds the example canvas (canvas/sampleCanvas.ts). */
  onCanvas: () => void;
  /** Adds the canvas that says how Glyph works (canvas/howCanvas.ts). */
  onHowCanvas: () => void;
  /** Opens Glyph Academy (academy/AcademyScreen.tsx). */
  onAcademy: () => void;
  /**
   * Asked from outside to open at the cheat sheet - the Academy's summary sends people there for the marks it has
   * not taught yet. The moment it was asked for, so asking twice opens it twice; 0 for not asked.
   */
  toCheatSheet?: number;
  /**
   * Asked from outside to open at Recording's Model card, lit: the home page's "Get a model" and its digest's phrase
   * send people there for a language model (home/TapeShelf.tsx, home/dashboard.ts). The same shape as `toCheatSheet`.
   */
  toModel?: number;
}

export function SettingsSheet({ open, onClose, updates, onGuide, onSample, onGuideBook, onBoard, onCanvas, onHowCanvas, onAcademy, toCheatSheet = 0, toModel = 0 }: SettingsSheetProps) {
  const prefs = usePreferences();
  const faces = facesOf(prefs);
  const account = useAccount();
  const syncStatus = useSyncStatus();
  const devMode = useDeveloperMode();
  // The sidebar's choice is drawn on Appearance only on a window wide enough for the sidebar, and searched only there.
  const wide = useSidebar();
  const { all: allPlugins, enabled: plugins } = usePlugins();
  const { models } = useModels();
  const [goTo, setGoTo] = useState<(SettingsTarget & { nonce: number }) | null>(null);
  /** Lands on a section, and on a setting there when one is named: a row that opens a sub-page, or a word like "Local only". */
  const go = useCallback((target: SettingsTarget) => setGoTo({ ...target, nonce: Date.now() }), []);
  // Opened from the Academy: the sheet comes up on the cheat sheet itself rather than on the list of sections.
  useEffect(() => {
    if (toCheatSheet) setGoTo({ id: 'cheatsheet', nonce: toCheatSheet });
  }, [toCheatSheet]);
  // Opened from the shelf's "Get a model": the sheet comes up on Recording with the Model card lit, where it is fetched.
  useEffect(() => {
    if (toModel) setGoTo({ id: 'recording', setting: 'Model', nonce: toModel });
  }, [toModel]);

  // Where a recorder with a model behind it runs: Android, and the Mac app (§127 section 2).
  const recording = isAndroid || (isTauri() && !isMobile);
  const chosenModel = modelSpec(prefs.formatModel);
  const modelHere = models.find((m) => m.id === prefs.formatModel)?.present ?? false;
  /**
   * The model that writes a take up, with what it takes to get when it is not here (Formatting's reading until §138),
   * then what a take becomes. The model first and no "on the phone": the split view's column is 20rem, and the longer
   * line lost its end there. Where there is no model to fetch (a browser on a phone), what a take becomes alone.
   */
  const take = prefs.refine ? 'better words' : 'words as heard';
  const recordingSummary = isTauri()
    ? `${modelName(prefs.formatModel)}${modelHere ? '' : `, ${gb(chosenModel?.bytes ?? 0)} to get`} · ${take}`
    : prefs.refine
      ? 'Better words'
      : 'Words as heard';

  const sections: SettingsSection[] = [
    // Who you are, first and on its own card (Matt: "move account to top of settings section"): it is what a person
    // opens Settings for on a new phone, and everything below it is how the app behaves once they are in. What leaves
    // the phone is here too: sync and shared links, and the Privacy and Location cards.
    {
      id: 'account',
      label: 'Account',
      words: 'sign in login handle encrypted sync',
      // Signed in, the page is the account's; signed out, it is the ways in. Privacy and Location either way.
      settings: accountFindable(Boolean(account.session), isTauri()),
      icon: <CircleUser size={16} />,
      content: <AccountPane onOpen={go} />,
      // Local only holds the sync off, so the line says it is on.
      summary: `${syncSummary(account.session?.handle ?? null, syncStatus)}${prefs.localOnly ? ' · Local only' : ''}`,
      group: 0,
    },
    {
      id: 'theme',
      label: 'Appearance',
      // Feel was a page's name until §138: its movement and its touch are cards here now.
      words: 'theme look feel',
      settings: appearanceFindable({ wide, haptics: hapticsAvailable() }),
      icon: <SunMoon size={16} />,
      content: <AppearancePane />,
      // The page and the note's face, then anything else that has been moved off its default.
      summary: [
        THEME_WORDS[prefs.theme],
        FACE_WORDS[faces.note],
        // The size as it is kept when it has no word: core/preferences.ts settles the faces on reading, not the size.
        prefs.textSize === DEFAULT_PREFERENCES.textSize ? null : (SIZE_WORDS[prefs.textSize] ?? prefs.textSize),
        faces.ui === DEFAULT_PREFERENCES.typeface ? null : FACE_WORDS[faces.ui],
        prefs.accent === 'ink' ? null : ACCENT_WORDS[prefs.accent],
        // The density is not settled on reading either (core/preferences.ts): one with no word is said as it is kept.
        prefs.density === 'comfortable' ? null : (DENSITY_WORDS[prefs.density] ?? prefs.density),
        prefs.rounding === 'round' ? null : ROUNDING_WORDS[prefs.rounding],
      ]
        .filter(Boolean)
        .join(' · '),
      group: 1,
    },
    ...(recording
      ? [
          {
            id: 'recording',
            label: 'Recording',
            words: 'voice microphone mic dictate',
            settings: recordingFindable({ android: isAndroid, app: isTauri() }),
            icon: <Mic size={16} />,
            content: <RecordingPane />,
            summary: recordingSummary,
            group: 1,
          },
        ]
      : []),
    {
      id: 'plugins',
      label: 'Plugins',
      words: 'extensions integrations add-ons',
      // Every plugin, on or off: the way to switch on one that has no page yet.
      settings: pluginsFindable(allPlugins),
      icon: <Puzzle size={16} />,
      // A card's row lands on that plugin's own page, and "Local only" on Account's Privacy card (plugins/PluginsPane.tsx).
      content: <PluginsPane onOpen={go} />,
      summary: `${plugins.length} of ${allPlugins.length} on`,
      group: 1,
    },
    // Each switched-on plugin's own page, behind its card: a sub-page of Plugins in the plugin's own colour.
    ...plugins.flatMap((plugin) => {
      const settings = plugin.settings;
      if (!settings) return [];
      const Icon = plugin.icon;
      return [
        {
          id: `plugin:${plugin.manifest.id}`,
          label: plugin.manifest.name,
          words: plugin.manifest.description,
          settings: settings.settings,
          hue: settings.hue,
          icon: <Icon size={16} />,
          content: <settings.Pane />,
          summary: settings.summary(),
          group: 1,
          listed: false,
          parent: 'plugins',
        },
      ];
    }),
    {
      id: 'about',
      label: 'About',
      words: 'version help',
      // The App Store says what is new on an iPhone, so About draws no What's new there (AboutPane.tsx).
      settings: aboutFindable({ whatsNew: storeOf(updates.status) !== 'appstore' }),
      icon: <Info size={16} />,
      content: <AboutPane updates={updates} onGuide={onGuide} onGuideBook={onGuideBook} onAcademy={onAcademy} onOpen={go} />,
      // The version and where it stands, now that updates live on this page too.
      summary: `${updates.version} · ${updatesSummary(updates)}`,
      group: 2,
    },
    // Help, not settings: two pages behind About's Help card, still searched, and found by their own names alone. About
    // does not list the rows that open them as well, or a search for either would show two rows of one name.
    {
      id: 'cheatsheet',
      label: 'Cheat sheet',
      // "Formatting cheat sheet" is its name in a note's More sheet, and was About's row's.
      words: 'markdown syntax marks help formatting',
      // Every mark it shows, so looking for "bold" or "spoiler" lands on it.
      settings: cheatSheetFindable(),
      icon: <BookOpen size={16} />,
      content: <CheatSheet />,
      // Marks only: the cues are the guide's to teach (guide/CheatSheet.tsx), so the line no longer promises them.
      summary: 'Every mark you can type',
      group: 2,
      listed: false,
      parent: 'about',
    },
    {
      id: 'spec',
      label: 'Specification',
      // GLY-4: the definition of every extension and AI fill, with the base specifications linked (docs/DESIGN.md §164).
      words: 'markdown spec commonmark gfm syntax extensions fills reference',
      settings: specFindable(),
      icon: <FileCode size={16} />,
      content: <SpecPane />,
      summary: 'Every extension and fill, defined',
      group: 2,
      listed: false,
      parent: 'about',
    },
    {
      id: 'examples',
      label: 'Examples',
      words: 'sample example',
      settings: examplesFindable,
      icon: <Shapes size={16} />,
      content: <ExamplesPane onSample={onSample} onBoard={onBoard} onCanvas={onCanvas} onHowCanvas={onHowCanvas} />,
      // As About's row says it.
      summary: 'A sample note, a board and two canvases',
      group: 2,
      listed: false,
      parent: 'about',
    },
    ...(devMode
      ? [
          {
            id: 'developer',
            label: 'Developer',
            words: 'debug',
            settings: developerFindable,
            icon: <Terminal size={16} />,
            content: <DeveloperPane />,
            summary: 'Benches, reset',
            group: 3,
          },
          {
            id: 'test-results',
            label: 'Test results',
            words: 'tests report',
            icon: <FlaskConical size={16} />,
            content: <TestResultsPane />,
            summary: reportSummary(),
            group: 3,
          },
        ]
      : []),
  ];

  return <SettingsScreen open={open} onClose={onClose} sections={sections} goTo={goTo} />;
}
