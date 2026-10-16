/// An Obsidian note made to read in Ghost.md as it read in Obsidian, without changing what it says. Pure.
///
/// - **Its name.** In Obsidian a note's name is its file's: `[[2026-10-15]]` finds `2026-10-15.md` whatever its first
///   line says. In Ghost.md a note's name is its first line, or the `title:` its front matter gives
///   (lib/core/note_text.dart `noteTitle`), and a `[[link]]` finds a note by that name. So a note whose first line is
///   not its file's name is given `title: "<the file's name>"`, the key the app itself writes when a note is named in
///   its More sheet; one that already says a `title:` keeps its own.
/// - **Its front matter**, read by the app only as lines that are each a `key:` (lib/core/front_matter.dart), where
///   Obsidian writes a list down the page:
///
///       tags:              tags: [start, garden]
///         - start    ->
///         - garden
///
///   The same list, written across, which Obsidian and YAML read as the same thing. A block that holds anything else
///   the app cannot read (a comment, a long string over several lines) is left exactly as it was.
library;

import '../core/front_matter.dart' show frontMatterLines, quotedTitle;
import '../core/note_text.dart' show noteTitle;
import '../core/title_key.dart';

final RegExp _fence = RegExp(r'^(---|\.\.\.)\s*$');
final RegExp _emptyKey = RegExp(r'^([\w.-]+)\s*:\s*$');
final RegExp _item = RegExp(r'^\s+-\s+(.*?)\s*$|^\s*-\s*$');
final RegExp _held = RegExp(r'^\s*[\w.-]+\s*:');
final RegExp _titleKey = RegExp(r'^\s*title\s*:', caseSensitive: false);
final RegExp _plain = RegExp(r'''^[^,\[\]{}#&*!|>'"%@`:]+$''');

/// One item of a list as a flow list holds it: as written where nothing in it would be misread, else in quotes.
String _flowItem(String item) {
  if (item.isEmpty) return '""';
  if ((item.startsWith('"') && item.endsWith('"') && item.length > 1) || (item.startsWith("'") && item.endsWith("'") && item.length > 1)) return item;
  if (_plain.hasMatch(item) && item.trim() == item) return item;
  return '"${item.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// Where [lines]' front matter closes (the index of its closing fence), or -1 where it has none the app would see.
int _closing(List<String> lines) {
  if (lines.isEmpty || lines.first.trim() != '---') return -1;
  for (var i = 1; i < lines.length; i += 1) {
    if (_fence.hasMatch(lines[i])) return i;
  }
  return -1;
}

/// [text] with its front matter's lists written across, where that is all that kept the app from reading the block.
String readableFrontMatter(String text) {
  final lines = text.split('\n');
  final close = _closing(lines);
  if (close < 0) return text;
  final block = lines.sublist(1, close);
  final out = <String>[];
  var changed = false;
  for (var i = 0; i < block.length; i += 1) {
    final key = _emptyKey.firstMatch(block[i]);
    if (key != null && i + 1 < block.length && _item.hasMatch(block[i + 1])) {
      final items = <String>[];
      while (i + 1 < block.length && _item.hasMatch(block[i + 1])) {
        i += 1;
        items.add(_item.firstMatch(block[i])!.group(1) ?? '');
      }
      out.add('${key.group(1)}: [${items.map(_flowItem).join(', ')}]');
      changed = true;
      continue;
    }
    out.add(block[i]);
  }
  final readable = out.every((line) => line.trim().isEmpty || _held.hasMatch(line)) && out.length + 2 <= frontMatterLines;
  if (!changed || !readable) return text;
  return ['---', ...out, '---', ...lines.sublist(close + 1)].join('\n');
}

/// [text] named for its file, [stem], where its first line is not that name and it says no `title:` of its own.
String namedForFile(String text, String stem) {
  final lines = text.split('\n');
  final close = _closing(lines);
  if (close > 0 && lines.sublist(1, close).any(_titleKey.hasMatch)) return text;
  final title = noteTitle(text);
  // A name with no letters the app matches by (one all in Japanese, say) is held to its first line as written.
  final same = titleKey(stem).isEmpty ? title.trim() == stem.trim() : sameTitle(title, stem);
  if (same || stem.trim().isEmpty) return text;
  final named = 'title: ${quotedTitle(stem, stem)}';
  if (close > 0) return ['---', named, ...lines.sublist(1)].join('\n');
  return '---\n$named\n---\n$text';
}

/// Both, as the importer asks them of each note.
String obsidianNoteBody(String text, String stem) => namedForFile(readableFrontMatter(text), stem);
