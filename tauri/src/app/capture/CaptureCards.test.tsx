import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { ListLanding } from './CaptureCards.tsx';

/** The recorder's cards (capture/CaptureCards.tsx): items landing in a list. */

describe('items landing in another note', () => {
  it('shows the list’s last lines as they were, then the new ones, all without their marks', () => {
    const body = '# Shopping\n\n- Eggs\n- Bread\n- [ ] Milk\n\n- Oat milk\n- Bin bags';
    const landing = show(<ListLanding title="Shopping" body={body} added={['- Oat milk', '- Bin bags']} />);
    const lines = [...landing.querySelectorAll('p')].map((line) => line.textContent);
    expect(lines).toEqual(['Shopping', 'Milk', 'Oat milk', 'Bin bags']);
  });
});
