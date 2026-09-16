import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { glyphMarkdown } from './language.ts';
import { calloutKind, extendedMarkdown } from './extended.ts';

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
