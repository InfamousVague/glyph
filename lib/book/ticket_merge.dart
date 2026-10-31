/// "Merge into…" on a ticket (Matt, 2026-10-31): a duplicate folded into the ticket it duplicates. What moves:
///
/// - **Its comments**: every thread of its comments fence, into the target's fence, under ids the target does not use
///   (a thread whose id the target has already gets a fresh one, its anchor with it); out of the duplicate.
/// - **Its watchers, labels and links**: into the target's front matter, each once: `watchers`, `labels` and
///   `blocked-by` (less any that name the two tickets themselves).
/// - **Its words**: under a `## Merged from GHO-12` heading at the end of the target's, before its comments, its title
///   heading and front matter left out.
/// - **Every link to it**: `[[GHO-12]]`, `[[Its title]]`, `[[GHO-12#Steps|the steps]]`, an embed too, across the
///   library (a notebook's list of its pages apart, where the duplicate stays, closed), rewritten to the target, its
///   heading and its words kept; read where each link stands, by the link index
///   (lib/core/link_index.dart), so one in code is left as it is. A team's note this device may not change is left out
///   and said ([MergePlan.skipped]); a Markdown link to its file is left too, and counted.
/// - **And it is closed**: its status the workflow's done one (a `Duplicate` where the workflow has one), and
///   `duplicate-of: "[[GHO-9]]"` written.
///
/// **One undo.** The merge is a plan first ([planMerge]): each note's words before and after, nothing written. The
/// sheet says what it will do and warns of what it will not; the merge writes the plan ([applyMerge]), a version kept of
/// each note's words before it (lib/core/versions_record.dart), and [undoMerge] puts every note back as one step, any
/// changed since left as it is and said. The two notes whose words change substantively, the target and the duplicate,
/// keep that version whether or not they keep versions (docs/MARKDOWN_FIRST.md §11, decision 21; Matt, 2026-10-31): the
/// undo record is this device's alone, so after a restore the `.versions` file beside each is what can take the merge
/// back. A note whose links were rewritten keeps one only where it keeps versions, as a merge can touch dozens.
///
/// Plain Markdown in and out, pure but for the writing, so each is a test (test/book_core/ticket_merge_test.dart).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comments/format.dart' show freshId, readComments, commentAnchor;
import '../core/front_matter.dart' show frontMatterEnd, frontMatterValue;
import '../core/link_index.dart' show LinkIndex, LinkOut, linksIn;
import '../core/note_facts.dart' show NoteFacts;
import '../core/properties.dart';
import '../core/stored.dart';
import '../core/title_key.dart' show titleKey;
import 'ticket_duplicates.dart' show duplicateOfKey;
import 'ticket_watchers.dart';
import 'tickets.dart';

/// One note's words before the merge and after it.
typedef MergeWrite = ({String id, String title, String before, String after});

/// What a merge will do, before anything is written.
@immutable
class MergePlan {
  const MergePlan({required this.duplicateId, required this.targetId, required this.duplicateName, required this.targetName, required this.writes, required this.links, required this.linkNotes, required this.skipped, required this.unchanged, required this.comments, required this.warnings});

  final String duplicateId;
  final String targetId;

  /// `GHO-12`, or the title where it has no key.
  final String duplicateName;
  final String targetName;

  /// Every note written: the target, the duplicate, and each note whose links change.
  final List<MergeWrite> writes;

  /// How many links to the duplicate are rewritten, and in how many other notes.
  final int links;
  final int linkNotes;

  /// The notes that link to it and are left as they are: a team's this device may not change.
  final List<String> skipped;

  /// Markdown links to its file, left as they are.
  final int unchanged;

  /// How many comment threads move.
  final int comments;

  /// What the sheet says before the merge is made, beyond what it does.
  final List<String> warnings;

  /// The sentence the sheet says of it.
  String get summary {
    final parts = <String>[
      'Its words go under “Merged from $duplicateName” in $targetName',
      if (comments > 0) '${comments == 1 ? 'its comment moves' : 'its $comments comments move'} with them',
      'its watchers and labels join $targetName’s',
      if (links > 0) '$links ${links == 1 ? 'link' : 'links'} in $linkNotes ${linkNotes == 1 ? 'note' : 'notes'} change to $targetName',
      '$duplicateName is closed as a duplicate of $targetName',
    ];
    return '${parts.join(', ')}.';
  }
}

/// A ticket's name as the merge says it and links to it: its key, or its title.
String _nameOf(TicketEntry entry) => entry.ticket.id ?? entry.title;

/// The status a duplicate is closed with: the workflow's `Duplicate` where it has one, else its last done status, else
/// `Done`.
String duplicateStatus(List<String> statuses) {
  for (final status in statuses) {
    if (status.trim().toLowerCase() == 'duplicate') return status;
  }
  for (final status in statuses.reversed) {
    if (statusCategory(status, statuses) == StatusCategory.done) return status;
  }
  return 'Done';
}

/// [items] and [more], each once, in order: compared without case or brackets' spaces.
List<String> _joined(List<String> items, List<String> more, {Set<String> without = const {}}) {
  final seen = <String>{for (final item in without) item.toLowerCase()};
  return [
    for (final item in [...items, ...more])
      if (seen.add(item.replaceAll(' ', '').toLowerCase())) item,
  ];
}

/// The body's lines and where its comments fence is: its first line and its closing line, from 0, or null.
({List<String> lines, int? open, int? close}) _fenceLines(String body) {
  final read = readComments(body);
  final fence = read.fence;
  final lines = body.split('\n');
  if (fence == null) return (lines: lines, open: null, close: null);
  return (lines: lines, open: fence.open - 1, close: fence.close == null ? null : fence.close! - 1);
}

/// The body without its comments fence ([unfenced], its anchors kept), the same without the anchors to its threads
/// ([body]), and the threads' lines.
({String body, String unfenced, List<List<String>> threads}) _takeComments(String body) {
  final read = readComments(body);
  if (read.fence == null) return (body: body, unfenced: body, threads: const []);
  final lines = body.split('\n');
  final threads = [for (final thread in read.threads) lines.sublist(thread.from - 1, thread.to)];
  final open = read.fence!.open - 1, close = read.fence!.close == null ? lines.length - 1 : read.fence!.close! - 1;
  final kept = [...lines.sublist(0, open), ...lines.sublist(close + 1)];
  while (kept.isNotEmpty && kept.last.trim().isEmpty) {
    kept.removeLast();
  }
  final unfenced = '${kept.join('\n')}\n';
  // An anchor to a thread that is no longer here is taken out with the thread.
  final text = unfenced.replaceAllMapped(commentAnchor, (m) => read.threads.any((t) => t.id == m[1]) ? '' : m[0]!);
  return (body: text, unfenced: unfenced, threads: threads);
}

/// The duplicate's words as they go under the target's heading: no front matter, no title heading, no comments fence.
String _wordsOf(String body) {
  final lines = body.split('\n');
  var at = frontMatterEnd(lines);
  while (at < lines.length && lines[at].trim().isEmpty) {
    at += 1;
  }
  if (at < lines.length && RegExp(r'^#\s+').hasMatch(lines[at])) at += 1;
  final rest = lines.sublist(at).join('\n').trim();
  return rest;
}

/// [body] with each of [rename]'s thread ids changed, in its fence's head lines and its anchors.
String _renamed(String body, Map<String, String> rename) {
  if (rename.isEmpty) return body;
  var text = body.replaceAllMapped(commentAnchor, (m) => '[^${rename[m[1]] ?? m[1]}]');
  text = text.replaceAllMapped(RegExp(r'^(c[0-9a-z]+) ', multiLine: true), (m) => '${rename[m[1]] ?? m[1]} ');
  return text;
}

/// [body] with each link [toRewrite] says is to the duplicate written as one to [name], its heading and words kept.
({String text, int count, int markdown}) _rewritten(String body, bool Function(LinkOut link) toRewrite, String name) {
  final found = [for (final link in linksIn(body)) if (toRewrite(link)) link]..sort((a, b) => b.from.compareTo(a.from));
  var text = body;
  var count = 0, markdown = 0;
  for (final link in found) {
    if (link.path != null) {
      markdown += 1;
      continue;
    }
    final anchor = link.anchor == null ? '' : '#${link.anchor}';
    final label = link.label == null ? '' : '|${link.label}';
    text = text.replaceRange(link.from, link.to, '${link.embed ? '!' : ''}[[$name$anchor$label]]');
    count += 1;
  }
  return (text: text, count: count, markdown: markdown);
}

/// What merging [duplicate] into [target] writes (see the header). [notes] is every note, by id, with its words now;
/// [index] the link index; [editable] whether a note may be changed here (a team's that this device can write);
/// [today] the day the duplicate is closed on (`withStatus`), the clock's where unsaid.
MergePlan planMerge({required TicketEntry duplicate, required TicketEntry target, required Map<String, ({String title, String body})> notes, required LinkIndex index, bool Function(String id)? editable, String? today}) {
  final dupName = _nameOf(duplicate), targetName = _nameOf(target);
  final dupKeys = <String>{
    titleKey(duplicate.title),
    if (duplicate.ticket.id != null) titleKey(duplicate.ticket.id!),
  }..remove('');
  bool toDuplicate(LinkOut link, String from) {
    if (link.path != null) return index.targetOf(link, from: from) == duplicate.note.id;
    return dupKeys.contains(link.key) || index.targetOf(link, from: from) == duplicate.note.id;
  }

  final warnings = <String>[];
  if (target.ticket.category == StatusCategory.done) warnings.add('$targetName is closed already: its status stays as it is.');
  if (duplicate.notebook?.id != target.notebook?.id) warnings.add('$dupName and $targetName are in different notebooks.');
  if (isDuplicateClosedBody(target.note.body)) warnings.add('$targetName is itself closed as a duplicate.');

  // The duplicate's comments, moved under ids the target does not use.
  final taken = _takeComments(duplicate.note.body);
  final dupComments = readComments(duplicate.note.body);
  final rename = <String, String>{};
  var against = target.note.body;
  for (final thread in dupComments.threads) {
    final used = RegExp('(^|\\[\\^)${RegExp.escape(thread.id)}(\\]| )', multiLine: true).hasMatch(against);
    if (used) {
      final fresh = freshId('$against\n${duplicate.note.body}');
      rename[thread.id] = fresh;
      against = '$against\n$fresh ';
    }
  }
  // Its words with their anchors, under the ids their threads move under.
  final words = _wordsOf(_renamedAnchors(taken.unfenced, rename));
  final movedThreads = [for (final lines in taken.threads) _renamed(lines.join('\n'), rename)];

  // The target: the duplicate's words under their heading, before the comments; the threads into its fence.
  var after = target.note.body;
  final fenced = _fenceLines(after);
  final section = '## Merged from $dupName\n\n${words.isEmpty ? '_(It had no words of its own.)_' : words}\n';
  if (fenced.open == null) {
    after = '${after.trimRight()}\n\n$section';
    if (movedThreads.isNotEmpty) after = '$after\n```comments\n${movedThreads.join('\n')}\n```\n';
  } else {
    final lines = fenced.lines;
    final before = lines.sublist(0, fenced.open!).join('\n').trimRight();
    final fenceLines = lines.sublist(fenced.open!, fenced.close == null ? lines.length : fenced.close!);
    final rest = fenced.close == null ? const <String>[] : lines.sublist(fenced.close!);
    final fence = [...fenceLines, ...movedThreads, if (fenced.close == null) '```'];
    after = '$before\n\n$section\n${fence.join('\n')}${rest.isEmpty ? '\n' : '\n${rest.join('\n')}'}';
  }
  // Its watchers, labels and links.
  after = withWatchers(after, watchersOf(duplicate.note.body));
  final labels = _joined(propertyList(frontMatterValue(after, 'labels')), propertyList(frontMatterValue(duplicate.note.body, 'labels')));
  if (labels.isNotEmpty) after = withProperty(after, 'labels', labels);
  final selves = <String>{
    '[[${duplicate.ticket.id ?? duplicate.title}]]',
    '[[${target.ticket.id ?? target.title}]]',
    '[[${duplicate.title}]]',
    '[[${target.title}]]',
  };
  final blockers = _joined(propertyList(frontMatterValue(after, 'blocked-by')), propertyList(frontMatterValue(duplicate.note.body, 'blocked-by')), without: selves);
  final hadBlockers = propertyList(frontMatterValue(after, 'blocked-by'));
  if (blockers.length != hadBlockers.length || blockers.isEmpty != hadBlockers.isEmpty) after = withProperty(after, 'blocked-by', blockers.isEmpty ? null : (blockers.length == 1 ? blockers.single : blockers));
  // A link the target makes to the duplicate (its words, or the words it took in) is to itself now: to its key.
  final inTarget = _rewritten(after, (link) => toDuplicate(link, target.note.id), targetName);
  after = inTarget.text;

  // The duplicate: closed, and pointing at the target; its comments gone with the move.
  var closed = taken.body;
  closed = withStatus(closed, duplicateStatus(duplicate.statuses), today: today, workflow: duplicate.statuses);
  closed = withProperty(closed, duplicateOfKey, '[[$targetName]]');

  final writes = <MergeWrite>[
    (id: target.note.id, title: target.title, before: target.note.body, after: after),
    (id: duplicate.note.id, title: duplicate.title, before: duplicate.note.body, after: closed),
  ];
  // Every other note that links to it.
  var links = 0, linkNotes = 0, unchanged = 0;
  final skipped = <String>[];
  for (final id in index.linkingTo(duplicate.note.id)) {
    if (id == duplicate.note.id || id == target.note.id) continue;
    final note = notes[id];
    // A notebook's list of its pages is where the duplicate is kept, closed, not a link to it: left as it is.
    if (note == null || NoteFacts.read(note.body).isBook) continue;
    if (editable != null && !editable(id)) {
      skipped.add(note.title.isEmpty ? 'Untitled' : note.title);
      continue;
    }
    final changed = _rewritten(note.body, (link) => toDuplicate(link, id), targetName);
    unchanged += changed.markdown;
    if (changed.count == 0) continue;
    links += changed.count;
    linkNotes += 1;
    writes.add((id: id, title: note.title, before: note.body, after: changed.text));
  }
  if (skipped.isNotEmpty) warnings.add('${skipped.length == 1 ? '1 note' : '${skipped.length} notes'} linking to $dupName cannot be changed here and keep their links: ${skipped.join(', ')}.');
  if (unchanged > 0) warnings.add('$unchanged Markdown ${unchanged == 1 ? 'link' : 'links'} to its file stay as written.');
  skipped.sort();
  return MergePlan(
    duplicateId: duplicate.note.id,
    targetId: target.note.id,
    duplicateName: dupName,
    targetName: targetName,
    writes: writes,
    links: links,
    linkNotes: linkNotes,
    skipped: skipped,
    unchanged: unchanged,
    comments: dupComments.threads.length,
    warnings: warnings,
  );
}

String _renamedAnchors(String body, Map<String, String> rename) => rename.isEmpty ? body : body.replaceAllMapped(commentAnchor, (m) => '[^${rename[m[1]] ?? m[1]}]');

/// Whether a body is closed as another's duplicate.
bool isDuplicateClosedBody(String body) => (frontMatterValue(body, duplicateOfKey) ?? '').trim().isNotEmpty;

// ---- writing it, and taking it back -------------------------------------------------------------------------------

/// A merge made, as the device keeps it for its Undo.
@immutable
class MergeRecord {
  const MergeRecord({required this.at, required this.duplicateId, required this.targetId, required this.duplicateName, required this.targetName, required this.writes});

  static MergeRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final writes = raw['writes'];
    if (raw['dup'] is! String || raw['target'] is! String || writes is! List) return null;
    return MergeRecord(
      at: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
      duplicateId: raw['dup'] as String,
      targetId: raw['target'] as String,
      duplicateName: raw['dupName'] is String ? raw['dupName'] as String : '',
      targetName: raw['targetName'] is String ? raw['targetName'] as String : '',
      writes: [
        for (final each in writes)
          if (each is Map && each['id'] is String && each['before'] is String && each['after'] is String)
            (id: each['id'] as String, title: each['title'] is String ? each['title'] as String : '', before: each['before'] as String, after: each['after'] as String),
      ],
    );
  }

  final int at;
  final String duplicateId;
  final String targetId;
  final String duplicateName;
  final String targetName;
  final List<MergeWrite> writes;

  Map<String, Object?> toJson() => {
        'at': at,
        'dup': duplicateId,
        'target': targetId,
        'dupName': duplicateName,
        'targetName': targetName,
        'writes': [for (final w in writes) {'id': w.id, 'title': w.title, 'before': w.before, 'after': w.after}],
      };
}

/// Where a merge reads and writes notes, and keeps their versions.
class MergeWorld {
  const MergeWorld({required this.body, required this.write, this.keepVersion, Stored? kept, int Function()? clock}) : _kept = kept, _clock = clock;

  /// A note's words now, or null where it is gone.
  final Future<String?> Function(String id) body;
  final Future<void> Function(String id, String body) write;

  /// Keeps [text] as a version of the note, named: where the note keeps versions, or whatever its switch says with
  /// [always] (the merge's two notes, lib/core/versions_record.dart `keepVersion` either way).
  final Future<void> Function(String id, String text, String label, {bool always})? keepVersion;
  final Stored? _kept;
  final int Function()? _clock;

  Stored get kept => _kept ?? stored;
  int now() => (_clock ?? () => DateTime.now().millisecondsSinceEpoch)();
}

const String _mergesKey = 'glyph-ticket-merges';

/// The merges this device made and can still take back, newest last.
List<MergeRecord> mergesKept(Stored kept) => kept.read<List<MergeRecord>>(_mergesKey, const [], (raw) => raw is List ? [for (final each in raw) ?MergeRecord.fromJson(each)] : const []);

/// The merge that closed [duplicateId], if this device made it and can take it back.
MergeRecord? mergeOf(Stored kept, String duplicateId) => mergesKept(kept).where((each) => each.duplicateId == duplicateId).lastOrNull;

/// Whether [id] is one of the two notes a merge changes substantively, the target or the duplicate: their version is
/// kept whatever their switch says (see the header).
bool _substantive(MergePlan plan, String id) => id == plan.targetId || id == plan.duplicateId;

/// The plan written: a version of each note's words before it kept, then each note written. Answers the record its
/// Undo takes back. A note changed since the plan was made is a conflict, and nothing is written.
Future<MergeRecord> applyMerge(MergePlan plan, MergeWorld world) async {
  for (final write in plan.writes) {
    final now = await world.body(write.id);
    if (now != write.before) throw StateError('${write.title.isEmpty ? 'A note' : write.title} changed while the merge was being made. Nothing was merged.');
  }
  final label = 'Before merging ${plan.duplicateName} into ${plan.targetName}';
  for (final write in plan.writes) {
    await world.keepVersion?.call(write.id, write.before, label, always: _substantive(plan, write.id));
  }
  for (final write in plan.writes) {
    await world.write(write.id, write.after);
  }
  final record = MergeRecord(at: world.now(), duplicateId: plan.duplicateId, targetId: plan.targetId, duplicateName: plan.duplicateName, targetName: plan.targetName, writes: plan.writes);
  final kept = [...mergesKept(world.kept), record];
  world.kept.write(_mergesKey, [for (final each in kept.length > 10 ? kept.sublist(kept.length - 10) : kept) each.toJson()]);
  return record;
}

/// The merge taken back as one step: each note still as the merge left it gets its words from before, a version kept
/// of what it had; any changed since is left and named. Answers the titles left.
Future<List<String>> undoMerge(MergeRecord record, MergeWorld world) async {
  final left = <String>[];
  for (final write in record.writes) {
    final now = await world.body(write.id);
    if (now == null || now != write.after) {
      left.add(write.title.isEmpty ? 'Untitled' : write.title);
      continue;
    }
    await world.keepVersion?.call(write.id, now, 'Before undoing the merge of ${record.duplicateName}', always: write.id == record.targetId || write.id == record.duplicateId);
    await world.write(write.id, write.before);
  }
  final kept = [for (final each in mergesKept(world.kept)) if (jsonEncode(each.toJson()) != jsonEncode(record.toJson())) each];
  world.kept.write(_mergesKey, [for (final each in kept) each.toJson()]);
  return left;
}
