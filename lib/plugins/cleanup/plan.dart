/// The cleanup's plan: what the folder is ([CleanupScope]), what may be asked ([CleanupOptions]), every suggestion as an
/// item with an id the review ticks ([CleanupItem]), and the reader that turns the AI's JSON into items, dropping what
/// is wrong rather than failing (docs/CLEANUP.md, "The plan the AI answers with"; Matt, 2026-11-02: "spawn a task
/// making a 'cleanup' plugin that allows us to use whatever AI we choose that's connected to clean up and sort the
/// notes in a given folder").
///
/// The AI never sees an id: a batch names its notes `n1`… and the folders `f0` (the chosen one), `f1`…, and a new
/// folder it proposes is `new1`…. [readBatch] maps them back and checks every one against the batch, the scope and the
/// rules; [CleanupPlan.join] puts the batches together, one new folder per name, one merge per note, and the
/// duplicates the app found itself.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/title_key.dart' show titleKey;
import 'text.dart';

// ---- what is asked ------------------------------------------------------------------------------------------------

/// The passes, in the order the review shows them and the page lists them.
enum CleanupPass {
  sort('Sort', 'Sub-folders, and which notes go in each', true, true),
  titles('Titles', 'A better title where there is none, a date alone, or one that doesn’t fit', true, true),
  duplicates('Duplicates', 'The same note twice merged into one, the copies to the Trash', true, true),
  tidy('Tidy', 'Broken Markdown fixed, your words kept as they are', true, false),
  links('Tags and links', 'Tags, and [[links]] between notes about the same thing', false, false),
  stale('Stale', 'Abandoned or empty notes into the Archive', false, false);

  const CleanupPass(this.label, this.about, this.onByDefault, this.basic);

  final String label;
  final String about;

  /// On until the person turns it off.
  final bool onByDefault;

  /// Shown in Simple mode; the others wait behind More (GHST-103).
  final bool basic;

  /// The key its answers come under in the AI's JSON.
  String get key => switch (this) {
        sort => 'moves',
        titles => 'titles',
        duplicates => 'duplicates',
        tidy => 'tidy',
        links => 'links',
        stale => 'stale',
      };
}

/// What a run is asked to do.
@immutable
class CleanupOptions {
  const CleanupOptions({this.passes = const {CleanupPass.sort, CleanupPass.titles, CleanupPass.duplicates, CleanupPass.tidy}, this.deeper = false, this.rewrite = false});

  final Set<CleanupPass> passes;

  /// New folders may go inside the chosen folder's own folders too, not only directly inside it.
  final bool deeper;

  /// Tidy may change the words for clarity, not only the formatting. Off unless the person says.
  final bool rewrite;

  bool has(CleanupPass pass) => passes.contains(pass);

  CleanupOptions copyWith({Set<CleanupPass>? passes, bool? deeper, bool? rewrite}) => CleanupOptions(passes: passes ?? this.passes, deeper: deeper ?? this.deeper, rewrite: rewrite ?? this.rewrite);

  CleanupOptions toggled(CleanupPass pass, bool on) => copyWith(passes: on ? {...passes, pass} : ({...passes}..remove(pass)));

  Map<String, Object?> toJson() => {'passes': [for (final p in CleanupPass.values) if (passes.contains(p)) p.name], 'deeper': deeper, 'rewrite': rewrite};

  static CleanupOptions fromJson(Object? json) {
    if (json is! Map) return const CleanupOptions();
    final named = json['passes'];
    return CleanupOptions(
      passes: named is List ? {for (final p in CleanupPass.values) if (named.contains(p.name)) p} : const CleanupOptions().passes,
      deeper: json['deeper'] == true,
      rewrite: json['rewrite'] == true,
    );
  }
}

/// What a run of [options] may do in [scope]: Duplicates is never asked in an organization's folders (Matt,
/// 2026-11-02, choosing "Skip team duplicates"): a member's Trash is their own, so a merged-away team note would go
/// on being every other member's, and deleting it for everyone is not this plugin's to do.
CleanupOptions optionsFor(CleanupScope scope, CleanupOptions options) => scope.org != null && options.has(CleanupPass.duplicates) ? options.toggled(CleanupPass.duplicates, false) : options;

/// The most new folders one run makes.
const int cleanupMaxNewFolders = 3;

/// The most tags and links a note is given.
const int cleanupMaxTags = 5;
const int cleanupMaxLinks = 5;

// ---- the folder as it was read ----------------------------------------------------------------------------------

/// One note of the folder, as it was read for the plan: an edit is written over exactly this [revision].
@immutable
class CleanupNote {
  const CleanupNote({required this.id, required this.title, required this.body, required this.revision, required this.folderId, required this.updatedAt});

  final String id;
  final String title;
  final String body;
  final int revision;

  /// The folder it is filed in: the chosen one or one under it.
  final String folderId;
  final int updatedAt;
}

/// One folder of the chosen one's family, itself first.
@immutable
class CleanupFolder {
  const CleanupFolder({required this.id, required this.name, required this.parent, required this.path, required this.depth});

  final String id;
  final String name;
  final String? parent;

  /// Its whole path, as the app says it: "HelloTrade › Meetings".
  final String path;

  /// How far under the chosen folder: 0 for the chosen one.
  final int depth;
}

/// The chosen folder and everything in it, as the plan was made from.
@immutable
class CleanupScope {
  const CleanupScope({required this.rootId, required this.org, required this.folders, required this.notes, this.linkedTitles = const {}});

  /// The chosen folder.
  final String rootId;

  /// The organization it is in, or null for a personal folder: every folder of the family is in the same one.
  final String? org;

  /// The chosen folder first, then every folder under it.
  final List<CleanupFolder> folders;
  final List<CleanupNote> notes;

  /// The titles other notes link to (`[[Title]]`), as [titleKey] reads them: such a note is never renamed.
  final Set<String> linkedTitles;

  CleanupFolder get root => folders.first;

  CleanupNote? note(String id) => notes.where((n) => n.id == id).firstOrNull;
  CleanupFolder? folder(String id) => folders.where((f) => f.id == id).firstOrNull;

  /// [id]'s path, or the id itself where the scope has no such folder.
  String pathOf(String id) => folder(id)?.path ?? id;
}

// ---- the items ------------------------------------------------------------------------------------------------------

/// One suggestion the review shows with its own tick. Its [id] is stable for the run: `move:<note>`, `folder:<key>`.
@immutable
sealed class CleanupItem {
  const CleanupItem({required this.why});

  String get id;
  CleanupPass get pass;

  /// What the AI said of it, or the app's own reason.
  final String why;

  /// The notes it changes, by id: what a note changed since the plan holds back.
  List<String> get notes;
}

/// A folder to make inside [parentId] (Sort). [key] is the name's, so two batches proposing it make one.
class NewFolderItem extends CleanupItem {
  const NewFolderItem({required this.key, required this.name, required this.parentId, super.why = ''});

  final String key;
  final String name;
  final String parentId;

  @override
  String get id => 'folder:$key';
  @override
  CleanupPass get pass => CleanupPass.sort;
  @override
  List<String> get notes => const [];
}

/// A note filed elsewhere in the folder (Sort): [to] is a folder's id, or a new folder's [NewFolderItem.id].
class MoveItem extends CleanupItem {
  const MoveItem({required this.noteId, required this.from, required this.to, super.why = ''});

  final String noteId;
  final String from;
  final String to;

  /// Whether it goes into a folder this run makes.
  bool get intoNew => to.startsWith('folder:');

  @override
  String get id => 'move:$noteId';
  @override
  CleanupPass get pass => CleanupPass.sort;
  @override
  List<String> get notes => [noteId];
}

/// A note titled anew (Titles).
class TitleItem extends CleanupItem {
  const TitleItem({required this.noteId, required this.from, required this.to, super.why = ''});

  final String noteId;
  final String from;
  final String to;

  @override
  String get id => 'title:$noteId';
  @override
  CleanupPass get pass => CleanupPass.titles;
  @override
  List<String> get notes => [noteId];
}

/// Notes that are one note (Duplicates): [others] merged into [keepId] (their lines it lacks), then to the Trash.
class MergeItem extends CleanupItem {
  const MergeItem({required this.keepId, required this.others, super.why = '', this.found = false});

  final String keepId;
  final List<String> others;

  /// Found by the app itself (the same title and words), not the AI.
  final bool found;

  @override
  String get id => 'merge:$keepId';
  @override
  CleanupPass get pass => CleanupPass.duplicates;
  @override
  List<String> get notes => [keepId, ...others];
}

/// A note's words changed: tidied (Tidy), or given tags and links (Tags and links). [after] is the whole body.
class EditItem extends CleanupItem {
  const EditItem({required this.noteId, required this.pass, required this.before, required this.after, super.why = '', this.tags = const [], this.links = const []});

  final String noteId;
  @override
  final CleanupPass pass;
  final String before;
  final String after;

  /// What Tags and links adds, for the review's line.
  final List<String> tags;
  final List<String> links;

  @override
  String get id => '${pass.name}:$noteId';
  @override
  List<String> get notes => [noteId];
}

/// A note into the Archive (Stale).
class ArchiveItem extends CleanupItem {
  const ArchiveItem({required this.noteId, super.why = ''});

  final String noteId;

  @override
  String get id => 'stale:$noteId';
  @override
  CleanupPass get pass => CleanupPass.stale;
  @override
  List<String> get notes => [noteId];
}

/// A note Tidy is to be asked about with its whole text, from the first pass's answer.
@immutable
class TidyAsk {
  const TidyAsk(this.noteId, this.why);
  final String noteId;
  final String why;
}

// ---- one batch ------------------------------------------------------------------------------------------------------

/// The notes and folders one ask names, by the refs the AI is given.
class CleanupBatch {
  CleanupBatch(this.scope, List<CleanupNote> notes) : notes = List.unmodifiable(notes) {
    for (var i = 0; i < this.notes.length; i += 1) {
      _noteRefs['n${i + 1}'] = this.notes[i].id;
    }
    for (var i = 0; i < scope.folders.length; i += 1) {
      _folderRefs['f$i'] = scope.folders[i].id;
    }
  }

  final CleanupScope scope;
  final List<CleanupNote> notes;
  final Map<String, String> _noteRefs = {};
  final Map<String, String> _folderRefs = {};

  /// The note a ref names in this batch, or null.
  String? noteOf(Object? ref) => ref is String ? _noteRefs[ref.trim().toLowerCase()] : null;

  /// The folder a ref names, or null.
  String? folderOf(Object? ref) => ref is String ? _folderRefs[ref.trim().toLowerCase()] : null;

  /// The ref of note [id].
  String refOfNote(String id) => _noteRefs.entries.firstWhere((e) => e.value == id).key;

  /// The ref of folder [id].
  String refOfFolder(String id) => _folderRefs.entries.firstWhere((e) => e.value == id).key;
}

/// What one batch's answer came to: its items, the notes Tidy wants to see whole, and what was dropped and why.
class BatchPlan {
  BatchPlan({this.items = const [], this.tidy = const [], this.dropped = const [], this.failed});

  final List<CleanupItem> items;
  final List<TidyAsk> tidy;

  /// Each suggestion dropped, in a few words: "a move to a folder outside Work".
  final List<String> dropped;

  /// Why the whole answer gave nothing (no JSON, the AI failed), or null.
  final String? failed;
}

// ---- reading the answer ---------------------------------------------------------------------------------------------

/// The first JSON object in [output], read past a model's thinking and a code fence; null where there is none.
Map<String, Object?>? jsonObjectIn(String output) {
  final text = output.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  for (var start = text.indexOf('{'); start >= 0; start = text.indexOf('{', start + 1)) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i += 1) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth += 1;
      } else if (c == '}') {
        depth -= 1;
        if (depth == 0) {
          try {
            final value = jsonDecode(text.substring(start, i + 1));
            if (value is Map) return value.cast<String, Object?>();
          } on FormatException {
            // Not this one: the next `{` may open the answer.
          }
          break;
        }
      }
    }
  }
  return null;
}

List<Map<String, Object?>> _entries(Map<String, Object?> answer, String key) {
  final list = answer[key];
  if (list is! List) return const [];
  return [for (final entry in list) if (entry is Map) entry.cast<String, Object?>()];
}

String _why(Map<String, Object?> entry) {
  final why = entry['why'];
  if (why is! String) return '';
  final clean = why.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length > 160 ? '${clean.substring(0, 157)}…' : clean;
}

final RegExp _tagShape = RegExp(r'^[\p{L}][\p{L}\p{N}_/-]{0,39}$', unicode: true);

/// The key a new folder's name is made one by: its parent, and the name in lower case with its spaces made one.
String newFolderKey(String parentId, String name) => '$parentId/${name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

/// The items [output] proposes for [batch], each checked (docs/CLEANUP.md, "Validation"). A new folder named as one
/// already in the same place is that one. Never throws: what is wrong is dropped and said in [BatchPlan.dropped].
BatchPlan readBatch(String output, CleanupBatch batch, CleanupOptions options) {
  final answer = jsonObjectIn(output);
  if (answer == null) return BatchPlan(failed: 'the answer had no JSON in it');
  final scope = batch.scope;
  final items = <CleanupItem>[];
  final tidy = <TidyAsk>[];
  final dropped = <String>[];
  final seen = <String>{};

  // New folders first, so a move can name one.
  final newRefs = <String, String>{}; // the AI's ref → a folder id, or a NewFolderItem id
  if (options.has(CleanupPass.sort)) {
    for (final entry in _entries(answer, 'folders')) {
      final ref = entry['ref'];
      final rawName = entry['name'];
      final name = rawName is String ? rawName.replaceAll(RegExp(r'\s+'), ' ').trim() : '';
      final parent = entry['parent'] == null ? scope.rootId : batch.folderOf(entry['parent']);
      if (ref is! String || ref.trim().isEmpty) {
        dropped.add('a new folder with no ref');
        continue;
      }
      if (name.isEmpty || name.length > 60 || name.contains('/') || name.contains('\\') || name.startsWith('.')) {
        dropped.add('a new folder named “$name”');
        continue;
      }
      if (parent == null) {
        dropped.add('a new folder in a folder that isn’t here');
        continue;
      }
      final parentFolder = scope.folder(parent)!;
      if (parent != scope.rootId && !options.deeper) {
        dropped.add('“$name” inside ${parentFolder.name}: new folders go directly inside ${scope.root.name}');
        continue;
      }
      // One of the same name already there is that one.
      final existing = scope.folders.where((f) => f.parent == parent && f.name.trim().toLowerCase() == name.toLowerCase()).firstOrNull;
      if (existing != null) {
        newRefs[ref.trim().toLowerCase()] = existing.id;
        continue;
      }
      final item = NewFolderItem(key: newFolderKey(parent, name), name: name, parentId: parent, why: _why(entry));
      newRefs[ref.trim().toLowerCase()] = item.id;
      if (seen.add(item.id)) items.add(item);
    }

    for (final entry in _entries(answer, 'moves')) {
      final noteId = batch.noteOf(entry['note']);
      final toRef = entry['to'];
      final to = batch.folderOf(toRef) ?? (toRef is String ? newRefs[toRef.trim().toLowerCase()] : null);
      if (noteId == null) {
        dropped.add('a move of a note that isn’t in this folder');
        continue;
      }
      final note = scope.note(noteId)!;
      if (to == null) {
        dropped.add('a move of “${note.title}” to a folder outside ${scope.root.name}');
        continue;
      }
      if (to == note.folderId) continue; // there already: nothing to say
      final item = MoveItem(noteId: noteId, from: note.folderId, to: to, why: _why(entry));
      if (seen.add(item.id)) items.add(item);
    }
  }

  if (options.has(CleanupPass.titles)) {
    for (final entry in _entries(answer, 'titles')) {
      final noteId = batch.noteOf(entry['note']);
      final raw = entry['title'];
      if (noteId == null) {
        dropped.add('a title for a note that isn’t in this folder');
        continue;
      }
      final note = scope.note(noteId)!;
      final title = raw is String ? raw.replaceAll(RegExp(r'^#+\s*'), '').trim() : '';
      if (title.isEmpty || title.contains('\n') || title.length > 120) {
        dropped.add('a title for “${note.title}” that was ${title.isEmpty ? 'empty' : 'too long'}');
        continue;
      }
      if (title == note.title) continue;
      if (note.title.isNotEmpty && scope.linkedTitles.contains(titleKey(note.title))) {
        dropped.add('a new title for “${note.title}”, which other notes link to by its title');
        continue;
      }
      final item = TitleItem(noteId: noteId, from: note.title, to: title, why: _why(entry));
      if (seen.add(item.id)) items.add(item);
    }
  }

  if (options.has(CleanupPass.duplicates)) {
    final merged = <String>{};
    for (final entry in _entries(answer, 'duplicates')) {
      final keep = batch.noteOf(entry['keep']);
      final rawOthers = entry['others'];
      final others = <String>[
        if (rawOthers is List)
          for (final ref in rawOthers) ?batch.noteOf(ref),
      ]..removeWhere((id) => id == keep);
      if (keep == null || others.isEmpty) {
        dropped.add('a merge that named no note to keep or none to merge');
        continue;
      }
      if (merged.contains(keep) || others.any(merged.contains)) {
        dropped.add('a merge of a note already in another');
        continue;
      }
      final unique = others.toSet().toList();
      merged.addAll([keep, ...unique]);
      final item = MergeItem(keepId: keep, others: unique, why: _why(entry));
      if (seen.add(item.id)) items.add(item);
    }
  }

  if (options.has(CleanupPass.tidy)) {
    final asked = <String>{};
    for (final entry in _entries(answer, 'tidy')) {
      final noteId = batch.noteOf(entry['note']);
      if (noteId == null) {
        dropped.add('a tidy of a note that isn’t in this folder');
        continue;
      }
      if (asked.add(noteId)) tidy.add(TidyAsk(noteId, _why(entry)));
    }
  }

  if (options.has(CleanupPass.links)) {
    final byNote = <String, ({List<String> tags, List<String> links, String why})>{};
    for (final entry in _entries(answer, 'tags')) {
      final noteId = batch.noteOf(entry['note']);
      final raw = entry['tags'];
      if (noteId == null || raw is! List) continue;
      final tags = <String>[
        for (final tag in raw)
          if (tag is String && _tagShape.hasMatch(tag.replaceFirst(RegExp(r'^#'), '').trim())) tag.replaceFirst(RegExp(r'^#'), '').trim(),
      ].take(cleanupMaxTags).toList();
      if (raw.length > tags.length && tags.length < cleanupMaxTags) dropped.add('${raw.length - tags.length} tags that weren’t tag-shaped');
      if (tags.isEmpty) continue;
      final had = byNote[noteId];
      byNote[noteId] = (tags: tags, links: had?.links ?? const [], why: had?.why ?? _why(entry));
    }
    for (final entry in _entries(answer, 'links')) {
      final noteId = batch.noteOf(entry['note']);
      final raw = entry['to'];
      if (noteId == null || raw is! List) continue;
      final links = <String>{
        for (final ref in raw)
          if (batch.noteOf(ref) case final id? when id != noteId)
            if (scope.note(id)!.title.trim().isNotEmpty) scope.note(id)!.title.trim(),
      }.take(cleanupMaxLinks).toList();
      if (links.isEmpty) continue;
      final had = byNote[noteId];
      byNote[noteId] = (tags: had?.tags ?? const [], links: links, why: had == null || had.why.isEmpty ? _why(entry) : had.why);
    }
    for (final MapEntry(key: noteId, value: add) in byNote.entries) {
      final note = scope.note(noteId)!;
      final after = withRelated(withTags(note.body, add.tags), add.links);
      if (after == note.body) continue;
      final item = EditItem(noteId: noteId, pass: CleanupPass.links, before: note.body, after: after, why: add.why, tags: add.tags, links: add.links);
      if (seen.add(item.id)) items.add(item);
    }
  }

  if (options.has(CleanupPass.stale)) {
    for (final entry in _entries(answer, 'stale')) {
      final noteId = batch.noteOf(entry['note']);
      if (noteId == null) {
        dropped.add('an archive of a note that isn’t in this folder');
        continue;
      }
      final item = ArchiveItem(noteId: noteId, why: _why(entry));
      if (seen.add(item.id)) items.add(item);
    }
  }

  return BatchPlan(items: items, tidy: tidy, dropped: dropped);
}

/// Tidy's answer for [note]: an [EditItem], or why it is dropped.
({EditItem? item, String? dropped}) readTidy(String output, CleanupNote note, CleanupOptions options, {String why = ''}) {
  final json = jsonObjectIn(output);
  final body = json != null && json['body'] is String ? json['body']! as String : unwrapBody(output);
  final after = note.body.endsWith('\n') && !body.endsWith('\n') ? '$body\n' : body;
  if (after == note.body) return (item: null, dropped: null);
  final wrong = options.rewrite ? rewriteWhy(note.body, after) : formattingOnlyWhy(note.body, after);
  if (wrong != null) return (item: null, dropped: 'a tidy of “${note.title}”: $wrong');
  return (item: EditItem(noteId: note.id, pass: CleanupPass.tidy, before: note.body, after: after, why: why), dropped: null);
}

// ---- the whole plan ------------------------------------------------------------------------------------------------

/// Every suggestion of a run, the batches joined, in the review's order (docs/CLEANUP.md, "The review").
class CleanupPlan {
  CleanupPlan({required this.scope, required this.options, required this.items, this.dropped = const [], this.failures = const [], this.asks = 0, this.stopped = false});

  final CleanupScope scope;
  final CleanupOptions options;
  final List<CleanupItem> items;
  final List<String> dropped;

  /// Each ask that failed, in its own words.
  final List<String> failures;

  /// How many asks the run made.
  final int asks;

  /// Whether the person stopped it before it had asked about every note.
  final bool stopped;

  bool get isEmpty => items.isEmpty;

  /// The items of [pass], in order.
  List<CleanupItem> of(CleanupPass pass) => [for (final item in items) if (item.pass == pass) item];

  CleanupItem? byId(String id) => items.where((i) => i.id == id).firstOrNull;

  /// The moves into the new folder [folderItemId].
  List<MoveItem> movesInto(String folderItemId) => [for (final item in items) if (item is MoveItem && item.to == folderItemId) item];

  /// What the review ticks to begin with: everything, except, on a plan of more than [bigPlan] items, the edits and
  /// merges, which the person ticks for themselves (docs/CLEANUP.md, "The review").
  Set<String> get startTicked {
    final big = items.length > bigPlan;
    return {
      for (final item in items)
        if (!big || (item is! EditItem && item is! MergeItem)) item.id,
    };
  }

  /// A plan of more than this many items is big: Apply all is not the default and edits start unticked.
  static const int bigPlan = 30;

  /// The batches joined (see the library doc): each note in one merge at most (the app's own [found] groups first),
  /// a note merged away never moved, retitled, tidied, tagged or archived, a new folder made once however many batches
  /// proposed it and only [cleanupMaxNewFolders] of them, a move into a folder past that limit dropped.
  static CleanupPlan join({required CleanupScope scope, required CleanupOptions options, required List<BatchPlan> batches, List<EditItem> tidied = const [], List<List<String>> found = const [], List<String> moreDropped = const [], int asks = 0, bool stopped = false}) {
    final dropped = [for (final b in batches) ...b.dropped, ...moreDropped];
    final failures = [for (final b in batches) if (b.failed != null) b.failed!];
    final all = [for (final b in batches) ...b.items];

    // Merges: the app's own first, then the AI's, each note once.
    final merges = <MergeItem>[];
    final inMerge = <String>{};
    if (options.has(CleanupPass.duplicates)) {
      for (final group in found) {
        if (group.length < 2 || group.any(inMerge.contains)) continue;
        inMerge.addAll(group);
        merges.add(MergeItem(keepId: group.first, others: group.sublist(1), why: 'The same title and words', found: true));
      }
      for (final item in all.whereType<MergeItem>()) {
        if (item.notes.any(inMerge.contains)) {
          if (!merges.any((m) => m.keepId == item.keepId && listEquals(m.others, item.others))) dropped.add('a merge of a note already in another');
          continue;
        }
        inMerge.addAll(item.notes);
        merges.add(item);
      }
    }
    final mergedAway = {for (final m in merges) ...m.others};

    // New folders: once each, at most the limit, in the order first proposed.
    final folders = <NewFolderItem>[];
    for (final item in all.whereType<NewFolderItem>()) {
      if (folders.any((f) => f.id == item.id)) continue;
      if (folders.length >= cleanupMaxNewFolders) {
        dropped.add('a new folder “${item.name}”: at most $cleanupMaxNewFolders a run');
        continue;
      }
      folders.add(item);
    }
    final made = {for (final f in folders) f.id};

    final rest = <CleanupItem>[];
    for (final item in [...all.where((i) => i is! MergeItem && i is! NewFolderItem), ...tidied]) {
      if (item.notes.any(mergedAway.contains)) continue;
      if (item is MoveItem && item.intoNew && !made.contains(item.to)) {
        dropped.add('a move into a folder that won’t be made');
        continue;
      }
      if (rest.any((r) => r.id == item.id)) continue;
      rest.add(item);
    }
    // A new folder nothing moves into is not made.
    final used = {for (final item in rest) if (item is MoveItem && item.intoNew) item.to};
    final kept = [for (final f in folders) if (used.contains(f.id)) f];

    final ordered = <CleanupItem>[
      for (final pass in CleanupPass.values) ...[
        if (pass == CleanupPass.sort) ...kept,
        if (pass == CleanupPass.duplicates) ...merges,
        for (final item in rest) if (item.pass == pass) item,
      ],
    ];
    return CleanupPlan(scope: scope, options: options, items: ordered, dropped: dropped, failures: failures, asks: asks, stopped: stopped);
  }
}
