#!/usr/bin/env node
/**
 * Ghost.md's Google Meet notetaker (GHST-106, docs/MEET.md): a signed-in Chrome that joins the meetings glyph-api
 * hands it, records what the meeting sounds like and what Meet's captions say, and hands the take back.
 *
 *   node bot.mjs              the service (glyph-meet.service): asks the server what is due every 20 s, one meeting
 *                             at a time
 *   node bot.mjs --check      opens the profile, visits myaccount.google.com, prints `SIGNED_IN yes` or `no`
 *                             (exit 0 / 3; `busy` and exit 0 while a meeting has the profile)
 *   node bot.mjs --signin     a plain Chrome on the profile at accounts.google.com, for Matt to sign in through VNC
 *                             (glyph-meet-signin.service); no automation at all, Google refuses a sign-in in an
 *                             automated browser. Runs until stopped.
 *
 * Environment: GLYPH_MEET_TOKEN (the service only), GLYPH_MEET_API (http://127.0.0.1:8796), GLYPH_MEET_DATA
 * (/var/lib/glyph-meet: profile/, work/, work/failed/), GLYPH_MEET_CHROME (the Chrome binary, else the installed one),
 * DISPLAY, PULSE_SERVER.
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readlinkSync, renameSync } from 'node:fs';
import { hostname } from 'node:os';
import { join } from 'node:path';
import { createApi } from './lib/api.mjs';
import { signinCommand } from './lib/chrome.mjs';
import { LIMITS, isMeetUrl, isSafeId, planIdle } from './lib/decide.mjs';
import { errorField, log } from './lib/log.mjs';

const DATA = process.env.GLYPH_MEET_DATA || '/var/lib/glyph-meet';
const PROFILE = join(DATA, 'profile');
const WORK = join(DATA, 'work');
const mode = process.argv.includes('--check') ? 'check' : process.argv.includes('--signin') ? 'signin' : 'service';

let stopping = false;
let wake = () => {};
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    if (stopping) return;
    stopping = true;
    log('stopping', { mode });
    wake();
  });
}
/** A sleep the service's stop cuts short. */
const pause = (ms) =>
  new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    wake = () => {
      clearTimeout(timer);
      resolve();
    };
  });

/** The pid holding the profile, when a Chrome on this host has it open (Chrome's SingletonLock is host-pid). */
function profileHolder() {
  try {
    const [host, pid] = readlinkSync(join(PROFILE, 'SingletonLock')).split(/-(?=\d+$)/);
    if (host !== hostname()) return null;
    process.kill(Number(pid), 0);
    return Number(pid);
  } catch {
    return null;
  }
}

async function check() {
  if (profileHolder()) {
    console.log('SIGNED_IN busy');
    return 0;
  }
  const meet = await import('./lib/meet.mjs');
  const { context, page } = await meet.openBrowser(PROFILE);
  try {
    const yes = await meet.signedIn(page);
    console.log(`SIGNED_IN ${yes ? 'yes' : 'no'}`);
    return yes ? 0 : 3;
  } finally {
    await context.close().catch(() => {});
  }
}

function signin() {
  mkdirSync(PROFILE, { recursive: true });
  const { command, args } = signinCommand(PROFILE);
  log('signin_started', { mode });
  const chrome = spawn(command, args, { stdio: 'ignore' });
  return new Promise((resolve) => {
    wake = () => chrome.kill('SIGTERM');
    if (stopping) wake();
    chrome.on('exit', (code) => {
      log('signin_ended', { status: code });
      resolve(0);
    });
    chrome.on('error', (e) => {
      log('signin_failed', { error: errorField(e) });
      resolve(1);
    });
  });
}

/** Files a previous run left (it was killed in a call): kept aside for a person to look at, not uploaded as if whole. */
function setAsideLeftovers() {
  mkdirSync(join(WORK, 'failed'), { recursive: true });
  for (const name of readdirSync(WORK)) {
    if (!/\.(webm|captions\.ndjson)$/.test(name)) continue;
    renameSync(join(WORK, name), join(WORK, 'failed', name));
    log('leftover_kept', { id: name.replace(/\..*$/, '') });
  }
}

async function service() {
  const api = createApi({ base: process.env.GLYPH_MEET_API || 'http://127.0.0.1:8796', token: process.env.GLYPH_MEET_TOKEN });
  const { runMeeting } = await import('./lib/session.mjs');
  mkdirSync(WORK, { recursive: true });
  setAsideLeftovers();
  const handled = new Set();
  const ctx = { api, work: WORK, profile: PROFILE, handled, stopping: () => stopping, limits: LIMITS };
  log('started', { mode, version: process.version });
  let failing = 0;
  while (!stopping) {
    let meetings = [];
    try {
      meetings = await api.due();
      if (failing) log('due_ok', { count: meetings.length });
      failing = 0;
    } catch (e) {
      // Logged on the first failure and every 15th after (5 minutes), not every 20 s while glyph-api is down.
      if (failing++ % 15 === 0) log('due_failed', { error: errorField(e), status: e.status });
    }
    const { join: next, skip } = planIdle(meetings, Date.now(), handled, LIMITS);
    for (const { id, detail } of skip) {
      handled.add(id);
      await api.state(id, 'skipped', detail).then(() => log('state', { id, state: 'skipped', detail }), (e) => log('state_failed', { id, error: errorField(e) }));
    }
    if (next && !stopping) {
      if (!isSafeId(next.id) || !isMeetUrl(next.url)) {
        handled.add(next.id);
        log('refused_meeting', { id: isSafeId(next.id) ? next.id : 'unsafe' });
        if (isSafeId(next.id)) await api.state(next.id, 'failed', 'bad_url').catch(() => {});
        continue;
      }
      if (profileHolder()) {
        // The sign-in browser (or a Chrome that outlived its bot) has the profile: try again on the next poll.
        log('profile_busy', { id: next.id });
      } else {
        await runMeeting(next, ctx).catch((e) => log('meeting_error', { id: next.id, error: errorField(e) }));
        continue;
      }
    }
    await pause(LIMITS.pollMs);
  }
  log('stopped', { mode });
  return 0;
}

const code = await (mode === 'check' ? check() : mode === 'signin' ? signin() : service()).catch((e) => {
  log('fatal', { mode, error: errorField(e) });
  return 1;
});
process.exit(code);
