import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { DEFAULT_PREFERENCES, setPreferences } from '../core/preferences.ts';
import { waitUntil } from '../../test/render.tsx';
import { isDrawnBlock } from './drawnBlock.ts';
import { placeCards, placeLook } from './placeCards.ts';

/**
 * A place in the words drawn as a map card under its line (editor/placeCards.ts), and the line folded to its name off
 * the caret: how the note screen draws it, how a shared page does, and where nothing may fetch.
 */

const CAIS = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';

function mount(doc: string, mode: 'live' | 'ask' | 'off', caret = 0, editable = true): EditorView {
  return new EditorView({
    state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [placeCards(mode, { dark: () => false }), EditorView.editable.of(editable)] }),
    parent: document.body.appendChild(document.createElement('div')),
  });
}

const cards = (view: EditorView) => view.dom.querySelectorAll('.cm-placeCard');
/** What the line shows, the folded parts left out. */
const shown = (view: EditorView, number: number) => {
  const line = view.contentDOM.querySelectorAll('.cm-line')[number - 1] as HTMLElement;
  return line.textContent;
};

beforeEach(() => {
  setPreferences({ localOnly: false, mapTiles: true });
});

afterEach(() => {
  setPreferences({ localOnly: DEFAULT_PREFERENCES.localOnly, mapTiles: DEFAULT_PREFERENCES.mapTiles });
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});

describe('a map card under a place line', () => {
  it('is drawn under a line that is a place, in any lead, and under nothing else', () => {
    const view = mount(`Lunch\n${CAIS}\n- ${CAIS}\nMet at ${CAIS}\n[site](https://example.com)`, 'live');
    expect(cards(view)).toHaveLength(2);
    view.destroy();
  });

  it('is not drawn in fenced code, or where the editor draws no cards at all', () => {
    expect(cards(mount(`\`\`\`\n${CAIS}\n\`\`\``, 'live'))).toHaveLength(0);
    expect(cards(mount(CAIS, 'off'))).toHaveLength(0);
  });

  it('leaves a place’s line in fenced code as the code was written, unfolded', () => {
    const view = mount(`Lunch\n\`\`\`\n${CAIS}\n\`\`\``, 'live');
    expect(shown(view, 3)).toBe(CAIS);
    view.destroy();
  });

  it('is the map card itself, with no place chip since the line says the name, and a press on it is not the note’s', async () => {
    const view = mount(`Lunch\n${CAIS}`, 'live');
    const card = cards(view)[0]!;
    await waitUntil(() => expect(card.querySelector('button[aria-label]')).not.toBeNull());
    expect(card.querySelector('button')!.getAttribute('aria-label')).toBe('Open Cais do Sodré, Lisbon on a map');
    expect([...card.querySelectorAll('span')].map((span) => span.textContent)).not.toContain('Cais do Sodré, Lisbon');
    expect(isDrawnBlock(card.querySelector('button'))).toBe(true);
    view.destroy();
  });
});

describe('a place at the very top of a note', () => {
  it('is drawn as the note’s header, and a place further down as the card', () => {
    const view = mount(`# Lisbon\n${CAIS}\n\nWe walked down to\n${CAIS}`, 'live');
    expect([...cards(view)].map((card) => (card as HTMLElement).dataset.size)).toEqual(['header', 'card']);
    view.destroy();
  });

  it('becomes the card once words are put above it', () => {
    const view = mount(`${CAIS}\nWords`, 'live');
    expect((cards(view)[0] as HTMLElement).dataset.size).toBe('header');
    view.dispatch({ changes: { from: 0, insert: '# Lisbon\nA day out\n' } });
    expect((cards(view)[0] as HTMLElement).dataset.size).toBe('card');
    view.destroy();
  });
});

describe('what the card draws', () => {
  it('on the note screen: the map where tiles may be fetched, quiet with the reason where not', () => {
    expect(placeLook('live', { localOnly: false, mapTiles: true })).toEqual({ mode: 'map' });
    expect(placeLook('live', { localOnly: true, mapTiles: true })).toEqual({ mode: 'quiet', quietWhy: 'local-only' });
    expect(placeLook('live', { localOnly: false, mapTiles: false })).toEqual({ mode: 'quiet', quietWhy: 'off' });
  });

  it('on a shared page: nothing fetched until the reader asks', () => {
    expect(placeLook('ask', { localOnly: false, mapTiles: true })).toEqual({ mode: 'ask' });
  });

  it('follows Local only as it changes', () => {
    const view = mount(`Lunch\n${CAIS}`, 'live');
    expect(cards(view)[0]!.getAttribute('data-mode')).toBe('map');
    setPreferences({ localOnly: true });
    expect(cards(view)[0]!.getAttribute('data-mode')).toBe('quiet');
    view.destroy();
  });
});

describe('the place line', () => {
  it('reads as its name off the caret’s line, and as written on it while the note is being written', async () => {
    const view = mount(`Lunch\n${CAIS}`, 'live', 0);
    expect(shown(view, 2)).toBe('Cais do Sodré, Lisbon');
    vi.spyOn(view, 'hasFocus', 'get').mockReturnValue(true);
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    expect(shown(view, 2)).toBe(CAIS);
    view.dispatch({ selection: { anchor: 0 } });
    expect(shown(view, 2)).toBe('Cais do Sodré, Lisbon');
    view.destroy();
  });

  it('reads as its name everywhere in a view that cannot be edited, even where no card is drawn', () => {
    const view = mount(`Lunch\n${CAIS}`, 'off', 7, false);
    expect(shown(view, 2)).toBe('Cais do Sodré, Lisbon');
    view.destroy();
  });
});
