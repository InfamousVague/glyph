import { placeOfLine } from '../core/placeRefs.ts';
import { videoOfLine } from '../core/videoRefs.ts';

/**
 * Places and videos through the model, kept by construction, as tables are (tables.ts).
 *
 * A place line is a link to a `geo:` address (core/placeRefs.ts), and a video line a picture linked to its film
 * (docs/DESIGN.md §141). A small model rewriting a note would read either as words: a place's coordinates are
 * exactly what it might round or move, links.ts masks only web addresses, and a model told nothing of them may describe
 * one or drop it. So before the note goes in, each such line, whole, lead and all, is swapped for a picture-shaped
 * token line the model copies, `![place-1](place)` or `![video-1](video)`, and after the rewrite each is swapped back,
 * verbatim. The token is a picture's shape for the reason the table's is: measured with the 4B, a picture line is kept
 * every time. The prompts are told what the tokens are (format/prompt.ts, ai/prompts.ts).
 *
 * A token that does not come back is added at the end of the note, for the modes that keep everything; a summary may
 * leave a place out.
 */

export interface ProtectedEmbed {
  /** `place-2` or `video-1`: what stands in for the line while the model works. */
  token: string;
  /** The line, exactly as written. */
  line: string;
}

/** A line that opens or closes fenced code. */
const FENCE = /^\s*(```|~~~)/;

/** The note with every place and video line replaced by a token line, and the lines to put back. */
export function protectEmbeds(body: string): { text: string; embeds: ProtectedEmbed[] } {
  const embeds: ProtectedEmbed[] = [];
  const counts = { place: 0, video: 0 };
  let fence: string | null = null;
  const lines = body.split('\n').map((line) => {
    const marker = FENCE.exec(line)?.[1];
    if (marker) fence = fence === null ? marker : fence === marker ? null : fence;
    if (fence || marker) return line;
    const kind = placeOfLine(line) ? 'place' : videoOfLine(line) ? 'video' : null;
    if (!kind) return line;
    counts[kind] += 1;
    const token = `${kind}-${counts[kind]}`;
    embeds.push({ token, line });
    return `![${token}](${kind})`;
  });
  return { text: lines.join('\n'), embeds };
}

/**
 * The rewrite with its places and videos back: a line that is a token, however the model wrote it (`![place-1](place)`,
 * `[place-1]`, `place 1`), becomes the line; a token buried in a sentence gets its line on a line of its own. With
 * `final` and `appendMissing`, a line whose token never came back is added at the end; a partial rewrite still
 * streaming is only substituted.
 */
export function restoreEmbeds(text: string, embeds: readonly ProtectedEmbed[], final = true, appendMissing = true): string {
  // Each line put back is held as a mark until every token is read, so a place named "Market place 2" is never taken
  // for the second place's token once it is back.
  const held = (index: number) => `${index}`;
  let out = text;
  const missing: ProtectedEmbed[] = [];
  embeds.forEach((embed, index) => {
    const [kind = '', number = ''] = embed.token.split('-');
    // Spaces and tabs only, never `\s`: that would swallow the line's newline.
    const token = `!?[[<(]?[ \\t]*${kind}[ \\t-]?${number}(?!\\d)[ \\t]*[\\]>)]?(?:\\([ \\t]*${kind}[ \\t]*\\))?`;
    let found = false;
    out = out.replace(new RegExp(`^[ \\t]*${token}[ \\t]*$`, 'gim'), () => {
      found = true;
      return held(index);
    });
    out = out.replace(new RegExp(token, 'gi'), () => {
      found = true;
      return `\n\n${held(index)}\n\n`;
    });
    if (!found) missing.push(embed);
  });
  out = out.replace(/(\d+)/g, (_whole, index: string) => embeds[Number(index)]?.line ?? '');
  if (!final || !appendMissing || !missing.length) return out;
  return `${out.replace(/\s+$/, '')}\n\n${missing.map((embed) => embed.line).join('\n\n')}\n`;
}
