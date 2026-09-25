import { pluginContextFor, pluginContextVersion } from '../plugins/registry.ts';
import { cleanNote, cleanRewrite } from './clean.ts';
import { bodyHash } from './bodyHash.ts';
import { protectLinks, restoreLinks } from './links.ts';
import type { Mode } from './modes.ts';
import { protectTables, restoreTables } from './tables.ts';

/**
 * A note as the model should see it, and the way back.
 *
 * This used to be formatting in passes - a quick draft by the smallest model
 * on the phone, then revisions by the bigger ones - and a queue that ran it in
 * the background after every recording into a text kept beside the note. Matt
 * has since chosen one pass by the chosen model, landing in the note itself
 * as it is written (ai/runs.ts, ai/useLanding.ts), and the queue went with
 * the view that showed its text. What stayed is the preparation every run
 * shares: the tidy-up before the model (clean.ts), tables and links swapped
 * for tokens it can copy and put back after (tables.ts, links.ts), and the
 * hash of the body a run was written from.
 */

/**
 * What a run was written from: the body, and the version of the context
 * plugins gave with it (plugins/registry.ts: the Projects plugin's briefing),
 * so a note whose project was re-read reads as edited.
 */
export function noteHash(id: string, body: string): number {
  const version = pluginContextVersion(id);
  return bodyHash(version ? `${body}\u0000project:${version}` : body);
}

/** What plugins know about the note (a linked project's briefing), for the system message, where it is snapshotted. */
export function noteContext(id: string): string | undefined {
  return pluginContextFor(id) ?? undefined;
}

/**
 * What a model still gets wrong at the edges: a code fence around the whole
 * note, and blank lines at either end. The words are left alone.
 */
function tidy(text: string): string {
  let out = text.trim();
  const fenced = /^```[a-z]*\n([\s\S]*?)\n```$/i.exec(out);
  if (fenced?.[1]) out = fenced[1].trim();
  return `${out}\n`;
}

/**
 * Tables and links go in as tokens the model can copy (tables first, so a
 * link in a cell is inside the block) and come back out in reverse; the
 * tidy-up before (clean.ts) keeps the hash the note's own. A summary may
 * leave a table out. `restore` with `final` is the tidy-up of the whole
 * answer once it has finished; without, the text so far, for the lines as
 * they land.
 */
export function prepareNote(body: string, mode: Mode): { prompt: string; restore: (text: string, final: boolean) => string } {
  const { text: withoutTables, tables } = protectTables(cleanNote(body));
  const { text: prompt, links } = protectLinks(withoutTables);
  const put = (text: string, final: boolean) => restoreTables(restoreLinks(text, links, final), tables, final, mode !== 'summarize');
  return {
    prompt,
    restore: (text, final) => (final ? tidy(cleanRewrite(put(tidy(text), true))) : put(text, false)),
  };
}
