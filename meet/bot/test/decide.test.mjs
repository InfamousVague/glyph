import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LIMITS, busyMisses, isMeetUrl, isSafeId, leaveReason, planIdle, trackAlone } from '../lib/decide.mjs';

const MIN = 60_000;
const START = 1_800_000_000_000;
const meeting = (id, startsAt, state = 'booked', length = 30 * MIN) => ({ id, url: 'https://meet.google.com/abc-defg-hij', startsAt, endsAt: startsAt + length, state });

test('idle: the earliest ready meeting is joined; one not yet near its start waits', () => {
  const plan = planIdle([meeting('later', START + 30 * MIN), meeting('now', START), meeting('soon', START + 2 * MIN)], START + MIN);
  assert.equal(plan.join.id, 'now');
  assert.deepEqual(plan.skip, []);
  assert.equal(planIdle([meeting('far', START + 20 * MIN)], START).join, null);
  assert.equal(planIdle([meeting('near', START + 4 * MIN)], START).join.id, 'near');
});

test('idle: one already over is skipped, `leave` and handled ones are let be, a restart rejoins', () => {
  const over = meeting('over', START - 40 * MIN);
  assert.deepEqual(planIdle([over], START), { join: null, skip: [{ id: 'over', detail: 'time_up' }] });
  assert.equal(planIdle([meeting('m', START, 'leave')], START).join, null);
  assert.equal(planIdle([meeting('m', START)], START, new Set(['m'])).join, null);
  assert.equal(planIdle([meeting('m', START, 'in_call')], START + 5 * MIN).join.id, 'm');
  assert.equal(planIdle(undefined, START).join, null);
});

test('busy: a waiting meeting is given up only once it is more than ten minutes late', () => {
  const due = [meeting('current', START, 'in_call'), meeting('next', START + 30 * MIN), meeting('done', START, 'booked')];
  assert.deepEqual(busyMisses(due, START + 40 * MIN, 'current', new Set(['done'])), []);
  assert.deepEqual(busyMisses(due, START + 40 * MIN + 1, 'current', new Set(['done'])), ['next']);
  assert.deepEqual(busyMisses(due, START + 40 * MIN + 1, 'current', new Set(['done', 'next'])), []);
});

test('the alone timer: starts on a count of one, resets on more or on no count', () => {
  assert.equal(trackAlone(null, 1, 100), 100);
  assert.equal(trackAlone(100, 1, 200), 100);
  assert.equal(trackAlone(100, 3, 200), null);
  assert.equal(trackAlone(100, null, 200), null);
});

const base = { joinedAt: START, startsAt: START, endsAt: START + 30 * MIN };

test('alone for two minutes after others had been there: leave', () => {
  const alone = START + 10 * MIN;
  assert.equal(leaveReason({ ...base, now: alone + 2 * MIN - 1, aloneSince: alone, seenOthers: true }), null);
  assert.equal(leaveReason({ ...base, now: alone + 2 * MIN, aloneSince: alone, seenOthers: true }), 'alone');
});

test('alone before the start, or waiting for the first person: not yet', () => {
  const early = { ...base, joinedAt: START - 2 * MIN };
  // In early and alone: the timer counts from the start, not from joining.
  assert.equal(leaveReason({ ...early, now: START + MIN, aloneSince: START - 2 * MIN, seenOthers: true }), null);
  // Nobody has come at all: wait ten minutes past the start, then go.
  assert.equal(leaveReason({ ...early, now: START + 9 * MIN, aloneSince: START - 2 * MIN }), null);
  assert.equal(leaveReason({ ...early, now: START + LIMITS.nobodyMs, aloneSince: START - 2 * MIN }), 'alone');
});

test('time up: ten minutes past the booked end, or three hours in', () => {
  assert.equal(leaveReason({ ...base, now: base.endsAt + 10 * MIN - 1 }), null);
  assert.equal(leaveReason({ ...base, now: base.endsAt + 10 * MIN }), 'time_up');
  const long = { ...base, endsAt: START + 8 * 60 * MIN };
  assert.equal(leaveReason({ ...long, now: START + 3 * 60 * MIN - 1 }), null);
  assert.equal(leaveReason({ ...long, now: START + 3 * 60 * MIN }), 'time_up');
});

test('the page, the server and a stop come first', () => {
  const now = START + 5 * MIN;
  assert.equal(leaveReason({ ...base, now, ended: 'meeting_ended', serverLeave: true }), 'meeting_ended');
  assert.equal(leaveReason({ ...base, now, serverLeave: true }), 'asked_to_leave');
  assert.equal(leaveReason({ ...base, now, stopping: true }), 'shutdown');
  assert.equal(leaveReason({ ...base, now }), null);
});

test('only Meet links and safe ids', () => {
  assert.ok(isMeetUrl('https://meet.google.com/abc-defg-hij'));
  assert.ok(isMeetUrl('https://meet.google.com/abc-defg-hij?authuser=0'));
  assert.ok(!isMeetUrl('http://meet.google.com/abc-defg-hij'));
  assert.ok(!isMeetUrl('https://meet.google.com.evil.example/abc-defg-hij'));
  assert.ok(!isMeetUrl('https://evil.example/?u=https://meet.google.com/abc'));
  assert.ok(!isMeetUrl('not a url'));
  assert.ok(isSafeId('Ab_3-x'));
  assert.ok(!isSafeId('../etc'));
  assert.ok(!isSafeId(''));
  assert.ok(!isSafeId(42));
});
