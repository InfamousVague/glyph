import { describe, expect, it, vi } from 'vitest';
import { quietHost } from '../../test/takeHost.ts';
import type { TakeNote } from './offers.ts';
import { Take } from './take.ts';
import { hostThrough, type TakeHost } from './takeHost.ts';

/** The host a recorder hands its take (capture/takeHost.ts `hostThrough`): always the newest render's. */

describe('a host through a ref', () => {
  it('reaches whichever host the ref holds when the take asks, not the one it held when the take was made', () => {
    const first = vi.fn();
    const second = vi.fn();
    const ref: { current: TakeHost<TakeNote> } = { current: quietHost({ said: first }) };
    const take = new Take(hostThrough(ref));
    take.listen({ text: 'One.', startMs: 0, endMs: 500 });
    ref.current = quietHost({ said: second });
    take.listen({ text: 'Two.', startMs: 600, endMs: 900 });
    expect(first).toHaveBeenCalledWith('One.');
    expect(second).toHaveBeenCalledWith('Two.');
    expect(first).toHaveBeenCalledOnce();
  });

  it('has the command model once it has been found, and not before', () => {
    const understand = () => ({ done: Promise.resolve(null), cancel: () => undefined });
    const ref: { current: TakeHost<TakeNote> } = { current: quietHost() };
    const host = hostThrough(ref);
    expect(host.understand).toBeUndefined();
    ref.current = quietHost({ understand });
    expect(host.understand).toBe(understand);
  });
});
