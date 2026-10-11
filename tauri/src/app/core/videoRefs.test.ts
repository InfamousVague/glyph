import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { imageNames } from './imageRefs.ts';
import { VIDEO_EXTENSIONS, lengthOf, lengthText, videoMarkdown, videoNames, videoOfLine } from './videoRefs.ts';

/**
 * How a note names a film (core/videoRefs.ts): a poster picture linked to it, whose poster every picture pipeline
 * carries and whose film no picture pipeline takes for a picture.
 */

const LINE = '[![video 0:12](image/0f8e-poster.jpg)](video/0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4)';

describe('a film in the words', () => {
  it('is written as its poster linked to it, with its length', () => {
    expect(videoMarkdown('0f8e-poster.jpg', '0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4', 12_300)).toBe(LINE);
    expect(videoMarkdown('p.jpg', 'f.webm', 3_723_000)).toBe('[![video 1:02:03](image/p.jpg)](video/f.webm)');
  });

  it('carries its poster as an ordinary picture, and its film as nothing a picture pipeline reads', () => {
    const body = `# Harbour\n\n${LINE}\n\n![](image/other.jpg)\n`;
    expect(imageNames(body)).toEqual(['0f8e-poster.jpg', 'other.jpg']);
    expect(imageNames(body).some((name) => name.endsWith('.mp4'))).toBe(false);
    expect(videoNames(body)).toEqual(['0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4']);
    expect(videoNames(`${body}${LINE}\n`)).toHaveLength(1);
  });

  it('is a line of its own, whatever its lead, and nothing else is', () => {
    for (const line of [LINE, `- ${LINE}`, `1. ${LINE}`, `> ${LINE}`, `- [ ] ${LINE}`, `  ${LINE}  `]) {
      expect(videoOfLine(line), line).toEqual({ poster: '0f8e-poster.jpg', video: '0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4', alt: 'video 0:12', ms: 12_000 });
    }
    for (const line of [
      `Look ${LINE}`,
      `${LINE} here`,
      '![video 0:12](image/p.jpg)',
      '[![video 0:12](image/p.jpg)](video/f.mkv)',
      '[![video 0:12](image/p.jpg)](video/../f.mp4)',
      '[![video 0:12](https://x/p.jpg)](video/f.mp4)',
      '[a film](video/f.mp4)',
    ]) {
      expect(videoOfLine(line), line).toBeNull();
    }
  });

  it('reads its length back from the alt, and says one it cannot read as none', () => {
    expect(lengthOf('video 0:12')).toBe(12_000);
    expect(lengthOf('video 12:04')).toBe(724_000);
    expect(lengthOf('video 1:02:03')).toBe(3_723_000);
    expect(lengthOf('video')).toBeNull();
    expect(lengthOf('a walk')).toBeNull();
    expect(videoOfLine('[![video](image/p.jpg)](video/f.mp4)')?.ms).toBeNull();
  });

  it('says its length as a person reads it, a second at least for any film', () => {
    expect(lengthText(0)).toBe('0:00');
    expect(lengthText(300)).toBe('0:01');
    expect(lengthText(12_499)).toBe('0:12');
    expect(lengthText(59_600)).toBe('1:00');
    expect(lengthText(724_000)).toBe('12:04');
    expect(lengthText(3_723_000)).toBe('1:02:03');
  });
});

describe('the kinds of film', () => {
  it('are the ones Rust keeps, each of which a line names', () => {
    const rust = readFileSync(join(process.cwd(), 'src-tauri/src/videos.rs'), 'utf8');
    const kept = /pub const EXTENSIONS: \[&str; \d+\] = \[([^\]]*)\]/.exec(rust)?.[1];
    expect(kept, 'videos.rs no longer says `pub const EXTENSIONS`').toBeDefined();
    expect([...kept!.matchAll(/"(\w+)"/g)].map((found) => found[1]).sort()).toEqual([...VIDEO_EXTENSIONS].sort());
    for (const kind of VIDEO_EXTENSIONS) expect(videoNames(`[![video 0:01](image/p.jpg)](video/f.${kind})`), kind).toEqual([`f.${kind}`]);
  });
});
