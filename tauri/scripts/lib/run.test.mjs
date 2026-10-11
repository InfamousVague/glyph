// @vitest-environment node
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ROOT } from './paths.mjs';
import { run } from './run.mjs';

/*
 * The two smallest pieces of the scripts' plumbing: where the repository is,
 * and the local step that stops a deploy when it fails, with the words each
 * deploy has always used for that.
 */

afterEach(() => vi.restoreAllMocks());

describe('the repository root', () => {
  it('is the directory two above scripts/lib, the one holding package.json', () => {
    expect(ROOT).toBe(dirname(dirname(dirname(fileURLToPath(import.meta.url)))));
    expect(existsSync(join(ROOT, 'package.json'))).toBe(true);
    expect(JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8')).name).toBe('glyph');
    expect(ROOT.endsWith('/')).toBe(false);
  });
});

describe('a local step of a release', () => {
  /** run() with the script's exit caught: undefined when it went through, or the exit and what it said. */
  function attempt(...args) {
    vi.restoreAllMocks();
    const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(process, 'exit').mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
    try {
      return run(...args);
    } catch (error) {
      return { stopped: error.message, said: errors.mock.calls.map((call) => call.join(' ')) };
    }
  }

  it('carries on when the command succeeds', () => {
    expect(attempt(process.execPath, ['-e', ''], { stdio: 'ignore' })).toBeUndefined();
  });

  it('stops the deploy with exit 1, naming the command and the code it exited with', () => {
    expect(attempt(process.execPath, ['-e', 'process.exit(3)'], { stdio: 'ignore' })).toEqual({
      stopped: 'exit 1',
      said: [`\x1b[31mx\x1b[0m ${process.execPath} failed (exit 3).`],
    });
  });

  it('names the step instead when told, as deploy-server does ("cargo test failed")', () => {
    expect(attempt(process.execPath, ['-e', 'process.exit(101)'], { stdio: 'ignore' }, 'cargo test').said).toEqual([
      '\x1b[31mx\x1b[0m cargo test failed (exit 101).',
    ]);
  });

  it('says "signal" when the command was killed rather than exiting', () => {
    expect(attempt(process.execPath, ['-e', "process.kill(process.pid, 'SIGKILL')"], { stdio: 'ignore' }).said).toEqual([
      `\x1b[31mx\x1b[0m ${process.execPath} failed (exit signal).`,
    ]);
  });
});
