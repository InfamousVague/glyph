// @vitest-environment node
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { describe, expect, it } from 'vitest';
import { ROOT } from './paths.mjs';
import { MARK, bold, dim } from './say.mjs';

/*
 * The bytes each line prints, pinned: six scripts printed these by hand before
 * say.mjs, and a deploy log is read by eye, so a mark that changes changes the
 * meaning of every log after it. The stopping forms run in a child Node, where
 * process.exit is real, so the exit code is checked as a shell sees it.
 */

const SAY = pathToFileURL(join(ROOT, 'scripts/lib/say.mjs')).href;

/** Runs `body` in a fresh Node with say.mjs's exports in scope; its stdout, stderr and exit code. */
function inNode(body) {
  const script = `import { fail, fatal, ok, say, step } from ${JSON.stringify(SAY)};\n${body}`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', script], { encoding: 'utf8' });
  return { stdout: result.stdout, stderr: result.stderr, status: result.status };
}

describe('the release voice', () => {
  it('marks a step cyan after a blank line, with its words in bold', () => {
    expect(inNode("step('Building the web app');").stdout).toBe('\n\x1b[36m>\x1b[0m \x1b[1mBuilding the web app\x1b[0m\n');
  });

  it('marks what went right with a green ok', () => {
    expect(inNode("ok('release 1.7.2-12');").stdout).toBe('\x1b[32mok\x1b[0m release 1.7.2-12\n');
  });

  it('stops on a red x, on stderr, with exit code 1 and nothing after it', () => {
    const run = inNode("fail('Remote command failed.'); ok('never printed');");
    expect(run).toEqual({ stdout: '', stderr: '\x1b[31mx\x1b[0m Remote command failed.\n', status: 1 });
  });

  it('dims and bolds as the terminal does, and the marks are the ones step, ok and fail print', () => {
    expect(dim('rollback')).toBe('\x1b[2mrollback\x1b[0m');
    expect(bold('Signing')).toBe('\x1b[1mSigning\x1b[0m');
    expect(MARK).toEqual({ step: '\x1b[36m>\x1b[0m', ok: '\x1b[32mok\x1b[0m', fail: '\x1b[31mx\x1b[0m' });
  });
});

describe('the tool voice', () => {
  it('indents a line of progress by two spaces', () => {
    expect(inNode("say('phone at 192.168.1.20:38081');").stdout).toBe('  phone at 192.168.1.20:38081\n');
  });

  it('stops on an Error: paragraph framed by blank lines, on stderr, with exit code 1', () => {
    const run = inNode("fatal('adb install failed'); say('never printed');");
    expect(run).toEqual({ stdout: '', stderr: '\nError: adb install failed\n\n', status: 1 });
  });
});
