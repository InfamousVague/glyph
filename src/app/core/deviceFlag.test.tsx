import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { deviceFlag, type DeviceFlag } from './deviceFlag.ts';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
beforeEach(() => localStorage.clear());
afterEach(() => {
  if (root) act(() => root!.unmount());
  host?.remove();
  root = null;
  host = null;
  vi.restoreAllMocks();
});

function Shows({ flag }: { flag: DeviceFlag }) {
  return <span>{flag.use() ? 'on' : 'off'}</span>;
}

describe('a switch kept on this device', () => {
  it('reads on, off, and its default for anything else', () => {
    const flag = deviceFlag('glyph-switch');
    expect(flag.read()).toBe(false);
    localStorage.setItem('glyph-switch', 'on');
    expect(flag.read()).toBe(true);
    localStorage.setItem('glyph-switch', 'sideways');
    expect(flag.read()).toBe(false);
    expect(deviceFlag('glyph-switch', true).read()).toBe(true);
    localStorage.setItem('glyph-switch', 'off');
    expect(deviceFlag('glyph-switch', true).read()).toBe(false);
  });

  it('keeps on as on, and off as nothing where off is the default, or as off where it is not', () => {
    const offByDefault = deviceFlag('glyph-a');
    offByDefault.set(true);
    expect(localStorage.getItem('glyph-a')).toBe('on');
    offByDefault.set(false);
    expect(localStorage.getItem('glyph-a')).toBeNull();
    const onByDefault = deviceFlag('glyph-b', true);
    onByDefault.set(false);
    expect(localStorage.getItem('glyph-b')).toBe('off');
    expect(onByDefault.read()).toBe(false);
    onByDefault.set(true);
    expect(localStorage.getItem('glyph-b')).toBe('on');
  });

  it('changes every component that shows it the moment it is flipped', () => {
    const flag = deviceFlag('glyph-switch');
    host = document.createElement('div');
    document.body.append(host);
    root = createRoot(host);
    act(() =>
      root!.render(
        <>
          <Shows flag={flag} />
          <Shows flag={flag} />
        </>,
      ),
    );
    expect(host.textContent).toBe('offoff');
    act(() => flag.set(true));
    expect(host.textContent).toBe('onon');
  });

  it('reads back as not kept when storage will not keep it', () => {
    const flag = deviceFlag('glyph-switch');
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('Quota exceeded', 'QuotaExceededError');
    });
    flag.set(true);
    expect(flag.read()).toBe(false);
  });

  it('reads off in a render with no client, whatever its default', () => {
    expect(renderToString(<Shows flag={deviceFlag('glyph-switch', true)} />)).toBe('<span>off</span>');
  });
});
