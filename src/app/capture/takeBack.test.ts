import { describe, expect, it } from 'vitest';
import { commandAfterOpener, contentWords, corrects, opensSend, opensTakeBack, quoted, readSend, readTakeBack, swapWord, takeBackAt } from './takeBack.ts';

/** The grammar of taking back what was just said (capture/takeBack.ts): which phrases are one, and what each holds. */

describe('a safe opener', () => {
  it.each(['Scratch that.', 'Strike that.', 'Take that back.', 'Forget that.', 'Delete that.', 'Never mind.', 'Cancel that.', 'Ignore that.', 'No wait.', 'No, wait.', 'Wait no.', 'Wait, no.'])(
    'is read alone: %s',
    (said) => {
      expect(readTakeBack(said)).toMatchObject({ head: '', risky: false, rest: '', send: null, keyed: false, afterComma: false });
    },
  );

  it('takes its rest after a pause, a colon or “and”, as said', () => {
    expect(readTakeBack('Scratch that, call the plumber.')).toMatchObject({ opener: 'Scratch that', rest: 'call the plumber.', said: 'Scratch that, call the plumber.' });
    // After a stop Whisper capitalises whatever comes next, so the first letter comes down: "Tomorrow" is no name.
    expect(readTakeBack('Scratch that. Call the plumber.')).toMatchObject({ rest: 'call the plumber.' });
    expect(readTakeBack('Scratch that. Tomorrow.')).toMatchObject({ rest: 'tomorrow.' });
    expect(readTakeBack('Scratch that. TODOs first.')).toMatchObject({ rest: 'TODOs first.' });
    expect(readTakeBack('Scratch that, Sarah.')).toMatchObject({ rest: 'Sarah.' });
    expect(readTakeBack('Scratch that: call the plumber.')).toMatchObject({ rest: 'call the plumber.' });
    expect(readTakeBack('Scratch that and call the plumber.')).toMatchObject({ rest: 'call the plumber.' });
    // Lead-ins after the opener stay: they may be written.
    expect(readTakeBack('Scratch that, um, call the plumber.')).toMatchObject({ rest: 'um, call the plumber.' });
  });

  it.each(['Take that back to the shop.', 'Scratch that off the list.', 'Strike that pose.', 'Forget that we spoke.', 'Delete that file.', 'Never mind the cost.', 'Cancel that order.', 'Ignore that noise.'])(
    'needs a pause after it, so prose is words: %s',
    (said) => {
      expect(readTakeBack(said)).toBeNull();
    },
  );

  it('is “no wait” only bare: with words after it, it is a risky opener', () => {
    expect(readTakeBack('No wait.')).toMatchObject({ risky: false, rest: '' });
    expect(readTakeBack('No wait, four.')).toMatchObject({ risky: true, rest: 'four.' });
    expect(readTakeBack('No wait four.')).toMatchObject({ risky: true, rest: 'four.' });
    expect(readTakeBack('Should we cancel the order? No wait, that is fine.')).toMatchObject({ head: 'Should we cancel the order?', risky: true, rest: 'that is fine.' });
    expect(readTakeBack('No waiter came.')).toBeNull();
  });

  it('reads a send said straight after it, with no pause', () => {
    expect(readTakeBack('scratch that add it to groceries')).toMatchObject({ rest: 'add it to groceries', send: 'groceries' });
  });
});

describe('a risky opener', () => {
  it('counts only with words after it, with or without a comma', () => {
    expect(readTakeBack('Actually, the meeting is at four.')).toMatchObject({ risky: true, opener: 'Actually', rest: 'the meeting is at four.' });
    expect(readTakeBack('Actually the meeting is at four.')).toMatchObject({ risky: true, rest: 'the meeting is at four.' });
    expect(readTakeBack('Actually.')).toBeNull();
    expect(readTakeBack('I mean the meeting is at four.')).toMatchObject({ risky: true, rest: 'the meeting is at four.' });
    expect(readTakeBack('Or rather, the meeting is at four.')).toMatchObject({ risky: true });
  });

  it('needs the comma after “sorry” and “no”, and takes repeated no’s', () => {
    expect(readTakeBack('Sorry, the meeting is at four.')).toMatchObject({ risky: true, rest: 'the meeting is at four.' });
    expect(readTakeBack('Sorry I am late.')).toBeNull();
    expect(readTakeBack('Sorry.')).toBeNull();
    expect(readTakeBack('No, the meeting is at four.')).toMatchObject({ risky: true, opener: 'No', rest: 'the meeting is at four.' });
    expect(readTakeBack('No no, four.')).toMatchObject({ risky: true, rest: 'four.' });
    expect(readTakeBack('No, no, no, four.')).toMatchObject({ risky: true, rest: 'four.' });
    expect(readTakeBack('No one came.')).toBeNull();
    expect(readTakeBack('No parking on Sunday.')).toBeNull();
    expect(readTakeBack('No.')).toBeNull();
  });
});

describe('where an opener stands', () => {
  it('after the lead-ins and the keyword, which sets keyed', () => {
    expect(readTakeBack('Okay, scratch that.')).toMatchObject({ head: '', keyed: false, said: 'scratch that.' });
    expect(readTakeBack('um, actually, the meeting is at four.')).toMatchObject({ head: '', risky: true, rest: 'the meeting is at four.' });
    expect(readTakeBack('Hey, like, scratch that.')).toMatchObject({ head: '', keyed: false });
    expect(readTakeBack('Hey Ghost, scratch that.')).toMatchObject({ head: '', keyed: true, headBeforeKeyword: false, said: 'scratch that.' });
    expect(readTakeBack('Hey Ghost, actually, call Sarah.')).toMatchObject({ keyed: true, risky: true, rest: 'call Sarah.' });
    expect(readTakeBack('Um, hey Ghost, scratch that.')).toMatchObject({ head: '', keyed: true });
  });

  it('after a stop, in either case, with what came before as the head', () => {
    expect(readTakeBack('We need eggs. Scratch that.')).toMatchObject({ head: 'We need eggs.', rest: '', said: 'Scratch that.', keyed: false });
    expect(readTakeBack('We need eggs. scratch that.')).toMatchObject({ head: 'We need eggs.' });
    expect(readTakeBack('We need eggs. Actually, we need bread.')).toMatchObject({ head: 'We need eggs.', risky: true, rest: 'we need bread.' });
    expect(readTakeBack('We need eggs! Never mind.')).toMatchObject({ head: 'We need eggs!' });
    expect(readTakeBack('Kevin owns it. Scratch that, hey Ghost, add it to Work.')).toMatchObject({ head: 'Kevin owns it.', keyed: false, send: 'Work' });
  });

  it('after the keyword said after the head, which is marked as words then the keyword', () => {
    expect(readTakeBack('The heating is fixed, hey Ghost, scratch that.')).toMatchObject({ head: 'The heating is fixed', headBeforeKeyword: true, keyed: true, said: 'scratch that.' });
    // The keyword before a command head stays in the head, so the head is read as the command it was, and the opener
    // after it is not keyed: the keyword was the command's, not the opener's.
    expect(readTakeBack('Hey Ghost, add call Sam to Work. Actually, call Sarah.')).toMatchObject({ head: 'Hey Ghost, add call Sam to Work.', headBeforeKeyword: false, keyed: false, rest: 'call Sarah.' });
    expect(readTakeBack('Hey Ghost, add call Sam to Work. Actually, we should go for a walk.')).toMatchObject({ keyed: false, risky: true });
    expect(readTakeBack('Hey Ghost, add a note to house, scratch that.')).toMatchObject({ head: 'Hey Ghost, add a note to house', afterComma: true, keyed: false });
  });

  it('after a comma inside a sentence, for a drop, a send or a change of one word, and not for a fragment', () => {
    expect(readTakeBack('The meeting is at three, scratch that.')).toMatchObject({ head: 'The meeting is at three', afterComma: true, rest: '' });
    expect(readTakeBack('Oat milk, scratch that, add it to groceries instead.')).toMatchObject({ head: 'Oat milk', afterComma: true, send: 'groceries' });
    expect(readTakeBack('The meeting is at three, no wait, four.')).toMatchObject({ head: 'The meeting is at three', afterComma: true, risky: true, rest: 'four.' });
    expect(readTakeBack('The meeting is at three, actually, the meeting is at four.')).toMatchObject({ head: 'The meeting is at three', afterComma: true, rest: 'the meeting is at four.' });
    expect(readTakeBack('The meeting is at three, no wait for me at the station.')).toBeNull();
    expect(readTakeBack('The meeting is at three, scratch that, call Sam.')).toBeNull();
    expect(readTakeBack('Milk, eggs, actually, bread.')).toBeNull();
  });

  it('is words anywhere else', () => {
    expect(readTakeBack('The heating is fixed.')).toBeNull();
    expect(readTakeBack('I actually think we should go.')).toBeNull();
    expect(readTakeBack('Hey Ghost, add a note to house to-dos.')).toBeNull();
    expect(readTakeBack('')).toBeNull();
  });
});

describe('a send', () => {
  it.each([
    ['Scratch that, add it to Groceries instead.', 'Groceries'],
    ['Scratch that, add it to Groceries.', 'Groceries'],
    ['Scratch that, put that in the house list.', 'house list'],
    ['Scratch that, put that in the list.', 'the list'],
    ['Scratch that, put that in my note.', 'my note'],
    ['Scratch that, that goes in Groceries.', 'Groceries'],
    ['Scratch that, it belongs in House TODOs.', 'House TODOs'],
    ['Scratch that, move it to House TODOs instead.', 'House TODOs'],
    ['Scratch that, this goes in House TODOs.', 'House TODOs'],
    ['Actually, put that in House TODOs.', 'House TODOs'],
    ['No wait, that goes in Groceries.', 'Groceries'],
    ['Scratch that, hey Ghost, add it to Groceries.', 'Groceries'],
    ['Scratch that, send those to my Work list instead.', 'Work list'],
  ])('reads the note named in the rest: %s', (said, name) => {
    expect(readTakeBack(said)?.send).toBe(name);
  });

  it('is not a send when the thing is words, or the name is none', () => {
    expect(readTakeBack('Scratch that, add milk to Groceries.')).toMatchObject({ send: null, rest: 'add milk to Groceries.' });
    expect(readTakeBack('Scratch that, add it to the top.')).toMatchObject({ send: null });
    expect(readTakeBack('Scratch that, put it to a table.')).toMatchObject({ send: null });
    // "This" is the take's own word: "move this to X" moves the recording.
    expect(readTakeBack('Scratch that, move this to Groceries.')).toMatchObject({ send: null });
  });

  it('is read over a whole phrase said in a breath of its own', () => {
    expect(readSend('Add it to Groceries instead.')).toBe('Groceries');
    expect(readSend('Put that in the list.')).toBe('the list');
    expect(readSend('Hey Ghost, put that in house to-dos.')).toBe('house to-dos');
    expect(readSend('Okay, that goes in Groceries.')).toBe('Groceries');
    expect(readSend('Add milk to Groceries.')).toBeNull();
    expect(readSend('Add it to Groceries. Then call Sam.')).toBeNull();
    expect(readSend('Call the plumber.')).toBeNull();
  });
});

describe('a sentence said again with a change', () => {
  it.each([
    ['The meeting is at three', 'the meeting is at four'],
    ['Call Sam about the invoice', 'call Sarah about the invoice'],
    ['Call Sam', 'call Sarah'],
    ['Oat milk', 'almond milk'],
    ['Bullet point: eggs', 'eggs and milk'],
    ["It's on Tuesday", "it's on Thursday"],
  ])('corrects: %s → %s', (before, after) => {
    expect(corrects(before, after)).toBe(true);
  });

  it.each([
    ['The heating is fixed', 'I think we should go'],
    ['We need eggs', 'the meeting is on Friday'],
    ['The meeting is at three', 'at four'],
    ['Eggs', 'eggs, milk, bread and butter for the weekend'],
    ['The meeting is at three', 'so'],
    ['Eggs', 'milk'],
    ['Call Sam', 'ring Sarah'],
    ["It's on Tuesday", "it's for Sam"],
    // One word of two shared is a new sentence about the same thing.
    ['Call Sam', 'Sam is away'],
    ['Ring the bank', 'the bank is shut'],
    ['It is', 'so'],
  ])('is a new sentence: %s → %s', (before, after) => {
    expect(corrects(before, after)).toBe(false);
  });

  // Accepted: one of two words shared, and the item becomes what was said.
  it('takes an item said again with more', () => {
    expect(corrects('Bullet point: eggs', 'eggs are in the fridge')).toBe(true);
  });

  it('reads the content words with the cue prefix off and contractions to their base', () => {
    expect(contentWords("Check box: call Sam's mum, don't forget.")).toEqual(['call', 'sam', 'mum', 'forget']);
  });
});

describe('a change of one word', () => {
  it('swaps the one word of the fragment’s kind, case and punctuation kept', () => {
    expect(swapWord('The meeting is at three.', 'four')).toEqual({ text: 'The meeting is at four.', from: 'three', to: 'four' });
    expect(swapWord('The meeting is at three.', 'Four.')).toEqual({ text: 'The meeting is at four.', from: 'three', to: 'four' });
    expect(swapWord('The meeting is on Tuesday.', 'Thursday')).toEqual({ text: 'The meeting is on Thursday.', from: 'Tuesday', to: 'Thursday' });
    expect(swapWord('Rent is due in March.', 'April')).toMatchObject({ text: 'Rent is due in April.' });
    expect(swapWord('Call Sam.', 'Sarah')).toEqual({ text: 'Call Sarah.', from: 'Sam', to: 'Sarah' });
    expect(swapWord('Check box: call Sam.', 'Sarah')).toMatchObject({ text: 'Check box: call Sarah.' });
    expect(swapWord('It starts at 3.', '4')).toMatchObject({ text: 'It starts at 4.' });
    expect(swapWord('It starts at 3pm.', '4pm')).toMatchObject({ text: 'It starts at 4pm.' });
    expect(swapWord('Meet at three.', 'um, four')).toMatchObject({ text: 'Meet at four.' });
  });

  it('is null for two words of the kind, none, or a fragment of no kind', () => {
    expect(swapWord('From three to four.', 'five')).toBeNull();
    expect(swapWord('We need eggs.', 'milk')).toBeNull();
    expect(swapWord('The meeting is at three.', 'at four')).toBeNull();
    expect(swapWord('Call Sam and Jo.', 'Sarah')).toBeNull();
    // The first word is capitalised whatever it is, so it is never a name.
    expect(swapWord('Sam owns it.', 'Sarah')).toBeNull();
    expect(swapWord('The meeting is at three.', 'three')).toBeNull();
  });
});

describe('what a person would quote', () => {
  it('leaves the cue prefix, the keyword and the stop off', () => {
    expect(quoted('Check box: call Sam.')).toBe('call Sam');
    expect(quoted('Bullet point: eggs.')).toBe('eggs');
    expect(quoted('The meeting is at three.')).toBe('The meeting is at three');
    expect(quoted('Hey Ghost, fix the spelling.')).toBe('fix the spelling');
    expect(quoted('The heating is fixed, hey Ghost, fix the spelling.')).toBe('The heating is fixed, hey Ghost, fix the spelling');
  });
});

describe('a command said with a risky opener', () => {
  it('is the command, the opener off, and words otherwise', () => {
    expect(commandAfterOpener('actually, add a note to House TODOs')).toBe('add a note to House TODOs');
    expect(commandAfterOpener('Actually add milk to groceries.')).toBe('add milk to groceries.');
    expect(commandAfterOpener('I mean, new item for groceries')).toBe('new item for groceries');
    expect(commandAfterOpener('sorry, add it to')).toBe('add it to');
    expect(commandAfterOpener('no wait, move this to groceries')).toBe('move this to groceries');
    expect(commandAfterOpener('actually, we should call the plumber')).toBe('actually, we should call the plumber');
    expect(commandAfterOpener('actually')).toBe('actually');
    expect(commandAfterOpener('add a note to House TODOs')).toBe('add a note to House TODOs');
  });
});

describe('a partial starting a take-back', () => {
  it.each(['Scratch', 'scratch tha', 'Scratch that', 'Strike', 'no w', 'No wait', 'wait n', 'take that b', 'forget t', 'delete t', 'never m', 'cancel t', 'ignore t', 'Okay scratch'])('is for the chip: %s', (partial) => {
    expect(opensTakeBack(partial)).toBe(true);
  });

  it.each(['no', 'No', 'wait', 'take', 'take that', 'forget', 'delete', 'never', 'cancel', 'ignore', 'Actually', 'I mean', 'The meeting', 'scr', ''])('is for the page: %s', (partial) => {
    expect(opensTakeBack(partial)).toBe(false);
  });

  it('is found after a stop or a comma inside the partial, the words before it left for the page', () => {
    expect(takeBackAt('Scratch tha')).toBe(0);
    expect(takeBackAt('The meeting is at three, no w')).toBe(25);
    expect(takeBackAt('We need eggs. Call Sam. Scratch that')).toBe(24);
    expect(takeBackAt('The meeting is at three, no')).toBe(-1);
    expect(takeBackAt('The meeting is at three')).toBe(-1);
    expect(takeBackAt('')).toBe(-1);
  });

  it('knows a send that is starting, keyword and lead-ins off', () => {
    expect(opensSend('Add it to')).toBe(true);
    expect(opensSend('Hey Ghost, put that in gro')).toBe(true);
    expect(opensSend('That goes')).toBe(true);
    expect(opensSend("It's in")).toBe(true);
    expect(opensSend('Add milk to')).toBe(false);
    expect(opensSend('Addition')).toBe(false);
    expect(opensSend('That')).toBe(false);
    expect(opensSend('')).toBe(false);
  });
});
