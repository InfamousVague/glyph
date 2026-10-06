import { expect, it } from 'vitest';
import { KIND_HUES, KINDS } from './kinds.ts';

/** Matt: "color code different notification icons so they're easier to match at first sight". */
it('gives every kind of notification one of the app’s hues, by what the news is', () => {
  for (const kind of KINDS) expect(['ember', 'amber', 'moss', 'sea', 'violet', 'rose']).toContain(KIND_HUES[kind]);
  expect(KIND_HUES['member-joined']).toBe(KIND_HUES['invite-accepted']);
  expect(KIND_HUES['member-left']).toBe(KIND_HUES['member-removed']);
  expect(KIND_HUES['member-joined']).not.toBe(KIND_HUES['member-left']);
  expect(KIND_HUES.invite).not.toBe(KIND_HUES['sync-conflict']);
});
