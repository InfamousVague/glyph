import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A note handed to the phone's own store as another device has it (store.ts `applyNote`), on a binary: what
 * `store_apply` is sent. The binary reads src-tauri/src/note.rs `Note`, which up to native generation 25 refuses a note
 * with no `starred`, and a note made in a browser was stored and synced without one.
 */

const sent: { command: string; args: unknown }[] = [];
vi.mock('./tauri.ts', () => ({
  isTauri: () => true,
  invoke: async (command: string, args: unknown) => {
    sent.push({ command, args });
    return (args as { note?: unknown }).note ?? null;
  },
}));

const { applyNote } = await import('./store.ts');

beforeEach(() => {
  sent.length = 0;
});

describe('a note applied on a binary', () => {
  it('always says whether it is pinned, though the note that came did not', async () => {
    // As a browser stored one before it said the pin: no `starred` at all.
    await applyNote({ id: 'web-1', body: '# Made in a browser', createdAt: 1, updatedAt: 2, source: 'editor', revision: 1 });
    expect(sent).toEqual([{ command: 'store_apply', args: { note: { id: 'web-1', body: '# Made in a browser', createdAt: 1, updatedAt: 2, source: 'editor', revision: 1, starred: false } } }]);
  });

  it('keeps a pin that was there, and everything else as it came', async () => {
    const note = { id: 'n-2', body: 'Pinned', createdAt: 1, updatedAt: 2, source: 'capture' as const, starred: true, archivedAt: 5, recordingMs: 900, path: 'Inbox/Pinned.md' };
    await applyNote(note);
    expect(sent[0]!.args).toEqual({ note });
  });
});
