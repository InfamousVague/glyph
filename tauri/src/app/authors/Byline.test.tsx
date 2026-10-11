import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { Byline } from './Byline.tsx';

const marks = (el: HTMLElement) => [...el.querySelectorAll<HTMLElement>('[title]')];

describe('the byline', () => {
  it('names the authors as a sentence says them', () => {
    expect(show(<Byline authors={['matt']} />).textContent).toContain('By matt');
    expect(show(<Byline authors={['matt', 'Claude']} />).textContent).toContain('By matt and Claude');
    const three = show(<Byline authors={['matt', 'Sam', 'Claude']} />);
    expect(three.textContent).toContain('By matt, Sam and Claude');
    expect(three.querySelector('p')?.getAttribute('aria-label')).toBe('Written by matt, Sam and Claude');
  });

  it('draws a person as their initial and an AI it knows as its spark', () => {
    const el = show(<Byline authors={['matt', 'Claude', 'Ghost', 'Hal']} />);
    const [person, claude, ghost, unknown] = marks(el);
    expect(person?.textContent).toBe('M');
    expect(person?.dataset.ai).toBeUndefined();
    for (const ai of [claude, ghost]) {
      expect(ai?.dataset.ai).toBe('true');
      expect(ai?.querySelector('svg')).not.toBeNull();
    }
    // A name the app does not know as an AI's is drawn like a person's.
    expect(unknown?.textContent).toBe('H');
  });

  it('draws four marks at most, and names everyone', () => {
    const el = show(<Byline authors={['a', 'b', 'c', 'd', 'e']} />);
    expect(marks(el).map((m) => m.title)).toEqual(['a', 'b', 'c', 'd']);
    expect(el.textContent).toContain('By a, b, c, d and e');
  });

  it('draws nothing for a note with no authors, which is the person’s own', () => {
    expect(show(<Byline authors={[]} />).innerHTML).toBe('');
  });
});
