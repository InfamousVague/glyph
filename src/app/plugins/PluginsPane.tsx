import { Switch } from '@glacier/react';
import { PaneSection, SettingRow, SettingsFootnote } from '../settings/kit/settingsKit.tsx';
import { usePlugins } from './registry.ts';
import type { GlyphPlugin, Permission } from './types.ts';

/**
 * Settings > Plugins: every plugin in this build, a switch for each, and what
 * each one may do, read from its manifest.
 *
 * A plugin switched off offers nothing anywhere (its page here, its rows on a
 * note's cog, its swipe, its voice commands, its context for the formatter)
 * and keeps its data, so switching it on again brings it back as it was.
 */

const PERMISSION_WORDS: Record<Permission, string> = {
  notes: 'Your notes',
  network: 'The internet',
  ai: 'The model on your phone',
  voice: 'Voice commands',
  native: 'Built-in app commands',
};

function PluginCard({ plugin, on, onChange }: { plugin: GlyphPlugin; on: boolean; onChange: (on: boolean) => void }) {
  const { manifest } = plugin;
  const Icon = plugin.icon;
  return (
    <PaneSection
      title={manifest.name}
      description={manifest.description}
      footer={`${manifest.standard ? 'Ships with Glyph' : manifest.author} · version ${manifest.version}`}
    >
      <SettingRow
        icon={<Icon size={16} />}
        label={on ? 'On' : 'Off'}
        hint={on ? 'Its settings are in the list, and its rows show on your notes.' : 'Nothing of it shows. What it kept stays, for when it is on again.'}
        control={<Switch aria-label={`${manifest.name} plugin`} checked={on} onCheckedChange={onChange} />}
      />
      {manifest.permissions.map((permission) => (
        <SettingRow
          key={permission.kind}
          label={permission.kind === 'network' && manifest.hosts?.length ? `${PERMISSION_WORDS.network}: ${manifest.hosts.join(', ')}` : PERMISSION_WORDS[permission.kind]}
          hint={permission.why}
        />
      ))}
    </PaneSection>
  );
}

export function PluginsPane() {
  const { all, enabled, setEnabled } = usePlugins();
  return (
    <>
      {all.map((plugin) => (
        <PluginCard key={plugin.manifest.id} plugin={plugin} on={enabled.includes(plugin)} onChange={(on) => setEnabled(plugin.manifest.id, on)} />
      ))}
      <SettingsFootnote>Plugins ship inside Glyph and update with it. Each can reach only what its card lists.</SettingsFootnote>
    </>
  );
}
