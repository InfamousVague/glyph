import { describe, expect, it } from 'vitest';
import { TOP_BAR_IDS } from '../core/preferences.ts';
import { barFoot, barRows, TOP_BAR_STYLES } from './topBar.ts';

/** The top bar's styles as the shell reads them (shell/topBar.ts; docs/DESIGN.md §178): how many lines, and a foot or not. */
describe('the top bar’s styles', () => {
  it('offers the six the preference knows, Classic first', () => {
    expect(TOP_BAR_STYLES.map((s) => s.id)).toEqual(['classic', 'ledger', 'strip', 'masthead', 'islands', 'thumb']);
    expect([...TOP_BAR_STYLES.map((s) => s.id)].sort()).toEqual([...TOP_BAR_IDS].sort());
  });

  it('is one line or two by the style and whether a note is open', () => {
    expect([barRows('classic', 0), barRows('classic', 2)]).toEqual(['on', 'rows']);
    expect([barRows('masthead', 0), barRows('masthead', 1)]).toEqual(['on', 'rows']);
    expect([barRows('islands', 0), barRows('islands', 1)]).toEqual(['on', 'rows']);
    // The Ledger's row of tabs is always there, Home pinned in it; the Strip and Thumb never grow a line.
    expect([barRows('ledger', 0), barRows('ledger', 3)]).toEqual(['rows', 'rows']);
    expect([barRows('strip', 0), barRows('strip', 3)]).toEqual(['on', 'on']);
    expect([barRows('thumb', 0), barRows('thumb', 3)]).toEqual(['on', 'on']);
  });

  it('stands the tabs at the foot only for Thumb, and only with a note open', () => {
    expect(barFoot('thumb', 1)).toBe(true);
    expect(barFoot('thumb', 0)).toBe(false);
    expect(TOP_BAR_IDS.filter((s) => s !== 'thumb').some((s) => barFoot(s, 2))).toBe(false);
  });
});
