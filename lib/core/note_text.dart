/// What a note's Markdown body says about it, for a list to show: its title, how it is matched by a search, the lines
/// its card draws small, and the small things done to its words on the way. Ports, under the web's own names:
///
/// - `core/noteTitle.ts`: [withoutFrontMatter], [noteTitle];
/// - `core/blanks.ts` (the title's half): [plainFills], [asksForTitle], [titleWords];
/// - `core/comments/format.ts`: [withoutAnchors];
/// - `core/itemSyntax.ts` (what a list item opens and ends with): [listLead], [taskBox], [anchorSpan],
///   [withoutAnchor];
/// - `core/titleKey.ts`: [titleKey], [sameTitle];
/// - `core/shortUrl.ts`: [shortUrl], [shortenUrls];
/// - `notes/allNotes.ts`: [hasTape], [matches];
/// - `notes/peek.ts`: [peekMarkdown].
///
/// What differs: `matches` names a to-do's priority by its sign alone (the web reads every task field through
/// `core/taskFields.ts`, which comes with the editor), so a sign inside a code fence is found here too.
library;

import 'front_matter.dart';
import 'note.dart';

// ---- blanks and fills (core/blanks.ts) ----------------------------------------------------------------------------

/// `{?what day}` (`BLANK`).
const String _blank = r'(?<![{\\$])\{\?(?!\?)([^{}|\n]{0,160})\}(?!\})';

/// An Unsure mark with a note: `??words??(note)` (`NOTED`).
final RegExp _noted = RegExp(r'\?\?(?=\S)((?:(?!\?\?).)*?\S)\?\?\(([^)\n]+)\)');

/// A bracket a fill wrote: the model, where the answer came from, the day (`FILLED`).
final RegExp _filled = RegExp(r'^(.+?) from (memory|this note|[A-Z][\w.-]*(?: and [A-Z][\w.-]*)?), (\d{4}-\d{2}-\d{2})(?:\. Asked: (.+?))?(?:\. (\d) of (\d))?$');

/// The text with every filled answer read as its words alone: what every reader but the editor sees.
String plainFills(String text) {
  if (!text.contains('??(')) return text;
  return text.replaceAllMapped(_noted, (m) => _filled.hasMatch((m.group(2) ?? '').trim()) ? (m.group(1) ?? '') : m.group(0)!);
}

final RegExp _asksTitle = RegExp(
  r'^(?:a |the )?(?:title|name|heading)(?: (?:this|it|for this|for it))?$|^(?:title|name) (?:this|it)$|^what to call (?:this|it)$',
  caseSensitive: false,
);

/// Whether a blank's question asks for a title: empty, or one of the few ways people ask for one.
bool asksForTitle(String question) {
  final words = question.trim().replaceFirst(RegExp(r'[?.!]+$'), '').trim();
  return words == '' || _asksTitle.hasMatch(words);
}

/// A note's first line as its title reads it: a filled answer as its words, a blank that is the whole line as nothing
/// when it asks for a title or as its question's words otherwise, and a blank among other words left out.
String titleWords(String line) {
  var text = plainFills(line);
  if (!text.contains('{?')) return text;
  final lead = RegExp(r'^\s*(?:#{1,6}\s+)?').firstMatch(text)?.group(0) ?? '';
  final rest = text.substring(lead.length);
  final whole = RegExp('^$_blank\\s*\$').firstMatch(rest.trim());
  if (whole != null) {
    final question = (whole.group(1) ?? '').trim();
    return asksForTitle(question) ? lead.replaceFirst(RegExp(r'#{1,6}\s+$'), '').trimRight() : '$lead$question';
  }
  text = text.replaceAll(RegExp(_blank), '');
  return text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceFirst(RegExp(r'\s+$'), '');
}

// ---- comments (core/comments/format.ts) ---------------------------------------------------------------------------

final RegExp _commentAnchor = RegExp(r'\[\^(c[0-9a-z]+)\]');

/// The note with its comment anchors taken out, for a label.
String withoutAnchors(String text) => text.replaceAll(_commentAnchor, '');

// ---- a list item's lead and its anchor (core/itemSyntax.ts) -------------------------------------------------------

const String _bullet = '[-*+]';
const String _number = r'\d+[.)]';

/// What opens a list item: a bullet or a number (`MARKER`).
const String listMarker = '(?:$_bullet|$_number)';

/// A to-do's box standing as a word (`BOX`).
const String taskBoxPattern = r'\[[ xX]\](?=\s|$)';
const String _choice = r'\([ xX]\)(?=\s|$)';
const String _anchor = r'\^[a-z0-9][a-z0-9_-]*';
const String _mark = r'\[[a-z][a-z0-9-]*\]\(https?:\/\/[^\s)]+\)';
const String _counter = r'\[\d{1,4}\/\d{1,4}\]';

final RegExp _open = RegExp('^(\\s*)($listMarker)\\s+');
final RegExp _boxFirst = RegExp('^$taskBoxPattern\\s?');
final RegExp _choiceFirst = RegExp('^$_choice\\s?');
final RegExp _isBullet = RegExp('^$_bullet\$');

/// The opening of a list item, pulled apart (`ListLead`).
class ListLead {
  const ListLead({required this.indent, required this.marker, required this.done, required this.picked, required this.boxAt, required this.wordsAt});

  /// The whitespace before the marker.
  final String indent;

  /// The marker as written: `-`, `*`, `+`, `1.`, `2)`.
  final String marker;

  /// A to-do's box, ticked or not; null for an item with none.
  final bool? done;

  /// A choice's round box, picked or not; null for an item with none.
  final bool? picked;

  /// Where the box or the choice opens in the line; -1 when there is neither.
  final int boxAt;

  /// Where the item's words start.
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

final RegExp _tail = RegExp('(?<!\\S)($_anchor)(?:\\s+(?:$_mark|$_counter))*\\s*\$');

/// Where the anchor naming an item sits in [text]: its caret at `from`, its name ending at `to`; or null for none.
({String id, int from, int to})? anchorSpan(String text) {
  final found = _tail.firstMatch(text);
  final anchor = found?.group(1);
  if (found == null || anchor == null) return null;
  return (id: anchor.substring(1), from: found.start, to: found.start + anchor.length);
}

/// [text] without the anchor naming it, and the one space before it: `- [ ] Ship it ^ship` is `- [ ] Ship it`.
String withoutAnchor(String text) {
  final span = anchorSpan(text);
  if (span == null) return text;
  final before = span.from - 1 < 0 ? 0 : span.from - 1;
  return '${text.substring(0, before)}${text.substring(span.to)}'.replaceFirst(RegExp(r'\s+$'), '');
}

// ---- the title (core/noteTitle.ts) --------------------------------------------------------------------------------

/// The bookmark and the whitespace either side of it, which a title reads as one space.
final RegExp _bookmarkInTitle = RegExp(r'\s*§§\s*');
final RegExp _titleKey = RegExp(r'^\s*title\s*:', caseSensitive: false);
final RegExp _imageOnly = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

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
  final title = named == null
      ? ''
      : named.replaceFirst(RegExp(r'^\s*title\s*:\s*', caseSensitive: false), '').replaceAll(RegExp('''^['"]|['"]\$'''), '').trim();
  return title.isNotEmpty ? [title, ...lines.sublist(end)] : lines.sublist(end);
}

/// The first line of a note, which is the only title Ghost.md has.
String noteTitle(String body) {
  final lines = withoutFrontMatter(body.split('\n'));
  // The first line that is words, not a picture: a note that opens with a photo is titled by what is said under it.
  var line = '';
  for (final each in lines) {
    if (each.trim().isNotEmpty && !_imageOnly.hasMatch(each)) {
      line = each;
      break;
    }
  }
  return withoutAnchors(titleWords(line)).replaceFirst(RegExp(r'^#{1,6}\s+'), '').replaceAll(_bookmarkInTitle, ' ').trim();
}

// ---- titles as they are matched (core/titleKey.ts) ----------------------------------------------------------------

/// [title] reduced to what is matched: "  The Oaks!  " -> "the oaks". Empty for a title with no letters or digits.
String titleKey(String title) => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Whether two titles are one note's: the same key, and a key with something in it.
bool sameTitle(String one, String two) {
  final key = titleKey(one);
  return key != '' && key == titleKey(two);
}

// ---- addresses, shortened (core/shortUrl.ts) ----------------------------------------------------------------------

/// The short form of [url]: the host without `www.`, then the first three and the last three characters of what
/// follows the host. A short path is kept whole.
String shortUrl(String url) {
  final bare = url.trim().replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*:\/\/', caseSensitive: false), '').replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  final cut = bare.indexOf(RegExp(r'[/?#]'));
  final host = cut < 0 ? bare : bare.substring(0, cut);
  final rest = (cut < 0 ? '' : bare.substring(cut)).replaceFirst(RegExp(r'^\/+'), '').replaceFirst(RegExp(r'\/+$'), '');
  if (rest.isEmpty) return host;
  if (rest.length <= 9) return '$host/$rest';
  return '$host/${rest.substring(0, 3)}…${rest.substring(rest.length - 3)}';
}

final RegExp _address = RegExp(r'\bhttps?:\/\/[^\s)\]>]+', caseSensitive: false);

/// Every http(s) address in running [text], shortened.
String shortenUrls(String text) => text.replaceAllMapped(_address, (m) => shortUrl(m.group(0)!));

// ---- search (notes/allNotes.ts) -----------------------------------------------------------------------------------

/// Whether a note has a recording on it, whatever made it.
bool hasTape(Note note) => (note.recordingMs ?? 0) > 0;

const Map<String, String> _priorities = {'🔺': 'highest', '⏫': 'high', '🔼': 'medium', '🔽': 'low', '⏬': 'lowest'};
final RegExp _prioritySign = RegExp('🔺|⏫|🔼|🔽|⏬', unicode: true);

/// What a note's to-dos' priorities say in words, for a search to find: "high priority" for a ⏫.
String _priorityWords(String body) {
  if (!_prioritySign.hasMatch(body)) return '';
  return _prioritySign.allMatches(body).map((m) => '${_priorities[m.group(0)]} priority').join(' ');
}

/// Whether a note has every word of the query, in its title or its body, whatever the case. Words rather than the
/// whole phrase, so "trip packing" finds a note with those two words anywhere in it.
bool matches(Note note, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return true;
  final text = '${plainFills(note.body)} ${_priorityWords(note.body)}'.toLowerCase();
  return words.every(text.contains);
}

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
  return out.join('\n').replaceFirst(RegExp(r'\s+$'), '');
}
