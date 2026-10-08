/// A list item's grammar, read here and nowhere else: what opens an item, the boxes it may carry, and what may end
/// its line after its words. A port of `src/app/core/itemSyntax.ts`, one to one.
///
///     - [ ] Ship the pricing page §§ [notion](https://…) [3/8] ^ship-page
///
///     `-`             the marker: `-`, `*` or `+`, or a number with `.` or `)`
///     `[ ]`           a to-do's box, `[ ]`, `[x]` or `[X]`; or, after a bullet, a choice's `( )`
///     `§§`            the bookmark, where the reader left off
///     `[notion](…)`   the mark: what the item is linked to
///     `[3/8]`         a counter
///     `^ship-page`    the anchor: the item's name, which a board points at
///
/// The atoms are regex sources with no groups of their own, so they compose into a larger pattern without
/// renumbering it; the patterns and helpers built from them are the questions the call sites actually ask.
///
/// What differs: the names. The web's upper-case constants are `bulletPattern`, `numberPattern`, `markerPattern`,
/// `boxPattern`, `choicePattern`, `anchorNamePattern`, `anchorPattern`, `markNamePattern`, `markUrlPattern`,
/// `markPattern`, `counterPattern`, `counterInWordsPattern`, `bookmarkSigns`, `bookmarkPattern`, `itemTailPattern`
/// and `afterMark` here; `taskBox` and `anchorSpan` answer records where the web answers object literals.
library;

// ---- the atoms ----------------------------------------------------------------------------------------------------

/// A bullet: `-`, `*` or `+` (`BULLET`).
const String bulletPattern = '[-*+]';

/// A numbered item's number and its `.` or `)`: `1.`, `12)` (`NUMBER`).
const String numberPattern = r'\d+[.)]';

/// What opens a list item: a bullet or a number (`MARKER`).
const String markerPattern = '(?:$bulletPattern|$numberPattern)';

/// A to-do's box: `[ ]`, `[x]` or `[X]`, standing as a word - whitespace or the end of the line after it (`BOX`).
/// That is the box the editor draws, so `- [x](https://…)` stays a link whose words are "x", and `- [ ]foo` stays
/// words: neither has a box to tick.
const String boxPattern = r'\[[ xX]\](?=\s|$)';

/// A choice's round box, `( )` or `(x)`, standing as a word (`CHOICE`). Only a bullet takes one.
const String choicePattern = r'\([ xX]\)(?=\s|$)';

/// An anchor's name: lower case, the shape a person can type and read (`ANCHOR_NAME`).
const String anchorNamePattern = '[a-z0-9][a-z0-9_-]*';

/// The anchor as written: a caret, then its name (`ANCHOR`).
const String anchorPattern = '\\^$anchorNamePattern';

/// A mark's name: the lowercase id of what the item is linked to, `notion` or `github` (`MARK_NAME`).
const String markNamePattern = '[a-z][a-z0-9-]*';

/// A mark's address (`MARK_URL`).
const String markUrlPattern = r'https?:\/\/[^\s)]+';

/// An item's mark: a link whose words are one lowercase name, `[notion](https://…)` (`MARK`).
const String markPattern = '\\[$markNamePattern\\]\\($markUrlPattern\\)';

/// A counter: a count and a goal, up to four digits each, `[3/8]` (`COUNTER`).
const String counterPattern = r'\[\d{1,4}\/\d{1,4}\]';

/// A counter standing in words: not a link's words `[3/8](…)`, a picture's `![3/8]`, or a footnote's
/// (`COUNTER_IN_WORDS`).
const String counterInWordsPattern = '(?<![!\\]\\w])$counterPattern(?!\\()';

/// The bookmark's two signs, as they are written into a line (`BOOKMARK_SIGNS`).
const String bookmarkSigns = '§§';

/// The bookmark standing as a word: its two signs with whitespace or the end of the line after them (`BOOKMARK`).
const String bookmarkPattern = '$bookmarkSigns(?=\\s|\$)';

/// What may follow an item's mark at the end of its line: a board's anchor and counters, in any order (`ITEM_TAIL`).
/// An alternation, so it goes inside a group.
const String itemTailPattern = '$anchorPattern|$counterPattern';

// ---- what opens an item -------------------------------------------------------------------------------------------

/// The indent, the marker and the spaces after it. Groups: the indent, the marker.
final RegExp _open = RegExp('^(\\s*)($markerPattern)\\s+');

/// A to-do's box where an item's words would start, and at most one space after it.
final RegExp _boxFirst = RegExp('^$boxPattern\\s?');

/// A choice's box where a bullet's words would start, and at most one space after it.
final RegExp _choiceFirst = RegExp('^$choicePattern\\s?');
final RegExp _isBullet = RegExp('^$bulletPattern\$');

/// The opening of a list item, pulled apart (`ListLead`).
class ListLead {
  const ListLead({required this.indent, required this.marker, required this.done, required this.picked, required this.boxAt, required this.wordsAt});

  /// The whitespace before the marker.
  final String indent;

  /// The marker as written: `-`, `*`, `+`, `1.`, `2)`.
  final String marker;

  /// A to-do's box, ticked or not; null for an item with none - a bullet, a numbered step or a choice.
  final bool? done;

  /// A choice's round box, picked or not; null for an item with none.
  final bool? picked;

  /// Where the box or the choice opens in the line, its `[` or `(`; -1 when there is neither.
  final int boxAt;

  /// Where the item's words start: past the marker, the box or the choice, and the one space after it.
  final int wordsAt;
}

/// A line's list lead, or null when the line is not a list item.
ListLead? listLead(String line) {
  final open = _open.firstMatch(line);
  if (open == null) return null;
  final marker = open.group(2) ?? '';
  final at = open.group(0)!.length;
  final rest = line.substring(at);
  final box = _boxFirst.firstMatch(rest);
  // A choice is only a choice after a bullet: `1. ( ) Pick` is a numbered step whose words start with brackets.
  final choice = box != null || !_isBullet.hasMatch(marker) ? null : _choiceFirst.firstMatch(rest);
  final found = box ?? choice;
  return ListLead(
    indent: open.group(1) ?? '',
    marker: marker,
    done: box != null ? rest[1] != ' ' : null,
    picked: choice != null ? rest[1] != ' ' : null,
    boxAt: found != null ? at : -1,
    wordsAt: at + (found?.group(0)!.length ?? 0),
  );
}

/// A to-do's box on a line: where its `[` is and whether it is ticked; null for a line that is not a to-do.
({int at, bool done})? taskBox(String line) {
  final lead = listLead(line);
  final done = lead?.done;
  return done == null ? null : (at: lead!.boxAt, done: done);
}

/// A line with its list lead taken off - indent, marker, and a to-do's box or a choice's - as a line is said back
/// to a person: "Added “Buy milk”", not "Added “- [ ] Buy milk”". A line that is not a list item comes back as it is.
String withoutLead(String line) {
  final lead = listLead(line);
  return lead != null ? line.substring(lead.wordsAt) : line;
}

// ---- what ends an item's line -------------------------------------------------------------------------------------

/// The anchor that names an item: a caret with whitespace before it (or nothing before it at all) and the end of
/// the line after it, which leaves `E = mc^2^` and `foo ^2^` the superscripts they are. A mark and counters may
/// follow it: a mark used to be added after the anchor when an item was sent to Notion, and those lines must still
/// be found.
final RegExp _tail = RegExp('(?<!\\S)($anchorPattern)(?:\\s+(?:$markPattern|$counterPattern))*\\s*\$');

/// Where the anchor naming an item sits in [text]: its caret at `from`, its name ending at `to`; or null for none.
({String id, int from, int to})? anchorSpan(String text) {
  final found = _tail.firstMatch(text);
  final anchor = found?.group(1);
  if (found == null || anchor == null || anchor.isEmpty) return null;
  return (id: anchor.substring(1), from: found.start, to: found.start + anchor.length);
}

final RegExp _trailingSpace = RegExp(r'\s+$');

/// [text] without the anchor naming it, and the one space before it: `- [ ] Ship it ^ship` is `- [ ] Ship it`, and
/// a mark or counter written after the anchor stays, in its place. Text with no anchor comes back as it is. [span]
/// is the anchor when the caller has already found it (the web's second parameter, which defaults to looking).
String withoutAnchor(String text, [({String id, int from, int to})? span]) {
  span ??= anchorSpan(text);
  if (span == null) return text;
  final before = span.from - 1 < 0 ? 0 : span.from - 1;
  return '${text.substring(0, before)}${text.substring(span.to)}'.replaceFirst(_trailingSpace, '');
}

/// The bookmark and the whitespace before it, wherever it stands in a line.
final RegExp _bookmarkSpaced = RegExp('\\s*$bookmarkPattern');

/// A line's text with the bookmark taken out: it is a place in the note, never something the line says.
String withoutBookmark(String text) => text.replaceAll(_bookmarkSpaced, '');

/// A quote's markers at the start of a line, however deep: `>`, `> >`, and the spaces after each.
final RegExp _quoteMarks = RegExp(r'^\s*(?:>[ \t]*)+');

/// What a line says: its text with the bookmark, the quote's markers, the list lead (a bullet or a number, and a
/// box or a choice) and the anchor naming it taken off, and trimmed. Empty for a line that has only a lead, `- `,
/// `- [ ] `, `3. `, `> `, or nothing at all: the line the + beside the line is drawn on, and one an insert may take
/// whole. A heading's `#` stays, since `# ` is already a heading being written.
String lineWords(String text) {
  final unquoted = text.replaceFirst(_quoteMarks, '');
  final lead = listLead(unquoted);
  // The bookmark after the lead is taken with its space, so it is taken from the words, not before the lead is read.
  return jsTrim(withoutAnchor(withoutBookmark(lead != null ? unquoted.substring(lead.wordsAt) : unquoted)));
}

/// What may end an item's line after its words: its anchor, a mark, a counter, the bookmark.
final RegExp _lineTail = RegExp('\\s+(?:$anchorPattern|$markPattern|$counterPattern|$bookmarkPattern)\$');

/// Where a list item's words end in its line: before its bookmark, mark, counters and anchor. The caret goes here
/// when a card or a pointer takes the note to the item, so what is typed next goes on the words and not into the
/// anchor that names them. A line that is not an item ends where its text does.
int wordsEnd(String line) {
  var rest = line.replaceFirst(_trailingSpace, '');
  final lead = listLead(line);
  if (lead == null) return rest.length;
  for (var found = _lineTail.firstMatch(rest); found != null; found = _lineTail.firstMatch(rest)) {
    rest = rest.substring(0, found.start);
  }
  return lead.wordsAt > rest.length ? lead.wordsAt : rest.length;
}

/// What may follow an item's mark to the end of its line: nothing, or a board's anchor and counters (`AFTER_MARK`).
final RegExp afterMark = RegExp('^(?:\\s+(?:$itemTailPattern))*\\s*\$');

// ---- what a tick means on a board ---------------------------------------------------------------------------------

final RegExp _doneName = RegExp(r'^done\b|\bdone$', caseSensitive: false);

/// Whether a board's column is its Done lane, the one a ticked item belongs in: a name that starts or ends with the
/// word, "Done" or "All done" or "Done this week".
bool isDoneName(String name) => _doneName.hasMatch(jsTrim(name));

// ---- JavaScript's trim --------------------------------------------------------------------------------------------

final RegExp _jsTrim = RegExp(r'^\s+|\s+$');

/// JavaScript's `String.prototype.trim`, which is the regex `\s` at both ends: Dart's `trim` disagrees about a
/// character or two (U+0085 is whitespace to Dart's and not to JavaScript's), and the ports are held to the web's
/// answers.
String jsTrim(String text) => text.replaceAll(_jsTrim, '');
