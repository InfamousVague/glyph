import { EditorState, Text } from '@codemirror/state';
import { ensureSyntaxTree } from '@codemirror/language';
import { describe, expect, it } from 'vitest';
import { bookmarkLineIn } from '../editor/bookmarkLine.ts';
import { choiceOn } from '../editor/choices.ts';
import { framesIn } from '../editor/canvasFrames.ts';
import { countersIn } from '../editor/counters.ts';
import { calloutKind } from '../editor/extended.ts';
import { footnotesIn } from '../editor/footnotes.ts';
import { headingCounts } from '../editor/headingProgress.ts';
import { glyphMarkdown } from '../editor/language.ts';
import { isTint, notePattern, notesIn } from '../editor/markNotes.ts';
import { sumOnLine } from '../editor/sums.ts';
import { tagsIn } from '../editor/tags.ts';
import { wikiLinksIn } from '../editor/wikiLinks.ts';
import { MARKS } from '../plugins/marks/index.tsx';
import { BUILT_IN } from '../plugins/registry.ts';
import { boardsIn, itemsIn, refsIn } from './boards.ts';
import { shortcodesIn } from './emoji.ts';
import { imageNames } from './images.ts';
import { peekMarkdown } from '../notes/peek.ts';
import { SAMPLE_TITLE, sampleNoteBody } from './sampleNote.ts';
import { noteTitle } from './store.ts';

const FORMATS = BUILT_IN.flatMap((plugin) => plugin.formats ?? []);

/** The set of node names the editor's parser finds in `doc`, plugin formattings included. */
function found(doc: string): Set<string> {
  const state = EditorState.create({ doc, extensions: [glyphMarkdown(FORMATS)] });
  const names = new Set<string>();
  // The whole note, however long the parse takes: the plain tree is only what the parser reached in its time slice,
  // and on a busy machine that stopped short of the table.
  ensureSyntaxTree(state, state.doc.length, 10_000)?.iterate({ enter: (node) => void names.add(node.name) });
  return names;
}

/** Everything the editor draws specially or highlights: each must be in the sample note. */
const EVERYTHING = [
  'ATXHeading1',
  'ATXHeading2',
  'ATXHeading3',
  'ATXHeading4',
  'ATXHeading5',
  'ATXHeading6',
  'StrongEmphasis',
  'Emphasis',
  'Strikethrough',
  'InlineCode',
  'Escape',
  'Superscript',
  'Subscript',
  'Emoji',
  'Spoiler',
  'Highlight',
  'Aside',
  'Unsure',
  'Shout',
  'Added',
  // The five effects (plugins/marks/index.tsx, editor/textEffects.ts).
  'Heat',
  'Frost',
  'Wave',
  'Shimmer',
  'Haunt',
  'BulletList',
  'OrderedList',
  'TaskMarker',
  'Blockquote',
  'Link',
  'URL',
  'Table',
  'FencedCode',
  'CodeInfo',
  'HorizontalRule',
  'Image',
];

const body = sampleNoteBody('a1b2c3.jpg');
const lines = body.split('\n');
const doc = Text.of(lines);

describe('the sample note', () => {
  it('holds one of everything the editor knows, and parses as such', () => {
    const names = found(body);
    for (const name of EVERYTHING) expect(names, name).toContain(name);
  });

  it('holds every mark the Marks plugin adds, each of them parsed', () => {
    const names = found(body);
    for (const mark of MARKS) expect(names, mark.name).toContain(mark.name);
  });

  it('teaches each of the plugin’s marks with the words that say it', () => {
    // A cue that is not the mark's own name is written out; the rest are covered by "the others work the same way",
    // which is only true while each of them is said as its name.
    for (const mark of MARKS) {
      if (!mark.cue) continue;
      if (mark.cue === mark.name.toLowerCase()) expect(body, mark.name).toMatch(new RegExp(`${mark.name}|${mark.cue}`, 'i'));
      else expect(body, mark.name).toContain(`"${mark.cue}"`);
    }
    expect(body).toContain('"spoiler", then "end spoiler"');
    expect(body).toContain('"highlight", then "end highlight"; the others work the same way');
    expect(body).toContain('"heated", then "end heated"');
  });

  it('holds the marks that are drawn by what the line says rather than by the parser, each found the way the editor finds it', () => {
    expect(tagsIn(body).map((tag) => tag.name)).toContain('cabin');
    expect(countersIn(body)).toHaveLength(1);
    expect(lines.filter((line) => sumOnLine(line))).toHaveLength(1);
    expect(lines.map((_, n) => choiceOn(doc, n + 1)).filter(Boolean)).toHaveLength(2);
    expect(lines.filter((line) => /^>\|\s*\S/.test(line))).toHaveLength(1);
    expect(lines.map(calloutKind).filter(Boolean)).toEqual(['tip']);
    expect(footnotesIn(body).map((note) => note.name)).toEqual(['sam']);
    expect(body).toMatch(/\[\^sam\](?!:)/);
    expect(lines.some((line, n) => n > 0 && /^\s{0,3}:\s+\S/.test(line) && (lines[n - 1] ?? '').trim() !== '')).toBe(true);
    expect(shortcodesIn(body).map((code) => code.emoji)).toContain('🎉');
    expect(body).toMatch(/\$x\^2 \+ y\$/);
    expect(wikiLinksIn(body).map((link) => link.title)).toContain('Weekend trip');
    // A name on an item, a pointer at it from the words, and a board laying the named items out.
    expect(itemsIn(body).map((item) => item.id)).toEqual(['book-cabin', 'call-sam']);
    expect(refsIn(body).map((ref) => ref.id)).toContain('book-cabin');
    expect(boardsIn(body)).toHaveLength(1);
    expect(body).toMatch(/```mermaid\n[\s\S]*?\n```/);
    // A heading with to-dos under it says how many are done.
    expect(headingCounts(doc).some((count) => count.total === 2 && count.done === 1)).toBe(true);
    // A highlight in a colour, and a note on a mark: the same brackets after the same marks, told apart.
    const notes = notesIn(body, notePattern(FORMATS)!);
    expect(notes.some((note) => isTint(note, FORMATS))).toBe(true);
    expect(notes.some((note) => !isTint(note, FORMATS))).toBe(true);
  });

  it('opens at the top, and needs nothing but itself: the bookmark and the frame are words about the marks', () => {
    expect(bookmarkLineIn(body)).toBeNull();
    expect(framesIn(body)).toEqual([]);
    expect(body).toContain('`§§`');
    expect(body).toContain('`![[ ]]`');
  });

  it('is titled, previews plainly, and names its picture', () => {
    expect(noteTitle(body)).toBe(SAMPLE_TITLE);
    expect(peekMarkdown(body)).toContain('A note is plain Markdown');
    expect(imageNames(body)).toEqual(['a1b2c3.jpg']);
  });

  it('says nothing of a picture where none could be drawn', () => {
    const plain = sampleNoteBody(null);
    expect(imageNames(plain)).toEqual([]);
    expect(plain).not.toContain('picture');
    expect(found(plain)).not.toContain('Image');
  });
});
