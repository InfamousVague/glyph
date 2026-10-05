import { expect, it } from 'vitest';
import { ownSelection } from './glyphTheme.ts';

/**
 * The selection in the person's own colour (Matt: "highlight in our own color not the default gray"). The rules
 * themselves, since jsdom drops `::selection` rules from a sheet and so cannot show them mounted.
 */
it('paints the selection in each hue under an element that names it, at the theme’s lightness, with the page’s paper for the words', () => {
  const light = ownSelection(false);
  expect(Object.keys(light)).toHaveLength(12);
  expect(light['[data-me-hue="rose"] & .cm-line ::selection']).toEqual({ backgroundColor: 'oklch(0.55 0.14 355)', color: 'oklch(0.995 0 0)', WebkitTextFillColor: 'oklch(0.995 0 0)' });
  expect(light['[data-me-hue="sea"] & .cm-line::selection']?.backgroundColor).toBe('oklch(0.55 0.14 230)');
  const dark = ownSelection(true);
  expect(dark['[data-me-hue="moss"] & .cm-line ::selection']).toEqual({ backgroundColor: 'oklch(0.78 0.13 150)', color: 'oklch(0.11 0 0)', WebkitTextFillColor: 'oklch(0.11 0 0)' });
  // Ink is no colour: no rule, and the ink bar stands.
  expect(Object.keys(dark).some((key) => key.includes('"ink"'))).toBe(false);
});
