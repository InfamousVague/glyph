/// Putting the remote's commits together with this device's before a push (docs/MARKDOWN_FIRST.md §10 Multi-device,
/// with the critic's finding on conflict copies folded in). The remote moved (another pusher, or Matt pushing from a
/// laptop) when the fetch says `diverged` or `behind`; then, file by file over what the remote changed since the
/// merge base (`git_diff base..theirs`):
///
/// - **A note (`.md`)** both sides changed: three-way with lib/core/merge_words.dart over the texts `git_three_way`
///   answers (base = the merge-base blob). Where the merge gives up (null), ours stays at its path and theirs is
///   written as a NEW note, `<Title> (conflict from git).md` beside it, with a FRESH `id:` in its front matter and no
///   `.glyph/notes` sidecar, so no id-keyed ledger ever points at the copy (the critic's high finding). A note only
///   the remote changed is taken as theirs; one only we changed stays.
/// - **`.versions`**: ours, with theirs' lines that ours has not appended after, so no history is lost and the file
///   stays a plain-text log.
/// - **Binaries** (`image/`, `file/`, `recordings/`, anything not text) both sides changed: theirs wins, and ours is
///   kept beside it as `<name>.conflict.<ext>` so nothing is lost.
/// - **`.glyph/config.json`**: key by key, the newer side's value for a key both changed (last writer), both sides'
///   keys kept.
/// - Everything else the remote alone changed: theirs; removed on the remote and unchanged here: a note or its
///   versions moved to `.trash/<path>` (out of the app, never lost), any other file removed.
///
/// Then the merge is committed with two parents (`git_commit` with `alsoParent` = theirs) and pushed. Never a force
/// push: a push that is still refused is a red row that says so.
library;

import 'dart:convert';
import 'dart:io';

import '../../core/front_matter.dart' show frontMatterSpan, frontMatterValue;
import '../../core/library.dart' show newNoteId;
import '../../core/merge_words.dart' show mergedWords;
import '../../core/versions_file.dart' show mergeFiles;
import 'repo.dart';

/// The suffix of a conflict copy's title.
const String conflictSuffix = ' (conflict from git)';

/// What one file's merge decided.
enum MergeTaken { ours, theirs, merged, conflictCopy, removed }

class MergeStep {
  const MergeStep(this.path, this.taken, {this.copy});
  final String path;
  final MergeTaken taken;

  /// The path the conflict copy was written at.
  final String? copy;

  @override
  String toString() => copy == null ? '${taken.name} $path' : '${taken.name} $path → $copy';
}

class MergeOutcome {
  const MergeOutcome(this.steps);
  final List<MergeStep> steps;

  int get conflicts => steps.where((s) => s.taken == MergeTaken.conflictCopy).length;
  List<String> get conflictCopies => [for (final s in steps) if (s.taken == MergeTaken.conflictCopy && s.copy != null) s.copy!];
}

bool isNotePath(String path) => path.toLowerCase().endsWith('.md');
bool isVersionsPath(String path) => path.endsWith('.versions');
bool isConfigPath(String path) => path == '.glyph/config.json';

/// Whether [path] is a text the merge reads line by line: notes, versions, canvases, the config and sidecars, the
/// generated files. Everything else is a binary.
bool isTextPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.versions') || lower.endsWith('.canvas') || lower.endsWith('.json') || lower.endsWith('.txt') || lower.endsWith('.yml') || lower.endsWith('.yaml') || lower == '.gitignore' || lower == '.gitattributes';
}

/// [theirs]' text with a fresh `id:` in its front matter (added where there was none), as the conflict copy's body.
String conflictCopyText(String theirs, {String? id}) {
  final fresh = id ?? newNoteId();
  final span = frontMatterSpan(theirs);
  if (span.offset == 0) return '---\nid: $fresh\n---\n$theirs';
  final head = theirs.substring(0, span.offset);
  final lines = head.split('\n');
  var replaced = false;
  for (var i = 0; i < lines.length; i += 1) {
    if (RegExp(r'^id\s*:', caseSensitive: false).hasMatch(lines[i])) {
      lines[i] = 'id: $fresh';
      replaced = true;
    }
  }
  if (!replaced) lines.insert(1, 'id: $fresh');
  return '${lines.join('\n')}${theirs.substring(span.offset)}';
}

/// The path the conflict copy of [path] is written at: beside the note, its title with [conflictSuffix], a number
/// where that is taken.
String conflictCopyPath(String path, {required bool Function(String) exists}) {
  final dot = path.lastIndexOf('.');
  final stem = dot > 0 ? path.substring(0, dot) : path;
  final ext = dot > 0 ? path.substring(dot) : '';
  var candidate = '$stem$conflictSuffix$ext';
  var n = 2;
  while (exists(candidate)) {
    candidate = '$stem$conflictSuffix $n$ext';
    n += 1;
  }
  return candidate;
}

/// `.versions` merged: every version either side kept, once, in order (lib/core/versions_file.dart `mergeFiles`, as
/// the sync merges them); ours as it is where theirs is not a versions file.
String mergedVersions(String ours, String theirs) => mergeFiles(ours, theirs, '') ?? ours;

/// `.glyph/config.json` merged key by key: a key one side changed from base is that side's; a key both changed is
/// theirs' where [theirsNewer], ours otherwise (last writer); keys only one side has are kept.
String mergedConfig(String? base, String ours, String theirs, {bool theirsNewer = true}) {
  Map<String, Object?> read(String? text) {
    if (text == null || text.trim().isEmpty) return {};
    try {
      final parsed = jsonDecode(text);
      return parsed is Map ? parsed.cast<String, Object?>() : {};
    } catch (_) {
      return {};
    }
  }

  final b = read(base), m = read(ours), t = read(theirs);
  final out = <String, Object?>{};
  for (final key in {...m.keys, ...t.keys}) {
    final bv = jsonEncode(b[key]), mv = jsonEncode(m[key]), tv = jsonEncode(t[key]);
    final mineChanged = mv != bv, theirsChanged = tv != bv;
    if (mineChanged && theirsChanged) {
      out[key] = theirsNewer ? t[key] : m[key];
    } else if (theirsChanged) {
      if (t.containsKey(key)) out[key] = t[key];
    } else {
      if (m.containsKey(key)) out[key] = m[key];
    }
  }
  return '${const JsonEncoder.withIndent('  ').convert(out)}\n';
}

/// The merge of the remote's changes since the merge base into the working tree at [repo]'s folder (see the header).
/// [theirs] is `origin/main`'s commit, [base] the merge base (null when the histories share none: everything theirs
/// has is new to us), [ours] `main`'s.
Future<MergeOutcome> mergeRemoteInto(GitRepo repo, {required String theirs, String? base, required String ours, DateTime? theirsTime, DateTime? oursTime, String Function()? freshId}) async {
  final changed = await repo.diff(from: base, to: theirs);
  final oursChanged = base == null ? const <GitChange>[] : await repo.diff(from: base, to: ours);
  final oursByPath = {for (final c in oursChanged) c.path: c};
  final steps = <MergeStep>[];
  final theirsNewer = theirsTime == null || oursTime == null || !theirsTime.isBefore(oursTime);
  for (final change in changed) {
    final path = change.path;
    final file = File('${repo.path}/$path');
    final weChanged = oursByPath.containsKey(path);
    if (change.kind == 'removed') {
      if (weChanged) {
        steps.add(MergeStep(path, MergeTaken.ours));
      } else if (isNotePath(path) || isVersionsPath(path)) {
        // A note the remote deleted goes to `.trash/` at its path (decision 2's folder): out of the app, since a dot
        // folder is never indexed, and never lost; the next commit records the move.
        if (file.existsSync()) {
          final into = File('${repo.path}/.trash/$path')..parent.createSync(recursive: true);
          file.renameSync(into.path);
        }
        steps.add(MergeStep(path, MergeTaken.removed, copy: '.trash/$path'));
      } else {
        if (file.existsSync()) file.deleteSync();
        steps.add(MergeStep(path, MergeTaken.removed));
      }
      continue;
    }
    if (change.kind == 'renamed' && change.from != null && !oursByPath.containsKey(change.from!)) {
      final old = File('${repo.path}/${change.from!}');
      if (old.existsSync()) old.deleteSync();
    }
    if (!weChanged) {
      await repo.writeBlob(theirs, path, file.path);
      steps.add(MergeStep(path, MergeTaken.theirs));
      continue;
    }
    // Both sides changed it.
    if (isNotePath(path)) {
      final texts = await repo.threeWay(path);
      final mine = file.existsSync() ? file.readAsStringSync() : (texts.ours ?? '');
      final their = texts.theirs ?? await repo.blob(theirs, path) ?? '';
      final merged = texts.base == null ? null : mergedWords(texts.base!, mine, their);
      if (merged != null) {
        file.writeAsStringSync(merged);
        steps.add(MergeStep(path, MergeTaken.merged));
      } else {
        final copyPath = conflictCopyPath(path, exists: (p) => File('${repo.path}/$p').existsSync());
        final copy = File('${repo.path}/$copyPath')..createSync(recursive: true);
        copy.writeAsStringSync(conflictCopyText(their, id: freshId?.call()));
        steps.add(MergeStep(path, MergeTaken.conflictCopy, copy: copyPath));
      }
    } else if (isVersionsPath(path)) {
      final their = await repo.blob(theirs, path) ?? '';
      final mine = file.existsSync() ? file.readAsStringSync() : '';
      file.writeAsStringSync(mergedVersions(mine, their));
      steps.add(MergeStep(path, MergeTaken.merged));
    } else if (isConfigPath(path)) {
      final texts = await repo.threeWay(path);
      final mine = file.existsSync() ? file.readAsStringSync() : (texts.ours ?? '{}');
      file.writeAsStringSync(mergedConfig(texts.base, mine, texts.theirs ?? '{}', theirsNewer: theirsNewer));
      steps.add(MergeStep(path, MergeTaken.merged));
    } else if (isTextPath(path)) {
      // Other texts (a canvas, a sidecar): theirs, ours kept as a conflict copy.
      final copyPath = conflictCopyPath(path, exists: (p) => File('${repo.path}/$p').existsSync());
      if (file.existsSync()) file.copySync('${repo.path}/$copyPath');
      await repo.writeBlob(theirs, path, file.path);
      steps.add(MergeStep(path, MergeTaken.conflictCopy, copy: copyPath));
    } else {
      // A binary: theirs wins, ours beside it.
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      final copyPath = dot > slash ? '${path.substring(0, dot)}.conflict${path.substring(dot)}' : '$path.conflict';
      if (file.existsSync()) file.copySync('${repo.path}/$copyPath');
      await repo.writeBlob(theirs, path, file.path);
      steps.add(MergeStep(path, MergeTaken.conflictCopy, copy: copyPath));
    }
  }
  return MergeOutcome(steps);
}

/// Whether [body] is a conflict copy: its title line carries the suffix.
bool isConflictCopy(String path) => path.contains(conflictSuffix);

/// The id a note's front matter carries, for tests that check a copy's is fresh.
String? noteIdOf(String body) => frontMatterValue(body, 'id');
