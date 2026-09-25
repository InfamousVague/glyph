/**
 * Whether one app version is newer than another, as a deploy asks it.
 *
 * deploy-ota refuses to publish an APK that is not newer than the live one,
 * because an installed Ghost.md would never offer it - the app makes the same
 * comparison (isNewerVersion in src/app/core/ota.ts) before it offers an
 * install. The two cannot share one module across the Node scripts and the
 * page's TypeScript, so version.test.mjs runs one table of versions through
 * both and fails the day they disagree.
 */

/** Dotted versions compared numerically on their first three parts. The app compares the same way (core/ota.ts). */
export function isNewerVersion(offered, installed) {
  const parse = (v) => String(v).split(/[.+-]/).slice(0, 3).map((p) => Number.parseInt(p, 10) || 0);
  const a = parse(offered);
  const b = parse(installed);
  for (let i = 0; i < 3; i += 1) if (a[i] !== b[i]) return a[i] > b[i];
  return false;
}
