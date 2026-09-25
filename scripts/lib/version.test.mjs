import { describe, expect, it } from 'vitest';
import { isNewerVersion as appIsNewer } from '../../src/app/core/ota.ts';
import { isNewerVersion } from './version.mjs';

/*
 * deploy-ota refuses an APK that is not newer than the live one because the
 * app would never offer it; that refusal is only right while the two compare
 * versions the same way. One table, both functions, so the day one of them
 * changes alone this fails.
 */

const TABLE = [
  // [offered, installed, newer?]
  ['1.7.3', '1.7.2', true],
  ['1.7.2', '1.7.2', false],
  ['1.7.1', '1.7.2', false],
  ['1.10.0', '1.9.9', true],
  ['2.0.0', '1.99.99', true],
  ['0.10.0', '0.9.9', true],
  // A suffix after a dash or a plus is not a version part: 1.7.2-12, the twelfth OTA on 1.7.2, is not past 1.7.2.
  ['1.7.2-12', '1.7.2', false],
  ['1.7.2', '1.7.2-12', false],
  ['1.7.3-1', '1.7.2-40', true],
  ['1.7.2+abc', '1.7.2', false],
  // Parts past the third are ignored, and what is not a number counts as nought.
  ['1.7.2.9', '1.7.2', false],
  ['1.x.0', '1.0.0', false],
  ['garbage', '0.0.1', false],
];

describe('whether a version is newer, as the deploy and the app each decide it', () => {
  it.each(TABLE)('%s over %s: %s', (offered, installed, newer) => {
    expect(isNewerVersion(offered, installed)).toBe(newer);
    expect(appIsNewer(offered, installed)).toBe(newer);
  });
});
