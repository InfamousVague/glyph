import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { rerender, show } from '../../test/render.tsx';

/**
 * A shared link that opened the app is saved once, and only once the notes are read: from the web app's `#fork=`,
 * which then leaves the address, and from the native side's `ghostmd://` links, however many arrive.
 */

const links = vi.hoisted(() => ({ open: null as ((link: string) => void) | null, stopped: 0 }));
vi.mock('../share/appLinks.ts', () => ({
  followAppLinks: (open: (link: string) => void) => {
    links.open = open;
    return () => {
      links.stopped += 1;
    };
  },
}));

const { useForkLinks } = await import('./useForkLinks.ts');

function Probe({ loading, fork }: { loading: boolean; fork: (link: string) => Promise<void> }) {
  useForkLinks(loading, fork);
  return null;
}

beforeEach(() => {
  links.open = null;
  links.stopped = 0;
  history.replaceState(null, '', '/');
});

describe('a shared link arriving', () => {
  it('in the address is saved once the notes are read, once, and taken out of the address', () => {
    history.replaceState(null, '', '/glyph/?x=1#fork=https://attack.fm/glyph/read.html#abc.def');
    const fork = vi.fn(async () => undefined);
    show(<Probe loading fork={fork} />);
    expect(fork).not.toHaveBeenCalled();
    rerender(<Probe loading={false} fork={fork} />);
    expect(fork).toHaveBeenCalledWith('https://attack.fm/glyph/read.html#abc.def');
    expect(location.pathname + location.search + location.hash).toBe('/glyph/?x=1');
    rerender(<Probe loading fork={fork} />);
    rerender(<Probe loading={false} fork={fork} />);
    expect(fork).toHaveBeenCalledTimes(1);
  });

  it('in the address is saved once even where the address cannot be rewritten', () => {
    history.replaceState(null, '', '/#fork=https://attack.fm/glyph/read.html#abc.def');
    // The link stays in the address, so only the hook's own memory stops a second copy.
    const rewrite = vi.spyOn(history, 'replaceState').mockImplementation(() => undefined);
    const fork = vi.fn(async () => undefined);
    try {
      show(<Probe loading={false} fork={fork} />);
      rerender(<Probe loading fork={fork} />);
      rerender(<Probe loading={false} fork={fork} />);
      expect(location.hash).toBe('#fork=https://attack.fm/glyph/read.html#abc.def');
      expect(fork).toHaveBeenCalledTimes(1);
    } finally {
      rewrite.mockRestore();
    }
  });

  it('from the native side is followed once the notes are read, by the saver of the moment it arrives', () => {
    const first = vi.fn(async () => undefined);
    const second = vi.fn(async () => undefined);
    show(<Probe loading fork={first} />);
    expect(links.open).toBeNull();
    rerender(<Probe loading={false} fork={first} />);
    rerender(<Probe loading={false} fork={second} />);
    act(() => links.open!('ghostmd://fork#abc.def'));
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledWith('ghostmd://fork#abc.def');
  });

  it('says in the console, and nowhere else, when a copy could not be saved', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const fork = vi.fn(async () => {
      throw new Error('offline');
    });
    show(<Probe loading={false} fork={fork} />);
    await act(async () => links.open!('ghostmd://fork#abc.def'));
    expect(warn).toHaveBeenCalledWith('[glyph] could not save the shared copy:', expect.any(Error));
    warn.mockRestore();
  });
});
