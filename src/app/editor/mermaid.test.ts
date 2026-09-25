import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_PREFERENCES, setPreferences } from '../core/preferences.ts';
import { diagramsIn, drawnMermaid } from './mermaid.ts';

/**
 * Mermaid itself, stood in for: each render is held until the test lets it finish (or fail), so the order the
 * diagrams are drawn in can be watched. What it was asked to draw, and with which settings, is kept.
 */
const library = vi.hoisted(() => {
  const pending: { code: string; finish: () => void; fail: (why: Error) => void }[] = [];
  return {
    pending,
    settings: [] as Record<string, unknown>[],
    initialize: (settings: Record<string, unknown>) => library.settings.push(settings),
    render: (_id: string, code: string) =>
      new Promise<{ svg: string }>((resolve, reject) => {
        pending.push({ code, finish: () => resolve({ svg: `<svg data-code="${code.split('\n')[0]}"></svg>` }), fail: reject });
      }),
  };
});
vi.mock('mermaid', () => ({ default: { initialize: library.initialize, render: library.render } }));

describe('mermaid fences in a note', () => {
  it('finds a fence and hands back what is between its lines', () => {
    const note = ['# Launch', '', '```mermaid', 'flowchart TD', '  A[Write it] --> B[Ship it]', '```', '', 'and then home', ''].join('\n');
    expect(diagramsIn(note)).toEqual([{ from: 3, to: 6, code: 'flowchart TD\n  A[Write it] --> B[Ship it]' }]);
  });

  it('takes the word however it is written, and squiggles as readily as backticks', () => {
    expect(diagramsIn('```Mermaid\nflowchart TD\n```')[0]?.code).toBe('flowchart TD');
    expect(diagramsIn('~~~mermaid\nflowchart TD\n~~~')[0]?.code).toBe('flowchart TD');
    expect(diagramsIn('````mermaid\nflowchart TD\n````')[0]?.code).toBe('flowchart TD');
  });

  it('leaves every other fence alone', () => {
    expect(diagramsIn('```js\nconst a = 1;\n```')).toEqual([]);
    expect(diagramsIn('```board\nTo do: a\n```')).toEqual([]);
    expect(diagramsIn('```\nplain\n```')).toEqual([]);
    // The word has to be the whole info string: a note about mermaids is not a diagram.
    expect(diagramsIn('```mermaid charts\nflowchart TD\n```')).toEqual([]);
  });

  it('reads several in one note, and skips a fence that never closes', () => {
    const two = ['```mermaid', 'flowchart TD', '```', 'words', '```mermaid', 'sequenceDiagram', '```'].join('\n');
    expect(diagramsIn(two).map((found) => found.code)).toEqual(['flowchart TD', 'sequenceDiagram']);
    expect(diagramsIn('```mermaid\nflowchart TD')).toEqual([]);
  });

  it('does not take the inside of a diagram for another one', () => {
    const nested = ['```mermaid', 'flowchart TD', '  A --> B', '```', '', '```mermaid', 'flowchart LR', '```'].join('\n');
    expect(diagramsIn(nested).length).toBe(2);
    expect(diagramsIn(nested)[1]).toEqual({ from: 6, to: 8, code: 'flowchart LR' });
  });
});

describe('a diagram drawn in a note', () => {
  const views: EditorView[] = [];

  beforeEach(() => {
    library.pending.length = 0;
    library.settings.length = 0;
    setPreferences({ theme: 'light' });
  });

  afterEach(() => {
    for (const view of views.splice(0)) view.destroy();
    setPreferences({ theme: DEFAULT_PREFERENCES.theme });
  });

  /** A note with a diagram of each of `codes`, in order. Every test draws codes of its own: what is drawn is kept. */
  function open(...codes: string[]): EditorView {
    const doc = ['Before', ...codes.map((code) => `\`\`\`mermaid\n${code}\n\`\`\``), 'After'].join('\n\n');
    const view = new EditorView({ state: EditorState.create({ doc, extensions: [drawnMermaid()] }), parent: document.body });
    views.push(view);
    return view;
  }
  /** Lets the library's loading and the queue's hops run. */
  const settle = () => new Promise((done) => setTimeout(done, 0));
  const diagrams = (view: EditorView) => [...view.dom.querySelectorAll<HTMLElement>('.cm-mermaid')];

  it('is its own text until it is drawn, then the picture, drawn safely and in the page’s colours', async () => {
    const view = open('flowchart TD\n  A --> B');
    const [diagram] = diagrams(view);
    expect(diagram?.getAttribute('aria-label')).toBe('Diagram');
    expect(diagram?.querySelector('.cm-mermaidText')?.textContent).toBe('flowchart TD\n  A --> B');
    await vi.waitFor(() => expect(library.pending).toHaveLength(1));
    library.pending[0]!.finish();
    await vi.waitFor(() => expect(diagram?.hasAttribute('data-drawn')).toBe(true));
    expect(diagram?.querySelector('svg')?.getAttribute('data-code')).toBe('flowchart TD');
    // A note can come from anywhere: no HTML out of a diagram, ever.
    expect(library.settings[0]).toMatchObject({ securityLevel: 'strict', theme: 'default', startOnLoad: false });
  });

  it('draws one diagram at a time, and draws what it has drawn once', async () => {
    const view = open('graph one', 'graph two');
    await vi.waitFor(() => expect(library.pending).toHaveLength(1));
    // The second waits its turn: mermaid keeps its settings in one place, and two at once could swap themes.
    await settle();
    expect(library.pending.map((render) => render.code)).toEqual(['graph one']);
    library.pending[0]!.finish();
    await vi.waitFor(() => expect(library.pending.map((render) => render.code)).toEqual(['graph one', 'graph two']));
    library.pending[1]!.finish();
    await vi.waitFor(() => expect(diagrams(view).every((diagram) => diagram.hasAttribute('data-drawn'))).toBe(true));

    // The same diagram shown again, in another note, is not drawn again.
    const again = open('graph one');
    await vi.waitFor(() => expect(diagrams(again)[0]?.hasAttribute('data-drawn')).toBe(true));
    expect(library.pending).toHaveLength(2);
  });

  it('keeps a diagram written wrong as its text, saying what mermaid said, and draws the ones after it', async () => {
    const view = open('graph broken', 'graph after');
    await vi.waitFor(() => expect(library.pending).toHaveLength(1));
    library.pending[0]!.fail(new Error('Parse error on line 2:\n...A -->\n------^'));
    await vi.waitFor(() => expect(library.pending).toHaveLength(2));
    library.pending[1]!.finish();
    const [broken, after] = diagrams(view);
    await vi.waitFor(() => expect(broken?.querySelector('.cm-mermaidWhy')?.textContent).toBe('That diagram has a mistake: Parse error on line 2:'));
    expect(broken?.hasAttribute('data-drawn')).toBe(false);
    expect(broken?.querySelector('.cm-mermaidText')?.textContent).toBe('graph broken');
    await vi.waitFor(() => expect(after?.hasAttribute('data-drawn')).toBe(true));
  });

  it('says a diagram could not be drawn here, not that it is wrong, when the library itself is missing', async () => {
    const view = open('graph offline');
    await vi.waitFor(() => expect(library.pending).toHaveLength(1));
    library.pending[0]!.fail(new Error('Failed to fetch dynamically imported module'));
    await vi.waitFor(() => expect(diagrams(view)[0]?.querySelector('.cm-mermaidWhy')?.textContent).toBe('This diagram could not be drawn here.'));
  });

  it('is drawn again in the other colours when the app is painted the other way', async () => {
    const view = open('graph painted');
    await vi.waitFor(() => expect(library.pending).toHaveLength(1));
    library.pending[0]!.finish();
    await vi.waitFor(() => expect(diagrams(view)[0]?.hasAttribute('data-drawn')).toBe(true));
    // A drawn diagram carries its colours inside its picture, so it cannot follow a CSS variable.
    setPreferences({ theme: 'dark' });
    await vi.waitFor(() => expect(library.pending).toHaveLength(2));
    expect(library.settings.map((settings) => settings.theme)).toEqual(['default', 'dark']);
  });

  it('draws nothing for an empty fence', () => {
    const view = new EditorView({ state: EditorState.create({ doc: '```mermaid\n\n```', extensions: [drawnMermaid()] }), parent: document.body });
    views.push(view);
    expect(diagrams(view)).toEqual([]);
  });
});
