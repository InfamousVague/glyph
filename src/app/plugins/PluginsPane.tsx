import { useState } from 'react';
import { Puzzle } from '@glacier/icons';
import { Switch } from '@glacier/react';
import { usePreferences } from '../core/preferences.ts';
import { GoWord, PaneHero, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsFootnote } from '../settings/kit/settingsKit.tsx';
import type { SettingsTarget } from '../settings/SettingsScreen.tsx';
import { usePlugins } from './hooks.ts';
import { PERMISSION_WORDS, reachLine, usesNetwork } from './reach.ts';
import type { GlyphPlugin } from './types.ts';

/**
 * Settings > Plugins: every plugin in this build, one card each (Matt: "revamp and redo the plugins page").
 *
 * A card leads with the plugin as a thing - its icon, its name, one line on what it does - and its switch, then
 * the way to its own page when it has one and is on, then what it may reach, said in one line with the reasons a
 * press away rather than a row per permission, which was most of the old page. A plugin switched off offers nothing
 * anywhere (its page here, its rows on a note's cog, its swipe, its tips in a pause, its context for the formatter)
 * and keeps its data, so switching it on again brings it back as it was.
 *
 * Local only (Settings › Account › Privacy) holds every plugin that uses the internet off, whatever its switch says
 * (plugins/registry.ts); the page says so at the top and on each card it holds, and "Local only" there is a word that
 * opens Account at the Privacy card (docs/DESIGN.md §138), where it said "in Formatting" and left the person to look.
 * A plugin's own page is a sub-page of this one, behind its card, and back from it comes here.
 *
 * What the search finds here is PluginsPane.findable.ts.
 */

interface PluginCardProps {
  plugin: GlyphPlugin;
  on: boolean;
  /** Held off by Local only, whatever the switch says. */
  held: boolean;
  onChange: (on: boolean) => void;
  /** Lands on a page of Settings: the plugin's own page, or Account at the Privacy card for "Local only". */
  onOpen?: (target: SettingsTarget) => void;
}

/** Account's Privacy card, where Local only is switched. */
const LOCAL_ONLY: SettingsTarget = { id: 'account', setting: 'Privacy' };

function PluginCard({ plugin, on, held, onChange, onOpen }: PluginCardProps) {
  const { manifest } = plugin;
  const Icon = plugin.icon;
  const [why, setWhy] = useState(false);
  return (
    <PaneSection footer={`${manifest.standard ? 'Ships with Ghost.md' : manifest.author} · version ${manifest.version}`}>
      <PaneHero glyph={<Icon size={22} />} title={manifest.name} meta={manifest.description} trailing={<Switch aria-label={`${manifest.name} plugin`} checked={on && !held} onCheckedChange={onChange} disabled={held} />} />
      {held ? (
        <SettingRow
          label="Off while Local only is on"
          hint={
            <>
              It uses the internet. Switch <GoWord onPress={onOpen ? () => onOpen(LOCAL_ONLY) : undefined}>Local only</GoWord> off to use it.
            </>
          }
        />
      ) : null}
      {on && !held && plugin.settings && onOpen ? (
        <SettingRow icon={<Icon size={16} />} label={plugin.settings.summary()} hint={`${manifest.name}’s own page: what it keeps, and how it is set.`} onPress={() => onOpen({ id: `plugin:${manifest.id}` })} />
      ) : null}
      <SettingRow label="What it may reach" hint={reachLine(manifest)} control={<RowAction onPress={() => setWhy((v) => !v)}>{why ? 'Less' : 'Why'}</RowAction>} />
      {why
        ? manifest.permissions.map((permission) => (
            <SettingRow key={permission.kind} label={PERMISSION_WORDS[permission.kind]} hint={permission.why} />
          ))
        : null}
    </PaneSection>
  );
}

export function PluginsPane({ onOpen }: { onOpen?: (target: SettingsTarget) => void }) {
  const { all, enabled, setEnabled } = usePlugins();
  const localOnly = usePreferences().localOnly;
  return (
    <>
      <PaneSection>
        <PaneHero
          glyph={<Puzzle size={22} />}
          title="Plugins"
          meta={`${enabled.length} of ${all.length} on. Each reaches only what its card says. One switched off offers nothing anywhere, not its rows, its commands or its page, until it is on again, and keeps what it kept.`}
        />
      </PaneSection>
      {localOnly ? (
        <SettingsCallout>
          <span>
            <GoWord onPress={onOpen ? () => onOpen(LOCAL_ONLY) : undefined}>Local only</GoWord> is on, so plugins that use the internet are held off until it is off.
          </span>
        </SettingsCallout>
      ) : null}
      {all.map((plugin) => (
        <PluginCard key={plugin.manifest.id} plugin={plugin} on={enabled.includes(plugin)} held={localOnly && usesNetwork(plugin.manifest)} onChange={(on) => setEnabled(plugin.manifest.id, on)} onOpen={onOpen} />
      ))}
      <SettingsFootnote>Plugins ship inside Ghost.md and update with it. There is nothing to install, and nothing here reaches anywhere its card does not say.</SettingsFootnote>
    </>
  );
}
