import type { TopBar } from '../core/preferences.ts';

/**
 * The four ways the top bar can be laid out (core/preferences.ts `TopBar`; docs/DESIGN.md §178, cut from six in §180),
 * in the order Settings offers them, each with the sentence Settings says under its picture (settings/TopBarCards.tsx).
 * What each one is, in markup and stylesheet, is notes/NoteTabs.tsx; this is what the shell needs to know of them: how
 * many lines the bar is.
 */
export const TOP_BAR_STYLES: readonly { id: TopBar; label: string; hint: string }[] = [
  { id: 'classic', label: 'Classic', hint: 'The controls on one line, the open notes as tabs on the next.' },
  { id: 'ledger', label: 'Ledger', hint: 'The tabs on top, as a browser has them; the open one holds its tools on the line below.' },
  { id: 'masthead', label: 'Masthead', hint: 'Words in place of rings, and the tabs as an index line under a rule.' },
  { id: 'islands', label: 'Islands', hint: 'No bar: three glass capsules float over the page, the tabs in one of them.' },
];

/**
 * How many lines the bar is, which is how tall it is (app.css `--app-tabs`): one, or the controls with the tabs under
 * them. The Ledger's tab row is always drawn, with Home pinned in it, so it is always two. The rest are two only with
 * a note open.
 */
export function barRows(style: TopBar, open: number): 'on' | 'rows' {
  if (style === 'ledger') return 'rows';
  return open > 0 ? 'rows' : 'on';
}
