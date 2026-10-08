/// What a recording left in a note that already existed, handed to the note as it opens after Done: which note, the
/// pieces of text put in (for its Undo to find and take out), and the other notes it wrote to or made. A port of
/// `src/app/capture/landing.ts`.
///
/// The Undo is an edit in the editor: the note's own saving writes it like typing, and the editor's own undo can
/// bring it back. The recording's sound and phrases stay as they are, as they would if the words were deleted by
/// hand, so the next recording still lines up with its sound. Pure, so each rule is a test.
///
/// What differs: `takeOut` answers a record, and each change is a record, where the web answers object literals.
library;

/// What a recording left behind it, for the note that opens.
class CaptureLanding {
  const CaptureLanding({
    required this.noteId,
    required this.title,
    required this.blocks,
    required this.others,
    this.into,
    required this.made,
    this.fromMs,
    this.tookBack,
  });

  /// The note that opens.
  final String noteId;
  final String title;

  /// The pieces of text put in it, each exactly as written.
  final List<String> blocks;

  /// Writes to other notes (a one-shot "add … to X"), by their `apply_command` mutation ids, for Undo to reverse.
  final List<String> others;

  /// Those other notes' titles, for the toast to name.
  final List<String>? into;

  /// Notes the recording made, to be filed in the workspace the list is showing.
  final List<String> made;

  /// Where the recording starts on the note's tape, for Undo to drop its better words (capture/refine.dart).
  final int? fromMs;

  /// What the recording took back at Done, unseen: for the toast to name, since its Undo could not be tapped.
  final List<String>? tookBack;

  /// The web's spread: this landing with some of it said again. A list left out stays as it is.
  CaptureLanding copyWith({
    String? noteId,
    String? title,
    List<String>? blocks,
    List<String>? others,
    List<String>? into,
    List<String>? made,
    int? fromMs,
    List<String>? tookBack,
  }) =>
      CaptureLanding(
        noteId: noteId ?? this.noteId,
        title: title ?? this.title,
        blocks: blocks ?? this.blocks,
        others: others ?? this.others,
        into: into ?? this.into,
        made: made ?? this.made,
        fromMs: fromMs ?? this.fromMs,
        tookBack: tookBack ?? this.tookBack,
      );
}

/// What the note's toast says: the note the words went into, and the others; or, for a note of the take's own, the
/// others. And what a take-back settled at Done took out, so nothing goes unsaid.
String landingLine(CaptureLanding landing) {
  final title = landing.title;
  final blocks = landing.blocks;
  final others = landing.others;
  final tookBack = landing.tookBack ?? const <String>[];
  final names = <String>{...?landing.into}.toList();
  final String added;
  if (blocks.isEmpty && names.isNotEmpty) {
    added = 'Added to ${names.length > 2 ? '${names.sublist(0, 2).join(', ')} and ${names.length - 2} more' : names.join(' and ')}';
  } else if (others.isEmpty) {
    added = 'Added to $title';
  } else {
    added = 'Added to $title and ${others.length == 1 ? (names.isNotEmpty ? names[0] : 'one other note') : '${others.length} other notes'}';
  }
  if (tookBack.isEmpty) return added;
  return '$added. Took back “${tookBack[0]}”${tookBack.length > 1 ? ' and ${tookBack.length - 1} more' : ''}';
}

final RegExp _itemLead = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s');

/// The edits that take [blocks] out of [doc]: each found exactly, once, nearest the line it went in at, with the
/// line break that joined it to the text above. A block that is no longer there as written - edited, or gone - is
/// left alone and counted in `missing`.
({List<({int from, int to})> changes, int missing}) takeOut(String doc, List<String> blocks) {
  final changes = <({int from, int to})>[];
  var missing = 0;
  for (final block in blocks) {
    if (block.isEmpty) continue;
    final found = <int>[];
    for (var at = doc.indexOf(block); at >= 0; at = at + 1 > doc.length ? -1 : doc.indexOf(block, at + 1)) {
      // A whole line or lines: starting at a line's start and ending at one's end.
      final starts = at == 0 || doc[at - 1] == '\n';
      final ends = at + block.length == doc.length || doc[at + block.length] == '\n';
      if (starts && ends) found.add(at);
    }
    if (found.length != 1) {
      missing += 1;
      continue;
    }
    final at = found[0];
    // With the break before it, or, for a block that opens the note, the one after it; a paragraph's blank line too.
    var from = at;
    var to = at + block.length;
    if (at > 0) {
      from = at - 1;
      if (block.contains('\n') || !_itemLead.hasMatch(block)) {
        while (from > 0 && doc[from - 1] == '\n') {
          from -= 1;
        }
      }
    } else if (to < doc.length && doc[to] == '\n') {
      to += 1;
    }
    if (changes.any((change) => from < change.to && to > change.from)) {
      missing += 1;
      continue;
    }
    changes.add((from: from, to: to));
  }
  changes.sort((a, b) => a.from - b.from);
  return (changes: changes, missing: missing);
}
