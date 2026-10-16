/// The other names a note answers to: `aliases:` in its front matter, as Obsidian writes it. A `[[link]]` to an
/// alias opens the note, the + sheet's A note offers it, a search finds the note by it as by its title, and a note
/// that says it without linking is one of the note's unlinked mentions (lib/core/link_index.dart).
///
/// Every way Obsidian has written them is read:
///
///     aliases: [Lisbon, "The trip"]      a list in brackets
///     aliases: Lisbon, The trip          a list with commas
///     aliases:                           a list of lines
///       - Lisbon
///       - "The trip"
///     alias: Lisbon                      the old one-name key
///
/// The list of lines is read here by its own walk of the front matter. The app's own rule for what front matter is
/// (lib/core/front_matter.dart, the web app's and the core's) takes only `key:` lines and blank ones, so a note whose
/// front matter holds a list of lines is, to the rest of the app, a note that opens with a rule: its aliases are
/// still read here, and its title is what that rule makes of it. test/core/aliases_test.dart says so.
///
/// Nothing is written: an alias is what the person typed in the note's own front matter.
library;

import 'note.dart';
import 'title_key.dart';

/// The most lines the walk reads, both fences included: the front matter's own limit (`FRONT_MATTER_LINES`).
const int _mostLines = 40;

final RegExp _fence = RegExp(r'^(---|\+\+\+)\s*$');
final RegExp _key = RegExp(r'^\s*(aliases|alias)\s*:\s*(.*?)\s*$', caseSensitive: false);
final RegExp _item = RegExp(r'^\s*-\s*(.*?)\s*$');

/// The names [body] gives its note besides its title, as written, in their order, each once (by its key) and none
/// empty. Empty for a note with no front matter or no `aliases:`.
List<String> aliasesOf(String body) {
  // Most notes stop here: front matter opens the body or there is none.
  if (body.length < 3) return const [];
  final first = body.codeUnitAt(0);
  if (first != 0x2D && first != 0x2B) return const [];
  final lines = _headLines(body);
  if (lines.isEmpty || !_fence.hasMatch(lines.first)) return const [];
  final found = <String>[];
  for (var n = 1; n < lines.length; n += 1) {
    final line = lines[n];
    if (_fence.hasMatch(line)) return _once(found);
    final key = _key.firstMatch(line);
    if (key == null) continue;
    final value = key.group(2) ?? '';
    if (value.isNotEmpty) {
      found.addAll(_inline(value));
      continue;
    }
    // A list of lines: each `- name` under the key, until a line that is not one.
    while (n + 1 < lines.length) {
      final next = lines[n + 1];
      final item = _item.firstMatch(next);
      if (item == null || _fence.hasMatch(next)) break;
      final name = _unquote(item.group(1) ?? '');
      if (name.isNotEmpty) found.add(name);
      n += 1;
    }
  }
  // No closing fence within the limit: not front matter, and no aliases.
  return const [];
}

/// The first lines of [body], up to the front matter's limit, each without a carriage return.
List<String> _headLines(String body) {
  final lines = <String>[];
  var from = 0;
  while (lines.length < _mostLines && from <= body.length) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? body.length : next;
    var line = body.substring(from, to);
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    lines.add(line);
    if (next < 0) break;
    from = next + 1;
  }
  return lines;
}

/// A value on the key's own line: `[a, "b"]` or `a, b`.
List<String> _inline(String value) {
  var inside = value;
  if (inside.startsWith('[') && inside.endsWith(']')) inside = inside.substring(1, inside.length - 1);
  return [
    for (final part in _split(inside))
      if (_unquote(part).isNotEmpty) _unquote(part),
  ];
}

/// Splits at commas that are not inside quotes.
List<String> _split(String text) {
  final parts = <String>[];
  final now = StringBuffer();
  String? quote;
  for (var i = 0; i < text.length; i += 1) {
    final c = text[i];
    if (quote != null) {
      now.write(c);
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
      now.write(c);
    } else if (c == ',') {
      parts.add(now.toString());
      now.clear();
    } else {
      now.write(c);
    }
  }
  parts.add(now.toString());
  return parts;
}

/// A name with its quotes off, the way YAML reads them, and trimmed.
String _unquote(String value) {
  final text = value.trim();
  if (text.length >= 2) {
    if (text.startsWith('"') && text.endsWith('"')) return text.substring(1, text.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\').trim();
    if (text.startsWith("'") && text.endsWith("'")) return text.substring(1, text.length - 1).replaceAll("''", "'").trim();
  }
  return text;
}

/// Each name once, by its key, and none whose key is empty.
List<String> _once(List<String> names) {
  if (names.isEmpty) return const [];
  final seen = <String>{};
  return List.unmodifiable([
    for (final name in names)
      if (titleKey(name).isNotEmpty && seen.add(titleKey(name))) name,
  ]);
}

/// The aliases of [note], read once for the body it has now and kept by its id, as the note's other facts are
/// (lib/core/note_facts.dart): asked of every note each time the library's titles are read again.
List<String> aliasesOfNote(Note note) {
  final body = note.body;
  final had = _kept[note.id];
  if (had != null && (identical(had.body, body) || had.body == body)) return had.aliases;
  if (_kept.length >= 32768) _kept.clear();
  final aliases = aliasesOf(body);
  _kept[note.id] = (body: body, aliases: aliases);
  return aliases;
}

final Map<String, ({String body, List<String> aliases})> _kept = <String, ({String body, List<String> aliases})>{};
