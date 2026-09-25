import { describe, expect, it, vi } from 'vitest';
import { createHost, onPluginStorage, PluginPermissionError } from './host.ts';
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

  it('ships Notion, GitHub, Marks and Claude as standard, each within its manifest', () => {
    expect(BUILT_IN.map((p) => [p.manifest.id, p.manifest.standard])).toEqual([
      ['notion', true],
      ['github', true],
      ['marks', true],
      ['claude', true],
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

  it('tells what draws from a plugin’s storage once a change is made, a removal as much as a write', () => {
    const host = createHost(manifest('t', { storage: ['glyph-told'] }));
    const heard: unknown[] = [];
    const stop = onPluginStorage(() => heard.push(host.storage.get('glyph-told', 'gone')));
    host.storage.set('glyph-told', { a: 1 });
    host.storage.remove('glyph-told');
    stop();
    host.storage.set('glyph-told', 2);
    expect(heard, 'each listener reads what the change left, not what was there before it').toEqual([{ a: 1 }, 'gone']);
  });

  it('parses a key once for as long as its stored text is the same, and again as soon as anything changes it', () => {
    const host = createHost(manifest('c', { storage: ['glyph-cached'] }));
    host.storage.set('glyph-cached', { links: { n1: 'b1' } });
    const first = host.storage.get<{ links: Record<string, string> }>('glyph-cached', { links: {} });
    // The same text: the same parsed value, not a fresh parse.
    expect(host.storage.get('glyph-cached', null)).toBe(first);
    // Written behind the host's back (a reset, another tab): the text differs, so it is read again.
    localStorage.setItem('glyph-cached', JSON.stringify({ links: { n2: 'b2' } }));
    expect(host.storage.get('glyph-cached', null)).toEqual({ links: { n2: 'b2' } });
    // Written through the host: the next read is the new value.
    host.storage.set('glyph-cached', { links: {} });
    expect(host.storage.get('glyph-cached', null)).toEqual({ links: {} });
    host.storage.remove('glyph-cached');
    expect(host.storage.get('glyph-cached', 'gone')).toBe('gone');
  });

  it('asserts permissions it declared and refuses the rest', () => {
    const host = createHost(manifest('p', { permissions: [{ kind: 'network', why: '' }] }));
    expect(() => host.require('network')).not.toThrow();
    expect(() => host.require('ai')).toThrow(/didn't declare the “ai” permission/);
  });
});

describe('what plugins offer on a note’s lines', () => {
  const offering: GlyphPlugin = {
    manifest: manifest('offering', { permissions: [{ kind: 'notes', why: '' }] }),
    icon: Icon,
    suggest: (noteId, body) => (noteId === 'n1' && body.includes('- [ ]') ? [{ line: 1, label: 'Notion', busyLabel: 'Sending', run: () => Promise.resolve() }] : []),
  };
  const quiet: GlyphPlugin = {
    manifest: manifest('quiet', { standard: false, permissions: [{ kind: 'notes', why: '' }] }),
    icon: Icon,
    suggest: () => [{ line: 2, label: 'Quiet', busyLabel: 'Quiet', run: () => Promise.resolve() }],
  };

  it('gathers the words of the switched-on plugins for the note as it stands', () => {
    const registry = createRegistry([offering, quiet], memoryStore());
    expect(registry.suggestions('n1', '- [ ] milk').map((s) => s.label)).toEqual(['Notion']);
    expect(registry.suggestions('n1', 'plain')).toEqual([]);
    expect(registry.suggestions('n2', '- [ ] milk')).toEqual([]);
  });

  it('refuses a plugin that offers words without the notes permission', () => {
    const overreach: GlyphPlugin = { manifest: manifest('overreach'), icon: Icon, suggest: () => [] };
    expect(() => createRegistry([overreach], memoryStore())).toThrow(PluginPermissionError);
  });
});

describe('Local only', () => {
  const online: GlyphPlugin = { manifest: manifest('online', { permissions: [{ kind: 'network', why: '' }], hosts: ['api.example'] }), icon: Icon };
  const offline: GlyphPlugin = { manifest: manifest('offline'), icon: Icon };

  it('turns off every plugin that uses the network, and tells listeners, until it is turned off again', async () => {
    const { setPreferences } = await import('../core/preferences.ts');
    const registry = createRegistry([online, offline], memoryStore());
    const heard = vi.fn();
    registry.subscribe(heard);
    expect(registry.enabled().map((p) => p.manifest.id)).toEqual(['online', 'offline']);
    setPreferences({ localOnly: true });
    expect(registry.enabled().map((p) => p.manifest.id)).toEqual(['offline']);
    expect(registry.isEnabled('online')).toBe(false);
    expect(heard).toHaveBeenCalled();
    setPreferences({ localOnly: false });
    expect(registry.enabled().map((p) => p.manifest.id)).toEqual(['online', 'offline']);
  });
});

describe('what a note is linked to', () => {
  const boards: GlyphPlugin = {
    manifest: manifest('boards'),
    icon: Icon,
    noteLinks: [{ id: 'board', label: 'Board', icon: Icon, hint: () => '', Picker: () => null, linked: (id) => (id === 'n1' ? 'Ghost.md Tasks' : null) }],
  };
  const repos: GlyphPlugin = {
    manifest: manifest('repos', { standard: false }),
    icon: Icon,
    noteLinks: [{ id: 'repo', label: 'Repo', icon: Icon, hint: () => '', Picker: () => null, linked: () => 'attackfm/app' }],
  };

  it('names each link from every switched-on plugin, and nothing for a note without one', () => {
    const registry = createRegistry([boards, repos], memoryStore({ repos: true }));
    expect(registry.linksOf('n1').map((l) => `${l.link.label}: ${l.name}`)).toEqual(['Board: Ghost.md Tasks', 'Repo: attackfm/app']);
    expect(registry.linksOf('n2').map((l) => l.name)).toEqual(['attackfm/app']);
    registry.setEnabled('repos', false);
    expect(registry.linksOf('n2')).toEqual([]);
  });

  it("offers the formattings of switched-on plugins only, and refuses a delimiter Markdown already uses", () => {
    const shout: GlyphPlugin = { manifest: manifest('shout'), icon: Icon, formats: [{ name: 'Shout', delimiter: '==', look: { kind: 'style', css: 'text-transform: uppercase' } }] };
    const registry = createRegistry([shout], memoryStore());
    expect(registry.formats().map((f) => f.name)).toEqual(['Shout']);
    registry.setEnabled('shout', false);
    expect(registry.formats()).toEqual([]);
    const bold: GlyphPlugin = { manifest: manifest('bold'), icon: Icon, formats: [{ name: 'Louder', delimiter: '**', look: { kind: 'wisp' } }] };
    expect(() => createRegistry([bold], memoryStore())).toThrow(/delimiter/);
    const lower: GlyphPlugin = { manifest: manifest('lower'), icon: Icon, formats: [{ name: 'shout', delimiter: '==', look: { kind: 'wisp' } }] };
    expect(() => createRegistry([lower], memoryStore())).toThrow(/capitalised/);
  });

  it('takes an emoji twice as an effect\'s delimiter, and not once, three times, or an emoji with words', () => {
    const effect = (delimiter: string): GlyphPlugin => ({
      manifest: manifest('effects'),
      icon: Icon,
      formats: [{ name: 'Glow', delimiter, look: { kind: 'effect', effect: 'heat' } }],
    });
    for (const delimiter of ['🔥🔥', '❄️❄️', '✨✨']) expect(() => createRegistry([effect(delimiter)], memoryStore()), delimiter).not.toThrow();
    for (const delimiter of ['🔥', '🔥🔥🔥', '🔥❄️', 'a🔥a🔥']) expect(() => createRegistry([effect(delimiter)], memoryStore()), delimiter).toThrow(/delimiter/);
  });
});

describe('what the registry gathers from the plugins that are on', () => {
  const noted = (id: string, over: Partial<GlyphPlugin> = {}): GlyphPlugin => ({ manifest: manifest(id, { permissions: [{ kind: 'notes', why: '' }] }), icon: Icon, ...over });
  const action = (id: string, available: (noteId: string) => boolean) => ({ id, label: id, busyLabel: '…', available, run: () => Promise.resolve() });

  it('offers a note the first switched-on plugin’s item action that is available for it', () => {
    const registry = createRegistry(
      [noted('a', { itemAction: action('a-send', (n) => n === 'n1') }), noted('b', { itemAction: action('b-send', () => true) })],
      memoryStore(),
    );
    expect(registry.itemAction('n1')?.id).toBe('a-send');
    expect(registry.itemAction('n2')?.id).toBe('b-send');
    registry.setEnabled('b', false);
    expect(registry.itemAction('n2')).toBeNull();
  });

  it('lists note actions and tips in the plugins’ order, and joins their context for the formatter', () => {
    const cog = (id: string) => ({ id, label: id, icon: Icon, visible: () => true, hint: () => '', enabled: () => true, run: () => Promise.resolve() });
    const registry = createRegistry(
      [
        noted('a', { noteActions: [cog('a1')], tips: () => [{ say: 'Send that to A', does: 'to send it' }], formatContext: { for: () => 'About A.', version: () => 1 } }),
        noted('b', { noteActions: [cog('b1'), cog('b2')], formatContext: { for: () => '  ', version: () => 0 } }),
        noted('c', { formatContext: { for: () => 'About C.', version: () => 2 } }),
      ],
      memoryStore(),
    );
    expect(registry.noteActions().map((a) => a.id)).toEqual(['a1', 'b1', 'b2']);
    expect(registry.tips(null)).toEqual([{ say: 'Send that to A', does: 'to send it' }]);
    // A context that is only space says nothing, and is not joined in.
    expect(registry.contextFor('n1')).toBe('About A.\n\nAbout C.');
    registry.setEnabled('a', false);
    registry.setEnabled('c', false);
    expect(registry.contextFor('n1')).toBeNull();
    expect(registry.noteActions().map((a) => a.id)).toEqual(['b1', 'b2']);
  });
});
