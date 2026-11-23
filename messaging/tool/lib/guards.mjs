/**
 * The guard tests, run by a release before it builds anything (tool/release.mjs, tool/release-mac.mjs). Each reads
 * the source for something no compiler error shows and a release build depends on: every question about the device
 * asked through lib/platform_info.dart (dart:io's Platform throws in a browser), heavy work done aside through
 * runAside (Isolate.run throws there), and each half of a file split for the browser reached only through the file
 * that chooses it, the right way round (the review of the web build's first step, 2026-11-22). They take seconds.
 */
import { spawnSync } from 'node:child_process';

export const guardTests = ['test/platform_info_test.dart', 'test/aside_test.dart', 'test/web_build_test.dart'];

/** Runs [guardTests] in [root]; stops the release with [fail], before anything is built or sent, where one fails. */
export function requireGuards(root, fail) {
  console.log(`> The guard tests: ${guardTests.join(', ')}`);
  const result = spawnSync('flutter', ['test', ...guardTests], { cwd: root, stdio: 'inherit' });
  if (result.error) fail(`flutter test could not run for the guard tests: ${result.error.message}`);
  if (result.status !== 0) fail(`A guard test failed (${guardTests.join(', ')}). Nothing was built or sent: what it says is wrong in the source, and a release built from it would carry it. Fix that, commit, then release.`);
  console.log('ok the guard tests pass');
}
