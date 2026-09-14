import { describe, expect, it } from 'vitest';
import { EditorState } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { glyphMarkdown } from './language.ts';

/** The node names in the document's syntax tree. */
function nodes(doc: string): string[] {
  const state = EditorState.create({ doc, extensions: [glyphMarkdown()] });
  const names: string[] = [];
  syntaxTree(state).iterate({ enter: (node) => void names.push(node.name) });
  return names;
}

describe("the editor's markdown", () => {
  it('does not turn a line into a heading because a dash follows it', () => {
    expect(nodes('Places to go\n-')).not.toContain('SetextHeading2');
    expect(nodes('Places to go\n---')).not.toContain('SetextHeading2');
    expect(nodes('Places to go\n===')).not.toContain('SetextHeading1');
  });

  it('still makes headings from #, lists from -, and rules from ---', () => {
    expect(nodes('# Places to go')).toContain('ATXHeading1');
    expect(nodes('- snacks')).toContain('ListItem');
    expect(nodes('Places to go\n\n---')).toContain('HorizontalRule');
    expect(nodes('- [ ] Book the cabin')).toContain('TaskMarker');
  });
});
