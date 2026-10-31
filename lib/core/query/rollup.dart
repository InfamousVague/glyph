/// A query's column worked out over the notes a record is linked with (the port's own; Matt, 2026-10-30, "add all
/// 12": relations and rollups, as a database's are). A rollup line names the column and says what it works out:
///
///     rollup: open = count(links where status != done)       the open tickets a notebook's index links to
///     rollup: hours = sum(hours of backlinks)                the hours on every page that links to a project
///     rollup: spent = sum(hours of backlinks.project)        the pages whose `project: [[…]]` names this one
///     rollup: shipped = percent(tasks)                       how many of the note's own to-dos are ticked
///     rollup: due = max(due of project)                      the latest due day of the notes `project:` names
///
/// Which notes: `links` (the notes its `[[links]]` name, its front matter's among them), `backlinks` (the notes whose
/// links name it), `tasks` (the to-dos in its note), a field that holds links (`project`, a relation, read as
/// properties.dart `linkTargets` reads it) and `backlinks.<field>` (the notes whose field names it: the relation from
/// the other side). What: `count`, `sum`, `average`, `min`, `max` of a field, as a total adds one up (sums.dart), a
/// day's least and most where the field holds days, and `percent`, the share of them that are done (a ticket or a
/// note by its status, a to-do by its box), weighed by a field where one is named. A `where` inside is a test on
/// each of those notes, in `where:`'s own grammar.
///
/// **Fast.** Everything is read from the library the query already has (records.dart): each record's links are its
/// note's, read once while its words stay the same, so nothing here opens a note. The notes that link to each note,
/// and to each by a field, are found once a run, on the first rollup that asks, and a record's rollup is worked out
/// once a run, on the first test, sort, cell or chart that reads it: a query whose rows never read one works none
/// out. A rollup is a value like any other once it is worked out: `where: open > 0`, `sort: open desc`,
/// `columns: title, open`, `total: open` and a chart's `y: sum(open)` all read it.
library;

import '../durations.dart' show spentTotal;
import '../properties.dart' show StatusCategory, linkTargets;
import '../sums.dart' show leadingNumber, totalOf, writtenNumber;
import 'read.dart';
import 'records.dart';
import 'values.dart';

/// What a field says on a record, rollups among them: run.dart's way of reading every field.
typedef FieldLook = Value Function(QueryRecord record, String field);

/// A value as a number, where it is one: a number, or words that start with one, as a total reads them (`5h`,
/// `$1,200 a month`).
double? numberOf(Value value) => switch (value) {
      NumberValue(:final value) => value,
      TextValue(:final text) => switch (leadingNumber(text)) {
          final lead? => writtenNumber(lead),
          null => null,
        },
      _ => null,
    };

/// A number as a cell writes one: a whole one bare, any other to two places at most.
String plainNumber(double value) {
  if (!value.isFinite) return '0';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Whether a record is finished with: a status that is done, or a ticked box.
bool isFinished(QueryRecord record) => record.done == true || categoryOf(record) == StatusCategory.done;

/// [measure] over [records], each field read through [look]: a count, a sum, an average, the least, the most, or the
/// share done. Nothing to work out is 0 for a count and a sum, and nothing at all for the rest.
Value aggregate(Measure measure, List<QueryRecord> records, FieldLook look) {
  final field = measure.field;
  switch (measure.fn) {
    case Aggregate.count:
      final n = field == null ? records.length : records.where((record) => !isEmptyValue(look(record, field))).length;
      return NumberValue(n.toDouble(), '$n');
    case Aggregate.sum:
      if (field == null) return NumberValue(records.length.toDouble(), '${records.length}');
      final texts = <String>[];
      var sum = 0.0;
      for (final record in records) {
        final value = look(record, field);
        final number = numberOf(value);
        if (number == null) continue;
        sum += number;
        texts.add(value is NumberValue ? value.text : (value as TextValue).text);
      }
      // Time spent is added up as time (`3h 20m` and `45m` are `4h 5m`; lib/core/durations.dart).
      if (spentTotal(texts) case final spent?) return NumberValue(sum, spent);
      // Written as a total writes it, its currency and its commas kept (`$1,200` and `$300` are `$1,500`).
      final written = texts.isEmpty ? null : totalOf(texts);
      return NumberValue(sum, written != null && writtenNumber(written) == sum ? written : plainNumber(sum));
    case Aggregate.average:
      final numbers = [for (final record in records) ?numberOf(look(record, field!))];
      if (numbers.isEmpty) return emptyValue;
      final mean = numbers.fold<double>(0, (a, b) => a + b) / numbers.length;
      return NumberValue(mean, plainNumber(mean));
    case Aggregate.min || Aggregate.max:
      final most = measure.fn == Aggregate.max;
      Value? best;
      for (final record in records) {
        final value = look(record, field!);
        if (value is DayValue) {
          if (best is! DayValue || (most ? value.day.compareTo(best.day) > 0 : value.day.compareTo(best.day) < 0)) best = value;
          continue;
        }
        final number = numberOf(value);
        if (number == null || best is DayValue) continue;
        final had = best == null ? null : numberOf(best);
        if (had == null || (most ? number > had : number < had)) best = value is NumberValue ? value : NumberValue(number, (value as TextValue).text);
      }
      return best ?? emptyValue;
    case Aggregate.percent:
      var done = 0.0;
      var all = 0.0;
      for (final record in records) {
        final weight = field == null ? 1.0 : numberOf(look(record, field));
        if (weight == null) continue;
        all += weight;
        if (isFinished(record)) done += weight;
      }
      if (all == 0) return emptyValue;
      final share = 100 * done / all;
      return NumberValue(share, '${share.round()}%');
  }
}

/// Whether [record] passes [condition] on [today], each field read through [look]: `where:`'s test, and a rollup's.
bool holdsOn(Condition condition, QueryRecord record, String today, FieldLook look) => switch (condition) {
      Compare(:final field, :final op, :final value) => valueMatches(look(record, field), op, value, today),
      EmptyTest(:final field, :final empty) => isEmptyValue(look(record, field)) == empty,
      Has(:final field) => says(look(record, field)),
      NotCondition(:final of) => !holdsOn(of, record, today, look),
      AndCondition(:final all) => all.every((each) => holdsOn(each, record, today, look)),
      OrCondition(:final any) => any.any((each) => holdsOn(each, record, today, look)),
    };

/// The library's notes by id, who links to whom, and each note's to-dos: found once a run, on the first rollup
/// that asks.
class LinkIndex {
  LinkIndex(this.library);

  final QueryLibrary library;

  /// Each note's own record (a note or a ticket) by its id.
  late final Map<String, QueryRecord> notes = () {
    final byId = <String, QueryRecord>{};
    for (final record in library.records) {
      if (record.kind == RecordKind.note || record.kind == RecordKind.ticket) byId.putIfAbsent(record.noteId, () => record);
    }
    return byId;
  }();

  /// The notes that link to each note, by its id, in the library's order; a note's link to itself is not one.
  late final Map<String, List<QueryRecord>> backlinks = () {
    final into = <String, List<QueryRecord>>{};
    for (final note in notes.values) {
      for (final id in note.linksTo) {
        if (id != note.noteId) into.putIfAbsent(id, () => []).add(note);
      }
    }
    return into;
  }();

  /// Each note's to-dos, by its id.
  late final Map<String, List<QueryRecord>> tasks = () {
    final into = <String, List<QueryRecord>>{};
    for (final record in library.records) {
      if (record.kind == RecordKind.task) into.putIfAbsent(record.noteId, () => []).add(record);
    }
    return into;
  }();

  final Map<String, Map<String, List<QueryRecord>>> _named = {};

  /// What a record's [field] says, as written: a note's front matter, a to-do's `[field:: …]`.
  static String? said(QueryRecord record, String field) => record.kind == RecordKind.task ? record.fields?.fields[field] : record.props[field];

  /// The notes [record]'s [field] names, in the order it names them: a relation.
  List<QueryRecord> related(QueryRecord record, String field) {
    final found = <QueryRecord>[];
    for (final title in linkTargets(said(record, field))) {
      final note = noteNamed(library, title);
      final target = note == null ? null : notes[note.id];
      if (target != null && target.noteId != record.noteId && !found.contains(target)) found.add(target);
    }
    return found;
  }

  /// The notes whose [field] names the note [id]: the relation from the other side.
  List<QueryRecord> namedBy(String field, String id) {
    final byTarget = _named.putIfAbsent(field, () {
      final into = <String, List<QueryRecord>>{};
      for (final note in notes.values) {
        for (final target in related(note, field)) {
          into.putIfAbsent(target.noteId, () => []).add(note);
        }
      }
      return into;
    });
    return byTarget[id] ?? const [];
  }

  /// The records [rollup] works over from [record].
  List<QueryRecord> reach(QueryRecord record, Rollup rollup) => switch (rollup.way) {
        RollupWay.links => [
            for (final id in record.linksTo)
              if (id != record.noteId) ?notes[id],
          ],
        RollupWay.backlinks => backlinks[record.noteId] ?? const [],
        RollupWay.tasks => tasks[record.noteId] ?? const [],
        RollupWay.relation => related(record, rollup.through ?? ''),
        RollupWay.backRelation => namedBy(rollup.through ?? '', record.noteId),
      };
}

/// How a query run reads a field: [valueOf], and each of [rollups] by its name, worked out once a record over
/// [library] and kept for the run. An event has no links, and no rollup.
FieldLook rollupLook(List<Rollup> rollups, QueryLibrary library, String today) {
  if (rollups.isEmpty) return valueOf;
  final byName = {for (final rollup in rollups) rollup.name: rollup};
  final index = LinkIndex(library);
  final kept = Map<QueryRecord, Map<String, Value>>.identity();
  Value look(QueryRecord record, String field) {
    final rollup = byName[field];
    if (rollup == null || record.kind == RecordKind.event) return valueOf(record, field);
    final mine = kept.putIfAbsent(record, () => <String, Value>{});
    final had = mine[field];
    if (had != null) return had;
    final where = rollup.where;
    final over = [
      for (final each in index.reach(record, rollup))
        if (where == null || holdsOn(where, each, today, valueOf)) each,
    ];
    return mine[field] = aggregate(rollup.measure, over, valueOf);
  }

  return look;
}
