/// A name on any line of a note, and the places inside a note a link can point at: a block's `^name` and a
/// heading. What `[[Note#^name]]` and `[[Note#Heading]]` open at, what `![[Note#^name]]` and `![[Note#Heading]]`
/// draw, and the name Copy link to this line gives a line that has none (lib/links/line_link.dart).
///
///     The ferry leaves at nine from Cais do Sodré. ^ferry
///
/// A list item has had its name this way since boards (lib/core/item_syntax.dart `anchorSpan`, docs/BOARDS.md);
/// Obsidian gives any paragraph one the same way, and so does this. The name is the same shape a board's anchor
/// is, lower case letters, digits, `-` and `_`, so one name is one thing to every piece that reads it. A name in
/// Obsidian's capitals is not read (Obsidian makes its own in lower case).
///
/// Nothing here writes a note but [withBlockId], whose line the editor puts in as an edit.
library;

import 'boards/items.dart' show anchorFor;
import 'front_matter.dart';
import 'item_syntax.dart' show anchorSpan;
import 'note_text.dart' show noteTitle;
import 'title_key.dart';

final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');

/// The name a line ends with, and where it is in the line: its caret at `from`, its name ending at `to`.
({String id, int from, int to})? blockIdOf(String line) => line.contains('^') ? anchorSpan(line) : null;

/// One line of a note, from 1, with its words.
typedef NoteLine = ({int line, int from, String text});

/// The lines of [body] that are words: the front matter and code blocks left out.
Iterable<NoteLine> wordLines(String body) sync* {
  final front = frontMatterSpan(body);
  var number = front.lines + 1;
  var from = front.offset;
  var inFence = false;
  while (from <= body.length) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? body.length : next;
    final text = body.substring(from, to);
    if (_fence.hasMatch(text)) {
      inFence = !inFence;
    } else if (!inFence) {
      yield (line: number, from: from, text: text.endsWith('\r') ? text.substring(0, text.length - 1) : text);
    }
    if (next < 0) break;
    from = next + 1;
    number += 1;
  }
}

/// The line named [id] (without its caret), from 1, or null where no line has that name.
int? blockLine(String body, String id) {
  if (id.isEmpty || !body.contains('^$id')) return null;
  for (final line in wordLines(body)) {
    if (blockIdOf(line.text)?.id == id) return line.line;
  }
  return null;
}

/// A heading of a note: its level, its words, and its line from 1.
typedef Heading = ({int level, String text, int line, int from});

/// The headings of [body], in order, the note's own title among them where it is one.
List<Heading> headingsOf(String body) {
  if (!body.contains('#')) return const [];
  return [
    for (final line in wordLines(body))
      if (line.text.startsWith('#'))
        if (_heading.firstMatch(line.text) case final found?)
          if ((found.group(2) ?? '').isNotEmpty) (level: found.group(1)!.length, text: found.group(2)!, line: line.line, from: line.from),
  ];
}

/// The first heading whose words are [words] as a title is matched, or null.
Heading? headingNamed(String body, String words) {
  final key = titleKey(words);
  if (key.isEmpty) return null;
  for (final heading in headingsOf(body)) {
    if (titleKey(heading.text) == key) return heading;
  }
  return null;
}

/// The line a link's anchor points at in [body], from 1: `^name` a named line, anything else a heading's words.
int? anchorLine(String body, String anchor) {
  final at = anchor.trim();
  if (at.isEmpty) return null;
  if (at.startsWith('^')) return blockLine(body, at.substring(1));
  return headingNamed(body, at)?.line;
}

final RegExp _listLead = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s');

/// What `![[Note#anchor]]` draws of [body]: under a heading, the heading and what follows it up to the next heading
/// as high or higher; a named line, the line, and a list item's own items under it with it. Null where the anchor
/// names nothing in the note. The words as written, the name's `^` and all.
String? sectionOf(String body, String anchor) {
  final at = anchor.trim();
  if (at.isEmpty) return null;
  final lines = body.split('\n');
  if (at.startsWith('^')) {
    final number = blockLine(body, at.substring(1));
    if (number == null) return null;
    final first = lines[number - 1];
    final lead = _listLead.firstMatch(first);
    final out = <String>[first];
    if (lead != null) {
      final indent = lead.group(1)!.length;
      for (var i = number; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trim().isEmpty) break;
        final own = line.length - line.trimLeft().length;
        if (own <= indent) break;
        out.add(line);
      }
    }
    return out.join('\n');
  }
  final heading = headingNamed(body, at);
  if (heading == null) return null;
  final out = <String>[lines[heading.line - 1]];
  final later = headingsOf(body).where((each) => each.line > heading.line && each.level <= heading.level).firstOrNull;
  final end = later == null ? lines.length : later.line - 1;
  for (var i = heading.line; i < end; i += 1) {
    out.add(lines[i]);
  }
  return out.join('\n').trimRight();
}

/// Every name the lines of [body] have, items' and paragraphs' alike.
Set<String> blockIdsIn(String body) => {
      if (body.contains('^'))
        for (final line in wordLines(body))
          if (blockIdOf(line.text) case final found?) found.id,
    };

final RegExp _trailing = RegExp(r'\s+$');
final RegExp _lead = RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)*');

/// A name for [line], made from its first words that say something (as a board names an item: `anchorFor`), and
/// none [taken].
String blockIdFor(String line, Iterable<String> taken) {
  final words = line.replaceFirst(_lead, '');
  return anchorFor(words.isEmpty ? 'line' : words, taken);
}

/// [line] with ` ^id` at its end, the spaces at its end first taken off; a line with a name already as it is.
String withBlockId(String line, String id) => blockIdOf(line) != null ? line : '${line.replaceFirst(_trailing, '')} ^$id';

/// The link to a place in a note as Obsidian writes it: `[[Title#^name]]`, or `[[Title#Heading]]`.
String placeLink(String title, String anchor) => '[[$title#$anchor]]';

/// [body]'s title as a link names it: [noteTitle], with the characters a link cannot hold taken out.
String linkTitle(String body) => noteTitle(body).replaceAll(RegExp(r'[\[\]|#^]'), '').trim();
