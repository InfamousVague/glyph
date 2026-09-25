// @vitest-environment node
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { boxSshOptions, openBox, tarball } from './box.mjs';

/*
 * No box is contacted here. `ssh`, `sshpass` and `rsync` are stand-ins put
 * first on PATH, which write down the arguments and the SSHPASS they were
 * started with and exit as the test tells them - so what is checked is the
 * exact command line each method hands the real tools, and that the password
 * is in the environment of the one process that needs it and in no argument
 * list anywhere.
 */

const PASSWORD = 'correct horse battery staple';
const ENV = { AFM_DEPLOY_HOST: 'box.example', AFM_DEPLOY_USER: 'deploy', AFM_DEPLOY_PASS: PASSWORD };
const SOCKET = `ControlPath=${join(homedir(), '.ssh', 'glyph-deploy-%C')}`;

const FAKE = `#!/usr/bin/env node
const fs = require('node:fs');
const name = require('node:path').basename(process.argv[1]);
const stdin = process.env.FAKE_READ_STDIN ? fs.readFileSync(0).length : null;
fs.appendFileSync(process.env.FAKE_LOG, JSON.stringify({ name, args: process.argv.slice(2), SSHPASS: process.env.SSHPASS ?? null, stdin }) + '\\n');
process.stdout.write(process.env.FAKE_STDOUT ?? '');
process.exit(Number(process.env['FAKE_EXIT_' + name.toUpperCase()] ?? 0));
`;

const scratch = mkdtempSync(join(tmpdir(), 'glyph-box-'));
const bin = join(scratch, 'bin');
mkdirSync(bin);
for (const name of ['ssh', 'sshpass', 'rsync']) {
  writeFileSync(join(bin, name), FAKE);
  chmodSync(join(bin, name), 0o755);
}
const log = join(scratch, 'calls.jsonl');
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

/** Every stand-in started since the test began, in order. */
const calls = () => (existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map((line) => JSON.parse(line)) : []);

/** Runs `act`, turning the script's exit into a throw; what it returned or the exit, and what it printed on stderr. */
function caught(act) {
  const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
  vi.spyOn(process, 'exit').mockImplementation((code) => {
    throw new Error(`exit ${code}`);
  });
  try {
    return { value: act(), said: errors.mock.calls.map((call) => call.join(' ')) };
  } catch (error) {
    return { stopped: error.message, said: errors.mock.calls.map((call) => call.join(' ')) };
  }
}

beforeEach(() => {
  rmSync(log, { force: true });
  vi.stubEnv('PATH', `${bin}:${process.env.PATH}`);
  vi.stubEnv('FAKE_LOG', log);
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

describe('the ssh options each deploy passes', () => {
  it('are, for deploy-ota, the shared socket and one password prompt', () => {
    expect(boxSshOptions()).toEqual([
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ControlMaster=auto',
      '-o', SOCKET,
      '-o', 'ControlPersist=120',
      '-o', 'NumberOfPasswordPrompts=1',
    ]);
  });

  it('are, for deploy-server, the same with a connect timeout, so it rides a master deploy-ota left open', () => {
    expect(boxSshOptions({ connectTimeout: 20 })).toEqual([
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=20',
      '-o', 'ControlMaster=auto',
      '-o', SOCKET,
      '-o', 'ControlPersist=120',
      '-o', 'NumberOfPasswordPrompts=1',
    ]);
  });

  it('are, for deploy-landing, a timeout and a known-hosts file and no shared connection', () => {
    const knownHosts = join(homedir(), '.ssh', 'known_hosts');
    expect(boxSshOptions({ connectTimeout: 20, shareConnection: false, knownHosts })).toEqual([
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'ConnectTimeout=20',
      '-o', 'NumberOfPasswordPrompts=1',
      '-o', `UserKnownHostsFile=${knownHosts}`,
    ]);
  });
});

describe('a session with the box', () => {
  const options = boxSshOptions();

  it('names the box as user@host', () => {
    expect(openBox(ENV, options).target).toBe('deploy@box.example');
  });

  it('runs a script as the one argument after the box, the password in SSHPASS alone, and hands back what happened', () => {
    vi.stubEnv('FAKE_STDOUT', 'STAMP 20260925\n');
    vi.stubEnv('FAKE_READ_STDIN', '1');
    const result = openBox(ENV, options).exec('set -e; echo hi', { input: Buffer.from('token\n'), stdio: ['pipe', 'pipe', 'inherit'] });
    expect(result.status).toBe(0);
    expect(String(result.stdout)).toBe('STAMP 20260925\n');
    expect(calls()).toEqual([
      { name: 'sshpass', args: ['-e', 'ssh', ...options, 'deploy@box.example', 'set -e; echo hi'], SSHPASS: PASSWORD, stdin: 6 },
    ]);
  });

  it('leaves the status to the caller of exec: a refused login is theirs to name', () => {
    vi.stubEnv('FAKE_EXIT_SSHPASS', '5');
    expect(openBox(ENV, options).exec('true', { stdio: 'ignore' }).status).toBe(5);
  });

  it('with ssh, hands back the trimmed output when asked, and stops the deploy when the script fails', () => {
    vi.stubEnv('FAKE_STDOUT', '  one\ntwo  \n');
    expect(caught(() => openBox(ENV, options).ssh('ls', { capture: true }))).toEqual({ value: 'one\ntwo', said: [] });
    vi.stubEnv('FAKE_STDOUT', '');
    vi.stubEnv('FAKE_EXIT_SSHPASS', '1');
    expect(caught(() => openBox(ENV, options).ssh('false'))).toEqual({
      stopped: 'exit 1',
      said: ['\x1b[31mx\x1b[0m Remote command failed.'],
    });
  });

  it('logs in by riding a master that is already open, spending no login', () => {
    expect(caught(() => openBox(ENV, options).logIn())).toEqual({ value: undefined, said: [] });
    expect(calls()).toEqual([{ name: 'ssh', args: [...options, '-O', 'check', 'deploy@box.example'], SSHPASS: null, stdin: null }]);
  });

  it('otherwise logs in once, in the background, before any command', () => {
    vi.stubEnv('FAKE_EXIT_SSH', '255');
    expect(caught(() => openBox(ENV, options).logIn())).toEqual({ value: undefined, said: [] });
    expect(calls().map(({ name, args, SSHPASS }) => ({ name, args, SSHPASS }))).toEqual([
      { name: 'ssh', args: [...options, '-O', 'check', 'deploy@box.example'], SSHPASS: null },
      { name: 'sshpass', args: ['-e', 'ssh', ...options, '-fN', 'deploy@box.example'], SSHPASS: PASSWORD },
    ]);
  });

  it('says a refused login may be the lockout, and to wait rather than retry', () => {
    vi.stubEnv('FAKE_EXIT_SSH', '255');
    vi.stubEnv('FAKE_EXIT_SSHPASS', '5');
    expect(caught(() => openBox(ENV, options).logIn())).toEqual({
      stopped: 'exit 1',
      said: ['\x1b[31mx\x1b[0m Could not log in to the box. If the password is right, it is the lockout: wait ten minutes, and do not retry sooner.'],
    });
  });

  it('uploads with rsync over the same options, flags first, and stops naming sshpass when it fails', () => {
    const box = openBox(ENV, options);
    expect(caught(() => box.rsync(['-az', '--delete'], '/tmp/dist/', '/home/deploy/.glyph-stage/'))).toEqual({ value: undefined, said: [] });
    expect(calls()).toEqual([
      {
        name: 'sshpass',
        args: ['-e', 'rsync', '-az', '--delete', '-e', `ssh ${options.join(' ')}`, '/tmp/dist/', 'deploy@box.example:/home/deploy/.glyph-stage/'],
        SSHPASS: PASSWORD,
        stdin: null,
      },
    ]);
    vi.stubEnv('FAKE_EXIT_SSHPASS', '23');
    expect(caught(() => box.rsync(['-z'], 'a', 'b')).said).toEqual(['\x1b[31mx\x1b[0m sshpass failed (exit 23).']);
  });

  it('quotes an option with a space in it for rsync, which hands its -e to a shell', () => {
    openBox(ENV, ['-o', 'ProxyCommand=nc %h 22']).rsync([], 'a', 'b');
    expect(calls()[0].args[3]).toBe("ssh -o 'ProxyCommand=nc %h 22'");
  });

  it('closes the master when asked, with no password', () => {
    openBox(ENV, options).close();
    expect(calls()).toEqual([{ name: 'ssh', args: [...options, '-O', 'exit', 'deploy@box.example'], SSHPASS: null, stdin: null }]);
  });

  it('never puts the password in an argument list, whatever it runs', () => {
    const box = openBox(ENV, options);
    vi.stubEnv('FAKE_EXIT_SSH', '255');
    box.logIn();
    box.exec('true', { stdio: 'ignore' });
    box.ssh('true');
    box.rsync(['-z'], 'a', 'b');
    box.close();
    expect(calls()).toHaveLength(6);
    for (const call of calls()) expect(call.args.join(' ')).not.toContain(PASSWORD);
  });
});

describe('a directory as a tarball for a remote script’s stdin', () => {
  it('holds the directory’s files, relative to it', () => {
    const dir = join(scratch, 'page');
    mkdirSync(join(dir, 'assets'), { recursive: true });
    writeFileSync(join(dir, 'index.html'), '<!doctype html>');
    writeFileSync(join(dir, 'assets/site.css'), 'body {}');
    vi.unstubAllEnvs();
    const listed = spawnSync('tar', ['-tzf', '-'], { input: tarball(dir, 1024 * 1024), encoding: 'utf8' }).stdout;
    expect(listed.split('\n').filter(Boolean).sort()).toEqual(['./', './assets/', './assets/site.css', './index.html']);
  });

  it('stops the deploy, with tar’s own complaint, when the directory cannot be read', () => {
    vi.unstubAllEnvs();
    const run = caught(() => tarball(join(scratch, 'not-there'), 1024 * 1024));
    expect(run.stopped).toBe('exit 1');
    expect(run.said[0].startsWith('\x1b[31mx\x1b[0m tar failed: ')).toBe(true);
    expect(run.said[0]).toContain('not-there');
  });
});
