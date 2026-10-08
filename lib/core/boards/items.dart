/// The items a board points at: a list item read as a card's item - its anchor, its words, its box - the anchor made
/// for one that has none, and the anchor pointed at from the words, `[[#^ask-sam]]`. A port of
/// `src/app/core/boards/items.ts`, one to one.
///
/// How the line is spelled is item_syntax.dart; what its parts mean to a board is here. Any list item that ends with
/// an anchor is an item - a bullet, a number or a to-do, all the same - and a card IS its item, so every card's words
/// and box are read through these (docs/BOARDS.md).
///
/// What differs: the shapes. `Item` and `ItemRef` are small immutable classes with value equality where the web has
/// interfaces; `anchorFor` takes any `Iterable` of the anchors taken; `String.prototype.trim` is `jsTrim`.
library;

import '../blanks_syntax.dart' show readableWords;
import '../item_syntax.dart'
    show anchorNamePattern, anchorSpan, counterPattern, jsTrim, listLead, taskBox, withoutAnchor, withoutBookmark;
import '../task_fields.dart' show withoutFields;

/// A list item a board can point at (`Item`).
class Item {
  const Item({required this.id, required this.text, required this.done, required this.line});

  /// The anchor that names it.
  final String id;

  /// The words, without the list marker, the tick box or the anchor.
  final String text;

  /// Ticked, unticked, or null for an item with no box at all: a bullet or a numbered step.
  final bool? done;

  /// Which line of the note it is on, counting from 1.
  final int line;

  @override
  bool operator ==(Object other) => other is Item && other.id == id && other.text == text && other.done == done && other.line == line;

  @override
  int get hashCode => Object.hash(id, text, done, line);

  @override
  String toString() => 'Item($id, "$text", done: $done, line: $line)';
}

/// A list item pulled apart: whether it has a box, its words, and the anchor naming it.
typedef _Parsed = ({bool? done, String text, String? id});

/// A list item read the way item_syntax.dart spells it. The words are what is left between the lead and the anchor:
/// a choice's box is not part of what the item says, and not a tick either; the bookmark is a place in the note, not
/// something the item says, so no card, title or anchor has it; and a mark or counter written after the anchor stays
/// with the words it belongs to.
_Parsed? _parse(String line) {
  final lead = listLead(line);
  if (lead == null) return null;
  final rest = line.substring(lead.wordsAt);
  final span = anchorSpan(rest);
  return (done: lead.done, text: jsTrim(withoutBookmark(withoutAnchor(rest, span))), id: span?.id);
}

/// `[[#^ask-sam]]`: an item in this note, pointed at from anywhere in it.
final RegExp _ref = RegExp('\\[\\[#\\^($anchorNamePattern)\\]\\]');

/// Every anchored item in the note, the first of a repeated anchor winning.
List<Item> itemsIn(String doc) {
  final items = <Item>[];
  final seen = <String>{};
  final lines = doc.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final item = itemOnLine(lines[index]);
    if (item == null || !seen.add(item.id)) continue;
    items.add(Item(id: item.id, text: item.text, done: item.done, line: index + 1));
  }
  return items;
}

/// The item a line is, if it is a list item with an anchor.
Item? itemOnLine(String line) {
  final found = _parse(line);
  final id = found?.id;
  return found != null && id != null && id.isNotEmpty ? Item(id: id, text: found.text, done: found.done, line: 0) : null;
}

/// Whether a line is a list item at all: what can be given an anchor and put on a board.
bool isItemLine(String line) {
  final found = _parse(line);
  return found != null && (found.text.isNotEmpty || (found.id ?? '').isNotEmpty);
}

/// The words of a list item, box and anchor off, or null where the line is not one.
String? itemWords(String line) => _parse(line)?.text;

/// That line with its box ticked or cleared: the one character between the brackets, and nothing else about the line
/// touched. An item with no box is left alone, since there is nothing to tick and writing a box is the person's to do.
String setItemDone(String line, bool done) {
  final box = taskBox(line);
  if (box == null) return line;
  return '${line.substring(0, box.at + 1)}${done ? 'x' : ' '}${line.substring(box.at + 2)}';
}

final RegExp _trailingSpace = RegExp(r'\s+$');

/// That line given an anchor, or left as it is when it has one already.
String withAnchor(String line, String id) => itemOnLine(line) != null ? line : '${line.replaceFirst(_trailingSpace, '')} ^$id';

/// Every counter in an item's words (editor/counters.ts): a count kept on the item, never part of its name.
final RegExp _counters = RegExp(counterPattern);

/// Words that say nothing about which item this is: an anchor made of "add-ability-to" names two different items
/// the same way, and is the name someone then has to point at.
final Set<String> _filler =
    'a an the to of in on at by for from with into onto and or but nor so is are was were be been being it its this that these those as up out'
        .split(' ')
        .toSet();

final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _notAnchorLetters = RegExp('[^a-z0-9]+');

/// An anchor made from an item's words: its first three words that carry meaning, lower case, and not one the note
/// already uses. "Add ability to auto-tag notes" is `add-ability-auto`, not `add-ability-to`; words that are all
/// filler ("To do") keep them rather than come out empty.
String anchorFor(String text, Iterable<String> taken) {
  // A due day or a person is not what the item is called: "Call @sam 📅 2026-10-03" is `call`, not `call-sam-2026`.
  final words = withoutBookmark(
    withoutFields(text)
        // A link is named by its words, not by where it points: [notion](https://…) anchors as "notion", never as a URL.
        .replaceAllMapped(_link, (m) => m.group(1) ?? '')
        // A counter is a count kept on the item, and the bookmark a place in the note: neither is part of its name.
        .replaceAll(_counters, ' '),
  ).toLowerCase().replaceAll(_notAnchorLetters, '-').split('-').where((word) => word.isNotEmpty).toList();
  final telling = words.where((word) => !_filler.contains(word)).toList();
  final joined = (telling.isNotEmpty ? telling : words).take(3).join('-');
  final base = joined.isNotEmpty ? joined : 'item';
  if (!taken.contains(base)) return base;
  for (var n = 2; ; n += 1) {
    final tried = '$base-$n';
    if (!taken.contains(tried)) return tried;
  }
}

/// Where an anchor is pointed at from: `[[#^ask-sam]]`, anywhere in a line, counting positions from `offset`
/// (`ItemRef`).
///
/// This is the anchor used as prose rather than as a card, and it is why the anchor is worth having on every kind of
/// item: "the copy is waiting on [[#^ask-sam]]" reads as words anywhere, and in Glyph it is a way back to the line.
class ItemRef {
  const ItemRef({required this.from, required this.to, required this.id});

  final int from;
  final int to;
  final String id;

  @override
  bool operator ==(Object other) => other is ItemRef && other.from == from && other.to == to && other.id == id;

  @override
  int get hashCode => Object.hash(from, to, id);

  @override
  String toString() => 'ItemRef($from, $to, $id)';
}

/// Every pointer at an anchor in [text], in order, counting positions from [offset].
List<ItemRef> refsIn(String text, [int offset = 0]) => [
  for (final match in _ref.allMatches(text)) ItemRef(from: offset + match.start, to: offset + match.end, id: match.group(1) ?? ''),
];

/// The item an anchor names, wherever it is in the note, or null.
Item? itemAt(String doc, String id) {
  for (final item in itemsIn(doc)) {
    if (item.id == id) return item;
  }
  return null;
}

/// An anchor written as a pointer to it, for anything that offers to write one.
String refFor(String id) => '[[#^$id]]';

final RegExp _linkOrPicture = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final RegExp _autolink = RegExp(r'<((?:https?|mailto):[^>]+)>');
final RegExp _marks = RegExp(r'[*_`~]');
final RegExp _spaces = RegExp(r'\s+');

/// An item's words as a card says them: links by their own words, not by where they point, a pointer at another item
/// by its anchor, and the marks that would be drawn as bold or code taken off. The note keeps every character; this
/// is only what the card shows.
///
/// Its fields are not its words (task_fields.dart, docs/DESIGN.md §158): a due day, a priority and a person are the
/// card's chips (editor/boards/fields.ts), so "Fix the login loop @sam ⏫ 📅 2026-10-03" says "Fix the login loop".
String cardText(String text) {
  // A filled blank as its answer's words and a blank as its question (docs/DESIGN.md §145): no card shows a bracket.
  return jsTrim(
    withoutBookmark(readableWords(withoutFields(text)))
        .replaceAllMapped(_ref, (m) => '^${m.group(1) ?? ''}')
        .replaceAllMapped(_linkOrPicture, (m) => m.group(1) ?? '')
        .replaceAllMapped(_autolink, (m) => m.group(1) ?? '')
        .replaceAll(_marks, '')
        .replaceAll(_spaces, ' '),
  );
}
