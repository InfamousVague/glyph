import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../../test/render.tsx';
import { PaneHero, PaneSection, Pick, SettingRow, SettingsEmpty } from './settingsKit.tsx';

/**
 * The settings vocabulary the panes speak in: a row that is disabled is out of reach of the keyboard too, a row that
 * is pressed is one button, and the hero that opens the developer tools is pressable without looking like a button.
 * The search finds settings by these classes (settingsSearch.ts), so they are what a test reads.
 */

describe('SettingRow', () => {
  it('seats its control at the end, or across the row under its words', () => {
    const trailing = show(<SettingRow label="Haptics" hint="A small tap." control={<input aria-label="on" />} />);
    expect(trailing.querySelector('.setk-row__control input')).not.toBeNull();
    const stacked = show(<SettingRow label="Text size" layout="stacked" control={<input aria-label="size" />} />);
    expect(stacked.querySelector('.setk-row')?.hasAttribute('data-stacked')).toBe(true);
    expect(stacked.querySelector('.setk-row__wide input')).not.toBeNull();
  });

  it('says why it is disabled, and cannot be reached by tapping or tabbing', () => {
    const host = show(<SettingRow label="Haptics" control={<input aria-label="on" />} disabledReason="This device has no motor." />);
    const row = host.querySelector<HTMLElement>('.setk-row')!;
    expect(row.querySelector('.setk-row__why')?.textContent).toBe('This device has no motor.');
    expect(row.hasAttribute('data-disabled')).toBe(true);
    // `inert`, not only the stylesheet's pointer-events: a Tab reached the control without it.
    expect(row.hasAttribute('inert')).toBe(true);
  });

  it('is one button when pressed, with a chevron, and a disabled one refuses the press', () => {
    const onPress = vi.fn();
    const host = show(<SettingRow label="Welcome guide" hint="From the first page." onPress={onPress} />);
    const button = host.querySelector<HTMLButtonElement>('button.setk-row--press')!;
    expect(button.querySelector('.setk-row__chevron')).not.toBeNull();
    act(() => button.click());
    expect(onPress).toHaveBeenCalledOnce();
    const off = show(<SettingRow label="Sync now" onPress={onPress} disabled />).querySelector<HTMLButtonElement>('button')!;
    expect(off.disabled).toBe(true);
  });

  it('draws no stacked control on a pressable row, which has only the trailing seat', () => {
    // A known edge of the kit, pinned so it is changed on purpose: a row that is a button has no room below its words.
    const host = show(<SettingRow label="Row" onPress={() => undefined} layout="stacked" control={<input aria-label="lost" />} />);
    expect(host.querySelector('input')).toBeNull();
  });
});

describe('the rest of the kit', () => {
  it('titles a card, describes it, and puts a footer under it', () => {
    const host = show(
      <PaneSection title="Updates" description="Where this build stands." footer="From the Play Store.">
        <SettingRow label="Up to date." />
      </PaneSection>,
    );
    expect([...host.querySelectorAll('.setk__title, .setk__desc, .setk__card, .setk__footer')].map((el) => el.textContent)).toEqual(['Updates', 'Where this build stands.', 'Up to date.', 'From the Play Store.']);
  });

  it('makes the hero pressable without making it look like a button, and says a state with its dot', () => {
    const onPress = vi.fn();
    const host = show(<PaneHero title="1.8.0" meta="Built into the app" status={{ text: 'Syncing', pulse: true }} onPress={onPress} />);
    const hero = host.querySelector<HTMLButtonElement>('button.setk-hero--press')!;
    expect(hero.querySelector('.setk-hero__title')?.textContent).toBe('1.8.0');
    expect(hero.querySelector('.setk-hero__status')?.getAttribute('data-pulse')).toBe('true');
    act(() => hero.click());
    expect(onPress).toHaveBeenCalledOnce();
    expect(show(<PaneHero title="sam" />).querySelector('button')).toBeNull();
  });

  it('draws a pick as a radio that says whether it is chosen', () => {
    const onPress = vi.fn();
    const pick = show(<Pick checked label="Use Qwen3.5 4B" onPress={onPress} />).querySelector<HTMLButtonElement>('[role="radio"]')!;
    expect(pick.getAttribute('aria-checked')).toBe('true');
    expect(pick.getAttribute('aria-label')).toBe('Use Qwen3.5 4B');
    act(() => pick.click());
    expect(onPress).toHaveBeenCalledOnce();
  });

  it('offers an empty state’s one action as a word', () => {
    const onPress = vi.fn();
    const host = show(<SettingsEmpty title="No repos yet." body="Link one from a note." action={{ label: 'Open a note', onPress }} />);
    act(() => host.querySelector<HTMLButtonElement>('.setk-empty__action')!.click());
    expect(onPress).toHaveBeenCalledOnce();
  });
});
