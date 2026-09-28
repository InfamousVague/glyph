import { describe, expect, it } from 'vitest';
import { EditorState, Text } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { calloutKind, extendedMarkdown, frontMatter, frontMatterFolded } from './extended.ts';

function drawn(doc: string) {
  const view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), extendedMarkdown()] }), parent: document.body });
  const html = view.contentDOM.innerHTML;
  const callouts = [...view.contentDOM.querySelectorAll('.cm-callout')].map((line) => line.getAttribute('data-callout'));
  view.destroy();
  return { html, callouts };
}

describe('the extended markdown the language already parsed', () => {
  it('raises a superscript and lowers a subscript, marks and all', () => {
    expect(drawn('x^2^ metres').html).toContain('cm-sup');
    expect(drawn('H~2~O').html).toContain('cm-sub');
    // The marks are still there to edit: nothing is hidden.
    expect(drawn('x^2^ metres').html).toContain('^');
  });

  it('leaves a lone caret or tilde alone', () => {
    expect(drawn('2 ^ 3 and a ~ b').html).not.toContain('cm-sup');
    expect(drawn('~~struck~~').html).not.toContain('cm-sub');
  });
});

describe('a callout', () => {
  it('is a quote whose first line names its kind', () => {
    expect(calloutKind('> [!NOTE]')).toBe('note');
    expect(calloutKind('> [!warning] mind this')).toBe('warning');
    expect(calloutKind('> an ordinary quote')).toBeNull();
    expect(calloutKind('> [!SHOUTING]')).toBeNull();
  });

  it('wears its kind on every line of the quote', () => {
    expect(drawn('> [!TIP]\n> Try the side key.\n> It is quicker.').callouts).toEqual(['tip', 'tip', 'tip']);
  });

  it('leaves an ordinary quote as a quote', () => {
    expect(drawn('> just a quote\n> over two lines').callouts).toEqual([]);
  });
});

describe('front matter', () => {
  it('is the note’s opening fence and its keys, drawn as keys rather than a rule, once open', async () => {
    const view = new EditorView({
      state: EditorState.create({ doc: '---\ntitle: A note\ntags: one, two\n---\n\nWords.', extensions: [glyphMarkdown([], []), extendedMarkdown()] }),
      parent: document.body,
    });
    // Folded to its line until the editor is focused with the caret in it (below); the focus is told a tick later.
    view.focus();
    view.dispatch({ selection: { anchor: 0 } });
    await Promise.resolve();
    expect(view.contentDOM.querySelectorAll('.cm-front')).toHaveLength(4);
    view.destroy();
  });

  it('is not a rule in the middle of a note, nor a fence with prose under it', () => {
    expect(drawn('Words.\n\n---\n\nMore.').html).not.toContain('cm-front');
    expect(drawn('---\njust some words\n---').html).not.toContain('cm-front');
  });

  it('covers the lines the list counts as front matter (core/frontMatter.ts), forty at most', () => {
    const block = (count: number) => Text.of(['---', ...Array.from({ length: count }, (_, n) => `key${n}: value`), '---', 'Words']);
    expect(frontMatter(Text.of(['---', 'title: A', '', '---', 'Words']))).toEqual({ from: 1, to: 4 });
    expect(frontMatter(block(38))).toEqual({ from: 1, to: 40 });
    expect(frontMatter(block(39))).toBeNull();
    expect(frontMatter(Text.of(['---']))).toBeNull();
  });
});

describe('a definition list', () => {
  it('sets the term apart and hangs the meaning under it', () => {
    const { html } = drawn('Deposit\n: what you pay up front');
    expect(html).toContain('cm-term');
    expect(html).toContain('cm-definition');
  });

  it('leaves a colon that starts an ordinary line alone', () => {
    expect(drawn('Words\n\n:not a definition').html).not.toContain('cm-definition');
  });
});

describe('maths', () => {
  it('sets both kinds as code, delimiters and all', () => {
    expect(drawn('when $x^2 + y$ holds').html).toContain('cm-maths');
    expect(drawn('$$\nx = y\n$$').html).not.toContain('cm-maths');
    expect(drawn('the sum $$a + b$$ inline').html).toContain('cm-maths');
  });

  it('leaves a price alone', () => {
    expect(drawn('it cost $20 and $30').html).toContain('cm-maths');
  });
});

describe('an emoji shortcode', () => {
  it('is drawn as its emoji', () => {
    const view = new EditorView({
      state: EditorState.create({ doc: 'words\nparty :tada: time', extensions: [glyphMarkdown([], []), extendedMarkdown()] }),
      parent: document.body,
    });
    expect(view.contentDOM.querySelector('.cm-emoji')?.textContent).toBe('🎉');
    view.destroy();
  });

  it('comes back as words while the caret is on its line', () => {
    const view = new EditorView({
      state: EditorState.create({ doc: 'party :tada: time', selection: { anchor: 2 }, extensions: [glyphMarkdown([], []), extendedMarkdown()] }),
      parent: document.body,
    });
    expect(view.contentDOM.querySelector('.cm-emoji')).toBeNull();
    view.destroy();
  });

  it('leaves a name it does not know as the words that were typed', () => {
    expect(drawn('a :not_an_emoji_name: here').html).not.toContain('cm-emoji');
  });
});

describe('front matter, folded', () => {
  const TAGGED = '---\ntitle: "A note"\nauthors: matt\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# A note\n\nWords.';
  const open = (doc: string) => new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown([], []), extendedMarkdown()] }), parent: document.body });

  it('is one quiet line naming its keys, in order, while the editor is not focused with the caret in it', () => {
    const view = open(TAGGED);
    expect(frontMatterFolded(view.state)).toBe(true);
    const fold = view.contentDOM.querySelector('.cm-frontFold');
    expect(fold?.textContent).toBe('title · authors · location · place');
    expect(view.contentDOM.querySelectorAll('.cm-front')).toHaveLength(0);
    // The words under it are drawn as they are.
    expect(view.contentDOM.textContent).toContain('Words.');
    view.destroy();
  });

  it('opens to its lines when the editor is focused with the caret in it, and folds again when the caret leaves', async () => {
    const view = open(TAGGED);
    view.focus();
    view.dispatch({ selection: { anchor: 4 } });
    // The editor tells its extensions of the focus a tick after the update that saw it.
    await Promise.resolve();
    expect(frontMatterFolded(view.state)).toBe(false);
    expect(view.contentDOM.querySelectorAll('.cm-front')).toHaveLength(6);
    expect(view.contentDOM.querySelector('.cm-frontFold')).toBeNull();
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    expect(frontMatterFolded(view.state)).toBe(true);
    // Losing focus folds it even with the caret inside.
    view.dispatch({ selection: { anchor: 4 } });
    expect(frontMatterFolded(view.state)).toBe(false);
    view.contentDOM.blur();
    view.dispatch(view.state.update());
    await Promise.resolve();
    expect(frontMatterFolded(view.state)).toBe(true);
    view.destroy();
  });

  it('opens on a tap, with the caret on its first key', () => {
    const view = open(TAGGED);
    const fold = view.contentDOM.querySelector<HTMLElement>('.cm-frontFold')!;
    fold.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    expect(frontMatterFolded(view.state)).toBe(false);
    expect(view.state.doc.lineAt(view.state.selection.main.head).text).toBe('title: "A note"');
    view.destroy();
  });

  it('is not folded where the words cannot be edited: the shared reader shows the lines as they are', () => {
    const view = new EditorView({
      state: EditorState.create({ doc: TAGGED, extensions: [glyphMarkdown([], []), extendedMarkdown(), EditorState.readOnly.of(true), EditorView.editable.of(false)] }),
      parent: document.body,
    });
    expect(frontMatterFolded(view.state)).toBe(false);
    expect(view.contentDOM.querySelectorAll('.cm-front')).toHaveLength(6);
    view.destroy();
  });

  it('never names the note’s look, and folds a block that holds only its look to nothing', async () => {
    const both = open('---\nlook: map\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Walk\n');
    expect(both.contentDOM.querySelector('.cm-frontFold')?.textContent).toBe('location · place');
    both.destroy();
    const reading = open('---\nlook: reading\n---\n# Walk\n');
    expect(frontMatterFolded(reading.state)).toBe(true);
    expect(reading.contentDOM.querySelector('.cm-frontFold')).toBeNull();
    expect(reading.contentDOM.textContent).not.toContain('look');
    expect(reading.contentDOM.textContent).toContain('# Walk');
    // The caret moved into it, in the Markdown view, still opens it.
    reading.focus();
    reading.dispatch({ selection: { anchor: 5 } });
    await Promise.resolve();
    expect(frontMatterFolded(reading.state)).toBe(false);
    expect(reading.contentDOM.textContent).toContain('look: reading');
    reading.destroy();
  });

  it('leaves a note with no front matter, and a rule with words under it, as they are', () => {
    expect(drawn('# Plain\n\nWords.').html).not.toContain('cm-frontFold');
    expect(drawn('---\njust some words\n---').html).not.toContain('cm-frontFold');
    expect(drawn('---\n---\nWords.').html).toContain('front matter');
  });
});
