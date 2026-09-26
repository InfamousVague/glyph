import { describe, expect, it, vi } from 'vitest';
import { rerender, show } from '../../test/render.tsx';
import type { CaptureLanding } from '../capture/landing.ts';
import { useLanding } from './useLanding.ts';

/** The landing's toast as the note's screen asks for it, with its toast and dismiss watched. */
function Probe({ noteId, landing, toast, dismiss }: { noteId: string; landing?: CaptureLanding & { key: number }; toast: () => void; dismiss: () => void }) {
  useLanding(noteId, landing, null, { toast, dismiss });
  return null;
}

describe('the toast of a note a recording wrote into', () => {
  it('goes when the note is left, so its Undo never takes out words no longer on screen', () => {
    const toast = vi.fn();
    const dismiss = vi.fn();
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: [], key: 1 };
    show(<Probe noteId="house" landing={landing} toast={toast} dismiss={dismiss} />);
    expect(toast).toHaveBeenCalledWith(expect.objectContaining({ message: 'Added to House TODOs', action: expect.objectContaining({ label: 'Undo' }) }));
    expect(dismiss).not.toHaveBeenCalled();
    rerender(<Probe noteId="work" toast={toast} dismiss={dismiss} />);
    expect(dismiss).toHaveBeenCalledTimes(1);
  });
});
