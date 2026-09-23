import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Updates } from '../core/ota.ts';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let native = false;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native }));
const { LaunchScreen } = await import('./LaunchScreen.tsx');

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  vi.useRealTimers();
});

const updates = (over: Partial<Updates> = {}): Updates =>
  ({ ready: null, apk: { kind: 'none' }, checking: false, lastError: null, lastChecked: null, status: null, build: 'b', version: 'v', check: vi.fn(), reload: vi.fn(), installApk: vi.fn(), ...over }) as Updates;
const sync = { phase: 'off' as const, lastAt: null, message: null, conflicts: 0 };

function show(element: React.ReactElement) {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(element));
}
const text = () => host!.textContent ?? '';

describe('the screen opening shows', () => {
  it('says what it is doing, ticks each step off, asks for the update check at once, and hands over when done', () => {
    vi.useFakeTimers();
    native = true;
    const onDone = vi.fn();
    const first = updates();
    show(<LaunchScreen loading notes={0} updates={first} sync={sync} onDone={onDone} />);
    expect(first.check).toHaveBeenCalledTimes(1);
    expect(text()).toContain('Opening your notes');
    // The check starts, then answers; the notes are read.
    act(() => root!.render(<LaunchScreen loading={false} notes={12} updates={updates({ checking: true })} sync={{ ...sync, phase: 'syncing' }} onDone={onDone} />));
    expect(text()).toContain('12 notes');
    expect(text()).toContain('Checking for updates');
    expect(text()).toContain('Syncing your devices');
    act(() => root!.render(<LaunchScreen loading={false} notes={12} updates={updates({ lastChecked: 1 })} sync={{ ...sync, phase: 'idle' }} onDone={onDone} />));
    expect(text()).toContain('Up to date');
    expect(text()).toContain('In sync');
    act(() => void vi.advanceTimersByTime(1000));
    // React renders once at the end of a jump in fake time, so the fade starts then: one more step for it.
    expect(onDone).not.toHaveBeenCalled();
    act(() => void vi.advanceTimersByTime(300));
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it('shows no update line where no check runs, and doesn’t wait for one', () => {
    vi.useFakeTimers();
    native = true;
    const onDone = vi.fn();
    show(<LaunchScreen loading={false} notes={3} updates={updates()} sync={sync} onDone={onDone} />);
    act(() => void vi.advanceTimersByTime(600));
    expect(text()).not.toContain('Checking for updates');
    act(() => void vi.advanceTimersByTime(700));
    act(() => void vi.advanceTimersByTime(300));
    expect(onDone).toHaveBeenCalledTimes(1);
  });
});
