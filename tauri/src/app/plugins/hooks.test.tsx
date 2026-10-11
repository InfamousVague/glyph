import { afterEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { press, rerender, show, unmount } from '../../test/render.tsx';
import { useNoteLinks, usePlugins } from './hooks.ts';
import { linkBoard } from './notion/client.ts';
import { plugins } from './registry.ts';

/**
 * The registry as a screen reads it (hooks.ts), with the real built-in plugins: a note's links drawn again when a
 * plugin writes what the note is linked to, and when a plugin is switched, which is how a board chosen from the cog
 * reaches the marks under the note's title (LinkMarks.tsx) without the note being opened again.
 */

const board = { id: 'b', title: 'Jobs', url: 'https://notion.so/b', titleProperty: 'Name', doneProperty: null };

/** A note's links as words: each link's id and what it names. */
function Links({ noteId }: { noteId: string }) {
  const links = useNoteLinks(noteId);
  return <p>{links.map(({ link, name }) => `${link.id}: ${name}`).join(', ')}</p>;
}

/** Which plugins are on, and a switch for GitHub. */
function Switches() {
  const { all, enabled, setEnabled } = usePlugins();
  const on = enabled.some((plugin) => plugin.manifest.id === 'github');
  return (
    <button type="button" data-all={all.length} onClick={() => setEnabled('github', !on)}>
      {enabled.map((plugin) => plugin.manifest.id).join(' ')}
    </button>
  );
}

afterEach(() => {
  // Down before the switches go back, so nothing drawn hears them.
  unmount();
  plugins.setEnabled('notion', true);
  plugins.setEnabled('github', true);
  localStorage.clear();
});

describe('useNoteLinks', () => {
  it('reads again when a plugin writes what the note is linked to', () => {
    const host = show(<Links noteId="n1" />);
    expect(host.textContent).toBe('');
    act(() => linkBoard('n1', board));
    expect(host.textContent).toBe('notion-board: Jobs');
    act(() => linkBoard('n1', null));
    expect(host.textContent).toBe('');
  });

  it('drops a plugin’s links while it is switched off, and brings them back when it is on', () => {
    linkBoard('n1', board);
    const host = show(<Links noteId="n1" />);
    expect(host.textContent).toBe('notion-board: Jobs');
    act(() => plugins.setEnabled('notion', false));
    expect(host.textContent).toBe('');
    act(() => plugins.setEnabled('notion', true));
    expect(host.textContent).toBe('notion-board: Jobs');
  });

  it('follows the note it is given', () => {
    linkBoard('n1', board);
    const host = show(<Links noteId="n1" />);
    rerender(<Links noteId="n2" />);
    expect(host.textContent).toBe('');
    rerender(<Links noteId="n1" />);
    expect(host.textContent).toBe('notion-board: Jobs');
  });
});

describe('usePlugins', () => {
  it('lists every plugin, and redraws with the ones on as a switch moves', () => {
    const button = show(<Switches />).querySelector('button')!;
    expect(button.dataset.all).toBe(String(plugins.all().length));
    expect(button.textContent).toContain('github');
    press(button);
    expect(button.textContent).not.toContain('github');
    expect(button.dataset.all).toBe(String(plugins.all().length));
    press(button);
    expect(button.textContent).toContain('github');
  });
});
