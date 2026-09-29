import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { MARKS } from '../plugins/marks/index.tsx';
import { editorBlanks } from '../editor/blanks.ts';
import { glyphMarkdown } from '../editor/language.ts';
import { blanksIn } from './blanks.ts';

/**
 * The two readers of blanks (docs/DESIGN.md §145, 1.6): the editor's, which asks its parser, and the pure one for the
 * places with no editor (a title, a gist, home's to-dos, the item text sent to a plugin, search). They are kept from
 * disagreeing where it matters, and where they still differ, the difference is named here rather than found.
 */

const CORPUS = [
  '---',
  'title: {?in front matter}',
  '---',
  '# Trip {?prose}',
  '- An item {?in a list}',
  '- [ ] {?a to-do}',
  '| Say | In Japanese |',
  '| --- | --- |',
  '| Thanks | {?a cell} |',
  '',
  'A `{?code span}` and ``{?two ticks}`` here.',
  '```',
  '{?fenced}',
  '```',
  'A comment <!-- {?comment} --> here.',
  'Maths $x {?maths}$ here.',
  '[words](https://a.b/{?address}) and <https://a.b/{?autolink}>',
  'HOCON ${?HOME} is not one.',
  '> A quote {?in a quote}',
].join('\n');

const editorRead = (text: string) => editorBlanks(EditorState.create({ doc: text, extensions: [glyphMarkdown(MARKS, [])] })).map((b) => b.question);

describe('the two readers of blanks', () => {
  it('agree on prose, lists, tables, fences, spans, comments, maths, addresses, front matter and ${?HOME}', () => {
    const expected = ['prose', 'in a list', 'a to-do', 'a cell', 'in a quote'];
    expect(blanksIn(CORPUS).map((b) => b.question)).toEqual(expected);
    expect(editorRead(CORPUS)).toEqual(expected);
  });

  it('read a fence past the parse a state was made with', () => {
    // A state parses its first 3000 characters as it is made. The fence below starts past them, so its blank is code
    // only in the tree the whole-note read asks for.
    const long = `${'Words to fill the note. '.repeat(200)}\n\n\`\`\`\n{?fenced}\n\`\`\`\n\nAfter {?prose}`;
    expect(editorRead(long)).toEqual(['prose']);
  });

  it('differ, as named, on an indented code block and an HTML block over several lines', () => {
    // An indented code block is code to the parser and words to the pure reader, which reads fences only.
    expect(editorRead('Words.\n\n    {?indented}\n')).toEqual([]);
    expect(blanksIn('Words.\n\n    {?indented}\n').map((b) => b.question)).toEqual(['indented']);
    // An HTML block's lines are HTML to the parser; the pure reader passes over its tags only.
    expect(editorRead('<div>\n{?in html}\n</div>')).toEqual([]);
    expect(blanksIn('<div>\n{?in html}\n</div>').map((b) => b.question)).toEqual(['in html']);
  });
});
