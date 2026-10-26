/**
 * Everything the bot says in Discord, in one place (docs/DISCORD_CALLS.md, "Recording people needs their
 * knowledge"). The Meet bot says in Meet's chat what it is and where the recording goes (server/src/meet.rs
 * `ANNOUNCE`); in Discord the person who asked is named too, since anyone in a server may run `/ghost join`.
 *
 * Names are Discord's own display names, put in as text: every message is sent with no mentions allowed (bot.mjs),
 * so a name is never a ping.
 */

/** Where in the app the Discord plugin's page is (lib/plugins/discord/calls_section.dart): added in the Market, it is
 * a row of Settings of its own. */
export const PLUGIN_PAGE = 'Ghost.md › Settings › Discord (add the Discord plugin in the Market first)';

/** Where in the app a code is made. */
export const WHERE_CODES_ARE = `${PLUGIN_PAGE} › Discord calls › Link Discord`;

/** What the voice channel's chat is told as Ghost starts recording: who asked, and what happens to the recording. */
export function announce(name) {
  return (
    `**Ghost is taking notes for ${clean(name)}.** This call is being recorded from now on, for ${clean(name)}'s Ghost.md, where it is written up ` +
    'with who said what. The recording is sealed to their account as it arrives. Anyone here can stop it with `/ghost leave`.'
  );
}

/** Said to someone who joins the channel while Ghost is recording it. */
export function newcomer(newName, forName) {
  return `${clean(newName)}, Ghost is recording this call for ${clean(forName)}'s Ghost.md. \`/ghost leave\` stops it.`;
}

/** The public answer to `/ghost join`, once Ghost is on its way in. */
export function joining(channelId, name) {
  return `Ghost is joining <#${channelId}> to take notes for ${clean(name)}.`;
}

/** The public answer to `/ghost leave`. */
export function leaving(forName) {
  return `Ghost has stopped recording. The call goes to ${clean(forName)}'s Ghost.md, to be written up there.`;
}

/** Said in the channel's chat when Ghost leaves by itself, and why. */
export function leftBecause(reason) {
  return (
    {
      alone: 'Ghost has left: everyone else had gone. The recording is on its way to Ghost.md.',
      few_left: 'Ghost has left now the call is nearly over. The recording is on its way to Ghost.md.',
      time_up: 'Ghost has left: three hours is the longest it records. The recording is on its way to Ghost.md.',
      asked_to_leave: 'Ghost has left, as asked in Ghost.md. The recording is on its way there.',
    }[reason] ?? null
  );
}

/** How to link, said to someone not linked yet (ephemeral). */
export const HOW_TO_LINK =
  'Link your Discord to Ghost.md first:\n' +
  `1. In ${WHERE_CODES_ARE}, you get a code.\n` +
  '2. Run `/ghost link` here with that code.\n' +
  'Then run `/ghost join` again from a voice channel.';

/** Linked, with the plugin's "Join Discord calls" switched off. */
export const CALLS_OFF = `Ghost joining your Discord calls is switched off. Turn on Join Discord calls in ${PLUGIN_PAGE}, then run \`/ghost join\` again.`;

export const NOT_IN_VOICE = 'Join a voice channel first, then run `/ghost join` there.';
export const NO_STAGES = 'Ghost takes notes in voice channels, not Stage channels. Move to a voice channel and run `/ghost join` there.';
export const NOT_HERE = 'Run `/ghost` in a server, not in a direct message.';
export const NO_ROOM = 'Ghost is in as many calls as it can be just now. Try again in a while.';
export const CANT_CONNECT = 'Ghost may not join that voice channel. A server admin can let it: Ghost needs View Channel and Connect there.';
export const NOT_RECORDING = 'Ghost is not recording a call in this server.';
export const NOT_YOURS_TO_STOP = 'Only someone in the call can stop Ghost recording it.';
export const JOIN_FAILED = 'Ghost could not get into the call. Try `/ghost join` again in a minute.';
export const SERVICE_DOWN = 'Ghost.md could not be reached just now. Try again in a minute.';

/** Ghost is already recording in this server: where, and for whom. */
export const alreadyIn = (channelId, name) => `Ghost is already taking notes in <#${channelId}> for ${clean(name)}. One call a server at a time.`;

/** The answer to a `/ghost join` the service refused, by its status: 409 no key yet, 429 too many. */
export function refusedJoin(status) {
  if (status === 409) return 'Your Ghost.md account is not ready for recordings yet: open Ghost.md on one of your devices and let it sync once, then try again.';
  if (status === 429) return 'That is a lot of calls for now. Wait a while, or skip a meeting you have booked in Ghost.md.';
  return SERVICE_DOWN;
}

/** The answer to `/ghost link <code>`, by what the service said (ephemeral). */
export function linkReply(outcome) {
  switch (outcome) {
    case 'linked':
      return 'Linked: Ghost.md now knows this Discord account is yours. Run `/ghost join` from a voice channel and Ghost records the call for you.';
    case 'bad_code':
      return `That code is not one Ghost.md gave, or it has run out (a code lasts ten minutes). Make a new one in ${WHERE_CODES_ARE}.`;
    case 'too_many':
      return 'Too many codes tried. Wait a while, then try again with a new code.';
    default:
      return SERVICE_DOWN;
  }
}

/** A name as text in a message: no markdown that would change how the message reads, never more than 80 characters. */
export function clean(name) {
  const plain = String(name ?? '').replace(/[*_`~|>\\[\]()<@#]/g, '').replace(/\s+/g, ' ').trim().slice(0, 80);
  return plain || 'someone';
}
