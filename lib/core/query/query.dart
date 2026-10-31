/// The query core's door: the grammar read (read.dart), what a field says (values.dart), the library a query reads
/// (records.dart), a query run (run.dart), and the ways it is shown and changed (fence.dart, gantt.dart,
/// calendar.dart, draft.dart, templates.dart, move.dart, tick.dart), and the port's own: a rollup worked out over linked
/// notes (rollup.dart), a chart's bars (chart.dart), a drawn timeline's plan (timeline.dart) and the lines written
/// back (write.dart). The web has no such file: its callers import
/// each module of `src/app/core/query/` by name. Here one import brings the lot.
library;

export 'calendar.dart';
export 'chart.dart';
export 'collate.dart';
export 'draft.dart';
export 'fence.dart';
export 'gantt.dart';
export 'move.dart';
export 'planning.dart';
export 'read.dart';
export 'records.dart';
export 'rollup.dart';
export 'run.dart';
export 'templates.dart';
export 'tick.dart';
export 'timeline.dart';
export 'values.dart';
export 'write.dart';
