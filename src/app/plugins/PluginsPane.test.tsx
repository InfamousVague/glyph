import { afterEach, describe, expect, it, vi } from 'vitest';
import { setPreferences } from '../core/preferences.ts';
import { button, press, show } from '../../test/render.tsx';
import type { SettingsTarget } from '../settings/SettingsScreen.tsx';
import { PluginsPane } from './PluginsPane.tsx';
import { reachLine } from './reach.ts';
import { manifest as claude } from './claude/index.tsx';
import { manifest as notion } from './notion/manifest.ts';

// The Glacier kit reads matchMedia as it loads; jsdom has none. Hoisted, so it is there before the imports run.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

afterEach(() => {
  setPreferences({ localOnly: false });
});

const cardOf = (pane: ParentNode, name: string) => Array.from(pane.querySelectorAll('section')).find((s) => s.querySelector('.setk-hero__title')?.textContent === name);

describe('Settings › Plugins', () => {
  it('has a card for every plugin that ships, Claude among them, each with its switch', () => {
    const pane = show(<PluginsPane />);
    const names = Array.from(pane.querySelectorAll('.setk-hero__title')).map((t) => t.textContent);
    expect(names).toEqual(['Plugins', 'Notion', 'GitHub', 'Marks', 'Claude', 'Library folder']);
    expect(pane.querySelector('[aria-label="Claude plugin"]')).not.toBeNull();
    // The Library folder is off until switched on: most people never move their notes.
    expect(pane.textContent).toContain('4 of 5 on');
    expect(pane.querySelector<HTMLInputElement>('[aria-label="Library folder plugin"]')?.checked).toBe(false);
    expect(pane.querySelector<HTMLInputElement>('[aria-label="Claude plugin"]')?.checked).toBe(true);
  });

  it('says what a plugin may reach in one line, and the reasons a press away', () => {
    expect(reachLine(notion)).toBe('Your notes · The internet (api.notion.com, ghostmarkdown.com) · Built-in app commands');
    expect(reachLine(claude)).toBe('Your notes · The internet (ghostmarkdown.com)');
    const pane = show(<PluginsPane />);
    const card = cardOf(pane, 'Claude')!;
    expect(card.textContent).toContain(reachLine(claude));
    expect(card.textContent).not.toContain(claude.permissions[0]!.why);
    press(button('Why', card));
    expect(card.textContent).toContain(claude.permissions[0]!.why);
    expect(button('Less', card)).toBeTruthy();
  });

  it('opens a plugin’s own page from its card', () => {
    const opened: SettingsTarget[] = [];
    const pane = show(<PluginsPane onOpen={(target) => opened.push(target)} />);
    const card = cardOf(pane, 'Claude')!;
    press(Array.from(card.querySelectorAll('button.setk-row--press')).find((b) => b.textContent?.includes('Read and write your notes from Claude')));
    expect(opened).toEqual([{ id: 'plugin:claude' }]);
  });

  // Changed on purpose (docs/DESIGN.md §138): "in Formatting" named a page; "Local only" is now a word that goes there.
  it('holds every plugin that uses the internet off under Local only, and its words open the switch', () => {
    setPreferences({ localOnly: true });
    const opened: SettingsTarget[] = [];
    const pane = show(<PluginsPane onOpen={(target) => opened.push(target)} />);
    expect(pane.querySelector('.setk-callout')?.textContent).toBe('Local only is on, so plugins that use the internet are held off until it is off.');
    press(pane.querySelector('.setk-callout .setk-go'));
    const notionCard = cardOf(pane, 'Notion')!;
    expect(notionCard.querySelector<HTMLButtonElement>('[aria-label="Notion plugin"]')?.disabled).toBe(true);
    expect(notionCard.textContent).toContain('Off while Local only is on');
    expect(notionCard.textContent).toContain('It uses the internet. Switch Local only off to use it.');
    press(notionCard.querySelector('.setk-go'));
    // Both land on Account, at the Privacy card, lit.
    expect(opened).toEqual([
      { id: 'account', setting: 'Privacy' },
      { id: 'account', setting: 'Privacy' },
    ]);
    // Marks reaches nothing past the phone, so it is not held.
    expect(cardOf(pane, 'Marks')!.textContent).not.toContain('Off while Local only is on');
  });

  it('says the internet plainly for a plugin that names no hosts', () => {
    expect(reachLine({ ...notion, hosts: [] })).toBe('Your notes · The internet · Built-in app commands');
  });
});
