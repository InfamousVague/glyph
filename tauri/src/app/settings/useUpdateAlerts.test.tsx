import { afterEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { useUpdateAlerts } from './useUpdateAlerts.ts';

/**
 * The update alerts switch as the page sees it: absent on a build whose activity has none, and otherwise read from
 * the activity every time it could have changed behind the page's back - the permission prompt answering later, or
 * notifications revoked in system settings while Ghost.md was closed.
 */

/** The activity's side of it: what it answers, and what it answers when switched. */
let held: string | undefined = 'off';
let answerOnSet: (on: boolean) => string | undefined = (on) => (on ? 'on' : 'off');

function activity(): void {
  window.GlyphHost = {
    updateAlerts: () => held,
    setUpdateAlerts: (on: boolean) => {
      held = answerOnSet(on);
      return held;
    },
  } as unknown as typeof window.GlyphHost;
}

function Probe() {
  const alerts = useUpdateAlerts();
  return (
    <button type="button" data-available={String(alerts.available)} onClick={() => alerts.set(alerts.state === 'off')}>
      {alerts.state}
    </button>
  );
}

const probe = () => show(<Probe />).querySelector('button')!;

afterEach(() => {
  delete window.GlyphHost;
  delete window.__glyph;
  held = 'off';
  answerOnSet = (on) => (on ? 'on' : 'off');
});

describe('useUpdateAlerts', () => {
  it('is not there on a build whose activity has no alerts, and reads off', () => {
    const button = probe();
    expect(button.dataset.available).toBe('false');
    expect(button.textContent).toBe('off');
  });

  it('takes the activity’s own answer when switched, blocked included', () => {
    activity();
    answerOnSet = () => 'blocked';
    const button = probe();
    expect(button.dataset.available).toBe('true');
    act(() => button.click());
    expect(button.textContent).toBe('blocked');
  });

  it('reads again when the app comes back to the screen, and when the activity says the prompt was answered', () => {
    activity();
    const button = probe();
    expect(button.textContent).toBe('off');
    // Allowed in system settings while the app was away.
    held = 'on';
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    expect(button.textContent).toBe('on');
    // Android's prompt, answered after the switch was turned on.
    held = 'blocked';
    act(() => window.__glyph?.alerts?.());
    expect(button.textContent).toBe('blocked');
  });

  it('reads anything it does not know as off', () => {
    activity();
    held = 'maybe';
    expect(probe().textContent).toBe('off');
  });
});
