// Ghost Messaging's Discord presence bot: one gateway connection (intents Guilds and GuildVoiceStates, nothing
// privileged), the /ghost commands, and the HTTP routes in http.js on 127.0.0.1. It does not join voice.
//
//   DISCORD_TOKEN   the bot's token (required)
//   DISCORD_APP_ID  the application's id (required: the invite link and the commands)
//   PORT            default 18788
//   DISCORD_DATA    where links.json lives, default ./data
import { createServer } from 'node:http';
import { Client, Events, GatewayIntentBits, MessageFlags, PermissionFlagsBits } from 'discord.js';
import { Codes } from './codes.js';
import { COMMAND, answer } from './commands.js';
import { createHandler, inviteUrl } from './http.js';
import { missingMembers } from './state.js';
import { TokenStore } from './store.js';

const log = (message) => console.log(`${new Date().toISOString()} ${message}`);
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

const TOKEN = process.env.DISCORD_TOKEN ?? '';
const APP_ID = process.env.DISCORD_APP_ID ?? '';
const PORT = Number(process.env.PORT || 18788);
const DATA = process.env.DISCORD_DATA || './data';
if (!TOKEN) fail('DISCORD_TOKEN is not set.');
if (!/^\d{15,22}$/.test(APP_ID)) fail('DISCORD_APP_ID is not set, or is not an application id (digits).');
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) fail('PORT is not a port.');

const codes = new Codes();
const store = TokenStore.open(DATA);
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates] });

const withTimeout = (promise, ms) => Promise.race([promise, new Promise((resolve) => setTimeout(() => resolve(null), ms))]);

/** People in voice whose member is not cached (a voice state can come without one): fetched over REST, which needs no
 * privileged intent, a few at a time and never for longer than the request can wait. */
async function fetchMissing(guild) {
  const ids = missingMembers(guild).slice(0, 50);
  for (let i = 0; i < ids.length; i += 10) {
    await withTimeout(Promise.all(ids.slice(i, i + 10).map((id) => guild.members.fetch(id).catch(() => null))), 3000);
  }
}

const guilds = {
  async lookup(id, { members }) {
    if (!client.isReady()) return { status: 'starting' };
    const guild = client.guilds.cache.get(id);
    if (!guild) return { status: 'gone' };
    if (!guild.available) return { status: 'starting' };
    if (members) await fetchMissing(guild);
    return { status: 'ok', guild };
  },
};

client.once(Events.ClientReady, async (c) => {
  log(`ready in ${c.guilds.cache.size} servers; ${store.links.size} links on file`);
  try {
    await c.application.commands.set([COMMAND]);
    log('/ghost registered globally');
  } catch (e) {
    log(`registering /ghost failed: ${e?.message ?? e}`);
  }
});

client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.isChatInputCommand() || interaction.commandName !== 'ghost') return;
  const sub = interaction.options.getSubcommand(false);
  const content = answer(
    { sub, guildId: interaction.guildId, canManage: Boolean(interaction.memberPermissions?.has(PermissionFlagsBits.ManageGuild)) },
    { codes, store },
  );
  log(`/ghost ${sub} in ${interaction.guildId ?? 'a DM'}`);
  try {
    await interaction.reply({ content, flags: MessageFlags.Ephemeral });
  } catch (e) {
    log(`reply failed: ${e?.message ?? e}`);
  }
});

client.on(Events.GuildCreate, (guild) => log(`added to server ${guild.id}`));
client.on(Events.GuildDelete, (guild) => {
  // Its links stay on file (they answer 410 gone, and work again if the bot is added back); its codes go.
  codes.dropGuild(guild.id);
  log(`removed from server ${guild.id} (${store.countGuild(guild.id)} links now answer gone)`);
});
client.on(Events.Error, (e) => log(`discord error: ${e?.message ?? e}`));

const server = createServer(createHandler({ codes, store, guilds, appId: APP_ID, log }));
server.headersTimeout = 10_000;
server.requestTimeout = 15_000;
server.listen(PORT, '127.0.0.1', () => {
  log(`listening on 127.0.0.1:${PORT}`);
  log(`invite: ${inviteUrl(APP_ID)}`);
});

let stopping = false;
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    if (stopping) return;
    stopping = true;
    log(`${signal}: stopping`);
    server.close();
    client.destroy().finally(() => process.exit(0));
    setTimeout(() => process.exit(0), 5000).unref();
  });
}

client.login(TOKEN).catch((e) => fail(`logging in to Discord failed: ${e?.message ?? e}`));
