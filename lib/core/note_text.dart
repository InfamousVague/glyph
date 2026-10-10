/// What a note's Markdown body says about it, for a list to show: its title, how it is matched by a search, the lines
/// its card draws small, and the small things done to its words on the way. Ports, under the web's own names:
///
/// - `core/noteTitle.ts`: [withoutFrontMatter], [noteTitle];
/// - `core/comments/format.ts`: [withoutAnchors];
/// - `notes/allNotes.ts`: [hasTape], [matches];
/// - `notes/peek.ts`: [peekMarkdown].
///
/// And, for the files written before the grammars had ports of their own, the names this file used to hold copies
/// of, passed on from where they now live:
///
/// - blanks_syntax.dart (`core/blanks.ts`): [plainFills], [asksForTitle], [titleWords];
/// - item_syntax.dart (`core/itemSyntax.ts`): [ListLead], [listLead], [taskBox], [anchorSpan], [withoutAnchor], and
///   its `markerPattern` and `boxPattern` under the names they had here, [listMarker] and [taskBoxPattern];
/// - title_key.dart (`core/titleKey.ts`): [titleKey], [sameTitle];
/// - short_url.dart (`core/shortUrl.ts`): [shortUrl], [shortenUrls].
///
/// What differs: nothing in the rules. [matches] names a to-do's priority through task_fields.dart's `fieldsIn`, as
/// the web does, so a sign inside code or a redaction is no priority here either.
library;

import 'blanks_syntax.dart';
import 'front_matter.dart';
import 'item_syntax.dart';
import 'note.dart';
import 'task_fields.dart';

export 'blanks_syntax.dart' show asksForTitle, plainFills, titleWords;
export 'item_syntax.dart' show ListLead, anchorSpan, listLead, taskBox, withoutAnchor;
export 'short_url.dart' show shortUrl, shortenUrls;
export 'title_key.dart' show sameTitle, titleKey;

// ---- comments (core/comments/format.ts) ---------------------------------------------------------------------------

final RegExp _commentAnchor = RegExp(r'\[\^(c[0-9a-z]+)\]');

/// The note with its comment anchors taken out, for a label.
String withoutAnchors(String text) => text.contains('[^') ? text.replaceAll(_commentAnchor, '') : text;

// ---- a list item's lead, under the names this file gave it (core/itemSyntax.ts) ------------------------------------

/// What opens a list item: a bullet or a number (`MARKER`); item_syntax.dart's `markerPattern`.
const String listMarker = markerPattern;

/// A to-do's box standing as a word (`BOX`); item_syntax.dart's `boxPattern`.
const String taskBoxPattern = boxPattern;

// ---- the title (core/noteTitle.ts) --------------------------------------------------------------------------------

/// The bookmark and the whitespace either side of it, which a title reads as one space.
final RegExp _bookmarkInTitle = RegExp(r'\s*§§\s*');
final RegExp _titleKey = RegExp(r'^\s*title\s*:', caseSensitive: false);
final RegExp _titleLead = RegExp(r'^\s*title\s*:\s*', caseSensitive: false);
final RegExp _titleQuotes = RegExp('''^['"]|['"]\$''');
final RegExp _imageOnly = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');
final RegExp _headingLead = RegExp(r'^#{1,6}\s+');

/// A front matter line that names the note, `title: "Flat"`, as the list reads it: the words after the colon, a
/// quote off each end.
String _named(String line) => line.replaceFirst(_titleLead, '').replaceAll(_titleQuotes, '').trim();

/// A note's lines with its front matter taken off, and its `title:` first where it has one.
List<String> withoutFrontMatter(List<String> lines) {
  final end = frontMatterEnd(lines);
  if (end == 0) return [...lines];
  String? named;
  for (final key in lines.sublist(1, end - 1)) {
    if (_titleKey.hasMatch(key)) {
      named = key;
      break;
    }
  }
  final title = named == null ? '' : _named(named);
  return title.isNotEmpty ? [title, ...lines.sublist(end)] : lines.sublist(end);
}

/// The line a note is titled by, found where it lies and with nothing else of the body read: its front matter's
/// `title:` where that says anything, else the first line after the front matter that is words, not a picture.
/// What [withoutFrontMatter] and the loop over its lines answered, without the lines. [span] is the body's
/// [frontMatterSpan], for a caller that has it.
String noteTitleLine(String body, [FrontMatterSpan? span]) {
  final front = span ?? frontMatterSpan(body);
  if (!front.isEmpty) {
    var from = body.indexOf('\n') + 1;
    while (from < front.closing) {
      final to = body.indexOf('\n', from);
      // `^\s*title\s*:` opens with spaces or a T: a line that opens with neither is not asked.
      var at = from;
      while (at < to && body.codeUnitAt(at) <= 0x20) {
        at += 1;
      }
      final first = at < to ? body.codeUnitAt(at) : 0;
      if (first == 0x74 || first == 0x54 || first >= 0x80) {
        final line = body.substring(from, to);
        if (_titleKey.hasMatch(line)) {
          final title = _named(line);
          if (title.isNotEmpty && !_imageOnly.hasMatch(title)) return title;
          break;
        }
      }
      from = to + 1;
    }
  }
  final length = body.length;
  var from = front.offset;
  while (true) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? length : next;
    if (!blankIn(body, from, to)) {
      final line = body.substring(from, to);
      // A picture alone on its line opens with its `!`.
      if (line.codeUnitAt(0) != 0x21 || !_imageOnly.hasMatch(line)) return line;
    }
    if (next < 0) return '';
    from = next + 1;
  }
}

/// A title's line as the title: a blank's question or its answer for the blank, its anchors and its heading's
/// hashes off, the bookmark a space.
String _titleOf(String line) {
  var text = withoutAnchors(titleWords(line));
  if (text.startsWith('#')) text = text.replaceFirst(_headingLead, '');
  if (text.contains('§§')) text = text.replaceAll(_bookmarkInTitle, ' ');
  return text.trim();
}

/// The first line of a note, which is the only title Ghost.md has.
///
/// The first line that is words, not a picture: a note that opens with a photo is titled by what is said under it.
/// A list asks this of a note through `NoteFacts.of(note).title` (note_facts.dart), which keeps the answer.
String noteTitle(String body) => _titleOf(noteTitleLine(body));

/// [noteTitle] for a body whose front matter has been found already.
String noteTitleIn(String body, FrontMatterSpan span) => _titleOf(noteTitleLine(body, span));

// ---- search (notes/allNotes.ts) -----------------------------------------------------------------------------------

/// Whether a note has a recording on it, whatever made it.
bool hasTape(Note note) => (note.recordingMs ?? 0) > 0;

final RegExp _spaces = RegExp(r'\s+');

/// A priority's sign (task_fields.dart): a note with none has no priority to name.
final RegExp _prioritySign = RegExp('🔺|⏫|🔼|🔽|⏬', unicode: true);

/// What a note's to-dos' priorities say in words, for a search to find (task_fields.dart, docs/DESIGN.md §158):
/// "high priority" for a ⏫, as its chip says it, since nobody types the sign into a search. A person and a day are
/// found as they are written, `sam` and `2026-10-03`.
String _priorityWords(String body) {
  if (!_prioritySign.hasMatch(body)) return '';
  return fieldsIn(body).where((span) => span.kind == FieldKind.priority).map((span) => '${span.value} priority').join(' ');
}

/// What a search looks through for each note, by the note's id, for the body it was read from.
final Map<String, ({String body, String text})> _searched = <String, ({String body, String text})>{};

/// What a search reads of [note]: its words with a filled blank's hidden bracket taken out (blanks_syntax.dart:
/// "memory" or "Asked" finds no note), then its to-dos' priorities in words, all in lower case. The page makes it
/// for every note at every letter typed, which is every letter of the library copied three times a keystroke; here
/// it is read once for the body the note has now, and kept: at most one reading for each note there is (and where
/// the library hands back the same words in a new string, the reading takes the new string and lets the old go).
/// The home page's search and All notes' both look through it ([matches], [hasWords]).
String searchText(Note note) {
  final body = note.body;
  final had = _searched[note.id];
  if (had != null) {
    if (identical(had.body, body)) return had.text;
    if (had.body == body) {
      _searched[note.id] = (body: body, text: had.text);
      return had.text;
    }
  }
  if (_searched.length >= 32768) _searched.clear();
  final text = '${plainFills(body)} ${_priorityWords(body)}'.toLowerCase();
  _searched[note.id] = (body: body, text: text);
  return text;
}

/// The words of a query as a search reads them: lower case, split at any run of white space. None for a blank one.
List<String> queryWords(String query) => query.isEmpty ? const <String>[] : query.toLowerCase().split(_spaces).where((word) => word.isNotEmpty).toList();

/// Whether a note has every one of [words] ([queryWords]); none asked for is every note, with nothing of it read.
bool hasWords(Note note, List<String> words) => words.isEmpty || words.every(searchText(note).contains);

/// Whether a note has every word of the query, in its title or its body, whatever the case. Words rather than the
/// whole phrase, so "trip packing" finds a note with those two words anywhere in it.
bool matches(Note note, String query) => hasWords(note, queryWords(query));

// ---- a note drawn small (notes/peek.ts) ---------------------------------------------------------------------------

/// How many lines are worth drawing (`PEEK_LINES`).
const int peekLines = 6;

/// How many lines of the note the card's drawing is given (`PEEK_SOURCE_LINES`).
const int peekSourceLines = 14;

final RegExp _fenced = RegExp(r'^\s*(```|~~~)\s*(\w*)');

/// The note after its title, as Markdown, for the card to draw as the note draws it. Front matter and the title go;
/// up to [most] lines follow, and a block of code opened inside them is kept to its closing fence. A board's fence is
/// left out altogether, the blank lines around the cut close up to one, and an item's anchor goes.
String peekMarkdown(String body, [int most = peekSourceLines]) {
  final lines = withoutFrontMatter(body.split('\n'));
  final title = lines.indexWhere((l) => l.trim().isNotEmpty && !_imageOnly.hasMatch(l));
  final out = <String>[];
  String? fence;
  var board = false;
  var fenceLines = 0;
  for (var n = title + 1; n < lines.length; n += 1) {
    final line = lines[n];
    final fenced = _fenced.firstMatch(line);
    if (fence != null) {
      if (!board) out.add(line);
      fenceLines += 1;
      if (fenced != null && line.trim().startsWith(fence)) {
        fence = null;
        board = false;
      }
      // A fence that never closes still ends somewhere.
      if (fenceLines >= most * 3) break;
      continue;
    }
    if (out.length >= most) break;
    // A blank line before anything is drawn, or after another, is nothing to draw.
    if (line.trim().isEmpty && (out.isEmpty || out.last.trim().isEmpty)) continue;
    if (fenced != null) {
      fence = fenced.group(1)!;
      fenceLines = 0;
      board = fenced.group(2)?.toLowerCase() == 'board';
      if (board) continue;
    }
    out.add(withoutAnchor(line));
  }
  return out.join('\n').replaceFirst(_trailingSpaces, '');
}

final RegExp _trailingSpaces = RegExp(r'\s+$');

// ---- how a note starts (home/homeLayout.ts) ------------------------------------------------------------------------

final RegExp _lineLead = RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|\d+[.)]\s+)');
final RegExp _stars = RegExp(r'\*\*|__|`');

/// How a note starts, on one line, after its name: its first line of words that is not its title, the marks that
/// start a line and the stars around words taken off. Empty for a note with nothing under its name
/// (`home/homeLayout.ts` `firstLine`; lib/home/home_layout.dart hands it on). Read a line at a time from where the
/// front matter ends, and no further than the line it answers with.
String firstLine(String body, [int most = 120]) {
  final span = frontMatterSpan(body);
  final title = noteTitleIn(body, span).trim();
  var titleSeen = false;
  final length = body.length;
  var from = span.offset;
  while (true) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? length : next;
    if (!blankIn(body, from, to)) {
      final line = body.substring(from, to).replaceFirst(_lineLead, '').replaceAll(_stars, '').trim();
      if (line.isNotEmpty) {
        if (!titleSeen && line == title) {
          titleSeen = true;
        } else {
          return line.length > most ? '${line.substring(0, most - 1).trimRight()}…' : line;
        }
      }
    }
    if (next < 0) return '';
    from = next + 1;
  }
}
