import { EditorState } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { describe, expect, it } from 'vitest';
import { glyphMarkdown } from '../../editor/language.ts';
import { styledRanges } from '../../editor/formatLooks.ts';
import { BUILT_IN } from '../registry.ts';
import { MARKS, marksPlugin } from './index.tsx';

const formats = MARKS;

function nodes(doc: string): string[] {
  const state = EditorState.create({ doc, extensions: [glyphMarkdown(formats)] });
  const names: string[] = [];
  syntaxTree(state).iterate({ enter: (node) => void names.push(node.name) });
  return names;
}

describe("Glyph's own marks", () => {
  it('are one plugin, with one switch, each mark carrying its own icon', () => {
    expect(marksPlugin.manifest.id).toBe('marks');
    expect(marksPlugin.formats).toBe(MARKS);
    expect(marksPlugin.manifest.permissions).toEqual([]);
    for (const format of MARKS) expect(format.icon, format.name).toBeTruthy();
    expect(MARKS.map((format) => format.name)).toContain('Spoiler');
  });

  it('each parses between its own delimiter, with a cue and a line for the guide', () => {
    for (const format of formats) {
      const doc = `say ${format.delimiter}these words${format.delimiter} now`;
      expect(nodes(doc), format.name).toContain(format.name);
      expect(format.cue, format.name).toBeTruthy();
      expect(format.about, format.name).toBeTruthy();
    }
  });

  it('shares no delimiter or node name with any other plugin', () => {
    const all = BUILT_IN.flatMap((plugin) => plugin.formats ?? []);
    expect(new Set(all.map((f) => f.delimiter)).size).toBe(all.length);
    expect(new Set(all.map((f) => f.name)).size).toBe(all.length);
  });

  it('leaves prose alone: a question, a comparison, a list marker', () => {
    expect(nodes('Really?? Sure?? Not that ??')).not.toContain('Unsure');
    expect(nodes('x == y and a == b')).not.toContain('Highlight');
    expect(nodes('+ an item\n+ another')).toContain('ListItem');
    expect(nodes('+ an item\n+ another')).not.toContain('Added');
  });

  it('lifts a redaction while the caret is in it, and keeps the rest', () => {
    const doc = 'name: @@Sam Ortiz@@ and ==keep==';
    const looks = new Map(formats.map((f) => [f.name, { length: f.delimiter.length, css: f.look.kind === 'style' ? f.look.css : '', clearAtCaret: f.look.kind === 'style' ? f.look.clearAtCaret : undefined }]));
    const inside = EditorState.create({ doc, extensions: [glyphMarkdown(formats)], selection: { anchor: 10 } });
    const words = (state: EditorState, atCaret: boolean) => styledRanges(state, looks, { from: 0, to: doc.length }, atCaret).map((r) => doc.slice(r.from, r.to));
    expect(words(inside, true)).toEqual(['keep']);
    expect(words(inside, false)).toEqual(['Sam Ortiz', 'keep']);
    const outside = EditorState.create({ doc, extensions: [glyphMarkdown(formats)], selection: { anchor: 0 } });
    expect(words(outside, true)).toEqual(['Sam Ortiz', 'keep']);
  });
});
