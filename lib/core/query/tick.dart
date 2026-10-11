/// A to-do ticked from a query, in a note that is not the one on screen (the open note's own are ticked in its
/// editor). A port of `src/app/core/query/tick.ts`. The same change a tap on its box makes there: the box turned,
/// and every board in that note brought into step with it, the card into Done or back out of it, in the one write
/// (boards.dart `settleTicks`), so a board never drifts from a tick made somewhere else.
///
/// The line is found where the query read it, or, where the note has moved since, by its words as the query read
/// them; a line that is gone, or is no longer a to-do, is left alone (null), rather than the wrong line ticked. Pure.
library;

import '../boards/items.dart' show setItemDone;
import '../boards/settle.dart' show settleTicks;
import '../item_syntax.dart' show taskBox;

String? tickedBody(String body, int line, String source, bool done) {
  final lines = body.split('\n');
  final at = line >= 0 && line < lines.length && lines[line] == source ? line : lines.indexOf(source);
  if (at < 0) return null;
  final text = lines[at];
  final box = taskBox(text);
  if (box == null) return null;
  if (box.done == done) return body;
  final settled = settleTicks(body, {at + 1: done});
  lines[at] = setItemDone(text, done);
  // The anchors first, on lines outside every fence, which a fence's new body can then not move.
  for (final joined in settled.lines) {
    lines[joined.number - 1] = '${lines[joined.number - 1]} ^${joined.anchor}';
  }
  // Each fence's lines from the last up, so the line numbers of the ones above still hold.
  for (final fence in [...settled.fences]..sort((a, b) => b.from - a.from)) {
    final start = fence.from > lines.length ? lines.length : fence.from;
    final count = fence.to - fence.from - 1;
    final end = start + (count < 0 ? 0 : count);
    lines.replaceRange(start, end > lines.length ? lines.length : end, fence.body.split('\n'));
  }
  return lines.join('\n');
}
