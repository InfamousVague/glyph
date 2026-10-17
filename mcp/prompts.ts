import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

/**
 * The connector's prompts (docs/CLAUDE_LIVE.md, "Resources, prompts, subscriptions"; Matt: "Build all of these"):
 * the slash commands Claude's app offers for this server. Each is a user message telling Claude what to do and with
 * which of the tools, so the work is the tools' and every rule they keep still holds: a weekly review, a plan for the
 * day, a note tidied as suggestions to keep or revert, and the Ask Claude inbox worked through.
 */

/** The personal note the inbox prompt and a scheduled routine work through (docs/CLAUDE_LIVE.md, "The Ask Claude inbox"). */
export const INBOX_TITLE = 'Ask Claude';

/** The inbox as it is made the first time: what it is for, and an open to-do to write the first request in. */
export const INBOX_BODY = `# ${INBOX_TITLE}

Write a request for Claude as a to-do below, one per line. Claude works through the open ones: it does each, writes what it did on a line under it, and ticks it.

- [ ] `;

/** A day as the prompts name one: the server's date, YYYY-MM-DD. */
function dayOf(at: Date): string {
  return at.toISOString().slice(0, 10);
}

const said = (text: string) => ({ messages: [{ role: 'user' as const, content: { type: 'text' as const, text } }] });

/** What every prompt says of the clock: the server's, which on the hosted one is not the person's. */
const CLOCK = 'Dates below are by the Ghost.md connector’s clock, which may be a day off the person’s; if they have said where they are, go by that.';

export function registerPrompts(server: McpServer, now: () => Date = () => new Date()): void {
  server.registerPrompt(
    'weekly-review',
    { title: 'Weekly review', description: 'A review of the last seven days in Ghost.md: what changed, what got done, and what is still open.' },
    () => {
      const today = now();
      const since = dayOf(new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000));
      return said(
        [
          `Write my weekly review from my Ghost.md notes. Today is ${dayOf(today)}; the week is from ${since}. ${CLOCK}`,
          '',
          `1. Call list_notes with a limit of 200 and take the notes whose \`updated\` is on or after ${since}. Read the ones that matter with read_note.`,
          '2. Find the open to-dos: search_notes for "- [ ]", and read the notes it finds. A due date is written `📅 YYYY-MM-DD` on the item.',
          '3. Write the review: what moved this week, by theme rather than note by note; what was finished (ticked items, tickets moved on); what is open, overdue first; and two or three things worth doing next week.',
          `4. Save it with create_note, titled "Weekly review ${dayOf(today)}", linking each note it mentions as [[its title]]. Do not change any other note.`,
          '',
          'Then tell me the review in a few lines and that it is saved.',
        ].join('\n'),
      );
    },
  );

  server.registerPrompt(
    'plan-my-day',
    { title: 'Plan my day', description: 'A plan for today from the to-dos due or overdue and the notes made or changed today.' },
    () => {
      const today = dayOf(now());
      return said(
        [
          `Plan my day from my Ghost.md notes. Today is ${today}. ${CLOCK}`,
          '',
          '1. Find the open to-dos: search_notes for "- [ ]" and for "📅", and read the notes they find with read_note. A due date is written `📅 YYYY-MM-DD` on the item, a priority as 🔺 ⏫ 🔼 🔽 ⏬, a person as @name.',
          `2. Take the items due on or before ${today} (overdue first), then the high-priority ones with no date.`,
          `3. Call list_notes and read the notes whose \`updated\` or \`created\` is ${today}: what I have already started today.`,
          '4. Write a plan: a short list in the order to do them, with a rough time for each, the overdue called out, and anything that can wait said so. Link each item’s note as [[its title]].',
          '',
          'Show me the plan. Only save it as a note (create_note) or change a to-do if I ask.',
        ].join('\n'),
      );
    },
  );

  server.registerPrompt(
    'tidy-note',
    {
      title: 'Tidy a note',
      description: 'A note restructured and cleaned up, written as suggestions the person keeps or reverts in the app.',
      argsSchema: { title: z.string().describe('The note’s title.') },
    },
    ({ title }) =>
      said(
        [
          `Tidy my Ghost.md note “${title}”.`,
          '',
          `1. Read it with read_note (title: "${title}").`,
          '2. Restructure it: clear headings, related lines together, lists where it is a list, typos and repeated words fixed. Keep every fact, link, to-do (ticked or not), picture and date it has; keep its front matter, its fenced blocks (boards, code, comments) and its title as they are.',
          '3. Write it back with update_note and `suggest: true`, so every change is a suggestion I keep or revert in the app rather than made outright. A long note can go a section at a time, each from what you last read.',
          '',
          'Then tell me in a few lines what you suggested and why.',
        ].join('\n'),
      ),
  );

  server.registerPrompt(
    'ask-claude-inbox',
    { title: 'Work through the Ask Claude inbox', description: `The open requests in the “${INBOX_TITLE}” note done, each answered under it and ticked.` },
    () =>
      said(
        [
          `Work through my “${INBOX_TITLE}” inbox in Ghost.md.`,
          '',
          `1. Find it: list_notes with query "${INBOX_TITLE}", the one titled exactly that that is not in an organization’s workspace. If there is none, make it with create_note and this body, exactly, then stop: there is nothing to do yet.`,
          '',
          '```markdown',
          INBOX_BODY,
          '```',
          '',
          '2. Read it with read_note. Each open `- [ ]` item with words is a request. Leave ticked items and empty ones alone.',
          '3. For each request, in order, do it with the tools: read, search, create, update, append, comment, file, as it needs. If one cannot be done (it needs something you do not have, or it would delete or share something), do not do it.',
          '4. Then write the answer into the inbox: under the request, a line indented two spaces as a bullet, `  - ` and one sentence saying what you did, linking any note you made or changed as [[its title]] (or why you could not). Tick the request: `- [x]`, unless it could not be done. Use update_note from the body you last read, one request at a time, so the inbox shows the work as it goes.',
          '',
          'When they are all done, tell me in a few lines what was asked and what you did.',
        ].join('\n'),
      ),
  );
}
