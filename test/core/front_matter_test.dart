import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/item_syntax.dart' show jsTrim;
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/sample_library.dart';

/// The front matter's readers (lib/core/front_matter.dart) and the title's (lib/core/note_text.dart) read a body
/// where it lies, a character at a time, with no line split off and no pattern made. They were the web's own
/// patterns over `body.split('\n')` until 2026-10-10, and the answers must not have moved: here the patterns are
/// written out again as they stood ("the pattern's reading") and every reader is held to them, over bodies chosen
/// to be awkward and over a few thousand made by chance from the awkward pieces.
///
/// The cases a list relies on (a title, `book: true`, a ticket's fields, the web's own fixtures) are
/// test/core/note_text_test.dart's and test/book_core/properties_test.dart's.

// ---- the pattern's reading, as it stood ----------------------------------------------------------------------------

final RegExp _fence = RegExp(r'^(---|\+\+\+)\s*$');
final RegExp _keyLine = RegExp(r'^\s*[\w.-]+\s*:');

int patternEnd(List<String> lines) {
  if (lines.isEmpty || !_fence.hasMatch(lines[0])) return 0;
  final most = lines.length < 40 ? lines.length : 40;
  for (var n = 1; n < most; n += 1) {
    final line = lines[n];
    if (_fence.hasMatch(line)) return n + 1;
    if (!_keyLine.hasMatch(line) && line.trim() != '') return 0;
  }
  return 0;
}

int patternOffset(String body) {
  final lines = body.split('\n');
  final end = patternEnd(lines);
  if (end == 0) return 0;
  final at = lines.sublist(0, end).join('\n').length + 1;
  return at < body.length ? at : body.length;
}

String? patternValue(String body, String key) {
  final lines = body.split('\n');
  final end = patternEnd(lines);
  if (end == 0) return null;
  final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*(.*?)\\s*\$', caseSensitive: false);
  for (final line in lines.sublist(1, end - 1)) {
    final m = pattern.firstMatch(line);
    if (m != null) return patternUnquoted(m.group(1) ?? '');
  }
  return null;
}

String patternUnquoted(String value) {
  final double = RegExp(r'^"(.*)"$').firstMatch(value);
  if (double != null) return (double.group(1) ?? '').replaceAllMapped(RegExp(r'\\(["\\])'), (m) => m.group(1)!);
  final single = RegExp(r"^'(.*)'$").firstMatch(value);
  if (single != null) return (single.group(1) ?? '').replaceAll("''", "'");
  return value;
}

final RegExp _imageOnly = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

List<String> patternWithoutFrontMatter(List<String> lines) {
  final end = patternEnd(lines);
  if (end == 0) return [...lines];
  String? named;
  for (final key in lines.sublist(1, end - 1)) {
    if (RegExp(r'^\s*title\s*:', caseSensitive: false).hasMatch(key)) {
      named = key;
      break;
    }
  }
  final title = named == null ? '' : named.replaceFirst(RegExp(r'^\s*title\s*:\s*', caseSensitive: false), '').replaceAll(RegExp('''^['"]|['"]\$'''), '').trim();
  return title.isNotEmpty ? [title, ...lines.sublist(end)] : lines.sublist(end);
}

String patternTitle(String body) {
  final lines = patternWithoutFrontMatter(body.split('\n'));
  var line = '';
  for (final each in lines) {
    if (each.trim().isNotEmpty && !_imageOnly.hasMatch(each)) {
      line = each;
      break;
    }
  }
  return titleWords(line).replaceAll(RegExp(r'\[\^(c[0-9a-z]+)\]'), '').replaceFirst(RegExp(r'^#{1,6}\s+'), '').replaceAll(RegExp(r'\s*§§\s*'), ' ').trim();
}

String patternFirstLine(String body, [int most = 120]) {
  final lines = body.split('\n');
  final title = patternTitle(body).trim();
  var titleSeen = false;
  for (final raw in lines.sublist(patternEnd(lines))) {
    final line = raw.replaceFirst(RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|\d+[.)]\s+)'), '').replaceAll(RegExp(r'\*\*|__|`'), '').trim();
    if (line.isEmpty) continue;
    if (!titleSeen && line == title) {
      titleSeen = true;
      continue;
    }
    return line.length > most ? '${line.substring(0, most - 1).trimRight()}…' : line;
  }
  return '';
}

bool patternYes(String? said) => said != null && RegExp(r'^(true|yes)$', caseSensitive: false).hasMatch(said);
bool patternIsBook(String body) => patternYes(patternValue(body, 'book'));
bool patternIsJournal(String body) => patternIsBook(body) && patternYes(patternValue(body, 'journal'));
bool patternIsTicket(String body) => patternValue(body, 'type')?.trim().toLowerCase() == 'ticket';

// ---- the bodies ----------------------------------------------------------------------------------------------------

/// Bodies chosen for where the readers could part from the patterns: where the front matter ends and does not,
/// what a fence and a key's line may hold, the spaces a pattern knows and `trim` does not, a line that ends in a
/// carriage return, and the fortieth line.
final List<String> awkward = [
  '',
  '-',
  '--',
  '---',
  '---\n',
  '---\n---',
  '---\n---\n',
  '---\n\n---\n',
  '---\n---\nWords',
  '+++\ntitle: Plus\n+++\nWords',
  '---\ntitle: Mixed\n+++\nWords',
  '--- \t\ntitle: Spaces after the fence\n---  \nWords',
  '---\u00a0\ntitle: A hard space after the fence\n---\nWords',
  '---\u0085\ntitle: A next-line after the fence, which no pattern calls a space\n---\nWords',
  '----\ntitle: Four dashes\n---\nWords',
  ' ---\ntitle: A space before the fence\n---\nWords',
  '---\r\ntitle: Windows\r\nbook: true\r\n---\r\nWords\r\n',
  '---\ntitle: "Quoted"\nbook: true\n---\n# Heading\n\nWords',
  "---\ntitle: 'Single'\nbook: yes\njournal: YES\n---\n",
  '---\nTitle: Capital key\nBOOK: True\n---\n',
  '---\n  title  :   Spaced   \n\tbook\t:\ttrue\t\n---\nWords',
  '---\ntitle:\nbook:\n---\nWords',
  '---\ntitle: ""\n---\nWords under an empty title',
  '---\ntitle: "\n---\nOne quote',
  '---\ntitle: "It\'s \\"so\\" \\\\ here"\n---\n',
  "---\ntitle: 'It''s'\n---\n",
  '---\ntitle: ![a](b.png)\n---\nUnder a title that is a picture',
  '---\ntitle: first\ntitle: second\n---\n',
  '---\nnot a key\n---\nWords',
  '---\nkey without colon\ntitle: x\n---\n',
  '---\n- item: one\n---\nA list item is no key',
  '---\nkey.with-dots_and: 1\n---\nWords',
  '---\nblocked-by: "[[GHO-9]]"\ntype: ticket\nid: gho-12\nstatus: In progress\n---\n# Ticket',
  '---\ntype:  Ticket \n---\n',
  '---\ntype: ticket\rid: x\n---\nA carriage return inside a line',
  '---\ntitle: a\rb\n---\nWords',
  '---\ntitle: a\u2028b\n---\nWords',
  '---\n\u00a0title: After a hard space\n---\n',
  '---\n\u0085\n---\nA next-line alone is blank to trim',
  '---\n\u0085title: After a next-line\n---\n',
  '---\ntitle : x\n   \n\t\nbook: true\n---\nBlank lines among the keys',
  '---\ntitle: No closing fence\nbook: true\n',
  '---\ntitle: No closing fence and no last line break',
  '---\ntitle: x\n---',
  '---\ntitle: x\n---\n',
  '---\ntitle: x\n---\n\n',
  '# A plain note\n\nWith words.',
  '\n\n# After blank lines',
  '![a photo](image/a.jpg)\n\nThe walk',
  '![a photo](image/a.jpg) and words',
  ' ![not alone](x.png)\nNext',
  '# Title [^c1x] §§ here',
  '{?}\n\nUnder a blank',
  '- [ ] A to-do first\n- second',
  '> A quote\n\n**Bold** start',
  '# Same\n\n# Same\n\nThen this',
  '---\ntitle: Same\n---\n# Same\n\nSame\n\nOther',
  'x' * 400,
  '# T\n\n${'long ' * 60}',
  // Thirty-eight keys and the fence on the fortieth line: read.
  '---\n${[for (var i = 0; i < 38; i += 1) 'k$i: $i'].join('\n')}\n---\nWords',
  // Thirty-nine keys, the fence on the forty-first: not front matter.
  '---\n${[for (var i = 0; i < 39; i += 1) 'k$i: $i'].join('\n')}\n---\nWords',
  '---\nşey: x\nİd: 2\n---\nKeys outside ASCII',
  '---\nk: 1\nK: 2\n---\nThe Kelvin sign is no k',
];

const List<String> keys = ['title', 'Title', 'book', 'journal', 'type', 'id', 'status', 'blocked-by', 'k', 'K', 'k1', 'key.with-dots_and', 'şey', 'id', 'İd', 'not', ' title', '', 'a b', 'tit.e'];

/// The pieces a body is made of by chance: fences, keys, values, quotes, and the spaces the rules turn on.
const List<String> pieces = [
  '---', '+++', '----', '--', '\n', '\n', '\n', '\r\n', ' ', '\t', '\u00a0', '\u0085', '\u2028', '\r',
  'title', 'Title', 'book', 'journal', 'type', 'id', ':', ': ', ' : ', 'true', 'yes', 'YES', 'no', 'ticket', 'Ticket',
  '"', "'", '\\', '#', '# ', '- ', '> ', '![a](b)', '[^c1]', '§§', '{?}', 'words', 'Some words', 'x', '1', '.', '-', '_',
];

String chanceBody(Random random) {
  String piece() => pieces[random.nextInt(pieces.length)];
  final out = StringBuffer();
  if (random.nextInt(3) == 0) {
    // Anything at all, though more often than not it opens as front matter does.
    if (random.nextInt(4) > 0) out.write(random.nextBool() ? '---\n' : '+++\n');
    final count = random.nextInt(24);
    for (var i = 0; i < count; i += 1) {
      out.write(piece());
    }
    return out.toString();
  }
  // Shaped as front matter is, each line with its chance of being wrong: a fence, some keys, a fence, some words.
  const fences = ['---', '+++', '--- ', '---\t', '---\r', '---\u00a0', '----', ' ---', '---x'];
  const names = ['title', 'Title', 'TITLE', 'book', 'Book', 'journal', 'type', 'id', 'status', 'k', 'key.with-dots_and'];
  const wrong = ['two words', 'şey', ''];
  const gaps = ['', ' ', '  ', '\t', '\u00a0', '\u0085'];
  const values = ['x', 'true', 'True', 'yes', 'YES', 'no', 'ticket', 'Ticket', '"Quoted"', "'Single'", '"', "''", '"a\\"b"', 'a: b', '![a](b)', 'Some words', '', '  ', 'a\rb', 'GHO-12', '[^c1] §§ x'];
  String fence() => random.nextInt(8) == 0 ? fences[random.nextInt(fences.length)] : fences[random.nextInt(2)];
  out
    ..write(fence())
    ..write('\n');
  final lines = random.nextInt(6);
  for (var i = 0; i < lines; i += 1) {
    switch (random.nextInt(12)) {
      case 0:
        out.write(gaps[random.nextInt(gaps.length)]);
      case 1:
        out.write(piece());
      default:
        out
          ..write(gaps[random.nextInt(gaps.length)])
          ..write(random.nextInt(16) == 0 ? wrong[random.nextInt(wrong.length)] : names[random.nextInt(names.length)])
          ..write(gaps[random.nextInt(gaps.length)])
          ..write(random.nextInt(16) == 0 ? '' : ':')
          ..write(gaps[random.nextInt(gaps.length)])
          ..write(values[random.nextInt(values.length)])
          ..write(gaps[random.nextInt(gaps.length)]);
    }
    out.write(random.nextInt(10) == 0 ? '\r\n' : '\n');
  }
  if (random.nextInt(8) > 0) {
    out.write(fence());
    if (random.nextInt(6) > 0) out.write('\n');
  }
  final rest = random.nextInt(8);
  for (var i = 0; i < rest; i += 1) {
    out.write(random.nextInt(3) == 0 ? '\n' : piece());
  }
  return out.toString();
}

void main() {
  void same(String body) {
    final said = body.length > 80 ? '${body.substring(0, 80)}…' : body;
    final reason = 'body: ${said.replaceAll('\n', r'\n').replaceAll('\r', r'\r')}';
    final lines = body.split('\n');
    expect(frontMatterEnd(lines), patternEnd(lines), reason: reason);
    final span = frontMatterSpan(body);
    expect(span.lines, patternEnd(lines), reason: reason);
    expect(frontMatterOffset(body), patternOffset(body), reason: reason);
    expect(span.offset, patternOffset(body), reason: reason);
    for (final key in keys) {
      expect(frontMatterValue(body, key), patternValue(body, key), reason: '$reason key: "$key"');
    }
    expect(withoutFrontMatter(lines), patternWithoutFrontMatter(lines), reason: reason);
    expect(noteTitle(body), patternTitle(body), reason: reason);
    expect(firstLine(body), patternFirstLine(body), reason: reason);
    expect(firstLine(body, 12), patternFirstLine(body, 12), reason: reason);
    expect(isBookBody(body), patternIsBook(body), reason: reason);
    expect(isJournalBody(body), patternIsJournal(body), reason: reason);
    expect(isTicket(body), patternIsTicket(body), reason: reason);
  }

  group('the front matter read where it lies', () {
    test('answers as the patterns did, for bodies chosen to be awkward', () {
      awkward.forEach(same);
    });

    test('answers as the patterns did, for every note of the seeded library and the starter notes', () {
      for (final note in [...seedLibrary(), ...starterNotes(seedNow)]) {
        same(note.body);
      }
    });

    test('answers as the patterns did, for four thousand bodies made by chance', () {
      final random = Random(20261010);
      var read = 0, named = 0, books = 0;
      for (var i = 0; i < 4000; i += 1) {
        final body = chanceBody(random);
        same(body);
        if (patternEnd(body.split('\n')) > 0) read += 1;
        if (patternValue(body, 'title') != null) named += 1;
        if (patternIsBook(body)) books += 1;
      }
      // Chance must reach what it is there to try: bodies with front matter, a title in it, and a notebook's yes.
      expect(read, greaterThan(600), reason: '$read $named $books');
      expect(named, greaterThan(120), reason: '$read $named $books');
      expect(books, greaterThan(8), reason: '$read $named $books');
    });

    test('says where the closing fence’s line begins, and where the words do', () {
      const body = '---\ntitle: x\nbook: true\n---\nWords';
      final span = frontMatterSpan(body);
      expect(span.lines, 4);
      expect(body.substring(span.closing, span.offset), '---\n');
      expect(body.substring(span.offset), 'Words');
      expect(frontMatterSpan('# No front matter').isEmpty, isTrue);
      expect(frontMatterSpan('# No front matter').offset, 0);
    });

    test('takes a value’s quotes off as the patterns did', () {
      for (final value in ['', 'x', '"x"', "'x'", '"', "'", '""', "''", '"a\\"b"', '"a\\\\b"', "'a''b'", '"x', 'x"', "'x\"", '"a"b"', ' "x"', '"x" ']) {
        expect(unquoted(value), patternUnquoted(value), reason: value);
      }
    });

    test('knows a blank stretch as trim does', () {
      for (var c = 0; c <= 0xFFFF; c += 1) {
        final char = String.fromCharCode(c);
        expect(blankIn('a${char}b', 1, 2), char.trim().isEmpty, reason: 'U+${c.toRadixString(16)}');
      }
      expect(blankIn('abc', 1, 1), isTrue);
      expect(blankIn(' \t x', 0, 3), isTrue);
      expect(blankIn(' \t x', 0, 4), isFalse);
    });

    test('reads yes as the pattern did', () {
      for (final said in <String?>[null, '', 'true', 'TRUE', 'True', 'yes', 'Yes', 'yEs', 'no', 'truee', ' true', 'true ', 'yeſ', 'ye', 'y', 'trues', 'on', '1']) {
        expect(saysYes(said), patternYes(said), reason: '$said');
      }
    });

    test('keeps JavaScript’s trim where the web trims', () {
      // A ticket's values are trimmed as the page trims them: a next-line is not a space there.
      expect(jsTrim('\u0085x\u0085'), '\u0085x\u0085');
      expect(ticketOf('---\ntype: ticket\nstatus: \u00a0Doing\u00a0\n---\n')!.status, 'Doing');
    });
  });
}
