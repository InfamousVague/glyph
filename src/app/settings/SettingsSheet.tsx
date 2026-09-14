import { useState } from 'react';
import { Info, Mic, Puzzle, RefreshCw, Sparkles, SunMoon, Terminal, Type, Vibrate } from '@glacier/icons';
import { gb, modelName, MODELS, useModels } from '../core/ai.ts';
import { hapticsAvailable, useHapticsPref } from '../core/haptics.ts';
import { isAndroid } from '../core/platform.ts';
import type { Updates } from '../core/ota.ts';
import { usePreferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { useDeveloperMode } from './developerMode.ts';
import { FormattingPane } from './FormattingPane.tsx';
import { PluginsPane } from '../plugins/PluginsPane.tsx';
import { usePlugins } from '../plugins/registry.ts';
import { AboutPane, DeveloperPane, FeelPane, RecordingPane, ThemePane, TypePane, UpdatesPane } from './panes.tsx';
import { SettingsScreen, type SettingsSection } from './SettingsScreen.tsx';

/**
 * Settings: the sections and their live one-line readings, handed to the
 * screen that lists them (SettingsScreen). The readings come from the same
 * stores the panes edit, so a row can never disagree with its pane.
 *
 * Five clusters: how it looks (Type, Theme), how it works (Recording,
 * Formatting, Feel), the plugins (each switched-on plugin's own page, then
 * Plugins to switch them), the app itself (Updates, About), and the hidden
 * page (Developer). Recording only where there is a side key, Feel only where
 * there is a motor, Developer only once unlocked.
 */

interface SettingsSheetProps {
  open: boolean;
  onClose: () => void;
  updates: Updates;
  /** Open the walkthrough, on its first page or a given one (Guide's page indexes). */
  onGuide: (page?: number) => void;
}

const SIZE_WORDS: Record<string, string> = { large: 'Large', larger: 'Larger', largest: 'Largest' };
const FACE_WORDS: Record<string, string> = { inter: 'Inter', noto: 'Noto', plex: 'Plex' };
const THEME_WORDS: Record<string, string> = { system: 'System', light: 'Light', dark: 'Dark' };

export function SettingsSheet({ open, onClose, updates, onGuide }: SettingsSheetProps) {
  const prefs = usePreferences();
  const haptics = useHapticsPref();
  const devMode = useDeveloperMode();
  const { all: allPlugins, enabled: plugins } = usePlugins();
  const { models } = useModels();
  const [goTo, setGoTo] = useState<{ id: string; nonce: number } | null>(null);

  const chosenModel = MODELS.find((m) => m.id === prefs.formatModel);
  const modelHere = models.find((m) => m.id === prefs.formatModel)?.present ?? false;
  const formattingSummary = !isTauri()
    ? 'Runs on the phone'
    : `${modelName(prefs.formatModel)} · ${modelHere ? 'on the phone' : `${gb(chosenModel?.bytes ?? 0)} to get`}`;

  let updatesSummary: string;
  if (!isTauri()) updatesSummary = 'Web version';
  else if (updates.checking) updatesSummary = 'Checking';
  else if (updates.apk.kind === 'available') updatesSummary = `${updates.apk.info.version} ready to install`;
  else if (updates.ready) updatesSummary = 'New version downloaded';
  else if (updates.lastError) updatesSummary = "Couldn't check";
  else updatesSummary = updates.lastChecked ? 'Up to date' : 'Not checked yet';

  const sections: SettingsSection[] = [
    {
      id: 'type',
      label: 'Type',
      icon: <Type size={16} />,
      content: <TypePane />,
      summary: `${SIZE_WORDS[prefs.textSize] ?? prefs.textSize} · ${FACE_WORDS[prefs.typeface] ?? prefs.typeface}`,
      group: 0,
    },
    {
      id: 'theme',
      label: 'Theme',
      icon: <SunMoon size={16} />,
      content: <ThemePane />,
      summary: THEME_WORDS[prefs.theme] ?? prefs.theme,
      group: 0,
    },
    ...(isAndroid
      ? [
          {
            id: 'recording',
            label: 'Recording',
            icon: <Mic size={16} />,
            content: <RecordingPane />,
            summary: [prefs.memo ? 'Memo mode' : 'A note a take', prefs.refine ? 'better words' : null].filter(Boolean).join(' · '),
            group: 1,
          },
        ]
      : []),
    {
      id: 'formatting',
      label: 'Formatting',
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
      icon: <Puzzle size={16} />,
      content: <PluginsPane />,
      summary: `${plugins.length} of ${allPlugins.length} on`,
      group: 2,
    },
    {
      id: 'updates',
      label: 'Updates',
      icon: <RefreshCw size={16} />,
      content: <UpdatesPane updates={updates} />,
      summary: updatesSummary,
      group: 3,
    },
    {
      id: 'about',
      label: 'About',
      icon: <Info size={16} />,
      content: <AboutPane updates={updates} onGuide={onGuide} onDeveloper={() => setGoTo({ id: 'developer', nonce: Date.now() })} />,
      summary: updates.version,
      group: 3,
    },
    ...(devMode
      ? [
          {
            id: 'developer',
            label: 'Developer',
            icon: <Terminal size={16} />,
            content: <DeveloperPane onGuide={onGuide} />,
            summary: 'Set-up, reset',
            group: 4,
          },
        ]
      : []),
  ];

  return <SettingsScreen open={open} onClose={onClose} sections={sections} goTo={goTo} />;
}
