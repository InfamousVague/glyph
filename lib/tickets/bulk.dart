/// Many tickets changed at once (Matt, 2026-10-31: "Select many cards on a board, or rows in a table or list query
/// … A bar appears with: Status, Assignee, Labels, Due, Priority, Move to notebook, Delete (to Trash). Each applies
/// as one undoable batch: one undo for all", "the batch stays safe: no partial writes left on failure; report what
/// failed"). The pure half: what each choice writes, and the batch that writes it; the bar is
/// lib/tickets/ui/bulk_bar.dart and the store the root's.
///
/// **A batch is all or nothing.** Every note is read first and its new words made; a note that is gone, or that the
/// change leaves as it was, is reported and not written. Then each is written in turn, from the revision read, so a
/// note changed elsewhere meanwhile is refused rather than overwritten. Where one write fails, the ones already
/// written are put back as they were, and the batch says which failed and why: nothing is left half done. A team
/// note is written as any note is, through the library, which sends it through the team's sync (lib/team).
///
/// **One undo for all.** What a batch wrote it can take back, together: each note whose words are still what the
/// batch left is put back; one changed since is left as it is now, and said.
///
/// Delete is the Trash's, not a write: every note goes in at once and Undo brings them all back.
///
/// Pure but for the store it is handed ([BulkStore]), so a batch, its rollback and its undo are tests
/// (test/tickets/bulk_test.dart).
library;

import '../core/book.dart' show withChapter;
import '../book/book_view.dart' show withoutChapter;
import '../core/properties.dart' show withTicketProperty;
import 'labels.dart' show withLabelsChanged;

/// A change to one note's words: the words in, the words out; null, or the same words, for nothing to write.
typedef BodyChange = String? Function(String body);

/// What a bulk edit sets on every ticket chosen.
sealed class BulkEdit {
  const BulkEdit();

  /// What the bar's toast calls it: "Status set to Done".
  String get said;
}

/// A front matter field set to a value, or taken off for null: status, assignee, due, priority.
class SetField extends BulkEdit {
  const SetField(this.field, this.value, {this.label});
  final String field;
  final String? value;

  /// The field as a person names it; the field's own name where none is given.
  final String? label;

  @override
  String get said {
    final name = label ?? '${field[0].toUpperCase()}${field.substring(1)}';
    return value == null ? '$name taken off' : '$name set to $value';
  }
}

/// Labels added and taken off.
class ChangeLabels extends BulkEdit {
  const ChangeLabels({this.add = const [], this.remove = const []});
  final List<String> add;
  final List<String> remove;

  @override
  String get said => [if (add.isNotEmpty) 'Labelled ${add.join(', ')}', if (remove.isNotEmpty) '${remove.join(', ')} taken off'].join('; ');
}

/// Each ticket's words with [edit] made.
String bulkBody(String body, BulkEdit edit) => switch (edit) {
      SetField(:final field, :final value) => withTicketProperty(body, field, value),
      ChangeLabels(:final add, :final remove) => withLabelsChanged(body, add: add, remove: remove),
    };

/// The plan for moving tickets to another notebook: each one's line out of the notebook it is a page of and into
/// [to]'s index, the notebooks' changes put together so each notebook is written once. [from] is each ticket's own
/// notebook by its id, null for none; [titles] each ticket's title, as its index line names it.
Map<String, BodyChange> movePlan({required String to, required Map<String, String?> from, required Map<String, String> titles}) {
  final plan = <String, List<BodyChange>>{};
  for (final MapEntry(key: ticket, value: notebook) in from.entries) {
    final title = titles[ticket];
    if (title == null || title.isEmpty || notebook == to) continue;
    if (notebook != null) plan.putIfAbsent(notebook, () => []).add((body) => withoutChapter(body, title));
    plan.putIfAbsent(to, () => []).add((body) => withChapter(body, title));
  }
  return {
    for (final MapEntry(:key, :value) in plan.entries)
      key: (body) {
        var out = body;
        for (final change in value) {
          out = change(out) ?? out;
        }
        return out == body ? null : out;
      },
  };
}

// ---- the batch ----------------------------------------------------------------------------------------------------

/// A note as the batch reads it: its words and the revision they are at.
class BulkNote {
  const BulkNote(this.body, this.revision);
  final String body;
  final int revision;
}

/// What a batch reads and writes through: the library, or a test's.
abstract interface class BulkStore {
  /// The note as it is now; null where it is gone.
  Future<BulkNote?> read(String id);

  /// [body] written over [revision]; throws where the note has moved on or cannot be written. Answers the revision
  /// it is at after.
  Future<int> write(String id, String body, int revision);
}

/// One note the batch wrote: what it was, what it is, and the revision that is at.
class Wrote {
  const Wrote({required this.id, required this.before, required this.after, required this.revision});
  final String id;
  final String before;
  final String after;
  final int revision;
}

/// What a batch did: the notes written, the ones that failed and why, and the ones it left as they were.
class BulkOutcome {
  const BulkOutcome({this.wrote = const [], this.failed = const {}, this.unchanged = const []});
  final List<Wrote> wrote;

  /// Why each note that failed did, by its id: "It is gone.", "It was changed somewhere else."
  final Map<String, String> failed;

  /// The notes the change left as they were: already so.
  final List<String> unchanged;

  /// Whether every note it was asked to change was changed (or already so).
  bool get whole => failed.isEmpty;
}

/// Why a write was refused, in words.
String whyFailed(Object error) {
  final said = '$error';
  if (said.contains('evision') || said.contains('onflict') || said.contains('moved on')) return 'It was changed somewhere else.';
  if (said.contains('No such') || said.contains('not found') || said.contains('gone')) return 'It is gone.';
  return 'It could not be written.';
}

/// [plan] written, all or nothing ([BulkOutcome]): every note read and changed first, then written in turn, and
/// where one write fails the ones before it put back.
Future<BulkOutcome> runBulk(Map<String, BodyChange> plan, BulkStore store) async {
  final failed = <String, String>{};
  final unchanged = <String>[];
  final writes = <({String id, String before, String after, int revision})>[];
  for (final MapEntry(key: id, value: change) in plan.entries) {
    BulkNote? note;
    try {
      note = await store.read(id);
    } catch (error) {
      failed[id] = whyFailed(error);
      continue;
    }
    if (note == null) {
      failed[id] = 'It is gone.';
      continue;
    }
    final next = change(note.body);
    if (next == null || next == note.body) {
      unchanged.add(id);
      continue;
    }
    writes.add((id: id, before: note.body, after: next, revision: note.revision));
  }
  // A note that could not even be read: nothing is written.
  if (failed.isNotEmpty) return BulkOutcome(failed: failed, unchanged: unchanged);

  final wrote = <Wrote>[];
  for (final each in writes) {
    try {
      final revision = await store.write(each.id, each.after, each.revision);
      wrote.add(Wrote(id: each.id, before: each.before, after: each.after, revision: revision));
    } catch (error) {
      failed[each.id] = whyFailed(error);
      break;
    }
  }
  if (failed.isEmpty) return BulkOutcome(wrote: wrote, unchanged: unchanged);
  // One failed: the ones written are put back, the last first.
  for (final done in wrote.reversed) {
    try {
      await store.write(done.id, done.before, done.revision);
    } catch (error) {
      failed[done.id] = 'It was changed, and could not be put back: ${whyFailed(error)}';
    }
  }
  return BulkOutcome(failed: failed, unchanged: unchanged);
}

/// What a batch wrote, taken back together: each note whose words are still what [outcome] left put back as it
/// was; one changed since is left, and said in [BulkOutcome.failed].
Future<BulkOutcome> undoBulk(BulkOutcome outcome, BulkStore store) async {
  final failed = <String, String>{};
  final wrote = <Wrote>[];
  for (final done in outcome.wrote.reversed) {
    try {
      final now = await store.read(done.id);
      if (now == null) {
        failed[done.id] = 'It is gone.';
        continue;
      }
      if (now.body != done.after) {
        failed[done.id] = 'It was changed since, so it is left as it is.';
        continue;
      }
      final revision = await store.write(done.id, done.before, now.revision);
      wrote.add(Wrote(id: done.id, before: done.after, after: done.before, revision: revision));
    } catch (error) {
      failed[done.id] = whyFailed(error);
    }
  }
  return BulkOutcome(wrote: wrote, failed: failed);
}

/// What the toast says after a batch: "Status set to Done on 3 tickets.", or which failed. [count] is how many
/// tickets it was for, where the notes it wrote are others (a move writes the notebooks).
String bulkReport(BulkOutcome outcome, String said, {required String Function(String id) nameOf, int? count}) {
  final tickets = count ?? outcome.wrote.length + outcome.unchanged.length;
  if (outcome.whole) return '$said on $tickets ${tickets == 1 ? 'ticket' : 'tickets'}.';
  final names = [for (final MapEntry(:key, :value) in outcome.failed.entries) '${nameOf(key)}: $value'];
  return 'Nothing was changed. ${names.join(' ')}';
}
