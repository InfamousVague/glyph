import { summaryOf } from '../../src/read/meeting.ts';
import { isOn } from './frontMatter.ts';

/**
 * A meeting note's transcript as the note keeps it (lib/tapes/transcript_words.dart `writtenTranscript`,
 * lib/meet/speakers.dart `captionsSection`): the paragraphs under `## Transcript` (or `## Captions`), each a turn,
 * `**Sam Lee (0:04):** words` where it is timed, `**Sam Lee:** words` where it is named and not timed, `(0:04) words`
 * where it is timed and nobody's, and plain words otherwise. A share carries the same turns as JSON (read/meeting.ts);
 * a repository carries only the words, so this reads them back out, and the page draws Summary | Transcript as the
 * share page does (MeetingRead.tsx), without the cassette unless the tape is in the repository.
 */

export interface WrittenTurn {
  speaker: string | null;
  /** The turn's start as written, "0:04"; null for one with no time. */
  at: string | null;
  text: string;
}

export interface Transcript {
  turns: WrittenTurn[];
  speakers: string[];
  /** The note's words without the transcript and its title (read/meeting.ts `summaryOf`). */
  summary: (title: string) => string;
}

const TIMED = /^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\*\s*([\s\S]*)$/;
const BARE = /^\((\d+(?::\d{2}){1,2})\)\s*([\s\S]*)$/;
const NAMED = /^\*\*([^*\n]+?):\*\*\s*([\s\S]*)$/;

/** The paragraphs under the heading, up to the next heading as high or higher; null for no such heading. */
function paragraphsUnder(body: string, heading: string): string[] | null {
  const lines = body.split('\n');
  const at = lines.findIndex((line) => line.trim() === heading);
  if (at < 0) return null;
  const out: string[] = [];
  let current: string[] = [];
  const flush = () => {
    if (current.length) out.push(current.join('\n').trim());
    current = [];
  };
  for (const line of lines.slice(at + 1)) {
    if (/^#{1,2}\s/.test(line)) break;
    if (line.trim() === '') flush();
    else current.push(line);
  }
  flush();
  return out.filter((p) => p !== '');
}

/** One paragraph as a turn. */
export function turnOf(paragraph: string): WrittenTurn {
  const timed = TIMED.exec(paragraph);
  if (timed) return { speaker: timed[1]!.trim(), at: timed[2]!, text: timed[3]!.trim() };
  const bare = BARE.exec(paragraph);
  if (bare) return { speaker: null, at: bare[1]!, text: bare[2]!.trim() };
  const named = NAMED.exec(paragraph);
  if (named) return { speaker: named[1]!.trim(), at: null, text: named[2]!.trim() };
  return { speaker: null, at: null, text: paragraph.trim() };
}

/**
 * The transcript of a note that is a meeting: one with `meeting: true` in its front matter (slice 2 of the plan), or
 * one whose words keep a `## Transcript` or `## Captions` section. Null for a note that is neither.
 */
export function transcriptOf(body: string, page: Record<string, string>): Transcript | null {
  const paragraphs = paragraphsUnder(body, '## Transcript') ?? paragraphsUnder(body, '## Captions');
  if (paragraphs === null && !isOn(page.meeting)) return null;
  const turns = (paragraphs ?? []).map(turnOf);
  const speakers = [...new Set(turns.map((turn) => turn.speaker).filter((name): name is string => name !== null))];
  return { turns, speakers, summary: (title) => summaryOf(body, title) };
}
