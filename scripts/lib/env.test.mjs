// @vitest-environment node
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadEnv, parseEnv } from './env.mjs';

/*
 * The parse the three deploy scripts each carried, pinned as it was: what a
 * .env line becomes, and the two lines a deploy stops on before it builds.
 */

describe('reading a .env', () => {
  it('takes NAME=value lines, with or without export, trimmed, one pair of surrounding quotes stripped', () => {
    const env = parseEnv(
      [
        'AFM_DEPLOY_HOST=box.example',
        'export AFM_DEPLOY_USER = deploy  ',
        'AFM_DEPLOY_PASS="pass word"',
        "NOTION_CLIENT_ID='abc'",
        'CRLF_KEY=value\r',
      ].join('\n'),
    );
    expect(env).toEqual({
      AFM_DEPLOY_HOST: 'box.example',
      AFM_DEPLOY_USER: 'deploy',
      AFM_DEPLOY_PASS: 'pass word',
      NOTION_CLIENT_ID: 'abc',
      CRLF_KEY: 'value',
    });
  });

  it('interprets nothing else: comments and lower-case names are skipped, a # inside a value is kept', () => {
    expect(parseEnv('# AFM_DEPLOY_HOST=commented\nlower=no\nTOKEN=ab#cd\nEMPTY=\nHALF="open')).toEqual({
      TOKEN: 'ab#cd',
      EMPTY: '',
      HALF: 'open',
    });
  });
});

describe('loading the repository’s .env', () => {
  let dir;
  afterEach(() => {
    vi.restoreAllMocks();
    if (dir) rmSync(dir, { recursive: true, force: true });
    dir = undefined;
  });

  /** loadEnv against a scratch root holding `text` as its .env (or no .env), with the exit caught. */
  function attempt(text, required) {
    dir = mkdtempSync(join(tmpdir(), 'glyph-env-'));
    if (text !== null) writeFileSync(join(dir, '.env'), text);
    vi.restoreAllMocks();
    const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(process, 'exit').mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
    try {
      return { env: loadEnv(required, dir), said: errors.mock.calls.map((call) => call.join(' ')) };
    } catch (error) {
      return { stopped: error.message, said: errors.mock.calls.map((call) => call.join(' ')) };
    }
  }

  it('hands back every value when the required keys are all there', () => {
    expect(attempt('A=1\nB=2\nC=3\n', ['A', 'B'])).toEqual({ env: { A: '1', B: '2', C: '3' }, said: [] });
  });

  it('stops with exit 1 when there is no .env, naming where it looked and every key it needs', () => {
    const run = attempt(null, ['AFM_DEPLOY_HOST', 'AFM_DEPLOY_USER', 'AFM_DEPLOY_PASS']);
    expect(run.stopped).toBe('exit 1');
    expect(run.said).toEqual([`\x1b[31mx\x1b[0m No .env at ${join(dir, '.env')} (needs AFM_DEPLOY_HOST / AFM_DEPLOY_USER / AFM_DEPLOY_PASS).`]);
  });

  it('stops with exit 1 on the first key that is missing or empty', () => {
    expect(attempt('AFM_DEPLOY_HOST=box\nAFM_DEPLOY_USER=\n', ['AFM_DEPLOY_HOST', 'AFM_DEPLOY_USER', 'AFM_DEPLOY_PASS'])).toEqual({
      stopped: 'exit 1',
      said: ['\x1b[31mx\x1b[0m .env is missing AFM_DEPLOY_USER.'],
    });
  });
});
