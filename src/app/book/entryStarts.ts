import { entryTitle, OWN, PRESETS } from './journal.ts';
import { fillTemplate } from './template.ts';

/**
 * What a new entry can start from, as New entry offers it on an open journal (book/JournalView.tsx `TemplateChoice`;
 * docs/DESIGN.md §142): the journal's usual template first, then the presets it is not, then an empty page, each told
 * on one line as it would start this minute. Pure, so the order and the line are tests.
 */

/** One way to start an entry: its name, and the text it starts with. */
export interface Start {
  id: string;
  name: string;
  text: string;
}

/** The journal's usual template first, then the presets it is not, then an empty page. */
export function entryStarts(usual: string): Start[] {
  const preset = PRESETS.find((each) => each.text === usual);
  const first: Start = { id: 'usual', name: preset?.name ?? OWN.name, text: usual };
  const rest = PRESETS.filter((each) => each.text !== usual).map((each) => ({ id: each.id, name: each.name, text: each.text }));
  return [first, ...rest, ...(usual.trim() ? [{ id: 'empty', name: 'An empty page', text: '' }] : [])];
}

/** How a template starts, on one line: filled for now, its marks taken off, its lines joined. */
export function startLine(text: string, journal: string, at = new Date()): string {
  const filled = fillTemplate(text, { at, title: entryTitle(at.getTime()), journal: journal.trim() || 'Journal' });
  const lines = filled
    .split('\n')
    .map((line) => line.replace(/^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+)/, '').replace(/\*\*|__|\*|_/g, '').trim())
    .filter(Boolean);
  return lines.length ? lines.join(' · ') : 'Nothing, a blank page';
}
