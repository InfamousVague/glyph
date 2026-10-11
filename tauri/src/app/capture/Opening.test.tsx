import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { Opening } from './Opening.tsx';

/** The recorder's picture while nothing has been heard (capture/Opening.tsx), and when the microphone never opened. */

describe('the recorder’s picture of sound beginning', () => {
  it('draws its three arcs, dashed when the microphone never opened', () => {
    const opening = show(<Opening />).querySelector('svg')!;
    expect(opening.querySelectorAll('path')).toHaveLength(3);
    expect(opening.dataset.failed).toBeUndefined();
    const failed = show(<Opening failed />).querySelector('svg')!;
    expect(failed.dataset.failed).toBe('');
    expect([...failed.querySelectorAll('path')].every((arc) => arc.getAttribute('stroke-dasharray') === '6 7')).toBe(true);
  });
});
