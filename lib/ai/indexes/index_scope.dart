/// Which notes an index covers, and the parts of it the app works out without an AI: who owns what and what changed
/// last (docs/AI_INDEXES.md §1, §3). Matt, 2026-11-02: "the AI keeps an index note (what's here, the key decisions,
/// who owns what) and updates it as notes change".
library;

import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/title_key.dart' show titleKey;
import '../../note/byline.dart' show authorsOf;

/// The folder a note's [path] is in: `orgs/Acme/Plan/index.md` is `orgs/Acme/Plan`; '' at the top.
String folderOf(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? '' : path.substring(0, at);
}

/// A note's title as its link names it: its own, else its file's name.
String titleOf(Note note) {
  final said = NoteFacts.of(note).title.trim();
  if (said.isNotEmpty) return said;
  final path = note.path ?? note.id;
  final file = path.substring(path.lastIndexOf('/') + 1);
  return file.toLowerCase().endsWith('.md') ? file.substring(0, file.length - 3) : file;
}

/// The notes [folder]'s index covers among [notes]: every markdown note under it, at any depth, out of the trash and
/// the archive, the index's own page ([pageId]) left out. Newest change first.
List<Note> notesIn(String folder, Iterable<Note> notes, {String? pageId}) {
  final under = folder.isEmpty ? '' : '$folder/';
  final found = [
    for (final note in notes)
      if (note.id != pageId && note.path != null && note.path!.startsWith(under) && note.path!.toLowerCase().endsWith('.md') && !note.inTrash && (note.archivedAt ?? 0) == 0) note,
  ];
  found.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return found;
}

/// The front matter keys that name who owns a note: its authors, its owner, a ticket's assignee.
const List<String> ownerKeys = ['owner', 'owners', 'assignee', 'assignees'];

/// The people a note names as its own: `authors:`, then `owner(s):` and `assignee(s):`, comma-separated, `@` and
/// `[[ ]]` taken off, each once.
List<String> ownersOfNote(Note note) {
  final names = <String>[...authorsOf(note.body)];
  for (final key in ownerKeys) {
    final said = frontMatterValue(note.body, key);
    if (said == null) continue;
    names.addAll(said.replaceAll(RegExp(r'[\[\]"]'), '').split(','));
  }
  final seen = <String>{};
  return [
    for (final raw in names)
      if (raw.trim().replaceFirst(RegExp('^@'), '') case final name when name.isNotEmpty && seen.add(name.toLowerCase())) name,
  ];
}

/// Each person to the titles of the notes they own among [notes] (docs/AI_INDEXES.md: "Who owns what"), the people
/// with most notes first. A note names at most its first [most] titles a person.
Map<String, List<String>> ownersIn(List<Note> notes, {int most = 8}) {
  final by = <String, List<String>>{};
  final names = <String, String>{};
  for (final note in notes) {
    for (final who in ownersOfNote(note)) {
      final key = who.toLowerCase();
      names.putIfAbsent(key, () => who);
      final titles = by.putIfAbsent(key, () => []);
      if (titles.length < most) titles.add(titleOf(note));
    }
  }
  final order = by.keys.toList()..sort((a, b) => by[b]!.length.compareTo(by[a]!.length));
  return {for (final key in order) names[key]!: by[key]!};
}

/// The [most] notes changed last, with their days.
List<(String, String)> recentIn(List<Note> notes, {int most = 8}) => [
      for (final note in notes.take(most)) (titleOf(note), dayOf(DateTime.fromMillisecondsSinceEpoch(note.updatedAt))),
    ];

/// `YYYY-MM-DD` of [at], in the device's own day.
String dayOf(DateTime at) => '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

/// Each title's key to its note, the first note to claim a title keeping it: what turns the AI's answer about a note
/// back into a link to a real one.
Map<String, Note> byTitle(List<Note> notes) {
  final found = <String, Note>{};
  for (final note in notes) {
    found.putIfAbsent(titleKey(titleOf(note)), () => note);
  }
  return found;
}
