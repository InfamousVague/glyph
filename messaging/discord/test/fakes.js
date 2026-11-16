// Plain objects shaped as the parts of discord.js's Guild that state.js reads.
export const VOICE = 2, CATEGORY = 4, TEXT = 0, STAGE = 13;

export function member(id, { nickname = null, globalName = null, username = `user${id}`, avatar = null, userAvatar = null, bot = false } = {}) {
  return { id, nickname, avatar, user: { id, username, globalName, avatar: userAvatar, bot } };
}

export function voiceState(id, channelId, extra = {}) {
  return { id, channelId, selfMute: false, serverMute: false, selfDeaf: false, serverDeaf: false, selfVideo: false, streaming: false, ...extra };
}

export function guild({ id = '100000000000000001', name = 'Test server', icon = null, channels = [], voiceStates = [], members = [] } = {}) {
  return {
    id,
    name,
    icon,
    channels: { cache: new Map(channels.map((c) => [c.id, c])) },
    voiceStates: { cache: new Map(voiceStates.map((v) => [v.id, v])) },
    members: { cache: new Map(members.map((m) => [m.id, m])) },
  };
}
