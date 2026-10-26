/**
 * `/ghost`, as Discord is told of it (register.mjs) and as the bot reads it (bot.mjs): one command with three
 * subcommands, in servers only.
 *
 *   /ghost join          Ghost joins the voice channel you are in and records it for your Ghost.md
 *   /ghost leave         Ghost stops recording and leaves (anyone in the call)
 *   /ghost link <code>   this Discord account linked to Ghost.md, with the code from the Discord plugin's page
 *
 * No permission is asked of the person running them (`default_member_permissions` unset): a server's admins can
 * narrow who may under Server Settings › Integrations, as with any app's commands.
 */

/** Discord's numbers for what the JSON names. */
const SUB_COMMAND = 1;
const STRING = 3;
const CHAT_INPUT = 1;
/** Interaction contexts and install types: a server, by a server install. */
const GUILD = 0;
const GUILD_INSTALL = 0;

export const COMMANDS = [
  {
    name: 'ghost',
    type: CHAT_INPUT,
    description: 'Ghost.md takes notes of this voice call',
    contexts: [GUILD],
    integration_types: [GUILD_INSTALL],
    options: [
      { type: SUB_COMMAND, name: 'join', description: 'Ghost joins your voice channel and records it for your Ghost.md' },
      { type: SUB_COMMAND, name: 'leave', description: 'Ghost stops recording and leaves the call' },
      {
        type: SUB_COMMAND,
        name: 'link',
        description: 'Link this Discord account to Ghost.md',
        options: [{ type: STRING, name: 'code', description: 'The code from Ghost.md: Settings › Discord › Link Discord', required: true, min_length: 8, max_length: 16 }],
      },
    ],
  },
];

/** Which subcommand an interaction is, or null for anything else. */
export function subcommandOf(interaction) {
  if (!interaction?.isChatInputCommand?.() || interaction.commandName !== 'ghost') return null;
  const sub = interaction.options.getSubcommand(false);
  return ['join', 'leave', 'link'].includes(sub) ? sub : null;
}
