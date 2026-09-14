import { describe, expect, it, vi } from 'vitest';
import { createHost, PluginPermissionError } from './host.ts';
import { BUILT_IN, createRegistry } from './registry.ts';
import type { GlyphPlugin, PluginManifest } from './types.ts';

const manifest = (id: string, extra: Partial<PluginManifest> = {}): PluginManifest => ({
  id,
  name: id,
  description: '',
  version: '1.0.0',
  author: 'test',
  standard: true,
  permissions: [],
  storage: [],
  ...extra,
});

const Icon = () => null;

function memoryStore(initial: Record<string, boolean> = {}) {
  let saved = { ...initial };
  return {
    read: () => saved,
    write: (next: Record<string, boolean>) => {
      saved = next;
    },
    saved: () => saved,
  };
}

describe('the plugin registry', () => {
  const linked: GlyphPlugin = {
    manifest: manifest('linked', { permissions: [{ kind: 'voice', why: '' }] }),
    icon: Icon,
    formatContext: { for: (id) => (id === 'n1' ? 'Briefing one.' : null), version: (id) => (id === 'n1' ? 42 : 0) },
    voice: [{ id: 'hello', parse: (text) => (text === 'hello' ? {} : null), describe: () => ({ title: 'Hello', action: 'Go' }), run: () => null }],
  };
  const optional: GlyphPlugin = {
    manifest: manifest('optional', { standard: false, storage: ['glyph-optional'] }),
    icon: Icon,
    formatContext: { for: () => 'Briefing two.', version: () => 7 },
  };

  it('has standard plugins on and others off until switched', () => {
    const registry = createRegistry([linked, optional], memoryStore());
    expect(registry.enabled().map((p) => p.manifest.id)).toEqual(['linked']);
    expect(registry.voiceCommands().map((c) => c.id)).toEqual(['hello']);
  });

  it('keeps a switch, tells listeners, and offers nothing from a plugin that is off', () => {
    const store = memoryStore();
    const registry = createRegistry([linked, optional], store);
    const heard = vi.fn();
    registry.subscribe(heard);
    registry.setEnabled('linked', false);
    registry.setEnabled('optional', true);
    expect(store.saved()).toEqual({ linked: false, optional: true });
    expect(heard).toHaveBeenCalledTimes(2);
    expect(registry.voiceCommands()).toEqual([]);
    expect(registry.contextFor('n1')).toBe('Briefing two.');
  });

  it('gives one plugin’s context version as it is, so notes formatted before plugins stay formatted', () => {
    const registry = createRegistry([linked, optional], memoryStore());
    expect(registry.contextFor('n1')).toBe('Briefing one.');
    expect(registry.contextVersion('n1')).toBe(42);
    expect(registry.contextVersion('n2')).toBe(0);
    registry.setEnabled('optional', true);
    expect(registry.contextFor('n1')).toBe('Briefing one.\n\nBriefing two.');
    expect(registry.contextVersion('n1')).not.toBe(42);
  });

  it('refuses a plugin whose extension points go past its manifest', () => {
    const noisy: GlyphPlugin = { manifest: manifest('noisy'), icon: Icon, voice: linked.voice };
    expect(() => createRegistry([noisy], memoryStore())).toThrow(PluginPermissionError);
    const editor: GlyphPlugin = {
      manifest: manifest('editor', { permissions: [{ kind: 'voice', why: '' }] }),
      icon: Icon,
      itemAction: { id: 'x', label: 'X', busyLabel: 'X…', available: () => true, run: async () => undefined },
    };
    expect(() => createRegistry([editor], memoryStore())).toThrow(/“notes” permission/);
  });

  it('refuses two plugins with one id', () => {
    expect(() => createRegistry([linked, linked])).toThrow(/Two plugins/);
  });

  it('lists every plugin’s storage for a reset, switched on or not', () => {
    expect(createRegistry([linked, optional], memoryStore()).storageKeys()).toEqual(['glyph-plugins', 'glyph-optional']);
  });

  it('ships Notion and Projects as standard, each within its manifest', () => {
    expect(BUILT_IN.map((p) => [p.manifest.id, p.manifest.standard])).toEqual([
      ['notion', true],
      ['projects', true],
    ]);
    for (const plugin of BUILT_IN) {
      const kinds = plugin.manifest.permissions.map((p) => p.kind);
      if (plugin.voice?.length || plugin.itemTargets?.length) expect(kinds).toContain('voice');
      if (plugin.manifest.native) expect(kinds).toContain('native');
      if (plugin.manifest.hosts?.length) expect(kinds).toContain('network');
    }
  });
});

describe('a plugin’s host', () => {
  it('calls only the native commands its manifest lists', async () => {
    const invoke = vi.fn(async () => 'answer');
    const host = createHost(manifest('n', { permissions: [{ kind: 'native', why: '' }], native: { generation: 1, commands: ['allowed'] } }), invoke as never);
    await expect(host.invoke('allowed')).resolves.toBe('answer');
    await expect(host.invoke('reset_local_data')).rejects.toBeInstanceOf(PluginPermissionError);
    expect(invoke).toHaveBeenCalledTimes(1);
  });

  it('refuses native calls without the native permission, even for a listed command', async () => {
    const host = createHost(manifest('n', { native: { generation: 1, commands: ['allowed'] } }), vi.fn() as never);
    await expect(host.invoke('allowed')).rejects.toBeInstanceOf(PluginPermissionError);
  });

  it('reads and writes only its own storage keys', () => {
    const host = createHost(manifest('s', { storage: ['glyph-mine'] }));
    host.storage.set('glyph-mine', { a: 1 });
    expect(host.storage.get('glyph-mine', null)).toEqual({ a: 1 });
    expect(() => host.storage.get('glyph-notes', null)).toThrow(PluginPermissionError);
    expect(() => host.storage.set('glyph-preferences', {})).toThrow(PluginPermissionError);
    host.storage.remove('glyph-mine');
    expect(host.storage.get('glyph-mine', 'gone')).toBe('gone');
  });

  it('asserts permissions it declared and refuses the rest', () => {
    const host = createHost(manifest('p', { permissions: [{ kind: 'network', why: '' }] }));
    expect(() => host.require('network')).not.toThrow();
    expect(() => host.require('ai')).toThrow(/didn't declare the “ai” permission/);
  });
});
