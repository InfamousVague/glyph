import assert from 'node:assert/strict';
import { test } from 'node:test';
import { IGNORE_DEFAULT_ARGS, botArgs, botLaunchOptions, signinCommand } from '../lib/chrome.mjs';
import { log } from '../lib/log.mjs';

test("the bot's Chrome: no automation markers, its own sandbox, tab capture accepted, no fake devices", () => {
  for (const flag of ['--enable-automation', '--no-sandbox', '--use-mock-keychain', '--password-store=basic']) {
    assert.ok(IGNORE_DEFAULT_ARGS.includes(flag), flag);
  }
  const options = botLaunchOptions({ platform: 'linux', executablePath: undefined });
  assert.equal(options.channel, 'chrome');
  assert.equal(options.headless, false);
  assert.equal(options.chromiumSandbox, true);
  assert.deepEqual(options.permissions, []);
  assert.ok(options.args.includes('--disable-blink-features=AutomationControlled'));
  assert.ok(options.args.includes('--auto-accept-this-tab-capture'));
  assert.ok(!options.args.some((a) => /no-sandbox|fake-device|fake-ui|enable-automation/.test(a)));
});

test('the same password store for the sign-in Chrome and the bot: basic on Linux, the keychain on a Mac', () => {
  const linuxSignin = signinCommand('/var/lib/glyph-meet/profile', 'linux');
  assert.ok(botArgs('linux').includes('--password-store=basic'));
  assert.ok(linuxSignin.args.includes('--password-store=basic'));
  assert.ok(!botArgs('darwin').some((a) => a.startsWith('--password-store')));
  assert.ok(!signinCommand('/p', 'darwin').args.some((a) => a.startsWith('--password-store')));
});

test('the sign-in Chrome is plain: the profile, accounts.google.com, nothing automated', () => {
  const { command, args } = signinCommand('/var/lib/glyph-meet/profile', 'linux');
  assert.equal(command, process.env.GLYPH_MEET_CHROME || '/usr/bin/google-chrome-stable');
  assert.ok(args.includes('--user-data-dir=/var/lib/glyph-meet/profile'));
  assert.equal(args.at(-1), 'https://accounts.google.com/');
  assert.ok(!args.some((a) => /automation|remote-debugging|no-sandbox/i.test(a)));
});

test('the log keeps only ids, states and sizes', (t) => {
  const lines = [];
  t.mock.method(console, 'log', (line) => lines.push(line));
  log('state', { id: 'm1', state: 'in_call', title: 'Board meeting', url: 'https://meet.google.com/x', text: 'secret' });
  log('uploaded', { id: 'm1', bytes: 123, error: 'a\nb c' });
  assert.deepEqual(lines, ['state id=m1 state=in_call', 'uploaded id=m1 bytes=123 error=a_b_c']);
});

test('a lapsed sign-in is seen on Google sign-in page, not mistaken for a lobby without a join button', async () => {
  const { isSignInPage } = await import('../lib/meet.mjs');
  assert.equal(isSignInPage('https://accounts.google.com/v3/signin/identifier?continue=https%3A%2F%2Fmeet.google.com%2Fabc'), true);
  assert.equal(isSignInPage('https://meet.google.com/abc-defg-hij'), false);
  assert.equal(isSignInPage('not a url'), false);
});

test('the join button is found with Meet warning badge in its name, and Other ways to join is not taken for it', async () => {
  const { JOIN_BUTTON } = await import('../lib/meet.mjs');
  for (const name of ['Join now', 'Join now warning', 'error Join now', 'Ask to join', 'Switch here']) assert.match(name, JOIN_BUTTON);
  for (const name of ['Other ways to join', 'Join here too', 'Leave call']) assert.doesNotMatch(name, JOIN_BUTTON);
});
