import { describe, expect, it } from 'vitest';
import { FULL_EVERY, hashText, mergeFiles, MOST_VERSIONS, readFile, withVersion, writeFile } from './file.ts';

const at = (minute: number) => Date.UTC(2026, 9, 4, 15, minute);
const keep = (file: string | null, text: string, minute: number, extra: { by?: string; label?: string } = {}) =>
  withVersion(file, 'gho-1', text, { at: at(minute), by: extra.by ?? 'matt', ...(extra.label ? { label: extra.label } : {}) });

describe('a versions file', () => {
  it('reads like a lock file: a head line per version, and under it only what changed', () => {
    let file = keep(null, '# Launch plan\n- book the venue\n', 0)!;
    file = keep(file, '# Launch plan\n- book the venue (done)\n- send invites\n', 42, { label: 'Before the review' })!;
    expect(file).toBe(
      [
        '# Ghost.md versions 1',
        '# note gho-1',
        '# A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.',
        '',
        `v1 2026-10-04T15:00:00.000Z matt ${hashText('# Launch plan\n- book the venue\n')} full`,
        '  +# Launch plan',
        '  +- book the venue',
        '  +',
        `v2 2026-10-04T15:42:00.000Z matt ${hashText('# Launch plan\n- book the venue (done)\n- send invites\n')} "Before the review"`,
        '  =1',
        '  -- book the venue',
        '  +- book the venue (done)',
        '  +- send invites',
        '  =1',
        '',
      ].join('\n'),
    );
  });

  it('gives back every version exactly, with how much each changed', () => {
    let file: string | null = null;
    const texts = ['a', 'a\nb', 'b\nc', '', 'line with "quotes" and  =3 inside\n  +not a step\n'];
    texts.forEach((text, i) => (file = keep(file, text, i) ?? file));
    const read = readFile(file!)!;
    expect(read.noteId).toBe('gho-1');
    expect(read.damaged).toBe(0);
    expect(read.versions.map((v) => v.text)).toEqual(texts);
    expect(read.versions.map((v) => v.n)).toEqual([1, 2, 3, 4, 5]);
    expect(read.versions[2]).toMatchObject({ added: 1, removed: 1, by: 'matt', at: at(2) });
  });

  it('keeps no version of no change, but names the last one when asked to', () => {
    const file = keep(null, 'words', 0)!;
    expect(keep(file, 'words', 5)).toBeNull();
    const named = keep(file, 'words', 5, { label: 'Sent to Sam' })!;
    expect(readFile(named)!.versions).toHaveLength(1);
    expect(readFile(named)!.versions[0]!.label).toBe('Sent to Sam');
  });

  it('writes a whole version every so often, so a damaged one costs only those up to the next', () => {
    let file: string | null = null;
    for (let i = 0; i < FULL_EVERY + 5; i += 1) file = keep(file, `version ${i}\nsame tail`, i);
    expect(file!.split('\n').filter((line) => line.endsWith(' full'))).toHaveLength(2);
    // Break version 3's change: versions 3 to 50 cannot be rebuilt, the whole one at 51 starts again.
    const broken = file!.replace('  +version 2', '  +version two');
    const read = readFile(broken)!;
    expect(read.damaged).toBe(FULL_EVERY - 2);
    expect(read.versions.map((v) => v.text.split('\n')[0])).toEqual(['version 0', 'version 1', ...Array.from({ length: 5 }, (_, i) => `version ${FULL_EVERY + i}`)]);
  });

  it('keeps at most MOST_VERSIONS, letting the oldest go', () => {
    const versions = Array.from({ length: MOST_VERSIONS + 3 }, (_, i) => ({ at: i, by: 'matt', text: `v${i}` }));
    const read = readFile(writeFile('gho-1', versions))!;
    expect(read.versions).toHaveLength(MOST_VERSIONS);
    expect(read.versions[0]!.text).toBe('v3');
  });

  it('is not a versions file when it does not say so', () => {
    expect(readFile('# Shopping\n- milk')).toBeNull();
    expect(keep('# Shopping', 'fresh', 1)).toContain('v1 ');
  });
});

describe('two devices’ versions, merged', () => {
  it('is every version from both, once, in the order they were kept', () => {
    const shared = keep(keep(null, 'one', 0)!, 'one\ntwo', 1)!;
    const phone = keep(shared, 'one\ntwo\nphone', 5, { by: 'matt' })!;
    const mac = keep(keep(shared, 'one\ntwo\nmac', 3, { by: 'matt' })!, 'one\ntwo\nmac\nmore', 7, { label: 'Done' })!;
    const merged = readFile(mergeFiles(phone, mac, 'gho-1')!)!;
    expect(merged.damaged).toBe(0);
    expect(merged.versions.map((v) => v.text)).toEqual(['one', 'one\ntwo', 'one\ntwo\nmac', 'one\ntwo\nphone', 'one\ntwo\nmac\nmore']);
    expect(merged.versions[4]!.label).toBe('Done');
    // Merging again changes nothing, either way round.
    expect(mergeFiles(mergeFiles(phone, mac, 'gho-1'), mac, 'gho-1')).toBe(mergeFiles(mac, phone, 'gho-1'));
  });

  it('takes the one there is when the other side has none', () => {
    const file = keep(null, 'only', 0)!;
    expect(mergeFiles(null, file, 'gho-1')).toBe(file);
    expect(mergeFiles(null, null, 'gho-1')).toBeNull();
  });
});
