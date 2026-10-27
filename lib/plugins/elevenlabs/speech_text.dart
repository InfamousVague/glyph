/// A note made into words to be read aloud, and those words cut into reads ElevenLabs takes (Matt, 2026-10-27: "allow
/// creating voice overs of notes"). Pure, for a test to ask.
///
/// What is read is what a person reads on the page, not the Markdown under it:
/// - **Left out:** the front matter; fenced code (and the fences that are the app's own, comments and canvases); a
///   picture, a film, a voice memo, a file's line (a voice-over made before among them); a horizontal rule; HTML; a
///   footnote's anchor and its definition; a `{image: …}` cue; a bare address.
/// - **Made words:** a link is its words, a `[[wiki link]]` its title (or what it says after a `|`); bold, italics,
///   strikes, highlights and inline code are their words; a heading, a list item, a to-do and a quote lose their
///   marks. A heading or an item that ends with no stop is given one, so it is read as a phrase of its own rather
///   than run into the next.
/// - **A table** is read a row at a time, each cell after its column's heading ("Name: Ada, Role: lead."), as a
///   person reads one aloud; the heading row itself is not read on its own.
///
/// The reads ([speechChunks]) are cut at paragraphs, then at sentences, then at spaces, each at most a model's
/// limit, so no read stops mid-word; together they are every word, in order.
library;

import '../../core/front_matter.dart' show frontMatterEnd;

final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+');
final RegExp _quote = RegExp(r'^\s*(>\s?)+');
final RegExp _listLead = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?');
final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final RegExp _tableRow = RegExp(r'^\s*\|.*\|\s*$');
final RegExp _tableRule = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');
final RegExp _footnoteDefinition = RegExp(r'^\s{0,3}\[\^[^\]]+\]:');
final RegExp _image = RegExp(r'!\[[^\]\n]*\]\([^)\n]*\)');
final RegExp _linkedImage = RegExp(r'\[!\[[^\]\n]*\]\([^)\n]*\)\]\([^)\n]*\)');
final RegExp _fileLink = RegExp(r'\[[^\]\n]*\]\(file/[^)\n]*\)');
final RegExp _link = RegExp(r'\[([^\]\n]*)\]\([^)\n]*\)');
final RegExp _wiki = RegExp(r'\[\[([^\]|\n]+)(?:\|([^\]\n]+))?\]\]');
final RegExp _footnote = RegExp(r'\[\^[^\]\n]+\]');
final RegExp _cue = RegExp(r'\{\s*image\s*:[^}\n]*\}', caseSensitive: false);
final RegExp _html = RegExp(r'</?[A-Za-z][^>\n]*>');
final RegExp _bareUrl = RegExp(r'<?https?://[^\s>)]+>?');
final RegExp _code = RegExp(r'`+([^`\n]*)`+');
final RegExp _strong = RegExp(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1');
final RegExp _em = RegExp(r'(?<![\w*])([*_])(?=\S)(.+?)(?<=\S)\1(?![\w*])');
final RegExp _strike = RegExp(r'~~(.+?)~~');
final RegExp _mark = RegExp(r'==(.+?)==');
final RegExp _tag = RegExp(r'(^|\s)#([A-Za-z][\w/-]*)');
final RegExp _spaces = RegExp(r'[ \t]+');
final RegExp _ends = RegExp(r'[.!?…:;,)"”’]$');

/// The words of one line, its marks taken off.
String _words(String line) {
  var text = line;
  text = text.replaceAll(_linkedImage, '').replaceAll(_image, '').replaceAll(_fileLink, '').replaceAll(_cue, '');
  text = text.replaceAllMapped(_wiki, (m) => (m.group(2) ?? m.group(1) ?? '').trim());
  text = text.replaceAllMapped(_link, (m) => m.group(1) ?? '');
  text = text.replaceAll(_footnote, '').replaceAll(_html, '').replaceAll(_bareUrl, '');
  text = text.replaceAllMapped(_code, (m) => m.group(1) ?? '');
  text = text.replaceAllMapped(_strong, (m) => m.group(2) ?? '');
  text = text.replaceAllMapped(_em, (m) => m.group(2) ?? '');
  text = text.replaceAllMapped(_strike, (m) => m.group(1) ?? '').replaceAllMapped(_mark, (m) => m.group(1) ?? '');
  text = text.replaceAllMapped(_tag, (m) => '${m.group(1)}${m.group(2)}');
  return text.replaceAll(_spaces, ' ').trim();
}

/// [words] with a stop after it where it has none, so it is read as a phrase of its own.
String _stopped(String words) => words.isEmpty || _ends.hasMatch(words) ? words : '$words.';

List<String> _cells(String row) {
  var inner = row.trim();
  if (inner.startsWith('|')) inner = inner.substring(1);
  if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
  return [for (final cell in inner.split('|')) _words(cell)];
}

/// A table's rows read aloud: each cell after its heading, a row a sentence.
List<String> _tableWords(List<String> rows) {
  if (rows.length < 2 || !_tableRule.hasMatch(rows[1])) return [for (final row in rows) _stopped(_cells(row).where((c) => c.isNotEmpty).join(', '))];
  final heads = _cells(rows[0]);
  final read = <String>[];
  for (final row in rows.skip(2)) {
    final cells = _cells(row);
    final parts = <String>[];
    for (var i = 0; i < cells.length; i += 1) {
      if (cells[i].isEmpty) continue;
      final head = i < heads.length ? heads[i] : '';
      parts.add(head.isEmpty ? cells[i] : '$head: ${cells[i]}');
    }
    if (parts.isNotEmpty) read.add(_stopped(parts.join(', ')));
  }
  return read;
}

/// The note [body] as words to read aloud: paragraphs apart by a blank line.
String speechText(String body) {
  final lines = body.replaceAll('\r\n', '\n').split('\n');
  final paragraphs = <String>[];
  final paragraph = <String>[];
  void close() {
    if (paragraph.isNotEmpty) paragraphs.add(paragraph.join(' '));
    paragraph.clear();
  }

  var n = frontMatterEnd(lines);
  while (n < lines.length) {
    final line = lines[n];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      // Code, and the app's own fenced blocks, are not read: to the fence that closes it, or the note's end.
      close();
      final mark = fence.group(1)!;
      n += 1;
      while (n < lines.length && !lines[n].trimLeft().startsWith(mark[0] * mark.length)) {
        n += 1;
      }
      n += 1;
      continue;
    }
    if (_tableRow.hasMatch(line)) {
      close();
      final rows = <String>[];
      while (n < lines.length && _tableRow.hasMatch(lines[n])) {
        rows.add(lines[n]);
        n += 1;
      }
      final read = _tableWords(rows);
      if (read.isNotEmpty) paragraphs.add(read.join(' '));
      continue;
    }
    n += 1;
    if (line.trim().isEmpty || _rule.hasMatch(line) || _footnoteDefinition.hasMatch(line)) {
      close();
      continue;
    }
    if (line.trimLeft().startsWith(r'$$')) {
      close();
      continue;
    }
    final heading = _heading.hasMatch(line);
    final item = _listLead.hasMatch(line);
    final words = _words(line.replaceFirst(_heading, '').replaceFirst(_quote, '').replaceFirst(_listLead, ''));
    if (words.isEmpty) continue;
    if (heading || item) {
      // A heading and each item are phrases of their own.
      close();
      paragraphs.add(_stopped(words));
      continue;
    }
    paragraph.add(words);
  }
  close();
  return paragraphs.where((p) => p.trim().isNotEmpty).join('\n\n');
}

/// How many characters ElevenLabs is asked to read for [text]: what it bills by.
int speechCharacters(String text) => text.length;

final RegExp _sentenceEnd = RegExp(r'(?<=[.!?…])\s+');

/// [text] cut into reads of at most [most] characters: at paragraphs where they fit, else at sentences, else at
/// spaces, else (one word longer than [most]) where it must be.
List<String> speechChunks(String text, {required int most}) {
  assert(most > 0);
  final chunks = <String>[];
  var current = '';
  void add(String piece, String joiner) {
    if (current.isEmpty) {
      current = piece;
    } else if (current.length + joiner.length + piece.length <= most) {
      current = '$current$joiner$piece';
    } else {
      chunks.add(current);
      current = piece;
    }
  }

  List<String> fitted(String piece, RegExp by, String joiner) {
    if (piece.length <= most) return [piece];
    final parts = piece.split(by).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return [piece];
    return parts;
  }

  for (final paragraph in text.split(RegExp(r'\n{2,}'))) {
    if (paragraph.trim().isEmpty) continue;
    var joiner = '\n\n';
    for (final sentence in fitted(paragraph, _sentenceEnd, ' ')) {
      for (final words in fitted(sentence, RegExp(r'\s+'), ' ')) {
        var rest = words;
        while (rest.length > most) {
          add(rest.substring(0, most), joiner);
          rest = rest.substring(most);
          joiner = ' ';
        }
        add(rest, joiner);
        joiner = ' ';
      }
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}
