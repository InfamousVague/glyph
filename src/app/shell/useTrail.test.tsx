import { describe, expect, it } from 'vitest';
import { act } from 'react';
import { ALL_NOTES, notePlace, type Place } from '../notes/visited.ts';
import { rerender, show } from '../../test/render.tsx';
import { useTrail, type TrailWalk } from './useTrail.ts';

/**
 * The arrows' half in React: arriving somewhere is recorded, a step answers where to go and is not itself recorded
 * as somewhere new, and a place whose note has gone is stepped over.
 */

let walk: TrailWalk;
function Probe({ place, live = new Set(['a', 'b']) }: { place: Place | null; live?: ReadonlySet<string> }) {
  walk = useTrail(place, live);
  return null;
}

describe('the trail, as the Shell walks it', () => {
  it('records each arrival, and steps back and forward through them', () => {
    show(<Probe place="list" />);
    expect(walk.canBack).toBe(false);
    rerender(<Probe place={notePlace('a')} />);
    rerender(<Probe place={ALL_NOTES} />);
    expect(walk.trail.places).toEqual(['list', 'note:a', 'notes']);
    let spot: Place | null = null;
    act(() => {
      spot = walk.back();
    });
    expect(spot).toBe('note:a');
    // The Shell goes where it was told, and the arrival is the step's, not somewhere new.
    rerender(<Probe place={notePlace('a')} />);
    expect(walk.trail.places).toEqual(['list', 'note:a', 'notes']);
    expect(walk.canOn).toBe(true);
    act(() => {
      spot = walk.on();
    });
    expect(spot).toBe('notes');
  });

  it('leaves out a place whose note can no longer be seen, and answers null with nowhere to go', () => {
    show(<Probe place="list" />);
    rerender(<Probe place={notePlace('a')} />);
    rerender(<Probe place={notePlace('b')} />);
    rerender(<Probe place={notePlace('b')} live={new Set(['b'])} />);
    let spot: Place | null = null;
    act(() => {
      spot = walk.back();
    });
    expect(spot).toBe('list');
    rerender(<Probe place="list" live={new Set(['b'])} />);
    expect(walk.canBack).toBe(false);
    act(() => {
      spot = walk.back();
    });
    expect(spot).toBeNull();
  });

  it('records the next arrival after a step that landed where the page already was', () => {
    show(<Probe place="list" />);
    rerender(<Probe place={notePlace('a')} />);
    rerender(<Probe place="list" />);
    // The note between the two visits home is gone: back steps over it, to home, where the page already is.
    rerender(<Probe place="list" live={new Set(['b'])} />);
    let spot: Place | null = null;
    act(() => {
      spot = walk.back();
    });
    expect(spot).toBe('list');
    rerender(<Probe place={notePlace('b')} live={new Set(['b'])} />);
    expect(walk.canBack).toBe(true);
    act(() => {
      spot = walk.back();
    });
    expect(spot).toBe('list');
  });

  it('does not count a capture or the Academy as a place', () => {
    show(<Probe place="list" />);
    rerender(<Probe place={null} />);
    rerender(<Probe place="list" />);
    expect(walk.trail.places).toEqual(['list']);
  });
});
