import { withProperty } from '../properties.ts';
import { withField } from '../taskFields.ts';
import type { RecordKind } from './records.ts';

/**
 * A card dragged into another lane of a query's board, in a note that is not the one on screen (editor/queries.ts; the
 * open note's own are written in its editor). The grouped field is set to the lane's value, or cleared with null for
 * the "No …" lane: a ticket's or a record's front-matter property (core/properties.ts `withProperty`), a to-do's inline
 * field (core/taskFields.ts `withField`).
 *
 * The to-do's line is found where the query read it, or, where the note has moved since, by its words as the query read
 * them; a line that is gone is left alone (null), rather than the wrong one written. A write that changes nothing gives
 * the body back unchanged. Pure.
 */
export function movedBody(body: string, line: number, source: string, kind: RecordKind, field: string, value: string | null): string | null {
  if (kind === 'task') {
    const lines = body.split('\n');
    const at = lines[line] === source ? line : lines.indexOf(source);
    const text = lines[at];
    if (at < 0 || text === undefined) return null;
    const next = withField(text, field, value);
    if (next === text) return body;
    lines[at] = next;
    return lines.join('\n');
  }
  return withProperty(body, field, value);
}
