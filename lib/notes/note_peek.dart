import 'package:flutter/widgets.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';
import '../editor/markdown_view.dart';

/// What draws a note small under its name on a row or a card: null for a note with nothing to draw. The drawing
/// alone: whoever lists the note keeps the room over it (the page's `.peek` has `var(--glacier-space-2)`, which a
/// sidebar row's `.rowPeek` makes `var(--glacier-space-1)`).
typedef NotePeekBuilder = Widget? Function(BuildContext context, String body);

/// The words of a note after its title, on one run: the lines [peekMarkdown] hands the small drawing, with what only
/// marks a line taken off its start (a heading's hashes, a list's bullet or number, a to-do's box) and the fences of
/// a block of code left out. What a row says of its note where there is no room to draw it, and to a search.
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

/// A note under its name, small: the card's description in the sidebar. Ports `src/app/notes/NotePeek.tsx` with the
/// box `NotePeek.module.css` gives it (`.peek`).
///
/// As on the web it is the note itself: its first lines after its title in the editor's own lines, formatted,
/// at the card's scale and in the third ink, clipped to six lines and a little with the last fading where the note
/// runs on ([MarkdownView], lib/editor/markdown_view.dart). It was two plain lines of the note's words until the
/// editor's view was ported.
///
/// What differs: the web builds a card's editor as it comes near the screen, one at a time, and keeps what it drew
/// as HTML, because an editor costs it 25 to 30 ms; a card's lines cost well under a millisecond here and are simply
/// drawn. `whole`, `look` and `openHeading` are a template's card's, which draws through [MarkdownView] itself. A
/// tag, a person and a heading's count are drawn by the home page's preview (lib/home/note_peek.dart) with
/// stand-ins of its own until the editor's pieces for them are ported; here they are the words they are.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body});

  final String body;

  /// The default [NotePeekBuilder]: this widget, or null where there is nothing after the title.
  static Widget? plain(BuildContext context, String body) => isCanvasBody(body) || peekMarkdown(body).isEmpty ? null : NotePeek(body: body);

  @override
  Widget build(BuildContext context) {
    // A canvas note is JSON, not words: its card shows nothing small until a canvas can be drawn small.
    final markdown = isCanvasBody(body) ? '' : peekMarkdown(body);
    if (markdown.isEmpty) return const SizedBox.shrink();
    return MarkdownView(markdown: markdown);
  }
}
