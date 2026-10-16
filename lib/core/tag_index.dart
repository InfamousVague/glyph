/// Every tag in the library, with how many notes carry it, as the Tags page lists them (lib/notes/tags_screen.dart),
/// and the one change a tag is given there: a new name across every note ([renameTagIn]).
///
/// A note's tags are its marks' (lib/core/note_marks.dart): every `#tag` in its words outside code and the other
/// quiet places, and its front matter's `tags:` and `tag:` lists, compared in lower case. A tag with a `/` in it is
/// a tag inside another (`#work/clients` is under `#work`), and the page draws them as a tree that folds: a tag's
/// count is of the notes with it or with any tag under it, each note once. A tag that is only ever written with
/// something under it (`#work/clients`, never `#work`) still has its place in the tree, with nothing of its own.
///
/// Counted over the notes a list shows: the archive is left out, as a search leaves it out. A rename reaches the
/// archive too, so a tag reads the same wherever it is.
library;

import 'blanks_syntax.dart' show quietRanges;
import 'front_matter.dart' show frontMatterEnd;
import 'note.dart';
import 'note_facts.dart' show NotesMemo;
import 'note_marks.dart';
import 'properties.dart' show propertyList;
import 'tags.dart' show tagsIn;

/// How the Tags page orders its tags: the most used first, or by name.
enum TagSort { count, name }

/// A tag in the tree: its whole name (`work/clients`), the part the tree shows (`clients`), how many notes carry
/// it as it is ([own]) and how many carry it or a tag under it ([count]), and the tags under it.
class TagNode {
  TagNode._(this.name, this.label);

  final String name;
  final String label;
  int own = 0;
  int count = 0;
  final List<TagNode> children = [];

  /// How deep it is: 0 at the top.
  int get depth => '/'.allMatches(name).length;
}

/// The library's tags: which notes carry each, and the tree.
class TagIndex {
  TagIndex._(this.notes, this._byTag);

  /// The notes counted: not archived.
  final List<Note> notes;
  final Map<String, List<Note>> _byTag;

  /// Every tag as it is written, lower case, in no order.
  Iterable<String> get names => _byTag.keys;

  /// How many different tags there are.
  int get length => _byTag.length;

  /// The notes carrying [tag] itself or a tag under it, each once, in the order they were given.
  List<Note> notesUnder(String tag) {
    final under = '$tag/';
    final seen = <String>{};
    final out = <Note>[];
    for (final note in notes) {
      final marks = NoteMarks.of(note);
      if ((marks.tags.contains(tag) || marks.tags.any((own) => own.startsWith(under))) && seen.add(note.id)) out.add(note);
    }
    return out;
  }

  /// How many notes carry [tag] or a tag under it.
  int countOf(String tag) => notesUnder(tag).length;

  final Map<TagSort, List<TagNode>> _trees = {};

  /// The tags as a tree, each level in [sort]'s order; made once for each order. Not to be changed.
  List<TagNode> tree([TagSort sort = TagSort.count]) => _trees[sort] ??= _tree(sort);

  List<TagNode> _tree(TagSort sort) {
    final nodes = <String, TagNode>{};
    TagNode nodeOf(String name) => nodes[name] ??= TagNode._(name, name.contains('/') ? name.substring(name.lastIndexOf('/') + 1) : name);
    for (final entry in _byTag.entries) {
      final parts = entry.key.split('/');
      for (var i = 1; i <= parts.length; i += 1) {
        nodeOf(parts.sublist(0, i).join('/'));
      }
      nodeOf(entry.key).own = entry.value.length;
    }
    final top = <TagNode>[];
    for (final node in nodes.values) {
      final at = node.name.lastIndexOf('/');
      if (at < 0) {
        top.add(node);
      } else {
        nodes[node.name.substring(0, at)]!.children.add(node);
      }
    }
    // Each note once in a count, whichever of the tags under a tag it carries.
    for (final note in notes) {
      final under = <String>{};
      for (final tag in NoteMarks.of(note).tags) {
        final parts = tag.split('/');
        for (var i = 1; i <= parts.length; i += 1) {
          under.add(parts.sublist(0, i).join('/'));
        }
      }
      for (final name in under) {
        nodes[name]?.count += 1;
      }
    }
    void order(List<TagNode> level) {
      level.sort((a, b) {
        if (sort == TagSort.count) {
          final by = b.count.compareTo(a.count);
          if (by != 0) return by;
        }
        return a.name.compareTo(b.name);
      });
      for (final node in level) {
        order(node.children);
      }
    }

    order(top);
    return top;
  }
}

final NotesMemo<TagIndex> _indexes = NotesMemo<TagIndex>();

/// The tags of [notes], the archive left out; kept for the notes it was made from.
TagIndex tagIndex(List<Note> notes) => _indexes.of(notes, () {
      final live = [for (final note in notes) if ((note.archivedAt ?? 0) == 0) note];
      final byTag = <String, List<Note>>{};
      for (final note in live) {
        for (final tag in NoteMarks.of(note).tags) {
          (byTag[tag] ??= <Note>[]).add(note);
        }
      }
      return TagIndex._(List.unmodifiable(live), byTag);
    });

/// A tag's name as a person may give one (lib/core/tags.dart): a letter, then letters, digits, `_`, `-` or `/`,
/// not ending in `-` or `/`; the `#` is left off.
final RegExp _name = RegExp(r'^[\p{L}][\p{L}\p{N}_/-]*$', unicode: true);

/// Whether [name] can be a tag's name.
bool isTagName(String name) => _name.hasMatch(name) && !name.endsWith('/') && !name.endsWith('-') && !name.contains('//');

/// A name typed for a tag, tidied: the `#` and the spaces round it off.
String tidyTagName(String typed) => typed.trim().replaceFirst(RegExp(r'^#+'), '').trim();

final RegExp _propertyLine = RegExp(r'^(\s*)(tags?)(\s*:\s*)(.*)$', caseSensitive: false);

/// [body] with the tag [from] called [to] wherever it is a tag: every `#from`, and every `#from/…` under it, in the
/// words outside code and the other quiet places, and each item of the front matter's `tags:` and `tag:` lists. The
/// rest of each tag is kept as it was written (`#Work/Clients` to `#office/Clients`). [body] itself, the same
/// string, where it has no such tag. [from] is compared in lower case; [to] is written as given.
String renameTagIn(String body, String from, String to) {
  final old = from.toLowerCase();
  if (old.isEmpty || !body.contains(RegExp(RegExp.escape(old), caseSensitive: false))) return body;
  bool matches(String name) => name == old || name.startsWith('$old/');

  // The front matter's lists, a line at a time.
  final lines = body.split('\n');
  final front = frontMatterEnd(lines);
  var frontChanged = false;
  for (var i = 1; i < front - 1; i += 1) {
    final m = _propertyLine.firstMatch(lines[i]);
    if (m == null) continue;
    final value = m[4]!.trim();
    final items = propertyList(value);
    if (!items.any((item) => matches(item.replaceFirst(RegExp(r'^#+'), '').trim().toLowerCase()))) continue;
    final renamed = [
      for (final item in items)
        () {
          final hashes = RegExp(r'^#*').firstMatch(item)![0]!;
          final bare = item.substring(hashes.length).trim();
          return matches(bare.toLowerCase()) ? '$hashes$to${bare.substring(old.length)}' : item;
        }(),
    ];
    final flow = value.startsWith('[') && value.endsWith(']');
    lines[i] = '${m[1]}${m[2]}${m[3]}${flow ? '[${renamed.join(', ')}]' : renamed.join(', ')}';
    frontChanged = true;
  }
  var text = frontChanged ? lines.join('\n') : body;

  // The words' tags, from the last, so each place found still stands where it was.
  final written = tagsIn(text).where((tag) => matches(tag.name)).toList();
  if (written.isEmpty) return frontChanged ? text : body;
  final quiet = quietRanges(text);
  for (final tag in written.reversed) {
    if (quiet.any((q) => tag.from >= q.from && tag.from < q.to)) continue;
    // After the `#`, as long as the old name, whatever its case.
    text = text.replaceRange(tag.from + 1, tag.from + 1 + old.length, to);
  }
  return text == body ? body : text;
}

/// What renaming [from] to [to] would change: each note whose words it changes, with its new words. The archive's
/// notes are among them.
List<({Note note, String body})> tagRenames(Iterable<Note> notes, String from, String to) => [
      for (final note in notes)
        if (renameTagIn(note.body, from, to) case final next when !identical(next, note.body) && next != note.body) (note: note, body: next),
    ];
