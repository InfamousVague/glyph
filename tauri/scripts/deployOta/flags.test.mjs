// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { deployFlags } from './flags.mjs';

/*
 * deploy-ota's flags, read without a deploy. The refusals are the point: they
 * used to throw a ReferenceError before the deploy's `fail` existed, so each
 * case here checks the sentence a person now sees, and the exit code.
 */

const ARGV = ['/usr/local/bin/node', '/repo/scripts/deploy-ota.mjs'];

afterEach(() => vi.restoreAllMocks());

/** deployFlags on these arguments, with the script's exit caught: the flags, or the exit and what it said. */
function read(...args) {
  vi.restoreAllMocks();
  const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
  vi.spyOn(process, 'exit').mockImplementation((code) => {
    throw new Error(`exit ${code}`);
  });
  try {
    return deployFlags([...ARGV, ...args]);
  } catch (error) {
    return { stopped: error.message, said: errors.mock.calls.map((call) => call.join(' ')) };
  }
}

describe('reading deploy-ota’s flags', () => {
  it('is the quick loop with none: web and OTA only, tests run, the release numbered from what is live', () => {
    expect(read()).toEqual({
      withApk: false,
      withDesktop: false,
      withMcp: false,
      sameVersion: false,
      isPublic: false,
      keepConnection: false,
      skipTests: false,
      askedRelease: null,
      notes: '',
    });
  });

  it('turns each switch on by its own name, in any order', () => {
    expect(read('--mcp', '--keep-connection', '--apk', '--skip-tests', '--desktop', '--same-version', '--public')).toMatchObject({
      withApk: true,
      withDesktop: true,
      withMcp: true,
      sameVersion: true,
      isPublic: true,
      keepConnection: true,
      skipTests: true,
    });
  });

  it('takes the release number and the notes from the word after each, the notes trimmed', () => {
    expect(read('--release', '13', '--notes', '  Faster voice notes. ', '--apk')).toMatchObject({
      askedRelease: 13,
      notes: 'Faster voice notes.',
      withApk: true,
    });
  });

  const needsNumber = {
    stopped: 'exit 1',
    said: ['\x1b[31mx\x1b[0m --release needs a whole number, the release this is on the current version.'],
  };

  it.each(['x', '0', '1.5', '--apk'])('refuses --release %s with the sentence saying what it needs', (value) => {
    expect(read('--release', value)).toEqual(needsNumber);
  });

  it('refuses --release with nothing after it the same way', () => {
    expect(read('--release')).toEqual(needsNumber);
  });

  it('refuses --notes with nothing after it, or with the next flag where the words should be', () => {
    const needs = { stopped: 'exit 1', said: ['\x1b[31mx\x1b[0m --notes needs the text of what changed.'] };
    expect(read('--notes')).toEqual(needs);
    expect(read('--notes', '   ')).toEqual(needs);
    expect(read('--notes', '--apk')).toEqual(needs);
  });

  const tooLong = {
    stopped: 'exit 1',
    said: ['\x1b[31mx\x1b[0m --notes is limited to 2000 bytes; the app refuses a longer manifest.'],
  };

  it('refuses notes longer than the app will take in a manifest', () => {
    expect(read('--notes', 'a'.repeat(2000)).notes).toHaveLength(2000);
    expect(read('--notes', 'a'.repeat(2001))).toEqual(tooLong);
  });

  it('counts the notes in bytes, as the app does, so curly quotes cannot slip a manifest past the deploy', () => {
    expect(read('--notes', '’'.repeat(666)).notes).toHaveLength(666);
    expect(read('--notes', '’'.repeat(667))).toEqual(tooLong);
  });
});
