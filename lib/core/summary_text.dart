/// The summary section a note carries in its body, as it is shaped, found, placed, written and taken off. A port of
/// `src/app/ai/summaryText.ts`: the half the sync merge leans on (core/sync/notes.ts), [summarySection],
/// [withSummary], [withoutSummary], [summaryLine], [summaryPlace], [hasWords], [dateTitled] and [retitled], and the
/// model's half, [shapeSummary], [carryTicked] and [transcriptPieces]. The AI reaches it as ai/summary_text.dart.
///
/// The summary is words in the body, under the title, so it syncs, shares and is in the `.md` file. It has a shape the
/// app owns: the heading `## Summary`, one prose line, then only item lines, with blanks between groups. That shape is
/// how the section is found again, by its shape and not by any marker: from the heading through the one prose line and
/// every following blank or item line, ending at the first line that is none of those, or a heading, or a rule, or the
/// end. Where the text the app wrote is known (`kept`), the section is that text's span while the body still reads so,
/// boxes ticked or not, so a list of the person's straight under it is not read as its.
///
/// Its place is after the front matter and after the first line of words, whatever its marks: never above them, since
/// `noteTitle` takes the first line and `## Summary` on top would title every card "Summary".
///
/// The section has a SHAPE THE APP OWNS ([shapeSummary]): the model's answer is read into it, whatever a 4B reached
/// for, and the same reading works on the answer so far, so a run's lines only ever grow as it streams. [carryTicked]
/// keeps every `- [x]` line of an old section in the new one, so a to-do he ticked never comes back open in To do,
/// however the model rephrases. [transcriptPieces] cuts a long transcript for the pieces pass.
///
/// What differs: nothing but where it lives (lib/core, since the sync merge came first). Offsets are UTF-16 units, as
/// the page's are.
library;

import 'front_matter.dart';
import 'item_syntax.dart' show jsTrim;
import 'note_text.dart';

/// The heading the section is known by (`SUMMARY_HEADING`).
const String summaryHeading = '## Summary';

/// A line of the section past the heading and the prose line: an item, a to-do, or a ticked to-do.
final RegExp _item = RegExp(r'^\s*-\s+(?:\[[ xX]\]\s+)?\S');

/// A to-do, ticked or not.
final RegExp _todo = RegExp(r'^\s*-\s+\[[ xX]\]\s+');

/// A heading of any level.
final RegExp _heading = RegExp(r'^#{1,6}\s+');

/// A horizontal rule.
final RegExp _rule = RegExp(r'^(?:-{3,}|\*{3,}|_{3,})\s*$');

/// A picture on a line of its own, which the title steps over.
final RegExp _picture = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

/// A to-do line with its box as an open one, for reading a kept section against a body where some were ticked.
String _untick(String line) => line.replaceFirst(_todo, '- [ ] ');

/// A bullet the model wrote with another mark, `*`, `+`, a number, a typographic bullet: made a dash.
final RegExp _otherBullet = RegExp(r'^(\s*)(?:[*+•·▪‣]|\d+[.)])\s+');

/// A box written tight against its dash, `-[ ]`: given its space.
final RegExp _tightBox = RegExp(r'^(\s*)-\[([ xX])\]');

/// A decision written without its dash: made an item, as the prompt asked.
final RegExp _bareDecided = RegExp(r'^(\s*)(decided:)', caseSensitive: false);

/// A label the model puts on the prose line, which the heading already says.
final RegExp _label = RegExp(r'^(?:\*\*summary:?\*\*:?|summary:)\s*', caseSensitive: false);

/// An introduction, "Here is the summary:", that says nothing itself.
final RegExp _intro = RegExp(r':$');

/// A prose line that ends its sentence; one that does not was wrapped, and the next line goes on from it.
final RegExp _sentenceDone = RegExp(r'[.!?…:]["”’)\]]*$');

/// A to-do that has been ticked.
final RegExp _ticked = RegExp(r'^\s*-\s+\[[xX]\]\s+');

/// A code fence, which the model sometimes puts round its answer.
final RegExp _fence = RegExp(r'^```');

/// A mark still under the pen as the model streams: a heading's hashes, an item's dash or number, a box not yet
/// closed.
final RegExp _underPen = RegExp(r'^(?:#{1,6}|-|-\s+\[[ xX]?\]?|\d+[.)]?|[*+•·▪‣])\s*$');

final RegExp _trailingSpace = RegExp(r'\s+$');

/// A transcript up to this many characters goes to the model in one pass (`ONE_PASS_CHARS`).
const int onePassChars = 20000;

/// About how many characters a piece of a longer transcript holds: about 3,000 tokens (`PIECE_CHARS`).
const int pieceChars = 12000;

// ---- the shape -------------------------------------------------------------------------------

/// The model's answer in the section's shape (`ShapedSummary`).
class ShapedSummary {
  const ShapedSummary({required this.title, required this.section});

  /// The model's `# heading`, for a note still wearing its date title; null when it gave none.
  final String? title;

  /// The section, in its shape: the heading, the prose line, the items. Empty when the model gave nothing to keep.
  final String section;

  @override
  bool operator ==(Object other) => other is ShapedSummary && other.title == title && other.section == section;

  @override
  int get hashCode => Object.hash(title, section);

  @override
  String toString() => 'ShapedSummary(title: $title, section: $section)';
}

/// The model's answer as the section the app writes: `## Summary`, one prose line, then only item lines, blanks
/// collapsed to one between groups (`shapeSummary`). The model's `# heading` first line is taken for the title and
/// never written into the section; a second prose line, a heading, a rule and a closing remark are dropped. What a
/// 4B reaches for is read as what was meant: a numbered or typographic bullet is an item, a label or an introduction
/// on the prose line is not the prose, and a sentence wrapped over two lines is one sentence. Works on the answer so
/// far as well as the finished one, so a run's lines only ever grow as it streams (ai/runs.dart `restore`).
ShapedSummary shapeSummary(String modelText) {
  String? title;
  String? prose;
  // The prose line may still go on: no blank, item or heading has come since it.
  var proseOpen = false;
  // A line of prose has come, if only a label: the heading is the section's from then on, so it never un-lands.
  var sawProse = false;
  final items = <String>[];
  var seenItem = false;
  for (final raw in modelText.split('\n')) {
    final line = raw
        .replaceFirst(_trailingSpace, '')
        .replaceFirstMapped(_otherBullet, (m) => '${m[1]}- ')
        .replaceFirstMapped(_tightBox, (m) => '${m[1]}- [${m[2]}]')
        .replaceFirstMapped(_bareDecided, (m) => '${m[1]}- ${m[2]}');
    final bare = jsTrim(line);
    if (bare.isEmpty) {
      proseOpen = false;
      // A blank between groups, once; none before the first item.
      if (items.isNotEmpty && items.last != '') items.add('');
      continue;
    }
    if (_fence.hasMatch(bare) || _underPen.hasMatch(bare)) continue;
    if (_item.hasMatch(line)) {
      proseOpen = false;
      items.add(bare);
      seenItem = true;
      continue;
    }
    if (_heading.hasMatch(bare)) {
      proseOpen = false;
      final words = jsTrim(bare.replaceFirst(_heading, ''));
      // The first heading names the recording; the section's own heading, echoed, is not a title.
      if (title == null && prose == null && !seenItem && words.isNotEmpty && words.toLowerCase() != 'summary') title = words;
      continue;
    }
    if (_rule.hasMatch(bare)) continue;
    if (seenItem) continue;
    sawProse = true;
    // The one prose line: a label alone or an introduction is not it, and the next line of prose is. A line that
    // did not end its sentence was wrapped, and the line after it goes on from it; every other line of prose is
    // dropped.
    if (prose == null) {
      final stripped = bare.replaceFirst(_label, '');
      if (stripped.isNotEmpty && !_intro.hasMatch(stripped)) {
        prose = stripped;
        proseOpen = true;
      }
    } else if (proseOpen && !_sentenceDone.hasMatch(prose)) {
      prose = '$prose $bare';
    }
  }
  while (items.isNotEmpty && items.last == '') {
    items.removeLast();
  }
  if (prose == null && items.isEmpty) return ShapedSummary(title: title, section: sawProse ? summaryHeading : '');
  final lines = [summaryHeading, ?prose, if (items.isNotEmpty) ...['', ...items]];
  return ShapedSummary(title: title, section: lines.join('\n'));
}

// ---- finding it -----------------------------------------------------------------------------

/// Where the section is in a body (`SummarySpan`).
class SummarySpan {
  const SummarySpan({required this.start, required this.end, required this.text});

  /// The offset of `## Summary` in the body.
  final int start;

  /// The offset after the section's last line, before its newline.
  final int end;

  /// The section's lines, joined.
  final String text;
}

bool _isHeading(String line) => line.trim() == summaryHeading;

/// The section's lines from the heading at [at]: the heading, then the one prose line if it comes before any item,
/// then every blank or item line, up to the first line that is none of those, a heading, a rule, or the end. Trailing
/// blanks are not the section's. Answers how many lines it takes (`sectionLength`).
int _sectionLength(List<String> lines, int at) {
  var n = at + 1;
  var prosePending = true;
  var last = at;
  while (n < lines.length) {
    final line = lines[n];
    final bare = line.trim();
    if (bare.isEmpty) {
      n += 1;
      continue;
    }
    if (_heading.hasMatch(bare) || _rule.hasMatch(bare)) break;
    if (_item.hasMatch(line)) {
      prosePending = false;
      last = n;
      n += 1;
      continue;
    }
    if (prosePending) {
      prosePending = false;
      last = n;
      n += 1;
      continue;
    }
    break;
  }
  return last - at + 1;
}

/// The lines the section takes, as (first line, count), or null without one (`findSection`). Front matter is never
/// searched.
(int, int)? _findSection(List<String> lines, [String? kept]) {
  for (var n = frontMatterEnd(lines); n < lines.length; n += 1) {
    if (!_isHeading(lines[n])) continue;
    if (kept != null && kept.isNotEmpty) {
      final keptLines = kept.split('\n');
      final after = n + keptLines.length;
      var reads = true;
      for (var i = 0; i < keptLines.length && reads; i += 1) {
        reads = n + i < lines.length && _untick(lines[n + i]) == _untick(keptLines[i]);
      }
      if (reads && (after >= lines.length || lines[after].trim().isEmpty)) return (n, keptLines.length);
    }
    return (n, _sectionLength(lines, n));
  }
  return null;
}

/// Where line [n] starts in a body split into [lines].
int _offsetOfLine(List<String> lines, int n) {
  var at = 0;
  for (var i = 0; i < n; i += 1) {
    at += lines[i].length + 1;
  }
  return at;
}

/// The section in [body]: the kept text's span where the body still reads so, else found by its shape; null without
/// one (`summarySection`).
SummarySpan? summarySection(String body, [String? kept]) {
  final lines = body.split('\n');
  final found = _findSection(lines, kept);
  if (found == null) return null;
  final (first, count) = found;
  final start = _offsetOfLine(lines, first);
  final text = lines.sublist(first, first + count).join('\n');
  return SummarySpan(start: start, end: start + text.length, text: text);
}

/// The summary's first prose line, under `## Summary`; null without one (`summaryLine`).
String? summaryLine(String body) {
  final section = summarySection(body);
  if (section == null) return null;
  final lines = section.text.split('\n');
  final second = lines.length > 1 ? lines[1] : '';
  final bare = second.trim();
  if (bare.isEmpty || _item.hasMatch(second)) return null;
  return bare;
}

/// Where a fresh section goes, as the index of the line it starts on (`placeLine`).
int _placeLine(List<String> lines) {
  var n = frontMatterEnd(lines);
  // Blank lines and pictures before the first words.
  while (n < lines.length && (lines[n].trim().isEmpty || _picture.hasMatch(lines[n]))) {
    n += 1;
  }
  if (n >= lines.length) return lines.length;
  if (_heading.hasMatch(lines[n].trim())) return n + 1;
  // A paragraph, or a list: through its last line.
  while (n < lines.length && lines[n].trim().isNotEmpty && !_picture.hasMatch(lines[n])) {
    n += 1;
  }
  return n;
}

/// The index of the first line of words in [lines], past the front matter and any picture; null with none.
int? _firstWordsLine(List<String> lines) {
  for (var n = frontMatterEnd(lines); n < lines.length; n += 1) {
    final line = lines[n];
    if (line.trim().isNotEmpty && !_picture.hasMatch(line)) return n;
  }
  return null;
}

final RegExp _titleKey = RegExp(r'^\s*title\s*:', caseSensitive: false);

/// Whether the front matter names the note's title, which `noteTitle` takes over the first line of words.
bool _titledInFrontMatter(List<String> lines) {
  final end = frontMatterEnd(lines);
  return end > 0 && lines.sublist(1, end - 1).any(_titleKey.hasMatch);
}

/// Whether the body has a line of words past the front matter and any picture, or a title named in the front matter
/// (`hasWords`): without one, `## Summary` would be its title.
bool hasWords(String body) {
  final lines = body.split('\n');
  return _firstWordsLine(lines) != null || _titledInFrontMatter(lines);
}

/// The offset a fresh section is written at: the start of the line after the first line of words (`summaryPlace`).
int summaryPlace(String body) {
  final lines = body.split('\n');
  final n = _placeLine(lines);
  return n >= lines.length ? body.length : _offsetOfLine(lines, n);
}

/// The body with the section written: over the one it has (closed by [kept], the text the app wrote, where there is
/// one), or fresh at its place with a blank line either side (`withSummary`). With [title], a note still wearing its
/// date title takes it as its first line, and a note with no words at all gets it as a `# title` line above the
/// section.
String withSummary(String body, String section, {String? title, String? kept}) {
  final lines = body.split('\n');
  final found = _findSection(lines, kept);
  final words = _firstWordsLine(lines) != null || _titledInFrontMatter(lines);
  final named = title != null && title.isNotEmpty;
  final head = !words && named ? ['# $title', ''] : const <String>[];
  final List<String> out;
  if (lines.every((l) => l.trim().isEmpty)) {
    out = [...head, ...section.split('\n')];
  } else if (found != null) {
    final (first, count) = found;
    out = [...lines.sublist(0, first), ...section.split('\n'), ...lines.sublist(first + count)];
  } else {
    final n = _placeLine(lines);
    final before = n > 0 && lines[n - 1].trim().isNotEmpty ? [''] : const <String>[];
    final after = n < lines.length && lines[n].trim().isNotEmpty ? [''] : const <String>[];
    out = [...lines.sublist(0, n), ...before, ...head, ...section.split('\n'), ...after, ...lines.sublist(n)];
  }
  return named && words ? retitled(out.join('\n'), title) : out.join('\n');
}

/// The body with the app's section taken off, and the blank line that went with it; [kept] closes the section as in
/// [summarySection] (`withoutSummary`).
String withoutSummary(String body, [String? kept]) {
  final lines = body.split('\n');
  final found = _findSection(lines, kept);
  if (found == null) return body;
  final (first, count) = found;
  final rest = [...lines.sublist(0, first), ...lines.sublist(first + count)];
  // The blank that separated the section from what follows is one blank too many now.
  if (first > 0 && first < rest.length && rest[first].trim().isEmpty && rest[first - 1].trim().isEmpty) {
    rest.removeAt(first);
  } else if (first == rest.length && first > 0 && rest[first - 1].trim().isEmpty) {
    rest.removeLast();
  }
  return rest.join('\n');
}

final RegExp _tickedTail = RegExp(r'[\s.!?,;:]+$');

/// A ticked line as it is matched against the new section: the box lower-cased, trailing punctuation and space
/// ignored.
String _tickedKey(String line) => jsTrim(line).replaceFirst(_ticked, '- [x] ').replaceFirst(_tickedTail, '').toLowerCase();

/// The new section with every ticked to-do of the old one carried in verbatim, after the new to-dos (`carryTicked`):
/// a to-do he ticked does not come back open, however the model rephrases it. Un-ticked old to-dos are not carried:
/// the new list is the new list. A ticked line the new section already has, whatever the case of its box or its
/// closing full stop, is not doubled.
String carryTicked(String old, String next) {
  final nextLines = next.split('\n');
  final have = {for (final line in nextLines) _tickedKey(line)};
  final ticked = [
    for (final line in old.split('\n').map(jsTrim))
      if (_ticked.hasMatch(line) && !have.contains(_tickedKey(line))) line,
  ];
  if (ticked.isEmpty) return next;
  var at = -1;
  for (var n = 0; n < nextLines.length; n += 1) {
    if (_todo.hasMatch(nextLines[n])) at = n;
  }
  if (at >= 0) {
    nextLines.insertAll(at + 1, ticked);
  } else {
    nextLines.addAll(['', ...ticked]);
  }
  return nextLines.join('\n');
}

// ---- the title -----------------------------------------------------------------------------

/// A meeting's title as it is made: "Meeting, 26 Sep 14:05", the day and the month in the device's own order.
final RegExp _dateTitle = RegExp(r'^Meeting, (?:\d{1,2} [A-Za-z]{3,}\.?|[A-Za-z]{3,}\.? \d{1,2}) \d{1,2}:\d{2}$');

/// Whether the note's title is still the date title a meeting is made with (`dateTitled`).
bool dateTitled(String body) => _dateTitle.hasMatch(noteTitle(body));

/// The body with [title] as its title, only while it still wears its date title; else as it was (`retitled`). A title
/// named in the front matter is not the first line's to change, and is left.
String retitled(String body, String title) {
  if (title.isEmpty || !dateTitled(body)) return body;
  final lines = body.split('\n');
  if (_titledInFrontMatter(lines)) return body;
  final at = _firstWordsLine(lines);
  if (at == null) return body;
  lines[at] = '# $title';
  return lines.join('\n');
}

// ---- long recordings ----------------------------------------------------------------------

/// A sentence's end, for cutting a paragraph that is longer than a piece.
final RegExp _sentenceEnd = RegExp(r'(?<=[.!?]["”’)]?)\s+');

final RegExp _paragraphBreak = RegExp(r'\n\s*\n');

/// The transcript in pieces of about [size] characters, cut at paragraph breaks; a paragraph longer than a piece is
/// cut at sentence ends (`transcriptPieces`). Up to [onePassChars] goes in one piece. Nothing is dropped: the pieces
/// joined by paragraph breaks are the transcript's paragraphs again.
List<String> transcriptPieces(String plain, [int size = pieceChars]) {
  final text = jsTrim(plain);
  if (text.isEmpty) return [];
  if (text.length <= onePassChars) return [text];
  final units = <String>[
    for (final paragraph in text.split(_paragraphBreak).map(jsTrim))
      if (paragraph.isNotEmpty) ...(paragraph.length <= size ? [paragraph] : _sentencesUnder(paragraph, size)),
  ];
  final pieces = <String>[];
  var piece = '';
  for (final unit in units) {
    if (piece.isNotEmpty && piece.length + 2 + unit.length > size) {
      pieces.add(piece);
      piece = unit;
    } else {
      piece = piece.isNotEmpty ? '$piece\n\n$unit' : unit;
    }
  }
  if (piece.isNotEmpty) pieces.add(piece);
  return pieces;
}

/// A long paragraph as runs of sentences each under [size], a sentence longer than that cut where it must be.
List<String> _sentencesUnder(String paragraph, int size) {
  final out = <String>[];
  var run = '';
  for (final sentence in paragraph.split(_sentenceEnd)) {
    for (var at = 0; at < sentence.length; at += size) {
      final part = sentence.substring(at, at + size < sentence.length ? at + size : sentence.length);
      if (run.isNotEmpty && run.length + 1 + part.length > size) {
        out.add(run);
        run = part;
      } else {
        run = run.isNotEmpty ? '$run $part' : part;
      }
    }
  }
  if (run.isNotEmpty) out.add(run);
  return out;
}
