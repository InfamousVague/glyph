/// List items and their marks: which items are not linked to anything yet, and what one becomes when it is. A port
/// of `src/app/core/itemLinks.ts`, one to one.
///
/// The one form, everywhere: a linked item keeps its words as they are and ends with a mark - a link whose words are
/// the lowercase name of what it is linked to, `- [ ] Buy milk [notion](https://www.notion.so/…)`. Matt: "we need a
/// common format for linking Notion pages to list items, as the AI will change how this looks when formatting or
/// enhancing". The words used to be the link, `[Buy milk](https://…)`, and a rewrite that moved or dropped the link
/// left the item looking unsent; a mark at the end is one small thing the model is told to keep in place, the editor
/// draws it as a pill, and the formatter puts it back on the item it came from when a model loses it. The old form
/// still counts as linked, so a note from before is never sent twice.
///
/// A board's name for the item (docs/BOARDS.md) comes after the mark: `- [ ] Buy milk [notion](…) ^buy-milk`. The
/// mark is last but for that, and every reader and writer here knows it - a mark written after the anchor left the
/// board unable to find the item, and the anchor sent to Notion as part of the task's title.
///
/// So "not linked yet" is a to-do or bullet with no mark and no link in its words, and linking a whole list twice
/// links nothing the second time. Ticked to-dos are left alone: a done thing is not a task to make. Plugins use
/// these for what they link items to (the Notion plugin's tasks). Pure, so every shape of line is a test.
///
/// An item the AI filled (docs/DESIGN.md §145) says its answer's words: the hidden bracket on `??Turn off the
/// water??(Qwen3.5 4B from memory, …)` is never a task's title, nor read aloud on home's To do. An item still
/// holding a blank is a question, not a task yet, so it is not sent, and it reads as its question's words where it
/// is shown.
///
/// What differs: `Item` and `ItemMark` are classes with value equality where the web has interfaces. The names a
/// mark can carry are kept in this library, as the web keeps them in its module, and start as `notion` alone.
library;

import 'blanks_syntax.dart' show hasBlank, readableWords;
import 'item_syntax.dart';
import 'task_fields.dart' show withoutFields;

/// A list item's line in two: what opens it (the indent, the marker, and a to-do's or a choice's box, as
/// item_syntax.dart reads them) and the rest, with whether its box is ticked. Null for a line that is not an item.
({String lead, String rest, bool ticked})? _item(String line) {
  final lead = listLead(line);
  return lead != null ? (lead: line.substring(0, lead.wordsAt), rest: line.substring(lead.wordsAt), ticked: lead.done == true) : null;
}

/// The mark: the last thing on a line but a board's anchor, a link whose words are one lowercase name.
final RegExp _markAtEnd = RegExp('\\s*\\[($markNamePattern)\\]\\(($markUrlPattern)\\)\\s*\$');

/// What may come after an item's mark, at the very end of its line (item_syntax.dart `itemTailPattern`): a board's
/// anchor and counters, in any order. An anchor needs whitespace, or nothing, before its caret and the end of the
/// line or another of these after its name, which is what leaves `x^2^` the superscript it is.
final RegExp _tailEnd = RegExp('(?:(?:^|\\s+)(?:$itemTailPattern))+\\s*\$');

/// Every counter in an item's words: `[3/8]`, as the editor's counters read it.
final RegExp _counters = RegExp(counterInWordsPattern);

final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingSpace = RegExp(r'\s+$');

String _trimEnd(String text) => text.replaceFirst(_trailingSpace, '');

/// [text] without what comes after its mark, and that tail as written (`[3/8] ^buy-milk`, or '' where there is
/// none).
({String body, String anchor}) _anchorOff(String text) {
  final found = _tailEnd.firstMatch(text);
  return found != null ? (body: text.substring(0, found.start), anchor: jsTrim(found.group(0)!)) : (body: text, anchor: '');
}

/// What an item says, for a title or for finding it again: no counters, which are a count kept on the item rather
/// than part of its name, and no bookmark. A choice's box is already off, with the lead it belongs to. No fields
/// either (task_fields.dart, docs/DESIGN.md §158): a task sent to Notion or an issue to GitHub is titled "Fix the
/// login loop", not "Fix the login loop @sam ⏫ 📅 2026-10-03", and an item that is only fields is not a task to
/// send.
String _said(String text) => jsTrim(withoutBookmark(readableWords(withoutFields(text)).replaceAll(_counters, '')).replaceAll(_spaces, ' '));

/// Words with an anchor put back after them, one space between.
String _withAnchorBack(String words, String anchor) {
  if (anchor.isEmpty) return words;
  return jsTrim(words).isNotEmpty ? '${_trimEnd(words)} $anchor' : anchor;
}

/// A list item that can be sent (`Item`).
class Item {
  const Item({required this.line, required this.text});

  /// 1-based line number in the note.
  final int line;

  /// The words, without the marker and without a mark.
  final String text;

  @override
  bool operator ==(Object other) => other is Item && other.line == line && other.text == text;

  @override
  int get hashCode => Object.hash(line, text);

  @override
  String toString() => 'Item($line, $text)';
}

/// An item's mark, read (`ItemMark`).
class ItemMark {
  const ItemMark({required this.name, required this.url});

  /// What it is linked to: "notion".
  final String name;
  final String url;

  @override
  bool operator ==(Object other) => other is ItemMark && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);

  @override
  String toString() => 'ItemMark($name, $url)';
}

/// The names a mark can carry: the ids of the plugins that link items, told here as they load. Without this, "read
/// the [docs](…)" at the end of an item would be a mark called docs.
final Set<String> _markNames = {'notion'};

/// Adds [name] to the names a mark can carry.
void registerMarkName(String name) => _markNames.add(name.toLowerCase());

/// Whether [name] is one a mark can carry.
bool isMarkName(String name) => _markNames.contains(name);

/// The mark at the end of [text], a board's anchor aside, if it has one.
ItemMark? markOf(String text) {
  final match = _markAtEnd.firstMatch(_anchorOff(text).body);
  return match != null && isMarkName(match.group(1) ?? '') ? ItemMark(name: match.group(1) ?? '', url: match.group(2) ?? '') : null;
}

/// [text] without its mark; a board's anchor after it stays.
String unmarked(String text) {
  final (:body, :anchor) = _anchorOff(text);
  final bare = markOf(body) != null ? _trimEnd(body.replaceFirst(_markAtEnd, '')) : _trimEnd(body);
  return _trimEnd(_withAnchorBack(bare, anchor));
}

/// The words of a list item line: marker, mark and a board's anchor aside - what the item says, and what is sent as
/// a task's title. Null for a line that is not an item.
String? itemWords(String lineText) {
  final found = _item(lineText);
  if (found == null) return null;
  final body = _anchorOff(found.rest).body;
  return _said(markOf(body) != null ? body.replaceFirst(_markAtEnd, '') : body);
}

/// [lineText] with [mark] (`[notion](…)`, as written) added where a mark goes: at the end, before a board's anchor
/// if the line has one.
String withMark(String lineText, String mark) {
  final (:body, :anchor) = _anchorOff(lineText);
  return _withAnchorBack('${_trimEnd(body)} $mark', anchor);
}

final RegExp _linkInWords = RegExp(r'\[[^\]]+\]\(https?:\/\/[^)]+\)');

/// Whether an item's words are already linked: a mark, or the old form with a link in the words.
bool _linked(String text) => markOf(text) != null || _linkInWords.hasMatch(text);

/// Every list item not linked yet, in note order.
List<Item> unsentItems(String body) {
  final items = <Item>[];
  final lines = body.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final found = _item(lines[index]);
    if (found == null) continue;
    // The anchor is the board's name for the item, not part of what it says, and a counter or a choice's box is not
    // part of its name: none of them is sent.
    final whole = jsTrim(_anchorOff(jsTrim(found.rest)).body);
    final text = _said(whole);
    if (text.isEmpty || found.ticked || _linked(whole) || whole.startsWith('![') || hasBlank(whole)) continue;
    items.add(Item(line: index + 1, text: text));
  }
  return items;
}

/// The item on [line] if it is one that can be sent, else null.
Item? itemAt(String lineText, int line) {
  final items = unsentItems(lineText);
  return items.isEmpty ? null : Item(line: line, text: items.first.text);
}

/// [lineText] with a mark to [url] at its end, before a board's anchor; the marker, the indent and the words stay.
String linkedLine(String lineText, String url, [String name = 'notion']) {
  final found = _item(lineText);
  if (found == null) return lineText;
  final (:body, :anchor) = _anchorOff(found.rest);
  final words = jsTrim(unmarked(body));
  // The lead ends in its own space, so an item with no words takes the mark straight after it.
  final mark = '[$name]($url)';
  return '${found.lead}${_withAnchorBack(words.isNotEmpty ? '$words $mark' : mark, anchor)}';
}
