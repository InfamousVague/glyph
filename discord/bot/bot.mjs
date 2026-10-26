#!/usr/bin/env node
/**
 * Ghost.md's Discord notetaker (docs/DISCORD_CALLS.md). Matt, 2026-10-26: "Add a new plugin to post notes to discord
 * chats as well as join discord calls to summarize meetings". Someone in a voice channel runs `/ghost join`; Ghost
 * joins the channel, says in its chat who it records for, records the call, and hands the take to glyph-api, which
 * seals it to their account on arrival; their device files it and writes it up as it does a Google Meet's
 * (lib/meet/meet_in.dart).
 *
 *   node bot.mjs        the service (glyph-discord.service): the gateway connection, the commands, the calls
 *
 * Environment: DISCORD_BOT_TOKEN (Discord's, to the gateway), GLYPH_DISCORD_TOKEN (the bot's to glyph-api's internal
 * routes, server/src/discord.rs), GLYPH_DISCORD_API (http://127.0.0.1:8796), GLYPH_DISCORD_DATA (/var/lib/glyph-
 * discord: work/, work/failed/).
 *
 * Intents: Guilds and GuildVoiceStates, neither privileged. The voice states bring each member in a voice channel
 * with them, nickname and all, so no Server Members intent is needed for the names; slash commands need no Message
 * Content. Every message is sent with no mentions allowed: a name in one is text, never a ping.
 *
 * One call a server at a time (Discord gives a bot one voice connection a server), and `MAX_CALLS` across them all,
 * for the box's CPU (each speaker is decoded, and the mix encoded, in WebAssembly).
 */
import { mkdirSync, readdirSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { ChannelType, Client, Events, GatewayIntentBits, MessageFlags, PermissionFlagsBits } from 'discord.js';
import { EndBehaviorType, VoiceConnectionStatus, entersState, joinVoiceChannel } from '@discordjs/voice';
import { LIMITS } from '../../meet/bot/lib/decide.mjs';
import { errorField, log } from '../../meet/bot/lib/log.mjs';
import { createDiscordApi, openCall, redeemCode } from './lib/api.mjs';
import { Call } from './lib/call.mjs';
import { opusCodec } from './lib/codec.mjs';
import { subcommandOf } from './lib/commands.mjs';
import * as words from './lib/words.mjs';

const DATA = process.env.GLYPH_DISCORD_DATA || '/var/lib/glyph-discord';
const WORK = join(DATA, 'work');
const MAX_CALLS = 4;
/** How often the people in a call are counted. */
const COUNT_MS = 5000;
const TICK_MS = 100;
const QUIET = { parse: [] };

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let stopping = false;
/** The calls under way, by server; the servers a call is being opened in. */
const calls = new Map();
const opening = new Set();
const running = new Set();

for (const name of ['DISCORD_BOT_TOKEN', 'GLYPH_DISCORD_TOKEN']) {
  if (!process.env[name]) {
    log('fatal', { error: `${name} is not set` });
    process.exit(1);
  }
}
const api = createDiscordApi({ base: process.env.GLYPH_DISCORD_API || 'http://127.0.0.1:8796', token: process.env.GLYPH_DISCORD_TOKEN, timeoutMs: 10_000 });
const codec = opusCodec();
const ctx = { api, work: WORK, codec, stopping: () => stopping, limits: LIMITS, log };

/** Files a killed run left behind: kept aside for a person to look at, not uploaded as if whole. */
function setAsideLeftovers() {
  mkdirSync(join(WORK, 'failed'), { recursive: true });
  for (const name of readdirSync(WORK)) {
    if (!/\.(webm|ndjson)$/.test(name)) continue;
    renameSync(join(WORK, name), join(WORK, 'failed', name));
    log('leftover_kept', { id: name.replace(/\..*$/, '') });
  }
}

/** Calls the server still has as under way, which this process (just started) cannot finish: `failed: restarted`. */
async function closeOrphans() {
  try {
    for (const m of await api.due()) {
      if (calls.has(m.id)) continue;
      await api.state(m.id, 'failed', 'restarted').then(() => log('state', { id: m.id, state: 'failed', detail: 'restarted' }), () => {});
    }
  } catch (e) {
    log('due_failed', { error: errorField(e), status: e.status });
  }
}

/** An answer only the person who asked sees. */
const privately = (interaction, content) =>
  interaction.deferred || interaction.replied
    ? interaction.editReply({ content, allowedMentions: QUIET })
    : interaction.reply({ content, flags: MessageFlags.Ephemeral, allowedMentions: QUIET });

/** A message in the voice channel's own chat; where Ghost may not post there, in the channel the command came from. */
async function say(channel, content, interaction = null) {
  try {
    await channel.send({ content, allowedMentions: QUIET });
    return true;
  } catch (e) {
    log('say_failed', { error: errorField(e) });
    if (!interaction) return false;
    return interaction.followUp({ content, allowedMentions: QUIET }).then(() => true, () => false);
  }
}

/** The people in a voice channel, Ghost counted: its human members, and Ghost. */
function peopleIn(guild, channelId) {
  const channel = guild.channels.cache.get(channelId);
  if (!channel?.members) return null;
  return [...channel.members.values()].filter((m) => !m.user.bot).length + 1;
}

async function onJoin(interaction) {
  if (!interaction.inCachedGuild()) return privately(interaction, words.NOT_HERE);
  const { guild, member } = interaction;
  const channel = member.voice.channel;
  if (!channel) return privately(interaction, words.NOT_IN_VOICE);
  if (channel.type === ChannelType.GuildStageVoice) return privately(interaction, words.NO_STAGES);
  const under = calls.get(guild.id);
  if (under) return privately(interaction, words.alreadyIn(under.channelId, under.forName));
  if (opening.has(guild.id) || calls.size + opening.size >= MAX_CALLS || stopping) return privately(interaction, words.NO_ROOM);
  const allowed = channel.permissionsFor(guild.members.me);
  if (!allowed?.has([PermissionFlagsBits.ViewChannel, PermissionFlagsBits.Connect]) || !channel.joinable) return privately(interaction, words.CANT_CONNECT);
  opening.add(guild.id);
  try {
    await interaction.deferReply({ flags: MessageFlags.Ephemeral });
    const opened = await openCall(api, { user: member.id, guild: guild.id, channel: channel.id, title: `${channel.name} in ${guild.name}` });
    if (!opened.ok) {
      log('join_refused', { detail: opened.why, status: opened.status });
      const why = { not_linked: words.HOW_TO_LINK, calls_off: words.CALLS_OFF, refused: words.refusedJoin(opened.status) }[opened.why];
      return privately(interaction, why ?? words.SERVICE_DOWN);
    }
    await privately(interaction, words.joining(channel.id, member.displayName));
    const call = new Call({ meeting: opened.meeting, forName: member.displayName, guildId: guild.id, channelId: channel.id, requester: member.id, ctx });
    calls.set(guild.id, call);
    const run = runCall(call, channel, interaction)
      .catch((e) => log('call_error', { id: call.id, error: errorField(e) }))
      .finally(() => {
        calls.delete(guild.id);
        running.delete(run);
      });
    running.add(run);
  } finally {
    opening.delete(guild.id);
  }
}

/** One call, start to finish (lib/call.mjs owns the recording, the leaving and the upload). */
async function runCall(call, channel, interaction) {
  const { guild } = channel;
  const id = call.id;
  log('joining', { id, calls: calls.size });
  const connection = joinVoiceChannel({ channelId: channel.id, guildId: guild.id, adapterCreator: guild.voiceAdapterCreator, selfDeaf: false, selfMute: true });
  try {
    await entersState(connection, VoiceConnectionStatus.Ready, 30_000);
  } catch (e) {
    log('join_failed', { id, error: errorField(e) });
    connection.destroy();
    await api.state(id, 'failed', 'join_failed').catch(() => {});
    await interaction.followUp({ content: words.JOIN_FAILED, flags: MessageFlags.Ephemeral, allowedMentions: QUIET }).catch(() => {});
    return;
  }
  try {
    await api.state(id, 'in_call');
  } catch (e) {
    // 409: called off on a device while Ghost was on its way in.
    log('state_failed', { id, state: 'in_call', status: e.status, error: errorField(e) });
    if (e.over) {
      connection.destroy();
      return;
    }
  }
  call.start(Date.now());
  await say(channel, words.announce(call.forName), interaction);
  log('recording', { id });

  const receiver = connection.receiver;
  const told = new Set([call.requester]);
  const listen = (userId) => {
    if (receiver.subscriptions.has(userId)) return;
    const stream = receiver.subscribe(userId, { end: { behavior: EndBehaviorType.Manual } });
    stream.on('data', (packet) => call.packet(userId, packet, Date.now()));
    // A stream the receiver gave up on (a packet that would not decrypt, past the DAVE session's tolerance) closes
    // and leaves the subscriptions; the person's next speaking subscribes them again.
    stream.on('error', (e) => log('receive_error', { id, error: errorField(e) }));
  };
  const named = (member) => {
    if (!member || member.user.bot) return false;
    call.name(member.id, member.displayName);
    return true;
  };
  for (const member of channel.members.values()) if (named(member)) listen(member.id);
  const onSpeaking = (userId) => {
    const member = guild.members.cache.get(userId);
    if (member?.user.bot) return;
    named(member);
    listen(userId);
  };
  receiver.speaking.on('start', onSpeaking);
  const onVoice = (was, now) => {
    if (now.guild.id !== guild.id) return;
    if (now.id === guild.client.user.id) {
      // Ghost moved, or put out of the channel.
      if (now.channelId !== channel.id) call.stop('removed');
      return;
    }
    if (now.channelId === channel.id && was.channelId !== channel.id && named(now.member)) {
      listen(now.id);
      if (!told.has(now.id)) {
        told.add(now.id);
        void say(channel, words.newcomer(now.member.displayName, call.forName));
      }
    }
  };
  guild.client.on(Events.VoiceStateUpdate, onVoice);
  connection.on(VoiceConnectionStatus.Disconnected, async () => {
    // Moved by Discord to another voice server it reconnects by itself; anything else is the end.
    try {
      await Promise.race([entersState(connection, VoiceConnectionStatus.Signalling, 5000), entersState(connection, VoiceConnectionStatus.Connecting, 5000)]);
    } catch {
      call.stop('disconnected');
    }
  });
  connection.on(VoiceConnectionStatus.Destroyed, () => call.stop('disconnected'));

  let counted = 0;
  let reason = null;
  let minute = Date.now();
  while (!reason) {
    const now = Date.now();
    if (now - counted >= COUNT_MS) {
      counted = now;
      call.counted(peopleIn(guild, channel.id), now);
    }
    if (now - minute >= 60_000) {
      minute = now;
      log('in_call', { id, seconds: Math.round((now - call.joinedAt) / 1000), packets: call.recorder.packets, speakers: call.recorder.speakers, people: call.presence.count });
    }
    reason = await call.tick(now);
    if (!reason) await sleep(TICK_MS);
  }
  receiver.speaking.off('start', onSpeaking);
  guild.client.off(Events.VoiceStateUpdate, onVoice);
  connection.removeAllListeners(VoiceConnectionStatus.Destroyed);
  connection.destroy();
  const parting = words.leftBecause(reason);
  if (parting) await say(channel, parting);
  await call.finish(Date.now());
}

async function onLeave(interaction) {
  if (!interaction.inCachedGuild()) return privately(interaction, words.NOT_HERE);
  const call = calls.get(interaction.guildId);
  if (!call) return privately(interaction, words.NOT_RECORDING);
  const { member } = interaction;
  const inCall = member.voice.channelId === call.channelId;
  if (!inCall && member.id !== call.requester && !member.permissions.has(PermissionFlagsBits.ManageChannels)) return privately(interaction, words.NOT_YOURS_TO_STOP);
  call.stop('asked');
  log('asked_to_leave', { id: call.id });
  return interaction.reply({ content: words.leaving(call.forName), allowedMentions: QUIET });
}

async function onLink(interaction) {
  await interaction.deferReply({ flags: MessageFlags.Ephemeral });
  const outcome = await redeemCode(api, { code: interaction.options.getString('code', true), user: interaction.user.id, name: interaction.user.username });
  log('link', { detail: outcome });
  return privately(interaction, words.linkReply(outcome));
}

const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates] });

client.once(Events.ClientReady, async (ready) => {
  log('started', { version: process.version, count: ready.guilds.cache.size });
  await closeOrphans();
});

client.on(Events.InteractionCreate, async (interaction) => {
  const sub = subcommandOf(interaction);
  if (!sub) return;
  try {
    if (sub === 'join') await onJoin(interaction);
    else if (sub === 'leave') await onLeave(interaction);
    else await onLink(interaction);
  } catch (e) {
    log('command_error', { detail: sub, error: errorField(e) });
    await privately(interaction, words.SERVICE_DOWN).catch(() => {});
  }
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, async () => {
    if (stopping) return;
    stopping = true;
    log('stopping', { calls: calls.size });
    // Each call sees `stopping`, leaves, and tries its upload once; then the gateway goes.
    await Promise.allSettled([...running]);
    await client.destroy();
    log('stopped', {});
    process.exit(0);
  });
}

mkdirSync(WORK, { recursive: true });
setAsideLeftovers();
await client.login(process.env.DISCORD_BOT_TOKEN).catch((e) => {
  log('fatal', { error: errorField(e) });
  process.exit(1);
});
