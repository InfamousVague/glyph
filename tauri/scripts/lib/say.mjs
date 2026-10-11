/**
 * How the scripts talk: the marks, the step lines and the way they stop.
 *
 * Two voices, kept apart on purpose because people read them differently.
 *
 *   The release voice (deploy-ota, deploy-server, deploy-landing, test-report):
 *   a cyan `>` opens each step, a green `ok` closes what went right, and a red
 *   `x` is the last line before the script stops with exit code 1. A deploy
 *   log is scanned for the `x`, so it is always the line that says why.
 *
 *   The tool voice (fetch-model, push-fold): indented lines as it goes, and a
 *   blank-line-framed `Error:` paragraph when it cannot carry on, because
 *   those failures are usually several lines of advice rather than one.
 *
 * These were copied into six scripts, the release marks byte for byte. They
 * live here so a mark changed once changes everywhere, and so the bytes each
 * one prints are pinned by say.test.mjs: a deploy log is read by eye, and a
 * mark that drifts between scripts reads as a different kind of line.
 */

/** The three release marks, colour codes included. */
export const MARK = {
  step: '\x1b[36m>\x1b[0m',
  ok: '\x1b[32mok\x1b[0m',
  fail: '\x1b[31mx\x1b[0m',
};

export const bold = (text) => `\x1b[1m${text}\x1b[0m`;
export const dim = (text) => `\x1b[2m${text}\x1b[0m`;

/** A step of a release, after a blank line so the steps stand apart in a long build log. */
export const step = (text) => console.log(`\n${MARK.step} ${bold(text)}`);

/** Something a release checked and found right. */
export const ok = (text) => console.log(`${MARK.ok} ${text}`);

/** Why a release stopped, on stderr, and the stop itself: exit code 1. */
export function fail(message) {
  console.error(`${MARK.fail} ${message}`);
  process.exit(1);
}

/** A line of a tool's progress, indented under the command that started it. */
export const say = (line) => console.log(`  ${line}`);

/** Why a tool stopped, as a paragraph of its own on stderr, and exit code 1. */
export function fatal(message) {
  console.error(`\nError: ${message}\n`);
  process.exit(1);
}
