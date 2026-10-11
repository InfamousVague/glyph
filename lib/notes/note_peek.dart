import 'package:flutter/widgets.dart';

import '../core/note_text.dart';

export '../home/note_peek.dart' show NotePeek;

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

/// A note under its name, small: the card's description in the sidebar is the home page's preview
/// (lib/home/note_peek.dart, `src/app/notes/NotePeek.tsx`, which is one component on the page too): the note itself,
/// its first lines after its title in the editor's own lines with the items the editor draws in them. It was two
/// plain lines of the note's words until the editor's view was ported, and a second widget until 2026-10-09.
/// [NotePeek.plain] is the default [NotePeekBuilder].
