/// A query drawn as a Gantt chart (`show: gantt`, and `show: timeline`, read as the same chart): the chart a ```gantt
/// fence draws (lib/editor/gantt/gantt_chart.dart), over the query's rows (lib/core/gantt/query.dart). Matt,
/// 2026-10-31: "work on making a better gannt chart implementation in markdown replacing the one we have now that's
/// quite hard to interact with": the Mermaid picture `show: gantt` was, and the drawn timeline beside it, are this one
/// chart now.
///
/// Each row is a record, as its ticket is a `[[link]]` in a fence: a bar carried, or its ends, writes the record's own
/// start and end fields (`start:` and `end:`, `start` and `due` unsaid) into its front matter, or a to-do's line,
/// through the query's one writer ([QueryActs.onSet]); its panel's person writes its `assignee`. What a ticket waits on
/// (`blocked-by:`) is an arrow, drawn and not drawn from here: a query's rows are not its lines to write, so adding a
/// task, a wait, a row's place and a name are the fence's and the record's own. Its panel's Open opens the record.
library;

import 'package:flutter/widgets.dart';

import '../../core/gantt/gantt.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/query/query.dart';
import '../gantt/gantt_chart.dart';
import 'query_look.dart';
import 'query_parts.dart';

class QueryGanttView extends StatelessWidget {
  const QueryGanttView({super.key, required this.look, required this.result, required this.acts});

  final QueryLook look;
  final QueryResult result;
  final QueryActs acts;

  @override
  Widget build(BuildContext context) {
    final rows = <String, QueryRow>{
      for (final group in result.groups)
        for (final row in group.rows) row.key: row,
    };
    final model = ganttOfQuery(result, acts.today, blockers: acts.marks == null ? null : (row) => acts.marks!(row)?.blockers ?? const <String>[]);
    final onSet = acts.onSet;
    final writes = acts.editable && onSet != null;
    final actions = GanttActions(
      move: !writes
          ? null
          : (key, start, end, how) {
              final row = rows[key];
              final item = model.byKey[key];
              if (row == null || row.kind == RecordKind.event || item == null) return null;
              // Each end carried writes its own field: where it changed, or where the record had none and the bar
              // was carried by that end (or whole).
              if (how != GanttGrip.end && (start != item.start || row.start == null)) onSet(row, result.startField, start);
              if (result.endField != result.startField && how != GanttGrip.start && (end != item.end || row.end == null)) onSet(row, result.endField, end);
              return null;
            },
      setPeople: !writes
          ? null
          : (key, people) {
              final row = rows[key];
              if (row == null) return null;
              onSet(row, 'assignee', people.isEmpty ? null : people.first.replaceFirst(RegExp('^@+'), ''));
              return null;
            },
      open: (item) {
        final row = rows[item.key];
        if (row != null) acts.onOpen(row);
      },
    );
    return GanttChart(look: look, model: model, actions: actions, simple: preferences.value.simple, label: 'Gantt', titled: false);
  }
}
