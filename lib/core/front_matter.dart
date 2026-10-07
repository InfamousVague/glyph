/// A note's front matter: what counts as it, and one key read out of it. A port of the reading half of
/// `src/app/core/frontMatter.ts`, under the web's own names, so the list's title, a notebook's `book: true` and a
/// ticket's `type: ticket` are all read where the web app reads them.
///
/// The rule is the list's: a fence on the first line, then lines that are each a `key:` or blank, then a fence that
/// closes it within the first 40 lines. A note that opens with a rule and some words is a note that opens with a rule.
///
/// What differs: only the readers and `quotedTitle` are here. The writers (`withFrontMatterTitle`,
/// `withFrontMatterValue`) come with the editor.
library;

/// A front matter fence, `---` or `+++`, on a line of its own (`FENCE`).
final RegExp frontMatterFence = RegExp(r'^(---|\+\+\+)\s*$');

/// The most lines front matter may take, both fences included (`FRONT_MATTER_LINES`).
const int frontMatterLines = 40;

/// A line front matter may hold, besides a blank one: a `key:`.
final RegExp _keyLine = RegExp(r'^\s*[\w.-]+\s*:');

/// Where a note's front matter ends: the index of the first line after its closing fence, or 0 where it has none.
/// So `lines.sublist(frontMatterEnd(lines))` is always the note's words.
int frontMatterEnd(List<String> lines) {
  if (lines.isEmpty || !frontMatterFence.hasMatch(lines[0])) return 0;
  final most = lines.length < frontMatterLines ? lines.length : frontMatterLines;
  for (var n = 1; n < most; n += 1) {
    final line = lines[n];
    if (frontMatterFence.hasMatch(line)) return n + 1;
    if (!_keyLine.hasMatch(line) && line.trim() != '') return 0;
  }
  return 0;
}

/// [frontMatterEnd] as an offset into the body: the first character after the closing fence's line break, or 0.
int frontMatterOffset(String body) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  if (end == 0) return 0;
  final at = lines.sublist(0, end).join('\n').length + 1;
  return at < body.length ? at : body.length;
}

/// One key's value from the front matter, its quotes taken off, or null where there is no front matter or no such
/// key. A book note says `book: true`; a canvas note is named by `title:`.
String? frontMatterValue(String body, String key) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  if (end == 0) return null;
  final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*(.*?)\\s*\$', caseSensitive: false);
  for (final line in lines.sublist(1, end - 1)) {
    final m = pattern.firstMatch(line);
    if (m != null) return unquoted(m.group(1) ?? '');
  }
  return null;
}

final RegExp _double = RegExp(r'^"(.*)"$');
final RegExp _single = RegExp(r"^'(.*)'$");
final RegExp _escaped = RegExp(r'\\(["\\])');

/// A value as written with its quotes taken off, the way YAML reads them: in double quotes `\"` is a quote and `\\` a
/// backslash, in single quotes `''` is one quote, and a value in neither is as it is.
String unquoted(String value) {
  final double = _double.firstMatch(value);
  if (double != null) return (double.group(1) ?? '').replaceAllMapped(_escaped, (m) => m.group(1)!);
  final single = _single.firstMatch(value);
  if (single != null) return (single.group(1) ?? '').replaceAll("''", "'");
  return value;
}

/// A title as a front matter value: quoted, with a quote or a line break in it made a single quote, and [fallback]
/// where nothing is left.
String quotedTitle(String title, String fallback) {
  final clean = title.replaceAll(RegExp(r'["\n]'), "'").trim();
  return '"${clean.isEmpty ? fallback : clean}"';
}
