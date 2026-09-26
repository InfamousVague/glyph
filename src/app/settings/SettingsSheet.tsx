import { useEffect, useState } from 'react';
import { BookOpen, CircleUser, FlaskConical, Info, Mic, Puzzle, Sparkles, SunMoon, Terminal, Type, Vibrate, Waves } from '@glacier/icons';
import { useAccount } from '../core/account/account.ts';
import { syncSummary, useSyncStatus } from '../core/sync/engine.ts';
import { AccountPane } from './AccountPane.tsx';
import { gb, modelName, modelSpec, useModels } from '../core/ai.ts';
import { hapticsAvailable, useHapticsPref } from '../core/haptics.ts';
import { isAndroid } from '../core/platform.ts';
import type { Updates } from '../core/ota.ts';
import { facesOf, usePreferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { useDeveloperMode } from './developerMode.ts';
import { CheatSheet } from '../guide/CheatSheet.tsx';
import { markGroups } from '../guide/marks.ts';
import { GUIDE_TITLE } from '../guidebook/guidebook.ts';
import { FormattingPane } from './FormattingPane.tsx';
import { PluginsPane } from '../plugins/PluginsPane.tsx';
import { usePlugins } from '../plugins/hooks.ts';
import { AboutPane } from './AboutPane.tsx';
import { AnimationsPane } from './AnimationsPane.tsx';
import { AppearancePane } from './AppearancePane.tsx';
import { DeveloperPane } from './DeveloperPane.tsx';
import { FeelPane } from './FeelPane.tsx';
import { RecordingPane } from './RecordingPane.tsx';
import { SettingsScreen, type SettingsSection } from './SettingsScreen.tsx';
import { TestResultsPane } from './TestResultsPane.tsx';
import { TypePane } from './TypePane.tsx';
import { updatesSummary } from './updateLines.ts';
import { ACCENT_WORDS, DENSITY_WORDS, FACE_WORDS, ROUNDING_WORDS, SIZE_WORDS, THEME_WORDS } from './words.ts';
import { reportSummary } from '../diag/testReport.ts';

/**
 * Settings: the sections and their live one-line readings, handed to the
 * screen that lists them (SettingsScreen). The readings come from the same
 * stores the panes edit, so a row can never disagree with its pane.
 *
 * Six clusters, in the list's order: who you are (Account); how it looks
 * (Type, Appearance); how it works (Recording, Formatting, Feel, and
 * Animations, which sits with them though it is listed after the plugins);
 * the plugins (each switched-on plugin's own page, then Plugins to switch
 * them); help and the app itself (the Cheat sheet, and About, which holds the
 * updates and what's new); and the hidden pages (Developer, Test results).
 * Recording only on Android, where there is a side key, Feel only where there
 * is a motor, the hidden pages only once unlocked. Each pane is a file of its
 * own; the words for a preference's values are words.ts, shared with the
 * panes, so a reading here says what the pane's control says.
 */

interface SettingsSheetProps {
  open: boolean;
  onClose: () => void;
  updates: Updates;
  /** Open the walkthrough, on its first page or a given one (Guide's page indexes). */
  onGuide: (page?: number) => void;
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
}

export function SettingsSheet({ open, onClose, updates, onGuide, onSample, onGuideBook, onBoard, onCanvas, onHowCanvas, onAcademy, toCheatSheet = 0 }: SettingsSheetProps) {
  const prefs = usePreferences();
  const faces = facesOf(prefs);
  const account = useAccount();
  const syncStatus = useSyncStatus();
  const haptics = useHapticsPref();
  const devMode = useDeveloperMode();
  const { all: allPlugins, enabled: plugins } = usePlugins();
  const { models } = useModels();
  const [goTo, setGoTo] = useState<{ id: string; nonce: number } | null>(null);
  // Opened from the Academy: the sheet comes up on the cheat sheet itself rather than on the list of sections.
  useEffect(() => {
    if (toCheatSheet) setGoTo({ id: 'cheatsheet', nonce: toCheatSheet });
  }, [toCheatSheet]);

  const chosenModel = modelSpec(prefs.formatModel);
  const modelHere = models.find((m) => m.id === prefs.formatModel)?.present ?? false;
  const formattingSummary = !isTauri()
    ? 'Runs on the phone'
    : `${modelName(prefs.formatModel)} · ${modelHere ? 'on the phone' : `${gb(chosenModel?.bytes ?? 0)} to get`}`;

  const sections: SettingsSection[] = [
    // Who you are, first and on its own card (Matt: "move account to top of settings section"): it is what a person
    // opens Settings for on a new phone, and everything below it is how the app behaves once they are in.
    {
      id: 'account',
      label: 'Account',
      words: 'sign in login handle encrypted',
      // Signed in, the page is the account's; signed out, it is the ways in.
      settings: account.session
        ? [
            { name: 'Sync now', words: 'devices' },
            { name: 'Live typing (trial)', words: 'realtime collaborate' },
            { name: 'Password and recovery codes', words: 'change' },
            { name: 'Sign out', words: 'log out logout' },
            { name: 'Shared links', words: 'share publish read' },
            { name: 'Delete account', words: 'remove close erase data' },
          ]
        : [
            { name: 'I have an account', words: 'sign in login' },
            { name: 'Create an account', words: 'sign up register' },
            { name: 'Lost the password', words: 'forgot recovery code reset' },
          ],
      icon: <CircleUser size={16} />,
      content: <AccountPane />,
      summary: syncSummary(account.session?.handle ?? null, syncStatus),
      group: 5,
    },
    {
      id: 'type',
      label: 'Type',
      words: 'text font',
      settings: [
        { name: 'Text size', words: 'font bigger smaller larger' },
        { name: 'Note font', words: 'font typeface body note editor maple fira mono monospace code coding ligatures inter noto plex' },
        { name: 'Interface font', words: 'font typeface ui app tabs menus inter noto plex' },
        { name: 'Link previews', words: 'links url cards' },
      ],
      icon: <Type size={16} />,
      content: <TypePane />,
      // Spacing moved to Appearance, where the rest of how the app is drawn lives.
      // The size, then the two faces: the note's, then the interface's.
      // The size as it is kept when it has no word: core/preferences.ts settles the faces on reading, not the size.
      summary: `${SIZE_WORDS[prefs.textSize] ?? prefs.textSize} · ${FACE_WORDS[faces.note]} · ${FACE_WORDS[faces.ui]}`,
      group: 0,
    },
    {
      id: 'theme',
      label: 'Appearance',
      words: 'theme look',
      settings: [
        { name: 'Page', words: 'theme light dark system dawn boreal ember' },
        { name: 'Accent', words: 'colour color highlight' },
        { name: 'Spacing', words: 'density compact padding roomy tight' },
        { name: 'Size', words: 'scale zoom interface ui bigger smaller' },
        { name: 'Sidebar', words: 'dock column popover notes list' },
        { name: 'Corners', words: 'rounding radius round square' },
        { name: 'Code', words: 'syntax highlighting colours colors' },
      ],
      icon: <SunMoon size={16} />,
      content: <AppearancePane />,
      // The page, then anything else that has been moved off its default: the colour, the air, the corners.
      summary: [
        THEME_WORDS[prefs.theme],
        prefs.accent === 'ink' ? null : ACCENT_WORDS[prefs.accent],
        // The density is not settled on reading either (core/preferences.ts): one with no word is said as it is kept.
        prefs.density === 'comfortable' ? null : (DENSITY_WORDS[prefs.density] ?? prefs.density),
        prefs.rounding === 'round' ? null : ROUNDING_WORDS[prefs.rounding],
      ]
        .filter(Boolean)
        .join(' · '),
      group: 0,
    },
    ...(isAndroid
      ? [
          {
            id: 'recording',
            label: 'Recording',
            words: 'voice microphone mic dictate',
            settings: [
              { name: 'Stop when I go quiet', words: 'silence auto stop' },
              { name: 'Commands start with “hey Ghost”', words: 'wake word voice cues' },
              { name: 'Review after recording', words: 'check transcript' },
              { name: 'Better words', words: 'refine clean up transcript' },
              { name: 'Where the side key is', words: 'button height position hardware' },
            ],
            icon: <Mic size={16} />,
            content: <RecordingPane />,
            summary: prefs.refine ? 'A note a take · better words' : 'A note a take',
            group: 1,
          },
        ]
      : []),
    {
      id: 'formatting',
      label: 'Formatting',
      words: 'ai model',
      settings: [
        { name: 'Local only', words: 'offline privacy network internet nothing leaves the phone' },
        { name: 'Model', words: 'ai download llm' },
      ],
      icon: <Sparkles size={16} />,
      content: <FormattingPane />,
      summary: formattingSummary,
      group: 1,
    },
    ...(hapticsAvailable()
      ? [
          {
            id: 'feel',
            label: 'Feel',
            words: 'vibration',
            settings: [{ name: 'Haptics', words: 'vibrate vibration buzz touch' }],
            icon: <Vibrate size={16} />,
            content: <FeelPane />,
            summary: haptics ? 'Haptics on' : 'Haptics off',
            group: 1,
          },
        ]
      : []),
    ...plugins.flatMap((plugin) => {
      const settings = plugin.settings;
      if (!settings) return [];
      const Icon = plugin.icon;
      return [
        {
          id: `plugin:${plugin.manifest.id}`,
          label: plugin.manifest.name,
          words: plugin.manifest.description,
          hue: settings.hue,
          icon: <Icon size={16} />,
          content: <settings.Pane />,
          summary: settings.summary(),
          group: 2,
        },
      ];
    }),
    {
      id: 'plugins',
      label: 'Plugins',
      words: 'extensions integrations add-ons',
      // Every plugin, on or off: the way to switch on one that has no page yet.
      settings: allPlugins.map((plugin) => ({ name: plugin.manifest.name, words: plugin.manifest.description })),
      icon: <Puzzle size={16} />,
      // A card's row lands on that plugin's own page (plugins/PluginsPane.tsx).
      content: <PluginsPane onOpen={(id) => setGoTo({ id, nonce: Date.now() })} />,
      summary: `${plugins.length} of ${allPlugins.length} on`,
      group: 2,
    },
    {
      id: 'animations',
      label: 'Animations',
      words: 'motion movement',
      settings: [
        { name: 'Animation speed', words: 'motion fast slow' },
        { name: 'Ghostly typing', words: 'wisp letters' },
        { name: 'Smoke at the edges', words: 'wisp fade scroll' },
        { name: 'Ripples while recording', words: 'waves voice' },
      ],
      icon: <Waves size={16} />,
      content: <AnimationsPane />,
      summary:
        [prefs.wisp ? 'Ghostly typing' : null, prefs.wispEdge ? 'smoke' : null, prefs.ripples ? 'ripples' : null, prefs.motionSpeed !== 'normal' ? prefs.motionSpeed : null]
          .filter(Boolean)
          .join(' · ') || 'All still',
      group: 1,
    },
    {
      id: 'cheatsheet',
      label: 'Cheat sheet',
      words: 'markdown syntax marks help',
      // Every mark it shows, so looking for "bold" or "spoiler" lands on it.
      settings: markGroups()
        .flatMap((group) => group.rows)
        .map((row) => ({ name: row.name, words: row.symbol })),
      icon: <BookOpen size={16} />,
      content: <CheatSheet />,
      summary: 'Every mark and every cue',
      group: 3,
    },
    {
      id: 'about',
      label: 'About',
      words: 'version help',
      settings: [
        { name: 'Updates', words: 'update check upgrade install' },
        { name: 'Update alerts', words: 'notifications notify' },
        { name: "What's new", words: 'changelog releases' },
        { name: 'Ghost.md Academy', words: 'learn tutorial lessons' },
        { name: 'How to talk to Ghost.md', words: 'voice commands cues' },
        { name: `Add ${GUIDE_TITLE}`, words: 'guide manual help book' },
        { name: 'Add the sample note', words: 'example' },
        { name: 'Add the example board', words: 'kanban' },
        { name: 'Add the example canvas' },
        { name: 'Privacy policy', words: 'data privacy personal information' },
      ],
      icon: <Info size={16} />,
      content: (
        <AboutPane
          updates={updates}
          onGuide={onGuide}
          onSample={onSample}
          onGuideBook={onGuideBook}
          onBoard={onBoard}
          onCanvas={onCanvas}
          onHowCanvas={onHowCanvas}
          onAcademy={onAcademy}
          onCheatSheet={() => setGoTo({ id: 'cheatsheet', nonce: Date.now() })}
          onDeveloper={() => setGoTo({ id: 'developer', nonce: Date.now() })}
        />
      ),
      // The version and where it stands, now that updates live on this page too.
      summary: `${updates.version} · ${updatesSummary(updates)}`,
      group: 3,
    },
    ...(devMode
      ? [
          {
            id: 'developer',
            label: 'Developer',
            words: 'debug',
            settings: [
              { name: 'Welcome guide', words: 'onboarding set-up' },
              { name: 'Choose your model' },
              { name: 'Smoke bench', words: 'wisp performance frames' },
              { name: 'Developer settings', words: 'mode' },
              { name: 'Reset local data', words: 'clear erase' },
              { name: 'Reset everything', words: 'clear erase models' },
              { name: 'Window', words: 'inset screen engine' },
            ],
            icon: <Terminal size={16} />,
            content: <DeveloperPane onGuide={onGuide} />,
            summary: 'Set-up, reset',
            group: 4,
          },
          {
            id: 'test-results',
            label: 'Test results',
            words: 'tests report',
            icon: <FlaskConical size={16} />,
            content: <TestResultsPane />,
            summary: reportSummary(),
            group: 4,
          },
        ]
      : []),
  ];

  return <SettingsScreen open={open} onClose={onClose} sections={sections} goTo={goTo} />;
}
