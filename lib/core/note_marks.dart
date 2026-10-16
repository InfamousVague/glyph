/// What a note's words hold that a search operator asks about (lib/core/search_query.dart): its tags, whether it
/// has to-dos open or ticked, a picture, a link. Read once for the body a note has now and kept, as its search
/// text is (note_text.dart `searchText`), so a filter over the whole library is a lookup a note at each letter
/// typed, never a reading of every note.
///
/// **Tags** are the ones a query finds (lib/core/query/records.dart): every `#tag` in the words outside what is
/// quiet for them (front matter, code, maths, an address, an HTML tag, a link's title: blanks_syntax.dart
/// `quietRanges`), and the front matter's `tags:` and `tag:` lists, lower case and without the `#`. A ticket's
/// `labels:` are its labels, not tags, and are not read here.
///
/// **To-dos** are list items with a box (item_syntax.dart `taskBox`) outside the front matter and fenced code, with
/// words after the box: a box with nothing after it is a to-do still being written.
///
/// **A picture** is `![…](…)` that is not a voice memo's `tape:` clip, or an embed of a picture file, `![[x.png]]`.
/// **A link** is a link to another note, `[[…]]`, or an address on the web, outside fenced code.
///
/// Pure, and kept by the note's id ([NoteMarks.of]); [NoteMarks.read] reads a body that is no note's.
library;

import 'blanks_syntax.dart' show quietRanges;
import 'front_matter.dart' show frontMatterEnd;
import 'item_syntax.dart' show taskBox;
import 'note.dart';
import 'properties.dart' show propertiesOf, propertyList;
import 'tags.dart' show tagsIn;

final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _picture = RegExp(r'!\[[^\]\n]*\]\((?!\s*tape:)[^)\n]+\)');
final RegExp _pictureEmbed = RegExp(r'!\[\[[^\]\n]+\.(?:png|jpe?g|gif|webp|heic|avif|svg|bmp)(?:\|[^\]\n]*)?\]\]', caseSensitive: false);
final RegExp _noteLink = RegExp(r'(?<!!)\[\[[^\]\n]+\]\]');
final RegExp _webLink = RegExp(r'https?://[^\s)>\]]+', caseSensitive: false);
final RegExp _clip = RegExp(r'\]\(\s*tape:');
final RegExp _hashes = RegExp(r'^#+');
final RegExp _boxWords = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]\s*(.*)$');

/// One note's marks.
class NoteMarks {
  NoteMarks._(this.tags, {required this.openTodos, required this.doneTodos, required this.picture, required this.link, required this.clip});

  /// Every tag, lower case, without the `#`, each once.
  final Set<String> tags;

  /// How many to-dos are open, and how many ticked.
  final int openTodos;
  final int doneTodos;
  final bool picture;
  final bool link;

  /// A voice memo's clip of the note's tape (`![voice 0:12](tape:…)`).
  final bool clip;

  /// Whether a note with these marks has [tag] or a tag under it: `work` for `#work` and `#work/clients`.
  bool tagged(String tag) {
    if (tags.contains(tag)) return true;
    final under = '$tag/';
    for (final own in tags) {
      if (own.startsWith(under)) return true;
    }
    return false;
  }

  /// [body] read, and not kept.
  factory NoteMarks.read(String body) {
    debugReadings += 1;
    final lines = body.split('\n');
    final front = frontMatterEnd(lines);
    final tags = <String>{};
    // The words' tags, outside what is quiet for them: what is quiet is only worked out for a body with a tag's
    // shape in it, which most are not (a heading's `# ` is no tag).
    final written = body.contains('#') ? tagsIn(body) : const [];
    if (written.isNotEmpty) {
      final quiet = quietRanges(body);
      for (final tag in written) {
        if (!quiet.any((q) => tag.from >= q.from && tag.from < q.to)) tags.add(tag.name);
      }
    }
    if (front > 0) {
      for (final property in propertiesOf(body)) {
        final key = property.key.toLowerCase();
        if (key != 'tags' && key != 'tag') continue;
        for (final item in propertyList(property.value)) {
          final clean = item.replaceFirst(_hashes, '').trim().toLowerCase();
          if (clean.isNotEmpty) tags.add(clean);
        }
      }
    }
    var open = 0, done = 0;
    var picture = false, link = false;
    String? fence;
    for (var index = front; index < lines.length; index += 1) {
      final line = lines[index];
      final marker = _fence.firstMatch(line)?.group(1);
      if (marker != null) {
        fence = fence == null ? marker : (fence == marker ? null : fence);
        continue;
      }
      if (fence != null) continue;
      if (line.contains('[')) {
        final box = taskBox(line);
        if (box != null && (_boxWords.firstMatch(line)?.group(1)?.trim().isNotEmpty ?? true)) {
          if (box.done) {
            done += 1;
          } else {
            open += 1;
          }
        }
        if (!picture && line.contains('![') && (_picture.hasMatch(line) || _pictureEmbed.hasMatch(line))) picture = true;
        if (!link && line.contains('[[') && _noteLink.hasMatch(line)) link = true;
      }
      if (!link && line.contains('://') && _webLink.hasMatch(line)) link = true;
    }
    return NoteMarks._(Set.unmodifiable(tags), openTodos: open, doneTodos: done, picture: picture, link: link, clip: _clip.hasMatch(body));
  }

  static final Map<String, ({String body, NoteMarks marks})> _kept = {};

  /// How many bodies have been read, for a test.
  static int debugReadings = 0;

  /// [note]'s marks, read once for the body it has now (and where the library hands back the same words in a new
  /// string, the reading takes the new string and lets the old go).
  static NoteMarks of(Note note) {
    final body = note.body;
    final had = _kept[note.id];
    if (had != null) {
      if (identical(had.body, body)) return had.marks;
      if (had.body == body) {
        _kept[note.id] = (body: body, marks: had.marks);
        return had.marks;
      }
    }
    if (_kept.length >= 32768) _kept.clear();
    final marks = NoteMarks.read(body);
    _kept[note.id] = (body: body, marks: marks);
    return marks;
  }

  /// Forgets every reading: for a test.
  static void debugForget() {
    _kept.clear();
    debugReadings = 0;
  }
}
