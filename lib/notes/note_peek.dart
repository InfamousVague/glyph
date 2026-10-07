import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';

/// What draws a note small under its name on a row or a card: null for a note with nothing to draw. The drawing
/// alone: whoever lists the note keeps the room over it (the page's `.peek` has `var(--glacier-space-2)`, which a
/// sidebar row's `.rowPeek` makes `var(--glacier-space-1)`).
typedef NotePeekBuilder = Widget? Function(BuildContext context, String body);

/// The words of a note after its title, on one run: what [NotePeek] sets while the note cannot be drawn. The lines
/// [peekMarkdown] would hand the page's small editor, with what only marks a line taken off its start (a heading's
/// hashes, a list's bullet or number, a to-do's box) and the fences of a block of code left out.
String peekWords(String body) {
  final words = <String>[];
  for (final line in peekMarkdown(body).split('\n')) {
    var text = line.trim();
    if (text.isEmpty || RegExp(r'^(```|~~~)').hasMatch(text)) continue;
    final lead = listLead(text);
    if (lead != null) {
      text = text.substring(lead.wordsAt).trim();
    } else {
      text = text.replaceFirst(RegExp(r'^(#{1,6}|>)\s+'), '');
    }
    if (text.isNotEmpty) words.add(plainFills(text));
  }
  return words.join(' ');
}

/// A note under its name, small: the card's description in the sidebar and on the home page. Stands where the web's
/// `src/app/notes/NotePeek.tsx` stands, with the box `NotePeek.module.css` gives it (`.peek`), and is NOT that
/// component yet.
///
/// The web draws the note itself: its first lines in the note's own editor (`editor/Editor.tsx`, read-only, in its
/// `peek` mode), so a to-do's box is the note's box and a table a table, built one card at a time as each comes near
/// the screen and kept as HTML afterwards. That editor and the Markdown it draws are a later stage of this port
/// (stage 4), and none of it is here: no formatted lines, no headings at the card's scale, no fade where the note
/// runs on (`data-clipped`), no building near the screen, and no `whole`, `look`, `openHeading` or `eager` for a
/// template's card.
///
/// What is here is the seam and a plain stand-in: [peekWords] on at most two lines, in the note's own face at the
/// size and in the ink the page's peek starts from (`font-size: var(--app-body)` at `--peek-scale`, 1.6 to a line,
/// `--app-ink-3`). A note with nothing after its title, and a canvas, draw nothing, as there. Whatever lists notes
/// takes a [NotePeekBuilder], so the drawn note replaces this in one place when it exists.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body});

  final String body;

  /// The default [NotePeekBuilder]: this widget, or null where there is nothing after the title.
  static Widget? plain(BuildContext context, String body) => isCanvasBody(body) || peekWords(body).isEmpty ? null : NotePeek(body: body);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // A canvas note is JSON, not words: its card shows nothing small until a canvas can be drawn small.
    final words = isCanvasBody(body) ? '' : peekWords(body);
    if (words.isEmpty) return const SizedBox.shrink();
    // `--peek-scale: calc(0.62 * var(--app-text-scale)); --app-body: calc(var(--glacier-font-size-lg) * var(--peek-scale));
    // font-size: var(--app-body)`
    final size = t.lenOf('calc(var(--glacier-font-size-lg) * 0.62 * var(--app-text-scale))');
    final faces = t.families('app-note-font');
    // It says nothing to a screen reader (`aria-hidden`): the row already has its name.
    return ExcludeSemantics(
      child: Text(
        words,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        // `color: var(--app-ink-3)`, and the editor's 1.6 to a line.
        style: t.textAt(size, color: t.color('app-ink-3'), height: 1.6).copyWith(
              fontFamily: faces.isEmpty ? null : faces.first,
              fontFamilyFallback: faces.length > 1 ? faces.sublist(1) : null,
              fontFeatures: const [],
              fontVariations: const [],
            ),
      ),
    );
  }
}
