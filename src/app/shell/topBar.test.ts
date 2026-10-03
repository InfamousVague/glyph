import { describe, expect, it } from 'vitest';
import { TOP_BAR_IDS } from '../core/preferences.ts';
import { barRows, TOP_BAR_STYLES } from './topBar.ts';

/** The top bar's styles as the shell reads them (shell/topBar.ts; docs/DESIGN.md §178, §180): how many lines. */
describe('the top bar’s styles', () => {
  it('offers the four the preference knows, Classic first', () => {
    expect(TOP_BAR_STYLES.map((s) => s.id)).toEqual(['classic', 'ledger', 'masthead', 'islands']);
    expect([...TOP_BAR_STYLES.map((s) => s.id)].sort()).toEqual([...TOP_BAR_IDS].sort());
  });

  it('is one line or two by the style and whether a note is open', () => {
    expect([barRows('classic', 0), barRows('classic', 2)]).toEqual(['on', 'rows']);
    expect([barRows('masthead', 0), barRows('masthead', 1)]).toEqual(['on', 'rows']);
    expect([barRows('islands', 0), barRows('islands', 1)]).toEqual(['on', 'rows']);
    // The Ledger's row of tabs is always there, Home pinned in it.
    expect([barRows('ledger', 0), barRows('ledger', 3)]).toEqual(['rows', 'rows']);
  });
});
