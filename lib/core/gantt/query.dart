/// A query drawn as a Gantt chart (`show: gantt`, and `show: timeline`, which is the same chart now): its rows as the
/// chart's bars ([GanttModel]), so the chart a ```gantt fence draws (plan.dart) draws a query's too, and a bar carried
/// writes the record's own fields (lib/editor/queries/query_gantt.dart).
///
/// - A row runs from the day in its query's `start:` field to the day in its `end:` field (`start` and `due` unsaid,
///   run.dart puts them on the row); one with only one of the two is a day long; one with neither is drawn dashed on
///   today, to be carried to its days.
/// - Each group of the query is a section, in its order; a query not grouped is one with no name.
/// - What a ticket waits on (`blocked-by:`, as its card's lock says) is an arrow from the row of each that is on the
///   chart.
/// - A row done is quiet, one overdue is late, and its person is the query's `assignee` column where it has one.
///
/// Pure (test/gantt/query_test.dart).
library;

import '../properties.dart' show StatusCategory;
import '../query/query.dart';
import 'format.dart';
import 'plan.dart';

/// The chart [result] draws on [today]: [blockers] are the ticket keys each row waits on, where they are known.
GanttModel ganttOfQuery(QueryResult result, String today, {List<String> Function(QueryRow row)? blockers}) {
  final person = result.columns.indexWhere((column) => column.field == 'assignee');
  final byId = <String, String>{
    for (final group in result.groups)
      for (final row in group.rows)
        if (row.id != null && row.id!.isNotEmpty) row.id!.toUpperCase(): row.key,
  };
  final groups = <GanttGroup>[];
  for (final group in result.groups) {
    final index = groups.length;
    final items = <GanttItem>[];
    for (final row in group.rows) {
      final one = row.start ?? row.end;
      final two = row.end ?? row.start;
      var start = one ?? today;
      var end = two ?? start;
      if (end.compareTo(start) < 0) (start, end) = (end, start);
      final cell = person >= 0 && person < row.cells.length ? row.cells[person] : null;
      final done = row.category == StatusCategory.done || row.done == true;
      items.add(
        GanttItem(
          key: row.key,
          name: row.name,
          label: row.id != null && row.id!.isNotEmpty ? row.id : null,
          start: start,
          end: end,
          group: index,
          undated: one == null,
          done: done,
          late: row.overdue,
          progress: done ? 100 : null,
          person: cell is PeopleCell && cell.names.isNotEmpty ? cell.names.first : null,
          after: [
            for (final key in blockers?.call(row) ?? const <String>[])
              if (byId[key.toUpperCase()] case final found? when found != row.key) found,
          ],
          ticket: GanttTicket(noteId: row.noteId, title: row.name, key: row.id, start: row.start, due: row.end, done: done),
        ),
      );
    }
    groups.add(GanttGroup(name: group.label, items: items));
  }
  final zoom = switch (result.zoom) {
    TimelineZoom.week => GanttZoom.week,
    TimelineZoom.month => GanttZoom.month,
    TimelineZoom.quarter => GanttZoom.quarter,
    null => null,
  };
  // A query's chart follows nothing: each row's days are its own record's, written one at a time.
  return GanttModel(groups: groups, today: today, zoom: zoom, follow: false);
}
