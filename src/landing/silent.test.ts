import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * The site plays no recording (Matt: "make sure the recorded meeting on the website doesn't use real audio"). Its
 * meeting is the app's own cassette (src/landing/Tape.tsx), which turns its reels and runs its counter on a tap and
 * makes no sound: there is no recording of anybody behind it. This fails if a sound file is ever added to the site,
 * or if the page or its built parts ever reach for a way to play one.
 */

const SITE = join(__dirname, '..', '..', 'landing');
const SOUND = /\.(wav|mp3|m4a|aac|ogg|oga|opus|flac|webm|weba|aiff?|caf)$/i;
const PLAYS = /<audio\b|new Audio\(|AudioContext|HTMLAudioElement|createMediaElementSource|data:audio\//;

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : [path];
  });
}

describe('the site', () => {
  it('holds no sound file', () => {
    expect(files(SITE).filter((path) => SOUND.test(path)).map((path) => relative(SITE, path))).toEqual([]);
  });

  it('never plays one: no page, script or part reaches for audio', () => {
    const playing = files(SITE)
      .filter((path) => /\.(html|js|css)$/.test(path))
      .filter((path) => PLAYS.test(readFileSync(path, 'utf8')))
      .map((path) => relative(SITE, path));
    expect(playing).toEqual([]);
  });

  it('draws its meeting with the cassette alone, which makes no sound', () => {
    const tape = readFileSync(join(__dirname, 'Tape.tsx'), 'utf8');
    expect(PLAYS.test(tape)).toBe(false);
  });
});
