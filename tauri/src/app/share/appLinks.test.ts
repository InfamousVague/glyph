import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Links that opened the app are taken from the native side once the app has its notes, and again each time the side
 * says another has arrived, and from the activity's own memory of the link it was opened with, which the deep-link
 * plugin can miss in an activity recreated inside a live process; the same link from both is opened once. Every link
 * goes to the opener, which sorts the shares from the note links; nothing is done in a browser.
 */

const native = vi.hoisted(() => ({ on: true, kept: [] as string[][], heard: null as (() => void) | null, stopped: 0 }));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native.on,
  invoke: vi.fn(async (command: string) => {
    if (command !== 'links_take') throw new Error(`unexpected ${command}`);
    return native.kept.shift() ?? [];
  }),
}));
vi.mock('../core/events.ts', () => ({
  listenTo: vi.fn(async (event: string, handler: () => void) => {
    if (event === 'glyph://link') native.heard = handler;
    return () => {
      native.stopped += 1;
    };
  }),
}));

const { followAppLinks, readNoteLink } = await import('./appLinks.ts');
const share = `ghostmd://fork#${'a'.repeat(22)}.${'b'.repeat(43)}`;
const noteLink = 'ghostmd://note/m1';
/** The native side's answers and the listener are promises: let them land. */
const settle = async () => {
  for (let i = 0; i < 5; i += 1) await Promise.resolve();
};

beforeEach(() => {
  native.on = true;
  native.kept = [];
  native.heard = null;
  native.stopped = 0;
  delete window.GlyphHost;
});

describe('a note link', () => {
  it('names the note the notification’s tap opens, and nothing else does', () => {
    expect(readNoteLink('ghostmd://note/m1')).toBe('m1');
    expect(readNoteLink(' ghostmd://note/abc_DEF-123/ ')).toBe('abc_DEF-123');
    expect(readNoteLink('ghostmd://note/')).toBeNull();
    expect(readNoteLink('ghostmd://note/a b')).toBeNull();
    expect(readNoteLink('ghostmd://note/../x')).toBeNull();
    expect(readNoteLink(share)).toBeNull();
    expect(readNoteLink('https://attack.fm/glyph/note/m1')).toBeNull();
  });
});

describe('links that opened the app', () => {
  it('hands every link the native side kept to the opener, which sorts them', async () => {
    native.kept = [[share, noteLink, 'ghostmd://something-else']];
    const open = vi.fn();
    followAppLinks(open);
    await settle();
    expect(open.mock.calls).toEqual([[share], [noteLink], ['ghostmd://something-else']]);
  });

  it('takes the link the activity was opened with as well, once, and the same link from both roads once', async () => {
    let held: string | null = noteLink;
    window.GlyphHost = {
      takeLink: () => {
        const link = held ?? '';
        held = null;
        return link;
      },
    } as unknown as Window['GlyphHost'];
    native.kept = [[noteLink]];
    const open = vi.fn();
    followAppLinks(open);
    await settle();
    expect(open.mock.calls).toEqual([[noteLink]]);
    // The plugin missed the next one; the activity did not.
    held = 'ghostmd://note/m2';
    native.heard!();
    await settle();
    expect(open.mock.calls).toEqual([[noteLink], ['ghostmd://note/m2']]);
    // Nothing anywhere: nothing opened.
    native.heard!();
    await settle();
    expect(open).toHaveBeenCalledTimes(2);
  });

  it('still takes the activity’s link when the native side cannot answer', async () => {
    window.GlyphHost = { takeLink: () => noteLink } as unknown as Window['GlyphHost'];
    const { invoke } = await import('../core/tauri.ts');
    (invoke as ReturnType<typeof vi.fn>).mockImplementationOnce(async () => {
      throw new Error('an older binary');
    });
    const open = vi.fn();
    followAppLinks(open);
    await settle();
    expect(open.mock.calls).toEqual([[noteLink]]);
  });

  it('takes again when another arrives while the app runs, and stops listening when asked', async () => {
    const open = vi.fn();
    const stop = followAppLinks(open);
    await settle();
    expect(open).not.toHaveBeenCalled();
    native.kept = [[share]];
    native.heard!();
    await settle();
    expect(open).toHaveBeenCalledWith(share);
    stop();
    expect(native.stopped).toBe(1);
    // A take that answers after the stop opens nothing.
    native.kept = [[share]];
    native.heard!();
    await settle();
    expect(open).toHaveBeenCalledTimes(1);
  });

  it('does nothing in a browser', async () => {
    native.on = false;
    const open = vi.fn();
    followAppLinks(open)();
    await settle();
    expect(native.heard).toBeNull();
    expect(open).not.toHaveBeenCalled();
  });
});
