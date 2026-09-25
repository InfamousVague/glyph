import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { act, useRef } from 'react';
import { rerender, show, unmount } from '../../test/render.tsx';
import { useReportedHeight } from './useReportedHeight.ts';

/** A ResizeObserver the test resizes by hand: jsdom has none, and lays nothing out to resize. */
const watching = new Set<() => void>();
const had = globalThis.ResizeObserver;
beforeAll(() => {
  globalThis.ResizeObserver = class {
    private readonly tell: () => void;
    constructor(callback: ResizeObserverCallback) {
      this.tell = () => callback([], this as unknown as ResizeObserver);
    }
    observe(): void {
      watching.add(this.tell);
    }
    unobserve(): void {}
    disconnect(): void {
      watching.delete(this.tell);
    }
  } as unknown as typeof ResizeObserver;
});
afterAll(() => {
  globalThis.ResizeObserver = had;
});

let height = 40;
function Floating({ drawn, onHeight }: { drawn: boolean; onHeight: (height: number) => void }) {
  const host = useRef<HTMLElement>(null);
  useReportedHeight(host, onHeight, drawn);
  if (!drawn) return null;
  return (
    <section
      ref={(el) => {
        host.current = el;
        if (el) Object.defineProperty(el, 'offsetHeight', { configurable: true, get: () => height });
      }}
    />
  );
}

describe('a floating piece telling the page its height', () => {
  it('tells it now, again as it resizes, and 0 once it steps out or is gone', () => {
    height = 40;
    const told: number[] = [];
    const onHeight = (h: number) => told.push(h);
    show(<Floating drawn onHeight={onHeight} />);
    expect(told).toEqual([40]);
    height = 64;
    act(() => watching.forEach((tell) => tell()));
    expect(told).toEqual([40, 64]);
    rerender(<Floating drawn={false} onHeight={onHeight} />);
    expect(told.slice(-2)).toEqual([0, 0]);
    expect(watching.size).toBe(0);
    rerender(<Floating drawn onHeight={onHeight} />);
    expect(told.at(-1)).toBe(64);
    unmount();
    expect(told.at(-1)).toBe(0);
    expect(watching.size).toBe(0);
  });
});
