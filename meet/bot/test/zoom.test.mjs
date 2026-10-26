import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CaptionTimeline } from '../lib/captions.mjs';
import { isMeetUrl, isZoomUrl, platformOf } from '../lib/decide.mjs';
import {
  NOBODY,
  ZOOM_NAME,
  captionBlocks,
  endedOutcome,
  isPersonalLink,
  isZoomHost,
  lobbyOutcome,
  participantsCount,
  resolvedWebClientUrl,
  waitingRoom,
  webClientUrl,
} from '../lib/zoomtext.mjs';

const BOOKED = 'https://us06web.zoom.us/j/83512345678?pwd=bWVvT3h5Vm1uVTNtTHpuNnJ3QT09.1';

test('a booked Zoom link opens the web client, the passcode kept and nothing else of the query', () => {
  assert.equal(webClientUrl(BOOKED), 'https://app.zoom.us/wc/join/83512345678?pwd=bWVvT3h5Vm1uVTNtTHpuNnJ3QT09.1');
  assert.equal(webClientUrl('https://zoom.us/j/123456789'), 'https://app.zoom.us/wc/join/123456789');
  assert.equal(webClientUrl('https://acme.zoom.us/wc/join/12345678901/?pwd=Ab.1&uname=Sam'), 'https://app.zoom.us/wc/join/12345678901?pwd=Ab.1');
  assert.equal(webClientUrl('https://zoom.us/j/123456789?pwd=bad%20one'), 'https://app.zoom.us/wc/join/123456789', 'a passcode Zoom would not write is dropped');
  for (const not of [
    'https://zoom.us/my/sam.lee',
    'https://zoom.us/w/123456789',
    'https://zoom.us/s/123456789',
    'https://zoom.us/j/12345678',
    'https://zoom.us/j/123456789/start',
    'http://zoom.us/j/123456789',
    'https://notzoom.us/j/123456789',
    'https://a.b.zoom.us/j/123456789',
    'https://zoom.us.evil.example/j/123456789',
    'not a url',
  ]) {
    assert.equal(webClientUrl(not), null, not);
  }
});

test('a personal link is asked of Zoom: where it moved to, or its "Join from your browser" link', () => {
  assert.ok(isPersonalLink('https://zoom.us/my/sam.lee'));
  assert.ok(isPersonalLink('https://acme.zoom.us/my/sam.lee/'));
  assert.ok(!isPersonalLink('https://zoom.us/my/'));
  assert.ok(!isPersonalLink('https://evil.example/my/sam.lee'));
  assert.equal(resolvedWebClientUrl('https://us06web.zoom.us/j/9876543210?pwd=Xy.1#success'), 'https://app.zoom.us/wc/join/9876543210?pwd=Xy.1');
  assert.equal(
    resolvedWebClientUrl('https://zoom.us/my/sam.lee', ['/download', 'https://zoom.us/support', '/wc/join/9876543210?pwd=Xy.1']),
    'https://app.zoom.us/wc/join/9876543210?pwd=Xy.1',
    'a relative link, read against the page',
  );
  assert.equal(resolvedWebClientUrl('https://zoom.us/my/sam.lee', ['https://evil.example/j/9876543210']), null);
  assert.equal(resolvedWebClientUrl('', [null, '']), null);
});

test('the bot opens Meet and Zoom links of the shapes the server books, and nothing else', () => {
  assert.equal(platformOf('https://meet.google.com/abc-defg-hij'), 'meet');
  assert.equal(platformOf(BOOKED), 'zoom');
  assert.equal(platformOf('https://zoom.us/my/sam.lee'), 'zoom');
  assert.equal(platformOf('https://zoom.us/wc/join/123456789'), 'zoom');
  for (const not of ['https://zoom.us/s/123456789', 'https://zoom.us/w/123456789', 'https://zoom.us/j/1', 'https://teams.microsoft.com/l/meetup-join/x', 'http://zoom.us/j/123456789', '']) {
    assert.equal(platformOf(not), null, not);
    assert.ok(!isZoomUrl(not), not);
  }
  assert.ok(!isMeetUrl(BOOKED));
  assert.ok(isZoomHost('zoom.us') && isZoomHost('us06web.zoom.us') && !isZoomHost('-x.zoom.us') && !isZoomHost('zoom.us.example'));
});

test("the lobby's words: a captcha, a sign-in wall and the browser join turned off are given up on at once", () => {
  assert.equal(lobbyOutcome("Please verify you're a human. I'm not a robot"), 'captcha');
  assert.equal(lobbyOutcome('This meeting is for authorized attendees only. Sign in to join'), 'sign_in_required');
  assert.equal(lobbyOutcome('', 'https://us06web.zoom.us/signin?from=join'), 'sign_in_required');
  assert.equal(lobbyOutcome('', 'https://acme.okta.com/app/zoom/sso'), 'sign_in_required');
  assert.equal(lobbyOutcome('', 'https://accounts.google.com/v3/signin'), 'sign_in_required');
  assert.equal(lobbyOutcome('The host has disabled joining from the browser.'), 'no_browser_join');
  assert.equal(lobbyOutcome('Wrong meeting passcode'), 'passcode_wrong');
  assert.equal(lobbyOutcome('Invalid meeting ID. Please check and try again.'), 'invalid_link');
  assert.equal(lobbyOutcome('This meeting has been ended by host'), 'meeting_ended');
  assert.equal(lobbyOutcome('The host has removed you from this meeting. You are not allowed to rejoin.'), 'refused');
  assert.equal(lobbyOutcome('This meeting is locked by the host'), 'refused');
  // The join page itself, with its terms and its own Sign in link, is no outcome.
  assert.equal(lobbyOutcome('Enter Meeting Info\nYour Name\nRemember my name for future meetings\nJoin\nBy clicking "Join", you agree to our Terms of Service and Privacy Statement\nSign In', 'https://app.zoom.us/wc/join/123456789'), null);
  assert.equal(lobbyOutcome(undefined, 'not a url'), null);
});

test('the waiting room and a host not yet there are waited in; the end of a call read from words or the page Zoom moves to', () => {
  assert.ok(waitingRoom('Please wait, the meeting host will let you in soon.'));
  assert.ok(waitingRoom("Host has joined. We've let them know you're here."));
  assert.ok(waitingRoom('Waiting for the host to start this meeting'));
  assert.ok(!waitingRoom('Design sync\nParticipants 4'));
  assert.equal(endedOutcome('This meeting has been ended by host'), 'meeting_ended');
  assert.equal(endedOutcome('You have been removed from this meeting by the host'), 'removed');
  assert.equal(endedOutcome('', 'https://us06web.zoom.us/postattendee?mn=x'), 'meeting_ended');
  assert.equal(endedOutcome('', 'https://app.zoom.us/wc/leave'), 'meeting_ended');
  assert.equal(endedOutcome('Leave\nChat\nParticipants', 'https://app.zoom.us/wc/123456789/start'), null);
});

test('the people count on the Participants button: its name, Zoom spelling included, or its badge', () => {
  assert.equal(participantsCount('open the participants list pane,[4] particpants', ''), 4);
  assert.equal(participantsCount('Participants 12', ''), 12);
  assert.equal(participantsCount('3 participants', ''), 3);
  assert.equal(participantsCount('Participants', '7'), 7);
  assert.equal(participantsCount('Participants', ''), null);
  assert.equal(participantsCount(undefined, undefined), null);
});

test("Zoom's captions become the blocks captions.mjs reads: Zoom's name, a 'Name:' line, the active speaker, or someone", () => {
  assert.deepEqual(captionBlocks([{ name: 'Sam Lee', text: 'we shipped the pricing page' }]), ['Sam Lee\nwe shipped the pricing page']);
  assert.deepEqual(captionBlocks([{ name: 'Sam Lee', text: 'Sam Lee: we shipped it' }]), ['Sam Lee\nwe shipped it']);
  assert.deepEqual(captionBlocks([{ text: 'Daniel: thanks, next item' }]), ['Daniel\nthanks, next item']);
  assert.deepEqual(captionBlocks([{ text: 'and that is the plan.' }], 'Ali Khan'), ['Ali Khan\nand that is the plan.']);
  assert.deepEqual(captionBlocks([{ text: 'Note: this is not a name. It is a sentence.' }]), ['Note\nthis is not a name. It is a sentence.'], 'a short word before a colon reads as a name');
  assert.deepEqual(captionBlocks([{ text: 'Well, as I said before this: it works' }], null), [`${NOBODY}\nWell, as I said before this: it works`], 'a long head is no name');
  assert.deepEqual(captionBlocks([{ text: '   ' }, null, { name: 'x', text: '' }]), []);
  assert.deepEqual(captionBlocks(undefined), []);
  // Through the timeline, as a Meet's are.
  const timeline = new CaptionTimeline();
  assert.deepEqual(timeline.update(captionBlocks([{ text: 'good morning everyone' }], 'Sam Lee'), 0), []);
  assert.deepEqual(timeline.update(captionBlocks([{ text: 'good morning everyone' }], 'Sam Lee'), 2500), [{ at: 0, speaker: 'Sam Lee', text: 'good morning everyone' }]);
  assert.equal(ZOOM_NAME, 'Ghost (notetaker)');
});
