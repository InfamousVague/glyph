#!/usr/bin/env node
// Ghost.md's PostHog dashboards (docs/ANALYTICS.md, "The dashboards"), made or brought up to date by name: run it as
// often as you like, it never makes a second of anything. It also holds the project to the app's privacy settings
// (no session replay, no autocapture, no surveys, the client's IP discarded) where the key is allowed to.
//
//   node tool/posthog/setup_dashboards.mjs            # the dashboards, and the project's settings
//   node tool/posthog/setup_dashboards.mjs --test     # and three test events from a throwaway install, tagged test
//
// It reads ~/.config/mattssoftware/posthog.env (GHOST_POSTHOG_ENV names another) itself, and never prints the
// personal key: POSTHOG_PERSONAL_API_KEY (phx_, the API's), POSTHOG_PROJECT_ID, POSTHOG_HOST (the capture host,
// us.i.posthog.com; the API is the same region's app host) and POSTHOG_PROJECT_KEY (phc_, for --test's events).
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';

const envPath = process.env.GHOST_POSTHOG_ENV || `${homedir()}/.config/mattssoftware/posthog.env`;
const env = {};
for (const line of readFileSync(envPath, 'utf8').split('\n')) {
  const m = line.match(/^\s*(?:export\s+)?([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
}
const key = env.POSTHOG_PERSONAL_API_KEY;
const project = env.POSTHOG_PROJECT_ID;
const capture = (env.POSTHOG_HOST || 'https://us.i.posthog.com').replace(/\/$/, '');
// us.i.posthog.com → us.posthog.com: the app host of the same region answers the API.
const app = capture.replace('://us.i.', '://us.').replace('://eu.i.', '://eu.');
if (!key || !project) throw new Error(`${envPath} names no POSTHOG_PERSONAL_API_KEY or POSTHOG_PROJECT_ID.`);

async function api(method, path, body) {
  const res = await fetch(`${app}/api/projects/${project}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { detail: text.slice(0, 200) }; }
  if (!res.ok) {
    const err = new Error(`${method} ${path}: ${res.status} ${json.detail || json.type || ''}`.trim());
    err.status = res.status;
    throw err;
  }
  return json;
}

async function all(path) {
  const out = [];
  let next = `${path}${path.includes('?') ? '&' : '?'}limit=200`;
  while (next) {
    const page = await api('GET', next);
    out.push(...(page.results || []));
    next = page.next ? page.next.replace(/^.*\/api\/projects\/[^/]+\//, '') : null;
  }
  return out;
}

// --- the query shapes -----------------------------------------------------------------------------------------------

const ev = (event, extra = {}) => ({ kind: 'EventsNode', event, name: event, ...extra });
const prop = (k, value, operator = 'exact') => ({ key: k, value, operator, type: 'event' });
const notTest = [{ key: 'test', value: ['true'], operator: 'is_not', type: 'event' }];
const viz = (source) => ({ kind: 'InsightVizNode', source: { filterTestAccounts: false, properties: notTest, ...source } });
const trends = (series, { from = '-30d', interval = 'day', breakdown, display = 'ActionsLineGraph', formula } = {}) => viz({
  kind: 'TrendsQuery',
  series,
  interval,
  dateRange: { date_from: from },
  ...(breakdown ? { breakdownFilter: { breakdown, breakdown_type: 'event' } } : {}),
  trendsFilter: { display, ...(formula ? { formula } : {}) },
});
const funnel = (steps, { from = '-30d', breakdown, days = 14 } = {}) => viz({
  kind: 'FunnelsQuery',
  series: steps.map((s) => (typeof s === 'string' ? ev(s) : s)),
  dateRange: { date_from: from },
  funnelsFilter: { funnelWindowInterval: days, funnelWindowIntervalUnit: 'day', funnelVizType: 'steps' },
  ...(breakdown ? { breakdownFilter: { breakdown, breakdown_type: 'event' } } : {}),
});
const retention = (period, intervals) => viz({
  kind: 'RetentionQuery',
  dateRange: { date_from: period === 'Week' ? '-56d' : '-30d' },
  retentionFilter: {
    period,
    totalIntervals: intervals,
    retentionType: 'retention_first_time',
    targetEntity: { id: 'app_opened', name: 'app_opened', type: 'events' },
    returningEntity: { id: 'app_opened', name: 'app_opened', type: 'events' },
  },
});

// The plugins that have a setup (a token or a sign-in), for the setup funnel's own series.
const PLUGINS_ACTIONS = ['lovart', 'notion', 'github', 'slack', 'discord', 'figma', 'claude', 'elevenlabs', 'cleanup', 'contradictions', 'git-backup'];

// --- the dashboards -------------------------------------------------------------------------------------------------

const dashboards = [
  {
    name: 'Ghost.md · Overview',
    description: 'Installs, activity and retention, by the random install ID (docs/ANALYTICS.md). No person profiles.',
    insights: [
      ['Daily active installs', trends([ev('app_opened', { math: 'dau' })])],
      ['Weekly active installs', trends([ev('app_opened', { math: 'weekly_active' })], { from: '-90d' })],
      ['Monthly active installs', trends([ev('app_opened', { math: 'monthly_active' })], { from: '-180d', interval: 'week' })],
      ['New installs', trends([ev('app_opened', { math: 'first_time_for_user' })], { from: '-90d' })],
      ['Stickiness (days active a week)', viz({ kind: 'StickinessQuery', series: [ev('app_opened')], interval: 'day', dateRange: { date_from: '-7d' } })],
      ['Retention, weekly (week 1 and week 4)', retention('Week', 8)],
      ['Platform split', trends([ev('app_opened', { math: 'dau' })], { breakdown: 'platform', display: 'ActionsPie', from: '-30d' })],
      ['Form factor split', trends([ev('app_opened', { math: 'dau' })], { breakdown: 'form_factor', display: 'ActionsPie', from: '-30d' })],
      ['App versions in use', trends([ev('app_opened', { math: 'dau' })], { breakdown: 'app_version', display: 'ActionsBar', from: '-14d' })],
      ['Simple vs Advanced', trends([ev('app_opened', { math: 'dau' })], { breakdown: 'simple', display: 'ActionsPie', from: '-30d' })],
      ['Cold start time', trends([ev('app_opened', { properties: [prop('cold', ['true'])] })], { breakdown: 'start', display: 'ActionsBar', from: '-14d' })],
      ['Screens viewed', trends([ev('screen_viewed')], { breakdown: 'screen', display: 'ActionsBar', from: '-30d' })],
    ],
  },
  {
    name: 'Ghost.md · Plugins',
    description: 'Which plugins are on, what they do, and how far their setup gets.',
    insights: [
      ['Installs with each plugin on', trends([ev('plugin_active', { math: 'dau' })], { breakdown: 'plugin', display: 'ActionsBar', from: '-7d' })],
      ['Plugins switched on and off', trends([ev('plugin_enabled'), ev('plugin_disabled')], { breakdown: 'plugin', display: 'ActionsBar' })],
      ['Plugin actions over time', trends([ev('plugin_action')], { breakdown: 'plugin' })],
      ['Plugin actions by kind', trends([ev('plugin_action')], { breakdown: 'action', display: 'ActionsBar' })],
      ['Plugin jobs over time', trends([ev('job_finished'), ev('job_failed')], { breakdown: 'plugin' })],
      ['Setup funnel, every plugin', funnel([ev('plugin_setup_started'), ev('plugin_setup_finished')], { breakdown: 'plugin' })],
      ...PLUGINS_ACTIONS.map((id) => [`Setup funnel · ${id}`, funnel([ev('plugin_setup_started', { properties: [prop('plugin', [id])] }), ev('plugin_setup_finished', { properties: [prop('plugin', [id])] })])]),
    ],
  },
  {
    name: 'Ghost.md · Notes & editing',
    description: 'Notes made, opened and edited (never which), search and the trash.',
    insights: [
      ['Notes created, opened, edited a day', trends([ev('note_created'), ev('note_opened'), ev('note_edited')])],
      ['Notes created by source', trends([ev('note_created')], { breakdown: 'source' })],
      ['Notes edited per active install', trends([ev('note_edited'), ev('app_opened', { math: 'dau' })], { formula: 'A / B' })],
      ['Search used', trends([ev('search_used')], { breakdown: 'results' })],
      ['Trashed, restored, deleted', trends([ev('note_trashed'), ev('note_restored'), ev('note_deleted')])],
      ['Folders and workspaces', trends([ev('folder_created'), ev('folder_deleted'), ev('workspace_created'), ev('workspace_deleted')], { display: 'ActionsBar' })],
      ['Recordings', trends([ev('recording_started'), ev('recording_finished')], { breakdown: 'mode' })],
      ['Recording length', trends([ev('recording_finished')], { breakdown: 'took', display: 'ActionsBar' })],
    ],
  },
  {
    name: 'Ghost.md · Jobs & reliability',
    description: 'Background jobs by kind, sync failures and uncaught errors by type.',
    insights: [
      ['Jobs finished vs failed', trends([ev('job_finished'), ev('job_failed'), ev('job_stopped')], { breakdown: 'job', display: 'ActionsBar' })],
      ['Job failure rate', trends([ev('job_failed'), ev('job_finished')], { formula: 'A / (A + B)' })],
      ['Job failure rate by kind', trends([ev('job_failed'), ev('job_finished')], { formula: 'A / (A + B)', breakdown: 'kind' })],
      ['Job durations', trends([ev('job_finished')], { breakdown: 'took', display: 'ActionsBar' })],
      ['Failed jobs by their fix', trends([ev('job_failed')], { breakdown: 'fix', display: 'ActionsPie' })],
      ['Sync failures by reason', trends([ev('sync_failed')], { breakdown: 'reason' })],
      ['Uncaught errors by type', trends([ev('error_caught')], { breakdown: 'type', display: 'ActionsTable' })],
      ['Errors by app version', trends([ev('error_caught')], { breakdown: 'app_version', display: 'ActionsBar' })],
      ['App versions in use', trends([ev('app_opened', { math: 'dau' })], { breakdown: 'app_version' })],
      ['Updates installed', trends([ev('update_installed')], { breakdown: 'app_version' })],
    ],
  },
  {
    name: 'Ghost.md · AI & Lovart',
    description: 'Header images, Lovart styles and models, Notion imports and syncs, and AI use by provider.',
    insights: [
      ['Header images made and failed', trends([ev('job_finished', { properties: [prop('job', ['banner', 'lovart-banners'])] }), ev('job_failed', { properties: [prop('job', ['banner', 'lovart-banners'])] })])],
      ['Header image runs (images asked)', trends([ev('plugin_action', { properties: [prop('plugin', ['lovart']), prop('action', ['banner_run_started'])] })], { breakdown: 'count', display: 'ActionsBar' })],
      ['Lovart styles chosen', trends([ev('plugin_action', { properties: [prop('plugin', ['lovart']), prop('action', ['style_chosen'])] })], { breakdown: 'choice', display: 'ActionsPie' })],
      ['Lovart models chosen', trends([ev('plugin_action', { properties: [prop('plugin', ['lovart']), prop('action', ['model_chosen'])] })], { breakdown: 'choice', display: 'ActionsBar' })],
      ['Notion imports', trends([ev('plugin_action', { properties: [prop('plugin', ['notion']), prop('action', ['import_started', 'import_finished', 'import_failed', 'import_stopped', 'import_removed'])] })], { breakdown: 'action' })],
      ['Notion import size', trends([ev('plugin_action', { properties: [prop('plugin', ['notion']), prop('action', ['import_finished'])] })], { breakdown: 'count', display: 'ActionsBar' })],
      ['Notion syncs', trends([ev('plugin_action', { properties: [prop('plugin', ['notion']), prop('action', ['sync_run'])] })], { breakdown: 'ok' })],
      ['AI requests by provider', trends([ev('ai_used')], { breakdown: 'provider' })],
      ['AI jobs (summaries, cleanup, contradictions)', trends([ev('job_finished', { properties: [prop('kind', ['ai'])] })], { breakdown: 'job' })],
    ],
  },
  {
    name: 'Ghost.md · Growth',
    description: 'The walkthrough, accounts and organizations.',
    insights: [
      ['Onboarding funnel', funnel(['onboarding_started', ev('onboarding_step', { properties: [prop('step', ['sync'])] }), ev('onboarding_step', { properties: [prop('step', ['mode'])] }), 'onboarding_finished'])],
      ['Onboarding pages reached', trends([ev('onboarding_step')], { breakdown: 'step', display: 'ActionsBar' })],
      ['Where onboarding was closed', trends([ev('onboarding_finished')], { breakdown: 'step', display: 'ActionsPie' })],
      ['Sign-ups and sign-ins', trends([ev('signed_up'), ev('signed_in'), ev('signed_out')])],
      ['Install to sign-up', funnel(['app_opened', 'signed_up'], { days: 30 })],
      ['Organization created → invite sent → joined', funnel(['org_created', 'invite_sent', 'org_joined'], { days: 30 })],
      ['Invites by way', trends([ev('invite_sent')], { breakdown: 'way', display: 'ActionsPie' })],
      ['Notes shared', trends([ev('note_shared')])],
      ['Settings changed', trends([ev('setting_changed')], { breakdown: 'setting', display: 'ActionsBar' })],
    ],
  },
];

// --- the work -------------------------------------------------------------------------------------------------------

async function holdProjectToPrivacy() {
  const wanted = {
    anonymize_ips: true,
    session_recording_opt_in: false,
    autocapture_opt_out: true,
    autocapture_exceptions_opt_in: false,
    autocapture_web_vitals_opt_in: false,
    capture_console_log_opt_in: false,
    capture_performance_opt_in: false,
    heatmaps_opt_in: false,
    surveys_opt_in: false,
  };
  try {
    const now = await api('GET', '');
    const change = Object.fromEntries(Object.entries(wanted).filter(([k, v]) => k in now && now[k] !== v));
    if (Object.keys(change).length) await api('PATCH', '', change);
    const after = await api('GET', '');
    const held = Object.entries(wanted).map(([k, v]) => `${k}=${k in after ? after[k] : 'n/a'}${k in after && after[k] !== v ? ' (NOT SET)' : ''}`);
    console.log(`Project settings: ${held.join(', ')}`);
    return after;
  } catch (e) {
    console.log(`Project settings could not be changed (${e.message}): set them by hand (docs/ANALYTICS.md).`);
    return null;
  }
}

async function main() {
  const proj = await holdProjectToPrivacy();
  const existingDash = await all('dashboards/');
  const existingInsights = await all('insights/?saved=true');
  for (const d of dashboards) {
    let dash = existingDash.find((x) => x.name === d.name && !x.deleted);
    if (dash) {
      dash = await api('PATCH', `dashboards/${dash.id}/`, { description: d.description });
    } else {
      dash = await api('POST', 'dashboards/', { name: d.name, description: d.description, pinned: true });
    }
    let made = 0, updated = 0;
    for (const [name, query] of d.insights) {
      const full = `${d.name.replace('Ghost.md · ', '')} · ${name}`;
      const had = existingInsights.find((x) => x.name === full && !x.deleted);
      if (had) {
        const on = new Set([...(had.dashboards || []), dash.id]);
        await api('PATCH', `insights/${had.id}/`, { query, dashboards: [...on] });
        updated += 1;
      } else {
        await api('POST', 'insights/', { name: full, query, dashboards: [dash.id], saved: true });
        made += 1;
      }
    }
    console.log(`${d.name}: ${made} made, ${updated} updated · ${app}/project/${project}/dashboard/${dash.id}`);
  }
  if (process.argv.includes('--test')) await sendTestEvents(proj);
}

async function sendTestEvents() {
  const projectKey = env.POSTHOG_PROJECT_KEY;
  if (!projectKey) return console.log('No POSTHOG_PROJECT_KEY: no test events sent.');
  const id = `test-${randomUUID()}`;
  const base = { distinct_id: id, $process_person_profile: false, $geoip_disable: true, $lib: 'ghost-md', test: true, app_version: '0.0.0-test', platform: 'macos', form_factor: 'desktop', simple: false, lang: 'en', plugins_on: ',', plugin_count: 0 };
  const batch = [
    { event: 'app_opened', uuid: randomUUID(), timestamp: new Date().toISOString(), properties: { ...base, cold: true, start: '1-2s' } },
    { event: 'screen_viewed', uuid: randomUUID(), timestamp: new Date().toISOString(), properties: { ...base, screen: 'list' } },
    { event: 'plugin_enabled', uuid: randomUUID(), timestamp: new Date().toISOString(), properties: { ...base, plugin: 'lovart' } },
  ];
  const res = await fetch(`${capture}/batch/`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ api_key: projectKey, batch }) });
  console.log(`Test events sent: ${res.status} (install ${id.slice(0, 13)}…)`);
  // Read them back through the query API: ingestion takes a little while.
  for (let i = 0; i < 12; i += 1) {
    await new Promise((r) => setTimeout(r, 10000));
    try {
      const q = await api('POST', 'query/', { query: { kind: 'HogQLQuery', query: `select event, properties.$process_person_profile, properties.$ip from events where distinct_id = '${id}' and timestamp > now() - interval 1 hour` } });
      if ((q.results || []).length) {
        console.log(`Seen through the API after ${(i + 1) * 10}s: ${q.results.map((r) => `${r[0]} (person profile ${r[1]}, ip ${r[2] ?? 'none'})`).join(', ')}`);
        return;
      }
    } catch (e) {
      console.log(`The query API refused (${e.message}).`);
      return;
    }
  }
  console.log('Not seen through the API within two minutes (ingestion may still be catching up).');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
