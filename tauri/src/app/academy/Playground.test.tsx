import { describe, expect, it, vi } from 'vitest';
import { rerender, show, typeInto } from '../../test/render.tsx';
import { Playground } from './Playground.tsx';

/**
 * The field under a lesson belongs to the phone's keyboard, not to React. A keyboard composes a word and commits it
 * on space; a field whose value is written back while it composes gets the letters committed twice (Matt: "when doing
 * the ## and then hitting space on the academy it shows an extra # and the lesson isn't passed"). So the Playground
 * writes into the field only when the app changed the text - Show me, a new lesson - and never with what was typed.
 */

/** The field, with every write into its value counted. */
function watched(field: HTMLTextAreaElement): { writes: string[] } {
  const own = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!;
  const seen = { writes: [] as string[] };
  Object.defineProperty(field, 'value', {
    configurable: true,
    get: () => own.get!.call(field),
    set: (text: string) => {
      seen.writes.push(text);
      own.set!.call(field, text);
    },
  });
  return seen;
}

describe('the Academy’s live page', () => {
  it('hands on what is typed and never writes it back into the field', () => {
    const onChange = vi.fn();
    const el = show(<Playground value="" onChange={onChange} placeholder="# Weekend trip" />);
    const field = el.querySelector('textarea')!;
    // Typed the way a keyboard types: straight into the field, which React then hears.
    typeInto(field, '##');
    expect(onChange).toHaveBeenLastCalledWith('##');
    const seen = watched(field);
    // The screen passes the text back down as it would after the change.
    rerender(<Playground value="##" onChange={onChange} placeholder="# Weekend trip" />);
    expect(seen.writes).toEqual([]);
    expect(field.value).toBe('##');
  });

  it('writes the text in when the app changes it: Show me, or a new lesson', () => {
    const el = show(<Playground value="" onChange={() => undefined} placeholder="# Weekend trip" />);
    const field = el.querySelector('textarea')!;
    typeInto(field, 'weekend');
    rerender(<Playground value="weekend" onChange={() => undefined} placeholder="# Weekend trip" />);
    const seen = watched(field);
    rerender(<Playground value="# Weekend trip" onChange={() => undefined} placeholder="# Weekend trip" />);
    expect(seen.writes).toEqual(['# Weekend trip']);
    expect(field.value).toBe('# Weekend trip');
    rerender(<Playground value="" onChange={() => undefined} placeholder="## The budget" />);
    expect(field.value).toBe('');
  });

  it('draws nothing typed as a line saying where it will appear', () => {
    const el = show(<Playground value="   " onChange={() => undefined} placeholder="# Weekend trip" />);
    expect(el.textContent).toContain('Whatever you type appears here');
  });
});
