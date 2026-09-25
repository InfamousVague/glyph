/**
 * The box: attack.fm's server, where the releases (deploy-ota), glyph-api
 * (deploy-server) and ghostmarkdown.com (deploy-landing) land.
 *
 * What every deploy shares is here: the one account, reached as
 * AFM_DEPLOY_USER@AFM_DEPLOY_HOST from .env; the password handed to sshpass
 * through the SSHPASS environment variable and never in an argument list,
 * where `ps` would show it for as long as ssh runs; and the multiplexed
 * connection that lets `deploy-ota --keep-connection && npm run
 * deploy:server` spend one login between them. That last works only because
 * both name the SAME control socket, which is the reason it is written once,
 * here, rather than once in each script.
 *
 * What is not shared is each script's own: its option list (boxSshOptions
 * names the three the scripts use, and they differ), how it tells a refused
 * password from a failed install, and the remote scripts themselves. The
 * three connect differently enough - deploy-ota opens a master and then runs
 * several commands and uploads over it, deploy-server and deploy-landing each
 * send one script with a tarball on its stdin - that a single "deploy" call
 * would be three calls behind one name.
 *
 * ONE LOGIN PER DEPLOY. The box locks an account out after a handful of logins
 * in a short window, and the lockout answers "Permission denied" with the right
 * password - on 2026-09-12 a deploy authenticated its backup and its web upload
 * and was refused on the third login, the APK. So every ssh and rsync here
 * shares one multiplexed connection: the first authenticates (sshpass supplies
 * the password once), the rest ride its control socket with no login at all,
 * and the master closes itself two minutes after the last use. ~/.ssh because a
 * control socket path must be short (%C is a hash) and private.
 */
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { run } from './run.mjs';
import { fail } from './say.mjs';

/** The shared connection: deploy-ota and deploy-server must name the same socket for one login to serve both. */
const CONTROL_SOCKET = [
  '-o', 'ControlMaster=auto',
  '-o', `ControlPath=${join(homedir(), '.ssh', 'glyph-deploy-%C')}`,
  '-o', 'ControlPersist=120',
];

/**
 * The ssh options a deploy passes, in the order the scripts have always
 * passed them. deploy-ota takes the defaults; deploy-server adds a connect
 * timeout; deploy-landing adds the timeout, names the known-hosts file and
 * opens no shared connection, so it logs in once of its own every run.
 */
export function boxSshOptions({ connectTimeout = null, shareConnection = true, knownHosts = null } = {}) {
  return [
    '-o', 'StrictHostKeyChecking=no',
    ...(connectTimeout ? ['-o', `ConnectTimeout=${connectTimeout}`] : []),
    ...(shareConnection ? CONTROL_SOCKET : []),
    // A refused login costs one strike, not ssh's default three prompts' worth.
    '-o', 'NumberOfPasswordPrompts=1',
    ...(knownHosts ? ['-o', `UserKnownHostsFile=${knownHosts}`] : []),
  ];
}

/**
 * A tarball of `dir`'s contents, in memory, for a remote script to unpack
 * from its stdin. `maxBuffer` is the most the caller expects it to weigh.
 */
export function tarball(dir, maxBuffer) {
  // --no-xattrs: macOS stamps com.apple.provenance on everything, and GNU
  // tar on the box prints a warning per file for each one it cannot place.
  const tar = spawnSync('tar', ['-czf', '-', '--no-xattrs', '--no-mac-metadata', '-C', dir, '.'], { maxBuffer });
  if (tar.status !== 0) fail(`tar failed: ${String(tar.stderr)}`);
  return tar.stdout;
}

/**
 * The box, as the account in `env` (a loadEnv result), reached with
 * `sshOptions` (a boxSshOptions list). Nothing connects until a method runs.
 */
export function openBox(env, sshOptions) {
  const target = `${env.AFM_DEPLOY_USER}@${env.AFM_DEPLOY_HOST}`;
  const withPassword = () => ({ ...process.env, SSHPASS: env.AFM_DEPLOY_PASS });
  const rsyncShell = `ssh ${sshOptions.map((o) => (o.includes(' ') ? `'${o}'` : o)).join(' ')}`;

  /** One remote script, and the raw spawnSync result, for a caller that reads the status itself. */
  const exec = (script, options = {}) =>
    spawnSync('sshpass', ['-e', 'ssh', ...sshOptions, target, script], { ...options, env: withPassword() });

  return {
    /** user@host, as ssh and rsync name the box. */
    target,

    /*
     * The master is opened on its own, before anything else, with every stdio
     * ignored and `-fN` (authenticate, then background with no command). Letting
     * the first real command create it instead does not work here: that master
     * inherits the command's stdout pipe, spawnSync waits for the pipe to close,
     * the pipe closes only when the master exits - and the next command, finding
     * no master, logs in again.
     */
    logIn() {
      // A master left open by a deploy a moment ago (deploy-server.mjs rides the
      // same socket) is a login already spent: use it.
      if (spawnSync('ssh', [...sshOptions, '-O', 'check', target], { stdio: 'ignore' }).status === 0) return;
      const result = spawnSync('sshpass', ['-e', 'ssh', ...sshOptions, '-fN', target], {
        stdio: 'ignore',
        env: withPassword(),
      });
      if (result.status !== 0) {
        fail('Could not log in to the box. If the password is right, it is the lockout: wait ten minutes, and do not retry sooner.');
      }
    },

    exec,

    /** One remote script that must succeed; with `capture`, its stdout, trimmed. */
    ssh(script, { capture = false } = {}) {
      const result = exec(script, { stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit', encoding: 'utf8' });
      if (result.status !== 0) fail('Remote command failed.');
      return capture ? String(result.stdout ?? '').trim() : '';
    },

    /** `from` on this Mac to `to` on the box, over the same options, with rsync's `flags` first. */
    rsync(flags, from, to) {
      run('sshpass', ['-e', 'rsync', ...flags, '-e', rsyncShell, from, `${target}:${to}`], { env: withPassword() });
    },

    /** Closes the shared master now, rather than two minutes after its last use. */
    close() {
      spawnSync('ssh', [...sshOptions, '-O', 'exit', target], { stdio: 'ignore' });
    },
  };
}
