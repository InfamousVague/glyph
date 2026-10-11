import { describe, expect, it } from 'vitest';
import { describeBuild, isNewerVersion, sourceHost } from './ota.ts';

describe('versions', () => {
  it('compares dotted versions numerically', () => {
    expect(isNewerVersion('0.10.0', '0.9.9')).toBe(true);
    expect(isNewerVersion('0.2.0', '0.2.0')).toBe(false);
    expect(isNewerVersion('0.1.9', '0.2.0')).toBe(false);
    expect(isNewerVersion('1.0.0', '0.99.0')).toBe(true);
  });

  it('names an update source by its host', () => {
    expect(sourceHost('https://attack.fm/glyph')).toBe('attack.fm');
    expect(sourceHost(undefined)).toBeNull();
    expect(sourceHost('not a url')).toBeNull();
  });

  it('describes a build id, and refuses to invent one', () => {
    expect(describeBuild('20260912221530')).not.toBe('unknown build');
    expect(describeBuild('nope')).toBe('unknown build');
    expect(describeBuild(null)).toBe('unknown build');
  });
});
