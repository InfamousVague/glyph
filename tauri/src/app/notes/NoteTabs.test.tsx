import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useState, type ComponentProps } from 'react';
import { canvasNoteBody } from '../canvas/jsonCanvas.ts';
import { goBack } from '../core/back.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show, typeInto, waitUntil } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';
import { NO_GROUPS, type TabGroups } from './tabGroups.ts';

/**
 * The app's top bar: the controls, the tabs and the gesture on them. The rules of where a dragged tab lands are
 * notes/tabDrag.ts's and tested there; this is the bar as a person meets it - which press opens, closes, moves or
 * offers a menu, and which press is swallowed because it ended a drag.
 */

// The Glacier kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
/** The tick a menu opened by holding says (core/haptics.ts), counted. */
const held = vi.hoisted(() => vi.fn());
vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), tickHeld: held }));
const { NoteTabs } = await import('./NoteTabs.tsx');

// The row watches its own size and its ends; jsdom lays nothing out, so nothing ever resizes.
stubResizeObserver();

type Props = ComponentProps<typeof NoteTabs>;
const notes = [makeNote('a', '# Apples'), makeNote('b', '# Bread'), makeNote('c', '# Cheese')];
const bar = (over: Partial<Props> = {}) => <NoteTabs tabs={notes} activeId="a" onOpen={() => undefined} onClose={() => undefined} onSidebar={() => undefined} {...over} />;

/** Every tab laid out a hundred pixels wide from the left, in the order drawn: jsdom has no layout of its own. */
function layOut() {
  return vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    const row = this.closest('[role="tablist"]');
    const items = row ? [...row.querySelectorAll('[data-tab], [data-group-chip], [data-new-tab]')] : [];
    const at = items.indexOf(this);
    const left = at < 0 ? 0 : at * 100;
    return new DOMRect(left, 0, at < 0 ? 0 : 100, 30);
  });
}
const tab = (id: string) => document.querySelector<HTMLElement>(`[data-tab-id="${id}"]`)!;
const pointer = (type: string, target: EventTarget, x: number, pointerType = 'mouse') =>
  act(() => {
    target.dispatchEvent(new PointerEvent(type, { bubbles: true, clientX: x, pointerType, button: 0 }));
  });
const menuItems = () => [...document.querySelectorAll('[role="menuitem"]')].map((item) => item.textContent?.trim());
/** A menu row by its whole name: its label where it has one (a row under a name), else its words. */
const menuRow = (name: string) =>
  [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => (item.getAttribute('aria-label') ?? item.textContent?.trim()) === name);
/** What a menu hands its owner a microtask after it closes (editor/PopMenu.tsx), heard, and drawn. */
const settle = () => act(async () => undefined);

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  // The outline's tests stand in an `animate` and ask for less motion; a failed assertion must not leave either behind.
  delete (HTMLElement.prototype as Partial<HTMLElement>).animate;
  stubMatchMedia(false);
});

describe('the top bar', () => {
  it('draws nothing when it has no controls and no tabs', () => {
    const host = show(<NoteTabs tabs={[]} activeId="" onOpen={() => undefined} onClose={() => undefined} />);
    expect(host.innerHTML).toBe('');
  });

  it('has no tab row with nothing open, and its controls still', () => {
    show(bar({ tabs: [], onHome: () => undefined }));
    expect(document.querySelector('[role="tablist"]')).toBeNull();
    expect(button('Home')).toBeTruthy();
    expect(button('All your notes')).toBeTruthy();
  });

  it('opens a tab on a tap, closes it on its cross, and marks the one being read', () => {
    const onOpen = vi.fn();
    const onClose = vi.fn();
    show(bar({ onOpen, onClose }));
    expect(document.querySelector('[role="tab"][aria-selected="true"]')?.textContent).toBe('Apples');
    act(() => button('Bread').click());
    expect(onOpen).toHaveBeenCalledWith('b');
    act(() => button('Close Cheese').click());
    expect(onClose).toHaveBeenCalledWith('c');
  });

  // The bell (docs/TEAMS.md): after the two arrows, a dot and no number while something unread waits.
  it('rings a bell at the right end, after Organizations, that opens the notifications, with a dot while something is unread', () => {
    const onNotifications = vi.fn();
    const onOrganizations = vi.fn();
    show(bar({ onGoBack: () => undefined, onGoOn: () => undefined, onNotifications, onOrganizations }));
    const bell = button('Notifications');
    // Organizations, then the bell, then the screen's More (Matt: "make an organizations entrypoint as a group of
    // users icon next to the bell, move the notification bell all the way to the right just before the vertical dots").
    expect(bell.previousElementSibling?.getAttribute('aria-label')).toBe('Organizations');
    expect(bell.nextElementSibling?.className).toContain('tail');
    act(() => button('Organizations').click());
    expect(onOrganizations).toHaveBeenCalledOnce();
    expect(bell.hasAttribute('data-on')).toBe(false);
    expect(bell.hasAttribute('data-unread')).toBe(false);
    expect(bell.textContent).toBe('');
    act(() => bell.click());
    expect(onNotifications).toHaveBeenCalledOnce();
    rerender(bar({ onGoBack: () => undefined, onGoOn: () => undefined, onNotifications, unread: true }));
    const ringing = button('Notifications, something new');
    expect(ringing.hasAttribute('data-on')).toBe(true);
    expect(ringing.hasAttribute('data-unread')).toBe(true);
    expect(ringing.textContent).toBe('');
    // With its drawer open the bell is lit and says so; it is the drawer's toggle, which a press outside it skips.
    expect(ringing.getAttribute('aria-expanded')).toBe('false');
    rerender(bar({ onGoBack: () => undefined, onGoOn: () => undefined, onNotifications, atNotifications: true }));
    expect(button('Notifications').getAttribute('aria-expanded')).toBe('true');
    expect(button('Notifications').hasAttribute('data-on')).toBe(true);
    expect(button('Notifications').hasAttribute('data-notifications-toggle')).toBe(true);
    expect(button('Notifications').hasAttribute('data-unread')).toBe(false);
    // No bell at all without the drawer to open.
    rerender(bar({}));
    expect(() => button('Notifications')).toThrow();
  });

  it('has the Settings cog to the right of the bell, before the screen’s More, and none without somewhere to go', () => {
    const onSettings = vi.fn();
    show(bar({ onNotifications: () => undefined, onSettings }));
    const cog = button('Settings');
    expect(cog.previousElementSibling).toBe(button('Notifications'));
    expect(cog.nextElementSibling?.className).toContain('tail');
    act(() => cog.click());
    expect(onSettings).toHaveBeenCalledOnce();
    rerender(bar({ onNotifications: () => undefined }));
    expect(() => button('Settings')).toThrow();
  });

  it('opens a picker of your organizations from the people icon, a pick going straight to its dashboard', async () => {
    const onOrganizations = vi.fn();
    const onOrganization = vi.fn();
    const organizations = [
      { id: 'o1', name: 'Studio', hue: 'teal' },
      { id: 'o2', name: 'Family', hue: null },
    ];
    show(bar({ onOrganizations, onOrganization, organizations }));
    act(() => button('Organizations').click());
    let found: Element | null = null;
    await waitUntil(() => {
      found = document.querySelector('[role="menu"][aria-label="Choose an organization"]');
      expect(found).not.toBeNull();
    });
    const picker = found as unknown as Element;
    const items = [...picker.querySelectorAll('[role="menuitem"]')].map((item) => item.textContent?.trim());
    expect(items).toEqual(['Studio', 'Family', 'All organizations…']);
    act(() => [...picker.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => item.textContent?.includes('Studio'))!.click());
    expect(onOrganization).toHaveBeenCalledWith('o1');
    expect(onOrganizations).not.toHaveBeenCalled();
  });

  it('closes the organizations’ picker on the back gesture, a second press on the icon, and a press anywhere else', async () => {
    const organizations = [{ id: 'o1', name: 'Studio', hue: 'teal' }];
    show(bar({ onOrganizations: vi.fn(), onOrganization: vi.fn(), organizations }));
    const picker = () => document.querySelector('[role="menu"][aria-label="Choose an organization"]');
    const icon = button('Organizations');
    const open = async () => {
      act(() => icon.click());
      await waitUntil(() => expect(picker()).not.toBeNull());
    };
    await open();
    // Hung from the icon, which says so while it is open (editor/PopMenu.tsx).
    expect(icon.getAttribute('aria-haspopup')).toBe('menu');
    expect(icon.getAttribute('aria-expanded')).toBe('true');
    let took = false;
    act(() => void (took = goBack()));
    await settle();
    expect(took).toBe(true);
    expect(picker()).toBeNull();
    expect(icon.hasAttribute('aria-expanded')).toBe(false);
    // A press on the icon is the picker's own: it closes it, and does not close and open it again.
    await open();
    act(() => void icon.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
    act(() => icon.click());
    await settle();
    expect(picker()).toBeNull();
    await open();
    act(() => void document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
    await settle();
    expect(picker()).toBeNull();
  });

  it('goes to Settings from the people icon when you belong to no organization yet', () => {
    const onOrganizations = vi.fn();
    show(bar({ onOrganizations, onOrganization: vi.fn(), organizations: [] }));
    act(() => button('Organizations').click());
    expect(onOrganizations).toHaveBeenCalledOnce();
    expect(document.querySelector('[role="menu"]')).toBeNull();
  });

  it('moves a tab by the arrow keys only with the platform’s modifier', () => {
    const onMove = vi.fn();
    show(bar({ onMove }));
    const key = (id: string, init: KeyboardEventInit) => act(() => void tab(id).querySelector('[role="tab"]')!.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, ...init })));
    key('a', { key: 'ArrowRight' });
    expect(onMove).not.toHaveBeenCalled();
    key('a', { key: 'ArrowRight', ctrlKey: true });
    expect(onMove).toHaveBeenLastCalledWith('a', 1);
    key('c', { key: 'ArrowLeft', metaKey: true });
    expect(onMove).toHaveBeenLastCalledWith('c', 1);
  });
});

describe('a tab’s title', () => {
  it('says what the open note’s editor has in line 1 as it is written, and the note’s own once that is newer', async () => {
    const { dropLiveTitles, setLiveTitle } = await import('../core/liveTitles.ts');
    const fresh = makeNote('n', '');
    show(bar({ tabs: [fresh, ...notes], activeId: 'n' }));
    expect(tab('n').textContent).toContain('Untitled');
    act(() => setLiveTitle('n', '2026-09-28'));
    expect(tab('n').textContent).toContain('2026-09-28');
    // Renamed elsewhere after it was said: the note App has now wins.
    rerender(bar({ tabs: [{ ...fresh, body: '# From the Mac', updatedAt: Date.now() + 1000 }, ...notes], activeId: 'n' }));
    expect(tab('n').textContent).toContain('From the Mac');
    dropLiveTitles(['n']);
  });
});

describe('a tab’s menu', () => {
  it('opens on a mouse’s right-click, and not on a finger’s press and hold that the phone would raise', () => {
    show(bar({ onGroups: () => undefined }));
    pointer('pointerdown', tab('b'), 150, 'touch');
    act(() => void tab('b').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
    expect(menuItems()).toEqual([]);
    pointer('pointerdown', tab('b'), 150, 'mouse');
    act(() => void tab('b').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
    expect(menuItems()).toEqual(['Add to a new group', 'Close tab']);
  });

  it('opens when a finger holds a tab and lets go where it was, and the tap that ends it opens nothing', () => {
    vi.useFakeTimers();
    const onOpen = vi.fn();
    show(bar({ onOpen, onMove: () => undefined, onGroups: () => undefined }));
    held.mockClear();
    pointer('pointerdown', tab('b').querySelector('[role="tab"]')!, 150, 'touch');
    act(() => void vi.advanceTimersByTime(220));
    pointer('pointerup', window, 150, 'touch');
    expect(menuItems()).toContain('Close tab');
    // One tick for the press, the tap tick's or the hold's (core/haptics.ts `tickHeld`).
    expect(held).toHaveBeenCalledOnce();
    act(() => button('Bread').click());
    expect(onOpen).not.toHaveBeenCalled();
  });

  it('renames a canvas: Enter and leaving the field keep the words, Escape and the same name keep nothing', () => {
    const onRename = vi.fn();
    const map = makeNote('m', canvasNoteBody('Map', { nodes: [], edges: [] }));
    show(bar({ tabs: [notes[0]!, map], onRename, onGroups: () => undefined }));
    const rename = (words: string, end: 'Enter' | 'Escape' | 'blur') => {
      act(() => void tab('m').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
      act(() => [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => item.textContent === 'Rename')!.click());
      const field = document.querySelector<HTMLInputElement>('input[aria-label="Canvas name"]')!;
      typeInto(field, words);
      if (end === 'blur') act(() => field.blur());
      else act(() => void field.dispatchEvent(new KeyboardEvent('keydown', { key: end, bubbles: true })));
      expect(document.querySelector('input[aria-label="Canvas name"]')).toBeNull();
    };
    rename('Atlas', 'Enter');
    expect(onRename).toHaveBeenLastCalledWith('m', 'Atlas');
    rename('Chart', 'Escape');
    rename('Map', 'Enter');
    expect(onRename).toHaveBeenCalledTimes(1);
    rename('Globe ', 'blur');
    expect(onRename).toHaveBeenLastCalledWith('m', 'Globe');
    // A note is named by its first line, so its tab offers no rename.
    act(() => void tab('a').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
    expect(menuItems()).not.toContain('Rename');
  });
});

describe('dragging a tab', () => {
  it('pans the row rather than moving a tab until the press has been held, and swallows the tap that ends the pan', () => {
    vi.useFakeTimers();
    layOut();
    const onMove = vi.fn();
    const onOpen = vi.fn();
    show(bar({ onMove, onOpen }));
    pointer('pointerdown', tab('a').querySelector('[role="tab"]')!, 50);
    // Most of the way to the hold, and then sideways: a pull on the row, which the hold then never becomes.
    act(() => void vi.advanceTimersByTime(200));
    pointer('pointermove', window, 80);
    act(() => void vi.advanceTimersByTime(500));
    pointer('pointermove', window, 180);
    pointer('pointerup', window, 180);
    expect(onMove).not.toHaveBeenCalled();
    act(() => button('Apples').click());
    expect(onOpen).not.toHaveBeenCalled();
  });

  it('carries a held tab to the place the pointer has passed, and into the group it is over', () => {
    vi.useFakeTimers();
    layOut();
    const onMove = vi.fn();
    const onGroups = vi.fn();
    const groups: TabGroups = { list: [{ id: 'g', name: 'Lunch', hue: 'sea' }], of: { c: 'g' } };
    // Drawn: a at 0, b at 100, the chip at 200, c at 300, the + at 400.
    show(bar({ onMove, onGroups, groups, onNew: () => undefined }));
    pointer('pointerdown', tab('a').querySelector('[role="tab"]')!, 50, 'touch');
    act(() => void vi.advanceTimersByTime(219));
    expect(tab('a').dataset.moving).toBeUndefined();
    act(() => void vi.advanceTimersByTime(1));
    expect(tab('a').dataset.moving).toBe('true');
    // Past b's middle, over b, a tab of no group.
    pointer('pointermove', window, 160, 'touch');
    expect(onMove).toHaveBeenLastCalledWith('a', 1, true);
    expect(onGroups).not.toHaveBeenCalled();
    // Over the chip: into its group.
    pointer('pointermove', window, 250, 'touch');
    expect(onGroups).toHaveBeenLastCalledWith({ list: groups.list, of: { c: 'g', a: 'g' } });
    pointer('pointerup', window, 250, 'touch');
    expect(tab('a').dataset.moving).toBeUndefined();
    expect(tab('a').style.transform).toBe('');
    // Held and carried is a move, not the hold that opens the menu.
    expect(menuItems()).toEqual([]);
  });
});

describe('dragging a tab, the finer rules', () => {
  /** A pointer event with the time it happened at, which a flick's speed is measured by. */
  const at = (type: string, target: EventTarget, x: number, time: number) =>
    act(() => {
      const event = new PointerEvent(type, { bubbles: true, clientX: x, pointerType: 'touch', button: 0 });
      Object.defineProperty(event, 'timeStamp', { value: time });
      target.dispatchEvent(event);
    });

  it('brings a group of one back when its tab is carried out and over its chip again before the row has redrawn', () => {
    vi.useFakeTimers();
    layOut();
    let held: TabGroups = { list: [{ id: 'g', name: 'Solo', hue: 'sea' }], of: { a: 'g' } };
    function Grouping() {
      const [groups, setGroups] = useState<TabGroups>(held);
      held = groups;
      return bar({ groups, onGroups: setGroups, onMove: () => undefined, onNew: () => undefined });
    }
    // Drawn: the chip at 0, a at 100, b at 200, c at 300, the + at 400.
    show(<Grouping />);
    pointer('pointerdown', tab('a').querySelector('[role="tab"]')!, 150, 'touch');
    act(() => void vi.advanceTimersByTime(220));
    // Over b, a tab of no group, and straight back over the chip: two moves inside one frame, as a quick finger makes.
    act(() => {
      window.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: 250, pointerType: 'touch' }));
      window.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: 50, pointerType: 'touch' }));
    });
    pointer('pointerup', window, 50, 'touch');
    expect(held).toEqual({ list: [{ id: 'g', name: 'Solo', hue: 'sea' }], of: { a: 'g' } });
  });

  it('counts a folded group as every tab it holds, and takes the tab into it only when let go', () => {
    vi.useFakeTimers();
    layOut();
    const onMove = vi.fn();
    const onGroups = vi.fn();
    const four = [...notes, makeNote('d', '# Dates')];
    const groups: TabGroups = { list: [{ id: 'g', name: 'Lunch', hue: 'sea', collapsed: true }], of: { b: 'g', c: 'g', d: 'g' } };
    // Drawn: a at 0, the folded chip at 100, the + at 200.
    show(bar({ tabs: four, onMove, onGroups, groups, onNew: () => undefined }));
    pointer('pointerdown', tab('a').querySelector('[role="tab"]')!, 50, 'touch');
    act(() => void vi.advanceTimersByTime(220));
    pointer('pointermove', window, 160, 'touch');
    expect(onMove).toHaveBeenLastCalledWith('a', 3, true);
    // Joining a folded group hides the tab, so not while it is under the finger.
    expect(onGroups).not.toHaveBeenCalled();
    pointer('pointerup', window, 160, 'touch');
    expect(onGroups).toHaveBeenCalledWith({ list: groups.list, of: { b: 'g', c: 'g', d: 'g', a: 'g' } });
  });

  it('carries a flick on after the finger lifts, slowing to a stop', () => {
    const frames: FrameRequestCallback[] = [];
    vi.stubGlobal('requestAnimationFrame', (step: FrameRequestCallback) => frames.push(step));
    vi.stubGlobal('cancelAnimationFrame', () => undefined);
    show(bar({ onMove: () => undefined }));
    const row = document.querySelector<HTMLElement>('[role="tablist"]')!;
    let left = 100;
    Object.defineProperty(row, 'scrollWidth', { configurable: true, get: () => 2000 });
    Object.defineProperty(row, 'clientWidth', { configurable: true, get: () => 300 });
    Object.defineProperty(row, 'scrollLeft', { configurable: true, get: () => left, set: (to: number) => void (left = to) });
    at('pointerdown', tab('b').querySelector('[role="tab"]')!, 250, 1000);
    at('pointermove', window, 230, 1010);
    at('pointermove', window, 200, 1020);
    expect(left).toBe(150);
    at('pointerup', window, 200, 1030);
    expect(frames).toHaveLength(1);
    const now = performance.now();
    act(() => frames.shift()!(now + 17));
    expect(left).toBeGreaterThan(150);
    const after = left;
    act(() => frames.shift()!(now + 34));
    expect(left).toBeGreaterThan(after);
  });

  it('opens no menu for a mouse held and let go in place: a mouse has its right-click', () => {
    vi.useFakeTimers();
    show(bar({ onMove: () => undefined, onGroups: () => undefined }));
    pointer('pointerdown', tab('b').querySelector('[role="tab"]')!, 150, 'mouse');
    act(() => void vi.advanceTimersByTime(220));
    pointer('pointerup', window, 150, 'mouse');
    expect(menuItems()).toEqual([]);
  });

  it('never picks a tab up by its cross', () => {
    vi.useFakeTimers();
    layOut();
    const onMove = vi.fn();
    show(bar({ onMove }));
    pointer('pointerdown', button('Close Apples'), 90, 'touch');
    act(() => void vi.advanceTimersByTime(220));
    pointer('pointermove', window, 250, 'touch');
    pointer('pointerup', window, 250, 'touch');
    expect(tab('a').dataset.moving).toBeUndefined();
    expect(onMove).not.toHaveBeenCalled();
  });
});

describe('a group’s chip', () => {
  const groups: TabGroups = { list: [{ id: 'g', name: 'Lunch', hue: 'sea' }], of: { b: 'g', c: 'g' } };

  it('says how many tabs it holds, and folds them away on a tap', () => {
    const onGroups = vi.fn();
    show(bar({ groups, onGroups }));
    act(() => button('Lunch, 2 tabs').click());
    expect(onGroups).toHaveBeenCalledWith({ list: [{ ...groups.list[0]!, collapsed: true }], of: groups.of });
    rerender(bar({ groups: { ...groups, list: [{ ...groups.list[0]!, collapsed: true }] }, onGroups }));
    // Folded, it is drawn alone: its tabs are counted, not shown.
    expect([...document.querySelectorAll('[data-tab]')].map((el) => el.getAttribute('data-tab-id'))).toEqual(['a']);
    expect(button('Lunch, 2 tabs, folded')).toBeTruthy();
  });

  const chipMenu = () => act(() => void button('Lunch, 2 tabs').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));

  it('offers its colours in place under their name, ungrouping, and closing every tab it holds', async () => {
    // The file's matchMedia answers no to everything: no mouse, so no flyout, as under a finger.
    const onGroups = vi.fn();
    const onCloseTabs = vi.fn();
    show(bar({ groups, onGroups, onCloseTabs }));
    chipMenu();
    expect(menuItems()).toEqual(['Rename', 'Ink', 'Ember', 'Amber', 'Moss', 'Sea', 'Violet', 'Rose', 'Ungroup', 'Close group']);
    // "Colour" is a name over its rows, not a row, and each row says the whole of what it is.
    expect(document.querySelector('[role="presentation"]')?.textContent).toBe('Colour');
    expect(document.querySelector('[aria-haspopup="menu"]')).toBeNull();
    expect(menuRow('Colour: Sea')?.textContent).toBe('Sea');
    act(() => menuRow('Colour: Moss')!.click());
    await settle();
    expect(onGroups).toHaveBeenCalledWith({ list: [{ ...groups.list[0]!, hue: 'moss' }], of: groups.of });
    expect(menuItems()).toEqual([]);
    chipMenu();
    act(() => menuRow('Close group')!.click());
    await settle();
    expect(onCloseTabs).toHaveBeenCalledWith(['b', 'c']);
  });

  it('flies its colours out for a mouse on a wide window', async () => {
    stubMatchMedia((query) => query.includes('pointer: fine') || query.includes('hover: hover'));
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1280 });
    try {
      show(bar({ groups, onGroups: () => undefined }));
      chipMenu();
      const colour = menuRow('Colour')!;
      expect(colour.getAttribute('aria-haspopup')).toBe('menu');
      expect(menuItems()).toEqual(['Rename', 'Colour', 'Ungroup', 'Close group']);
      act(() => colour.click());
      await settle();
      expect(menuItems()).toEqual(expect.arrayContaining(['Ink', 'Sea']));
    } finally {
      Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1024 });
    }
  });

  it('closes on the back gesture, and leaves the gesture to nothing else', async () => {
    show(bar({ groups, onGroups: () => undefined }));
    chipMenu();
    let took = false;
    act(() => void (took = goBack()));
    await settle();
    expect(took).toBe(true);
    expect(menuItems()).toEqual([]);
  });
});

describe('grouping tabs from their menus', () => {
  /** The bar with its groups held as the Shell holds them, and read back out. */
  let held: TabGroups = NO_GROUPS;
  function Grouping() {
    const [groups, setGroups] = useState<TabGroups>(NO_GROUPS);
    held = groups;
    return bar({ groups, onGroups: setGroups });
  }
  const menuOf = (id: string) => act(() => void tab(id).dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
  /** A row chosen, by its words, and the menu closed after it. */
  const choose = async (words: string) => {
    act(() => [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => item.textContent?.trim() === words)!.click());
    await settle();
  };

  it('makes a group around a tab and names it at once: Enter keeps the name, Escape the one it had', async () => {
    show(<Grouping />);
    menuOf('a');
    await choose('Add to a new group');
    expect(held.of).toEqual({ a: held.list[0]!.id });
    const field = document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')!;
    expect(field.value).toBe('Group');
    typeInto(field, 'Lunch');
    act(() => void field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect(held.list[0]!.name).toBe('Lunch');
    act(() => void button('Lunch, 1 tab').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
    await choose('Rename');
    const again = document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')!;
    typeInto(again, 'Dinner');
    act(() => void again.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(held.list[0]!.name).toBe('Lunch');
  });

  it('adds a tab to a group there already is, and takes it out again', async () => {
    show(<Grouping />);
    menuOf('a');
    await choose('Add to a new group');
    act(() => void document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')!.blur());
    menuOf('c');
    // The groups there are, listed in place under "Add to group", each named for what choosing it does.
    expect(menuRow('Add to Group')?.textContent).toBe('Group');
    await choose('Group');
    expect(held.of.c).toBe(held.of.a);
    menuOf('c');
    await choose('Remove from group');
    expect(held.of.c).toBeUndefined();
  });

  it('closes a tab’s menu on the back gesture', async () => {
    show(<Grouping />);
    menuOf('b');
    expect(menuItems()).toContain('Close tab');
    act(() => void goBack());
    await settle();
    expect(menuItems()).toEqual([]);
  });
});

describe('the outline of the tab being read', () => {
  it('slides to a tab chosen, and not for someone who asked for less motion', () => {
    const animate = vi.fn(() => ({ cancel: () => undefined, onfinish: null }) as unknown as Animation);
    HTMLElement.prototype.animate = animate;
    show(bar());
    rerender(bar({ activeId: 'b' }));
    // The outline, and the gap in the line under it.
    expect(animate).toHaveBeenCalledTimes(2);
    stubMatchMedia(true);
    rerender(bar({ activeId: 'c' }));
    expect(animate).toHaveBeenCalledTimes(2);
  });

  it('does not slide from under a tab being carried', () => {
    vi.useFakeTimers();
    layOut();
    const animate = vi.fn(() => ({ cancel: () => undefined, onfinish: null }) as unknown as Animation);
    HTMLElement.prototype.animate = animate;
    show(bar({ onMove: () => undefined }));
    pointer('pointerdown', tab('b').querySelector('[role="tab"]')!, 150, 'touch');
    act(() => void vi.advanceTimersByTime(220));
    rerender(bar({ onMove: () => undefined, activeId: 'b' }));
    expect(animate).not.toHaveBeenCalled();
    pointer('pointerup', window, 150, 'touch');
  });

  it('is drawn under the tab being read, and not with none of them being read', () => {
    layOut();
    show(bar());
    const glide = () => document.querySelector<HTMLElement>('[role="tablist"] > span[aria-hidden="true"]')!;
    expect(glide().dataset.on).toBe('');
    expect(glide().style.width).toBe('100px');
    rerender(bar({ activeId: '' }));
    expect(glide().dataset.on).toBeUndefined();
  });

  it('fades whichever end of the row has tabs past it, and never the start at the start', () => {
    show(bar());
    const row = document.querySelector<HTMLElement>('[role="tablist"]')!;
    let left = 0;
    Object.defineProperty(row, 'scrollWidth', { configurable: true, get: () => 900 });
    Object.defineProperty(row, 'clientWidth', { configurable: true, get: () => 300 });
    Object.defineProperty(row, 'scrollLeft', { configurable: true, get: () => left, set: (to: number) => void (left = to) });
    const scrolled = (to: number) => {
      left = to;
      act(() => void row.dispatchEvent(new Event('scroll')));
      return [row.dataset.fadeStart !== undefined, row.dataset.fadeEnd !== undefined];
    };
    expect(scrolled(0)).toEqual([false, true]);
    expect(scrolled(200)).toEqual([true, true]);
    expect(scrolled(600)).toEqual([true, false]);
  });
});

/** The bar's six ways (NoteTabs.tsx `style`; docs/DESIGN.md §178): the same pieces, placed and shaped by the style. */
describe('the bar’s styles', () => {
  const props = { onHome: () => undefined, onGoBack: () => undefined, onGoOn: () => undefined, onNew: () => undefined, onNotifications: () => undefined, onOrganizations: () => undefined };
  const barOf = () => document.querySelector<HTMLElement>('[data-style]')!;
  const top = () => document.querySelector<HTMLElement>('[class*="top"]')!;
  const row = () => document.querySelector<HTMLElement>('[role="tablist"]');
  const closes = () => [...document.querySelectorAll('[data-close]')].map((b) => b.getAttribute('aria-label'));

  it('is Classic unless told otherwise: the controls, then the tabs, every tab with its cross', () => {
    show(bar(props));
    expect(barOf().dataset).toMatchObject({ style: 'classic', shape: 'tab' });
    expect(top().nextElementSibling).toBe(row());
    expect(button('Home')).toBeTruthy();
    expect(closes()).toEqual(['Close Apples', 'Close Bread', 'Close Cheese']);
  });

  it('as the Ledger puts the tabs first, with Home pinned in the row, and the row there with nothing open', () => {
    show(bar({ ...props, style: 'ledger' }));
    expect(barOf().dataset.style).toBe('ledger');
    expect(row()!.nextElementSibling).toBe(top());
    expect(row()!.querySelector('[data-home-tab]')?.getAttribute('aria-label')).toBe('Home');
    // The cross is the open tab's alone.
    expect(closes()).toEqual(['Close Apples']);
    rerender(bar({ ...props, style: 'ledger', tabs: [] }));
    expect(row()).not.toBeNull();
    expect(button('Home')).toBeTruthy();
  });

  it('as the Masthead says Home, Notes and Back as words, and draws the tabs as an index line', () => {
    const onHome = vi.fn();
    show(bar({ ...props, style: 'masthead', onHome, canGoOn: true }));
    expect(barOf().dataset.shape).toBe('index');
    const words = [...top().querySelectorAll('button')].map((b) => b.textContent?.trim());
    expect(words.slice(0, 4)).toEqual(['Home', 'Notes', 'Back', 'Forward']);
    act(() => button('Home').click());
    expect(onHome).toHaveBeenCalledTimes(1);
    expect(button('Organizations').textContent).toBe('Teams');
    // Forward only when there is somewhere forward to go.
    rerender(bar({ ...props, style: 'masthead', canGoOn: false }));
    expect(button('Back to where you were')).toBeTruthy();
    expect(document.querySelector('[aria-label="Forward again"]')).toBeNull();
  });

  it('as the Islands floats three capsules: the way around, the tabs, and the screen’s own', () => {
    show(bar({ ...props, style: 'islands' }));
    const capsules = [...document.querySelectorAll<HTMLElement>('[data-capsule]')].map((c) => c.dataset.capsule);
    expect(capsules).toEqual(['way', 'tools']);
    expect(document.querySelector('[data-capsule="way"] [aria-label="Home"]')).not.toBeNull();
    expect(document.querySelector('[data-capsule="tools"] [aria-label="Notifications"]')).not.toBeNull();
    expect(row()!.parentElement).toBe(top());
    expect(row()!.previousElementSibling?.getAttribute('data-capsule')).toBe('way');
  });
});
