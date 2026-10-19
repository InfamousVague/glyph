import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CaptionTimeline, align, newWordsFrom, parseBlock, similar, tokens } from '../lib/captions.mjs';

const block = (speaker, text) => `${speaker}\n${text}`;

test('a block is a name over text; furniture is not a block', () => {
  assert.deepEqual(parseBlock('Alice\nGood morning everyone.'), { speaker: 'Alice', text: 'Good morning everyone.' });
  assert.deepEqual(parseBlock('Alice\nGood morning\neveryone.'), { speaker: 'Alice', text: 'Good morning everyone.' });
  assert.deepEqual(parseBlock('Alice'), { speaker: 'Alice', text: '' });
  assert.equal(parseBlock('arrow_downward\nJump to bottom'), null);
  assert.equal(parseBlock('  \n '), null);
});

test('similar: growth, a revision, a trimmed head; not a different sentence', () => {
  assert.ok(similar('Good morning', 'Good morning everyone this is Alice'));
  assert.ok(similar('Good morning everyone this is', 'Good morning everyone, this is Alice.'));
  assert.ok(similar('the launch checklist for the project page', 'the launch checklist for the pricing page'));
  assert.ok(similar('one two three four five six seven eight', 'four five six seven eight nine ten'));
  assert.ok(similar('', 'anything'));
  assert.ok(!similar('Thanks Alice Bob here', 'Great can you also book the venue'));
});

test('align: blocks that scrolled off the top are counted', () => {
  const before = [{ speaker: 'Alice', text: 'Good morning everyone' }, { speaker: 'Bob', text: 'Thanks Alice' }];
  assert.equal(align(before, [{ speaker: 'Alice', text: 'Good morning everyone.' }, { speaker: 'Bob', text: 'Thanks Alice, Bob here' }]), 0);
  assert.equal(align(before, [{ speaker: 'Bob', text: 'Thanks Alice, Bob here' }, { speaker: 'Alice', text: 'Great' }]), 1);
  assert.equal(align(before, [{ speaker: 'Carol', text: 'Hello' }]), 2);
  assert.equal(align([], [{ speaker: 'Carol', text: 'Hello' }]), 0);
});

test('newWordsFrom: growth, revision, trimmed head', () => {
  const k = (s) => tokens(s).map((t) => t.key);
  assert.equal(newWordsFrom([], tokens('a b c')), 0);
  assert.equal(newWordsFrom(k('a b c'), tokens('a b c d e')), 3);
  // The head was trimmed: picked up after the last words written.
  assert.equal(newWordsFrom(k('one two three four five'), tokens('four five six seven')), 2);
  // A revision of what was written, and nothing more: nothing new.
  assert.equal(newWordsFrom(k('for the project'), tokens('for the pricing page')), 4);
});

test('a phrase is written once it has been quiet for two seconds', () => {
  const t = new CaptionTimeline();
  assert.deepEqual(t.update([block('Alice', 'Good morning')], 0), []);
  assert.deepEqual(t.update([block('Alice', 'Good morning everyone.')], 500), []);
  assert.deepEqual(t.update([block('Alice', 'Good morning everyone. This is Alice.')], 1000), []);
  assert.deepEqual(t.update([block('Alice', 'Good morning everyone. This is Alice.')], 2500), []);
  assert.deepEqual(t.update([block('Alice', 'Good morning everyone. This is Alice.')], 3000), [
    { at: 0, speaker: 'Alice', text: 'Good morning everyone. This is Alice.' },
  ]);
  // And not again.
  assert.deepEqual(t.update([block('Alice', 'Good morning everyone. This is Alice.')], 9000), []);
  assert.deepEqual(t.flush(), []);
});

test('a new speaker block finishes the one above it at once', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', "Let's start with the launch checklist")], 0);
  assert.deepEqual(t.update([block('Alice', "Let's start with the launch checklist."), block('Bob', 'Thanks')], 900), [
    { at: 0, speaker: 'Alice', text: "Let's start with the launch checklist." },
  ]);
  assert.deepEqual(t.flush(), [{ at: 900, speaker: 'Bob', text: 'Thanks' }]);
});

test('a revision before the phrase is finished is written as revised', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'the launch checklist for the project')], 0);
  t.update([block('Alice', 'the launch checklist for the pricing page')], 700);
  assert.deepEqual(t.update([block('Alice', 'the launch checklist for the pricing page')], 2700), [
    { at: 0, speaker: 'Alice', text: 'the launch checklist for the pricing page' },
  ]);
});

test('a block that grows again after a pause gives only its new words, stamped when they began', () => {
  const t = new CaptionTimeline();
  t.update([block('Bob', 'The pricing page is drafted.')], 0);
  assert.equal(t.update([block('Bob', 'The pricing page is drafted.')], 2000).length, 1);
  t.update([block('Bob', 'The pricing page is drafted. And I will send')], 4000);
  t.update([block('Bob', 'The pricing page is drafted. And I will send the deck to Sam.')], 4500);
  assert.deepEqual(t.update([block('Bob', 'The pricing page is drafted. And I will send the deck to Sam.')], 6500), [
    { at: 4000, speaker: 'Bob', text: 'And I will send the deck to Sam.' },
  ]);
});

test('a revision of words already written out is let go, not written twice', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'see you on the tenth')], 0);
  assert.equal(t.update([block('Alice', 'see you on the tenth')], 2000).length, 1);
  t.update([block('Alice', 'see you on the 10th.')], 2500);
  assert.deepEqual(t.update([block('Alice', 'see you on the 10th.')], 5000), []);
});

test('a long turn whose head Meet trims keeps going without repeats', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'one two three four five six')], 0);
  assert.equal(t.update([block('Alice', 'one two three four five six')], 2000)[0].text, 'one two three four five six');
  t.update([block('Alice', 'four five six seven eight nine')], 3000);
  assert.deepEqual(t.update([block('Alice', 'four five six seven eight nine')], 5000), [{ at: 3000, speaker: 'Alice', text: 'seven eight nine' }]);
});

test('blocks scrolling off the top are finished, and the rest are not taken for new ones', () => {
  const t = new CaptionTimeline();
  // Alice's block has Bob's under it: finished at once.
  assert.deepEqual(t.update([block('Alice', 'Great.'), block('Bob', 'Yes, I will book the venue')], 0), [{ at: 0, speaker: 'Alice', text: 'Great.' }]);
  // Alice's scrolls off; Bob's grows and has a new one under it.
  const out = t.update([block('Bob', 'Yes, I will book the venue, and I will ask Ali.'), block('Alice', 'Perfect.')], 800);
  assert.deepEqual(out, [{ at: 0, speaker: 'Bob', text: 'Yes, I will book the venue, and I will ask Ali.' }]);
  assert.deepEqual(t.flush(), [{ at: 800, speaker: 'Alice', text: 'Perfect.' }]);
});

test('the same line from the same speaker twice in a row is written once', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'Thank you.')], 0);
  assert.equal(t.update([block('Alice', 'Thank you.')], 2000).length, 1);
  // Meet redraws the region with the same block as a new one, under somebody else's.
  assert.deepEqual(t.update([block('Carol', 'Hi'), block('Alice', 'Thank you.')], 2500), [{ at: 2500, speaker: 'Carol', text: 'Hi' }]);
  assert.deepEqual(t.flush(), []);
});

test('a speaker named before they say anything writes nothing', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'Hello there')], 0);
  assert.deepEqual(t.update([block('Alice', 'Hello there'), 'Bob'], 500), [{ at: 0, speaker: 'Alice', text: 'Hello there' }]);
  assert.deepEqual(t.update([block('Alice', 'Hello there'), 'Bob'], 3000), []);
  assert.deepEqual(t.update([block('Alice', 'Hello there'), block('Bob', 'Hi Alice')], 3500), []);
  assert.deepEqual(t.flush(), [{ at: 3500, speaker: 'Bob', text: 'Hi Alice' }]);
});

test('the captions going away finishes what was on screen', () => {
  const t = new CaptionTimeline();
  t.update([block('Alice', 'Bye everyone')], 0);
  assert.deepEqual(t.update([], 300), [{ at: 0, speaker: 'Alice', text: 'Bye everyone' }]);
});
