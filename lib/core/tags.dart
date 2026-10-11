/// A tag's grammar, read here and drawn in the editor (Matt: "add ability to make tags on list items"). A port of
/// `src/app/core/tags.ts`, one to one.
///
///     - [ ] Ship the pricing page #web #launch
///
/// Written the way Obsidian and Bear write them, so a note reads the same elsewhere: a `#` straight against a letter,
/// then letters, digits, `_`, `-` or `/` (for `#work/clients`). A `#` with a space after it is a heading, a `#` inside
/// a word or a link is part of that. On a linked item, tags go with the words, before the mark and the anchor:
/// `- [ ] Ship it #web [notion](…) ^ship`.
///
/// Here in core and not beside the drawing, because two readers away from the editor need the same answer: a query's
/// `from: #bug` (docs/DESIGN.md §156), which reads notes the editor has never opened, and the fields' writer
/// (task_fields.dart), which keeps Obsidian Tasks' fields at the end of an item's words with its tags among them.
/// Pure, and it imports nothing. What counts as code or an address is the caller's to say: the editor asks its
/// parser.
///
/// What differs: the names. The web's `TAG` is [tagPattern], and its `Tag` interface is the class [Tag].
library;

/// A tag: after the line's start or a space or an opening bracket, `#`, a letter, then the rest of the name (`TAG`).
final RegExp tagPattern = RegExp(r'(^|[\s([{])(#[\p{L}][\p{L}\p{N}_/-]*)', unicode: true);

final RegExp _trailing = RegExp(r'[-/]+$');

/// One tag in a text (`Tag`).
class Tag {
  const Tag({required this.from, required this.to, required this.name});

  /// Where the `#` is.
  final int from;

  /// The end of the name.
  final int to;

  /// The name without the `#`, lower-cased: how two tags are compared.
  final String name;

  @override
  bool operator ==(Object other) => other is Tag && other.from == from && other.to == to && other.name == name;

  @override
  int get hashCode => Object.hash(from, to, name);

  @override
  String toString() => 'Tag($from, $to, $name)';
}

/// Every tag in [text], counting positions from [offset]. A trailing `-` or `/` is punctuation, not the name.
List<Tag> tagsIn(String text, [int offset = 0]) {
  final found = <Tag>[];
  for (final match in tagPattern.allMatches(text)) {
    final written = (match.group(2) ?? '').replaceFirst(_trailing, '');
    final from = offset + match.start + (match.group(1) ?? '').length;
    found.add(Tag(from: from, to: from + written.length, name: written.substring(1).toLowerCase()));
  }
  return found;
}
