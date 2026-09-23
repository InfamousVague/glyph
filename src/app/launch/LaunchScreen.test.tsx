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

describe('the ghost on the screen', () => {
  it('draws two eyes over the picture, and turns them toward the bar as it goes round', () => {
    native = false;
    // The DOM here has no geometry and no frames: the ring answers with the point the test puts the bar at, and the
    // frames are run by hand.
    let target = { x: 124, y: 66 };
    const proto = SVGElement.prototype as unknown as { getTotalLength?: () => number; getPointAtLength?: (n: number) => DOMPoint };
    proto.getTotalLength = () => 400;
    proto.getPointAtLength = () => ({ x: target.x, y: target.y }) as DOMPoint;
    const frames: FrameRequestCallback[] = [];
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => frames.push(cb));
    vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => undefined);
    // A frame every 16 ms, up to `until`, as a screen draws them.
    let clock = 0;
    const run = (until: number) => {
      for (; clock < until; clock += 16) act(() => frames.shift()?.(clock));
    };
    show(<LaunchScreen loading notes={0} updates={updates()} sync={sync} onDone={() => {}} />);
    const eyes = [...host!.querySelectorAll('ellipse')];
    expect(eyes).toHaveLength(2);
    const moved = () => eyes.map((eye) => (eye.getAttribute('transform') ?? '').match(/-?\d+\.\d+/g)!.map(Number));
    clock = performance.now();
    const start = clock;
    run(start + 300);
    // The bar off to the right: both look right, and hardly up or down.
    for (const [x, y] of moved()) {
      expect(x).toBeGreaterThan(2);
      expect(Math.abs(y!)).toBeLessThan(0.5);
    }
    // The bar below them: both look down.
    target = { x: 72, y: 124 };
    run(start + 600);
    for (const [, y] of moved()) expect(y).toBeGreaterThan(2.5);
    // And the bar is moved on the same clock.
    expect(host!.querySelector('path[data-driven]')).toBeTruthy();
    raf.mockRestore();
    delete proto.getTotalLength;
    delete proto.getPointAtLength;
  });

  it('once the app is open, looks out of the screen and winks, then goes', () => {
    native = false;
    vi.useFakeTimers();
    const proto = SVGElement.prototype as unknown as { getTotalLength?: () => number; getPointAtLength?: (n: number) => DOMPoint };
    proto.getTotalLength = () => 400;
    proto.getPointAtLength = () => ({ x: 124, y: 66 }) as DOMPoint;
    const frames: FrameRequestCallback[] = [];
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => frames.push(cb));
    let clock = performance.now();
    // The frames, one every 16 ms, with the timers moved on alongside them.
    const run = (ms: number) => {
      for (let t = 0; t < ms; t += 16) {
        clock += 16;
        act(() => {
          vi.advanceTimersByTime(16);
          frames.shift()?.(clock);
        });
      }
    };
    const onDone = vi.fn();
    show(<LaunchScreen loading={false} notes={3} updates={updates()} sync={sync} onDone={onDone} />);
    const svg = host!.querySelector('svg')!;
    const eyes = [...host!.querySelectorAll('ellipse')];
    const moved = () => eyes.map((eye) => (eye.getAttribute('transform') ?? '').match(/-?\d+\.\d+/g)!.map(Number));
    // Watching the bar off to the right while the app opens.
    run(600);
    expect(svg.hasAttribute('data-finishing')).toBe(false);
    for (const [x] of moved()) expect(x).toBeGreaterThan(2);
    // Open: the bar goes, and the eyes come back to the middle, looking out.
    run(450);
    expect(svg.hasAttribute('data-finishing')).toBe(true);
    run(200);
    for (const [x, y] of moved()) {
      expect(Math.abs(x!)).toBeLessThan(0.5);
      expect(Math.abs(y!)).toBeLessThan(0.5);
    }
    // Then one eye winks, the one on the right, and only after that does the screen fade.
    run(100);
    const groups = [...svg.querySelectorAll('ellipse')].map((eye) => eye.parentElement!.getAttribute('class') ?? '');
    expect(groups[0]).toBe('');
    expect(groups[1]).toMatch(/wink/);
    expect(host!.querySelector('[data-leaving]')).toBeNull();
    run(400);
    expect(host!.querySelector('[data-leaving]')).not.toBeNull();
    expect(onDone).not.toHaveBeenCalled();
    run(300);
    expect(onDone).toHaveBeenCalledTimes(1);
    raf.mockRestore();
    delete proto.getTotalLength;
    delete proto.getPointAtLength;
  });
});
