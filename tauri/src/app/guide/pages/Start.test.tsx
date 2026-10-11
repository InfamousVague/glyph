import { describe, expect, it, vi } from 'vitest';
import { button, press, show } from '../../../test/render.tsx';
import { Start } from './Start.tsx';

/** The last page: the Academy offered, and nothing left to read. */
describe('the guide’s last page', () => {
  it('offers the Academy for the rest, and says the home page offers it too', () => {
    const onAcademy = vi.fn();
    const el = show(<Start onAcademy={onAcademy} />);
    expect(el.textContent).toContain('Learn it, or just start.');
    expect(el.textContent).toContain('find it on the home page');
    press(button('Take the Ghost.md Academy', el));
    expect(onAcademy).toHaveBeenCalledTimes(1);
    // No side key, no habits: those pages are gone, and nothing here is a step to follow.
    expect(el.querySelector('ol')).toBeNull();
    expect(el.textContent).not.toMatch(/side key|habit/i);
  });
});
