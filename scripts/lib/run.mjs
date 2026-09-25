/**
 * Running a local step of a release - a build, a test run, an upload - the
 * way the deploy scripts always have: its output straight to the terminal,
 * and the whole deploy stopped, naming the command, the moment one fails.
 *
 * A step that fails and is carried past is how a release goes out half
 * built, so there is no "warn and continue" form here. A caller that has a
 * better sentence for a failure than "<command> failed" spawns the command
 * itself and says it (deploy-ota's APK and Mac checks do).
 */
import { spawnSync } from 'node:child_process';
import { fail } from './say.mjs';

/**
 * `command args`, with the terminal as its stdio unless `options` says
 * otherwise. A non-zero exit, or a signal, stops the script with
 * "<what> failed (exit <n>)." - `what` is the command unless the caller
 * names the step more exactly.
 */
export function run(command, args, options = {}, what = command) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (result.status !== 0) fail(`${what} failed (exit ${result.status ?? 'signal'}).`);
}
