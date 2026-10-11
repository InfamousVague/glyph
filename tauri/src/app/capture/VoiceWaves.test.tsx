import { afterEach, describe, expect, it } from 'vitest';
import { createRef } from 'react';
import { show, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';
import { VoiceWaves } from './VoiceWaves.tsx';

// The layer watches its own box and the mic's; jsdom has no observer.
stubResizeObserver();

/** The rings behind the recorder's mic: a layer that is decoration only, and empty until the layer has a size. */
describe('the voice’s rings', () => {
  afterEach(unmount);

  it('draws nothing a screen reader or a touch could reach, and no rings before the layer is laid out', () => {
    const anchor = createRef<HTMLElement>();
    const el = show(<VoiceWaves anchor={anchor} />);
    const layer = el.querySelector<HTMLElement>('[data-testid="voice-waves"]')!;
    expect(layer.getAttribute('aria-hidden')).toBe('true');
    // jsdom lays nothing out: the layer is 0 by 0, so no svg is drawn into it.
    expect(layer.querySelector('svg')).toBeNull();
  });
});
