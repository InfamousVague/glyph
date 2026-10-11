import { describe, expect, it } from 'vitest';
import { rerender, show, unmount } from '../../test/render.tsx';
import { useRootStamp } from './useRootStamp.ts';

/**
 * The stamps the stylesheets read the Shell's layout from: on the page's root while there is a value, changed with
 * it, and gone when it is null or the Shell unmounts - a stamp left behind keeps sizing a tab bar that is not there.
 */

function Probe({ value }: { value: string | null }) {
  useRootStamp('tabs', value);
  return null;
}
const stamp = () => document.documentElement.getAttribute('data-tabs');

describe('a stamp on the root', () => {
  it('follows its value, and goes when the value is null', () => {
    show(<Probe value="on" />);
    expect(stamp()).toBe('on');
    rerender(<Probe value="rows" />);
    expect(stamp()).toBe('rows');
    rerender(<Probe value={null} />);
    expect(stamp()).toBeNull();
    rerender(<Probe value="on" />);
    expect(stamp()).toBe('on');
  });

  it('goes when the Shell unmounts', () => {
    show(<Probe value="rows" />);
    unmount();
    expect(stamp()).toBeNull();
  });
});
