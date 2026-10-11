import { beforeEach, describe, expect, it, vi } from 'vitest';

let native = true;
const unlisten = vi.fn();
const heard = new Map<string, (message: { event: string; id: number; payload: unknown }) => void>();
const listen = vi.fn(async (event: string, handler: (message: { event: string; id: number; payload: unknown }) => void) => {
  heard.set(event, handler);
  return unlisten;
});

vi.mock('./tauri.ts', () => ({ isTauri: () => native }));
vi.mock('@tauri-apps/api/event', () => ({ listen }));

const { listenTo } = await import('./events.ts');

describe('listening to Rust', () => {
  beforeEach(() => {
    native = true;
    heard.clear();
    listen.mockClear();
    unlisten.mockClear();
  });

  it('hands the handler each event’s payload, not its envelope', async () => {
    const got: unknown[] = [];
    await listenTo<{ receivedBytes: number }>('capture://model-progress', (payload) => got.push(payload));
    heard.get('capture://model-progress')?.({ event: 'capture://model-progress', id: 7, payload: { receivedBytes: 10 } });
    heard.get('capture://model-progress')?.({ event: 'capture://model-progress', id: 7, payload: { receivedBytes: 20 } });
    expect(got).toEqual([{ receivedBytes: 10 }, { receivedBytes: 20 }]);
  });

  it('answers the way to stop listening', async () => {
    const stop = await listenTo('glyph://link', () => undefined);
    expect(listen).toHaveBeenCalledWith('glyph://link', expect.any(Function));
    stop();
    expect(unlisten).toHaveBeenCalledTimes(1);
  });

  it('rejects outside the webview, as invoke does, without asking to listen', async () => {
    native = false;
    await expect(listenTo('ai://progress', () => undefined)).rejects.toThrow(/no Tauri runtime for event "ai:\/\/progress"/);
    expect(listen).not.toHaveBeenCalled();
  });
});
