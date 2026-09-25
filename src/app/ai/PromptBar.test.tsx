import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, buttonSaying, press, show, typeInto } from '../../test/render.tsx';
import { PromptBar } from './PromptBar.tsx';
import type { Availability } from './available.ts';

const ready: Availability = { ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' };
const buttons = (el: HTMLElement) => [...el.querySelectorAll('button')].map((b) => b.textContent?.trim());

describe('the prompt bar', () => {
  it('offers the six chips and sends a typed instruction', () => {
    const runs: unknown[] = [];
    const el = show(<PromptBar availability={ready} onRun={(...args) => runs.push(args)} scope={null} />);
    expect(buttons(el)).toEqual(['Format', 'Summarize', 'Enhance', 'Fix spelling', 'Make a list', 'Continue', '']);
    act(() => (el.querySelectorAll('button')[3] as HTMLButtonElement).click());
    expect(runs).toEqual([['fix', undefined, null]]);
    const field = el.querySelector('input') as HTMLInputElement;
    typeInto(field, 'make it shorter');
    act(() => el.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })));
    expect(runs[1]).toEqual(['ask', 'make it shorter', null]);
    expect(field.value).toBe('');
  });

  it('asks which part when words are selected, and runs on the part or the note', () => {
    const runs: unknown[] = [];
    const used = vi.fn();
    const el = show(<PromptBar availability={ready} onRun={(...args) => runs.push(args)} scope={{ from: 4, to: 20 }} onScopeUsed={used} />);
    act(() => (el.querySelectorAll('button')[0] as HTMLButtonElement).click());
    expect(runs).toEqual([]);
    expect(el.textContent).toContain('Format, on');
    act(() => button('This part', el).click());
    expect(runs).toEqual([['format', undefined, { from: 4, to: 20 }]]);
    expect(used).toHaveBeenCalled();
  });

  it('shows the reason, greyed, where the AI cannot run, and offers the model to get', () => {
    const got: string[] = [];
    const el = show(
      <PromptBar
        availability={{ ok: false, reason: 'The AI needs a model on the phone. It runs here; nothing leaves the phone.', get: 'qwen3.5-4b', waiting: false }}
        onRun={() => undefined}
        onGet={(id) => got.push(id)}
        scope={null}
      />,
    );
    const field = el.querySelector('input') as HTMLInputElement;
    expect(field.disabled).toBe(true);
    expect(field.placeholder).toContain('needs a model');
    expect(buttons(el).some((b) => b?.startsWith('Get Qwen3.5 4B'))).toBe(true);
    press(buttonSaying(el, 'Get Qwen3.5 4B'));
    expect(got).toEqual(['qwen3.5-4b']);
    expect((el.querySelectorAll('button')[0] as HTMLButtonElement).disabled).toBe(true);
  });

  it('puts itself away with its spark, where it is given a way to, and keeps a plain spark where it is not', () => {
    const hid = vi.fn();
    const el = show(<PromptBar availability={ready} onRun={() => {}} scope={null} onHide={hid} />);
    const spark = el.querySelector<HTMLButtonElement>('button[aria-label="Hide the AI bar"]');
    expect(spark?.getAttribute('aria-expanded')).toBe('true');
    act(() => spark!.click());
    expect(hid).toHaveBeenCalledTimes(1);
    act(() => root!.render(<PromptBar availability={ready} onRun={() => {}} scope={null} />));
    expect(el.querySelector('button[aria-label="Hide the AI bar"]')).toBeNull();
  });

  it('steps out where there is nothing to ask on', () => {
    const el = show(<PromptBar availability={ready} onRun={() => undefined} scope={null} disabled />);
    expect(el.textContent).toBe('');
  });
});
