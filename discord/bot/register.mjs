#!/usr/bin/env node
/**
 * Tells Discord of `/ghost` (lib/commands.mjs): a PUT of the whole list, so running it again changes nothing that
 * did not change, and a subcommand taken out of the list goes from Discord too.
 *
 *   node register.mjs            global commands: every server Ghost is in (Discord updates them within the hour,
 *                                usually at once)
 *   node register.mjs --guild    only the server DISCORD_GUILD_ID, at once: for trying a change first
 *   node register.mjs --print    the JSON it would send, and nothing sent
 *
 * Environment: DISCORD_BOT_TOKEN, DISCORD_APP_ID (the application's id, Developer Portal › General Information), and
 * DISCORD_GUILD_ID with --guild. On the box, scripts/setup-discord-box.mjs --register-commands runs it as the bot's
 * user with the bot's env file; the token is never an argument.
 */
import { REST, Routes } from 'discord.js';
import { COMMANDS } from './lib/commands.mjs';

const args = process.argv.slice(2);
if (args.includes('--print')) {
  console.log(JSON.stringify(COMMANDS, null, 2));
  process.exit(0);
}
const { DISCORD_BOT_TOKEN: token, DISCORD_APP_ID: app, DISCORD_GUILD_ID: guild } = process.env;
if (!token || !app) {
  console.error('DISCORD_BOT_TOKEN and DISCORD_APP_ID are both needed.');
  process.exit(2);
}
if (!/^\d{15,21}$/.test(app)) {
  console.error('DISCORD_APP_ID is the application id: digits only.');
  process.exit(2);
}
const inGuild = args.includes('--guild');
if (inGuild && !/^\d{15,21}$/.test(guild ?? '')) {
  console.error('--guild needs DISCORD_GUILD_ID, the server id (digits).');
  process.exit(2);
}
const rest = new REST({ version: '10' }).setToken(token);
try {
  const route = inGuild ? Routes.applicationGuildCommands(app, guild) : Routes.applicationCommands(app);
  const done = await rest.put(route, { body: COMMANDS });
  console.log(`REGISTERED ${done.length} command(s) ${inGuild ? 'in the one server' : 'globally'}: ${done.map((c) => `/${c.name}`).join(', ')}`);
} catch (e) {
  // The error's status and code, not its body: Discord's bodies echo what was sent.
  console.error(`REGISTER_FAILED ${e.status ?? ''} ${e.code ?? e.message}`.trim());
  process.exit(1);
}
