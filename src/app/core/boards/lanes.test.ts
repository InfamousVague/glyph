import { describe, expect, it } from 'vitest';
import {
  addToLane,
  lanesOf,
  matchLane,
  moveToLane,
} from '../boards.ts';

/**
 * Lanes by voice: a lane found by the name said, a to-do added to it, an item moved into it.
 *
 * core/boards/lanes.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

describe('lanes, by voice', () => {
  // Matt: "add voice commands and cues for adding to swimlanes on the board".
  const doc = [
    '# Launch',
    '',
    '```board height=18',
    'To do: ship-page',
    'In progress:',
    'Waiting on Sam: photos',
    'Done: pick-date',
    '```',
    '',
    '- [ ] Ship the pricing page ^ship-page',
    '- [ ] Get the photos back ^photos',
    '- [x] Pick a launch date ^pick-date',
    '- [ ] Email the beta list',
    '- A thought with no box',
    '',
    '```md',
    '- [ ] Fix the login button in an example',
    '```',
  ].join('\n');

  it('lists every board\u2019s lanes, with where each board opens', () => {
    expect(lanesOf(doc)).toEqual([
      { name: 'To do', board: 3, column: 0 },
      { name: 'In progress', board: 3, column: 1 },
      { name: 'Waiting on Sam', board: 3, column: 2 },
      { name: 'Done', board: 3, column: 3 },
    ]);
    expect(lanesOf('- [ ] No board here')).toEqual([]);
  });

  it('finds the lane a name says, however it is said', () => {
    const lanes = lanesOf(doc);
    const named = (spoken: string) => matchLane(spoken, lanes)?.lane.name ?? null;
    expect(named('todo')).toBe('To do');
    expect(named('the to-do column')).toBe('To do');
    expect(named('In Progress lane')).toBe('In progress');
    expect(named('waiting')).toBe('Waiting on Sam');
    expect(named('finished')).toBe('Done');
    expect(named('done swimlane')).toBe('Done');
    expect(named('groceries')).toBeNull();
    expect(matchLane('done', lanes)?.score).toBe(1);
  });

  it('adds a to-do to a lane: the line under the board\u2019s last item, the card at the top of the lane', () => {
    const lane = matchLane('in progress', lanesOf(doc))!.lane;
    const added = addToLane(doc, lane, 'Call Sam about the copy')!;
    expect(added.line).toBe('- [ ] Call Sam about the copy ^call-sam-about');
    const lines = added.body.split('\n');
    expect(lines.slice(2, 8)).toEqual(['```board height=18', 'To do: ship-page', 'In progress: call-sam-about', 'Waiting on Sam: photos', 'Done: pick-date', '```']);
    expect(lines[12]).toBe('- [ ] Call Sam about the copy ^call-sam-about');
    expect(addToLane(doc, lane, '  ')).toBeNull();
  });

  it('moves an item on the board to a lane, and ticks it going into Done', () => {
    const lanes = lanesOf(doc);
    const moved = moveToLane(doc, 'the pricing page', matchLane('done', lanes)!.lane)!;
    expect(moved.item).toEqual({ id: 'ship-page', text: 'Ship the pricing page', line: 10 });
    expect(moved.ticked).toBe(true);
    expect(moved.body).toContain('To do:\nIn progress:\nWaiting on Sam: photos\nDone: pick-date, ship-page\n');
    expect(moved.body).toContain('- [x] Ship the pricing page ^ship-page\n');
  });

  it('unticks an item taken out of Done, and leaves a box alone between other lanes', () => {
    const lanes = lanesOf(doc);
    const back = moveToLane(doc, 'launch date', matchLane('in progress', lanes)!.lane)!;
    expect(back.ticked).toBe(false);
    expect(back.body).toContain('- [ ] Pick a launch date ^pick-date');
    expect(back.body).toContain('In progress: pick-date\n');
    const across = moveToLane(doc, 'photos back', matchLane('to do', lanes)!.lane)!;
    expect(across.ticked).toBeNull();
    expect(across.body).toContain('To do: ship-page, photos\nIn progress:\nWaiting on Sam:\n');
  });

  it('names an item not yet on the board and puts it there, a box or none', () => {
    const lanes = lanesOf(doc);
    const email = moveToLane(doc, 'email beta list', matchLane('waiting', lanes)!.lane)!;
    expect(email.item).toMatchObject({ id: 'email-beta-list', line: 13 });
    expect(email.body).toContain('- [ ] Email the beta list ^email-beta-list\n');
    expect(email.body).toContain('Waiting on Sam: photos, email-beta-list\n');
    // An item with no box goes into Done without a tick, since there is nothing to tick.
    const thought = moveToLane(doc, 'a thought with no box', matchLane('done', lanes)!.lane)!;
    expect(thought.ticked).toBeNull();
    expect(thought.body).toContain('- A thought with no box ^thought-no-box\n');
  });

  it('finds nothing in a block of code, nothing for words that match no item, and nothing for a lane that is gone', () => {
    const lanes = lanesOf(doc);
    expect(moveToLane(doc, 'fix the login button', lanes[0]!)).toBeNull();
    expect(moveToLane(doc, 'water the plants', lanes[0]!)).toBeNull();
    const renamed = doc.replace('In progress:', 'Doing:');
    expect(moveToLane(renamed, 'pricing page', lanes[1]!)).toBeNull();
    expect(addToLane(renamed, lanes[1]!, 'Anything')).toBeNull();
  });
});
