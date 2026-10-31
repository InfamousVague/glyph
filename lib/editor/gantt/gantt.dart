/// A ```gantt fence, drawn as the Gantt chart it is (docs/GANTT.md; Matt, 2026-10-31: "work on making a better gannt
/// chart implementation in markdown replacing the one we have now that's quite hard to interact with").
///
/// The fence is a list, readable as one anywhere (lib/core/gantt/format.dart); here it is drawn in place of its lines
/// as a table and a board are, and everything done to the chart (gantt_chart.dart) writes the fence's lines back
/// (lib/core/gantt/edits.dart): only the lines it changes, as one step of the note's undo, under the `input.gantt`
/// user event. The pencil in the chart's bar puts the caret in the fence, and the drawing steps aside for its lines.
///
/// A task that is a `[[ticket]]` is read from the library the screen hands the editor (the queries' own
/// [QueryOptions]): its days, person and status are the ticket's, and carrying its bar writes the ticket's `start:`
/// and `due:`, through the screen, into the ticket's front matter. Those writes are the ticket's own note's, and not
/// this note's undo; the fence's lines are.
///
/// The note screen adds [drawnGantt] to its extensions beside [queries], with the same options.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../core/boards/fence.dart' show closesBoardFence;
import '../../core/days.dart' show isIsoDay;
import '../../core/gantt/gantt.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/properties.dart' show StatusCategory, withProperty;
import '../../core/query/query.dart';
import '../editor.dart';
import '../items/task_fields.dart' show fieldsToday;
import '../items/field_menu.dart' show todayIs;
import '../queries/queries.dart' show QueryOptions, refreshQueries;
import '../queries/query_look.dart';
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/line_facts.dart' show bareFenceFacts;
import 'gantt_chart.dart';

export 'gantt_chart.dart';
export 'gantt_panel.dart';

/// What a change a chart makes to its fence is called in the note's history.
const String ganttUserEvent = 'input.gantt';

/// A ```gantt fence in a document: its opening and closing lines (from 1) and what is between them.
class GanttFence {
  const GanttFence({required this.from, required this.to, required this.body});
  final int from;
  final int to;
  final String body;

  /// Whether it has no lines between its two.
  bool get empty => to == from + 1;
}

final RegExp _opening = RegExp(r'^\s*(`{3,}|~{3,})\s*gantt\s*$', caseSensitive: false);

final LineFact<String> _openings = LineFact<String>((text) {
  if (!text.contains('```') && !text.contains('~~~')) return null;
  return _opening.firstMatch(text)?.group(1);
});

final DocMemo<List<GanttFence>> _fences = DocMemo<List<GanttFence>>((doc) {
  final openings = _openings.of(doc);
  if (openings.isEmpty) return const <GanttFence>[];
  final closers = bareFenceFacts.of(doc);
  final found = <GanttFence>[];
  var after = 0, closer = 0;
  for (final open in openings) {
    if (open.number <= after) continue;
    while (closer < closers.length && closers[closer].number <= open.number) {
      closer += 1;
    }
    var end = -1;
    for (var at = closer; at < closers.length; at += 1) {
      if (closesBoardFence(closers[at].fact, open.fact)) {
        end = closers[at].number;
        break;
      }
    }
    // One never closed is still being typed: nothing after it is looked at.
    if (end < 0) break;
    final body = end > open.number + 1 ? doc.sliceString(open.to + 1, doc.line(end - 1).to) : '';
    found.add(GanttFence(from: open.number, to: end, body: body));
    after = end;
  }
  return found;
});

/// Every closed ```gantt fence of a document, in order, worked out once for each document.
List<GanttFence> ganttFencesOf(Doc doc) => _fences.of(doc);

/// The ticket [title] names in [library], as a chart reads one.
GanttTicket? ticketIn(QueryLibrary library, String title) {
  final note = noteNamed(library, title);
  if (note == null) return null;
  QueryRecord? record;
  for (final each in library.records) {
    if (each.noteId == note.id && each.kind != RecordKind.task) {
      record = each;
      break;
    }
  }
  if (record == null) return null;
  final props = record.props;
  String? day(String key) {
    final value = props[key];
    return value != null && isIsoDay(value) ? value : null;
  }

  final ticket = record.ticket;
  final assignee = ticket?.assignee ?? props['assignee']?.replaceFirst(RegExp('^@+'), '');
  return GanttTicket(
    noteId: note.id,
    title: record.title,
    key: ticket?.id,
    start: ticket?.start ?? day('start'),
    due: ticket?.due ?? day('due'),
    assignee: assignee == null || assignee.isEmpty ? null : assignee,
    done: categoryOf(record) == StatusCategory.done,
    status: ticket?.status ?? props['status'],
  );
}

/// The library read for each editor, kept while each note's words stay the same.
final Expando<RecordCache> _caches = Expando<RecordCache>('gantt records');

/// A chart drawn in place of its fence.
class GanttWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const GanttWidget({required this.body, required this.from, required this.at, required this.stamp, required this.today, required this.canEdit, required this.options});

  final String body;

  /// Where the opening fence's line starts, and where the caret goes to show its lines.
  final int from;
  final int at;

  /// Moves when the library does, which is when a ticket's days can.
  final int stamp;
  final String today;
  final bool canEdit;
  final QueryOptions? Function() options;

  @override
  String get className => 'cm-gantt';

  @override
  bool eq(GanttWidget other) => other.body == body && other.from == from && other.at == at && other.stamp == stamp && other.today == today && other.canEdit == canEdit;

  @override
  double get estimatedHeight => 80 + ganttDaysHead + ganttRow * '\n'.allMatches(body).length;

  @override
  Widget build(BuildContext context) => DrawnGantt(widget: this);

  /// Every press on the chart is its own: a bar carried, a row chosen. None of it moves the caret.
  @override
  bool takesPointer(PointerEvent event) => true;
}

/// The fence read and drawn, and what each thing done to it writes.
class DrawnGantt extends StatelessWidget {
  const DrawnGantt({super.key, required this.widget});

  final GanttWidget widget;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.of(context);
    final options = widget.options();
    final body = readGantt(widget.body);
    QueryLibrary? library;
    GanttTicket? find(String title) {
      if (options == null) return null;
      library ??= libraryOf(options.notes(), _caches[view] ??= recordCache());
      return ticketIn(library!, title);
    }

    final tickets = body.tasks.any((task) => task.link != null) ? find : null;
    final model = ganttModelOf(body, today: widget.today, tickets: tickets);
    final editable = widget.canEdit;

    /// The fence as the live document has it, where the widget was told it starts.
    GanttFence? fence() {
      final doc = view.state.doc;
      if (widget.from > doc.length) return null;
      final line = doc.lineAt(widget.from);
      if (line.from != widget.from) return null;
      return ganttFencesOf(doc).where((each) => each.from == line.number).firstOrNull;
    }

    /// The fence's body and chart as they are now, for a change to be worked out on.
    ({GanttBody body, GanttModel model})? now() {
      final found = fence();
      if (found == null) return null;
      final read = readGantt(found.body);
      return (body: read, model: ganttModelOf(read, today: widget.today, tickets: read.tasks.any((task) => task.link != null) ? find : null));
    }

    /// Writes [change]: the fence's lines into the editor as one step, the tickets' fields through the screen.
    /// Answers why nothing was written, or null.
    String? write(GanttChange change) {
      if (change.refused != null) return change.refused;
      final found = fence();
      if (found == null) return null;
      final doc = view.state.doc;
      final specs = <ChangeSpec>[];
      if (change.lines.isNotEmpty) {
        if (found.empty) {
          var text = appliedGantt('', change);
          if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
          specs.add(ChangeSpec(from: doc.line(found.to).from, insert: '$text\n'));
        } else {
          for (final each in change.lines) {
            final first = found.from + 1 + each.at;
            if (each.remove > 0) {
              final last = first + each.remove - 1;
              final from = doc.line(first).from;
              var to = doc.line(last).to;
              if (each.insert.isEmpty) to += 1;
              specs.add(ChangeSpec(from: from, to: to, insert: each.insert.join('\n')));
            } else {
              specs.add(ChangeSpec(from: doc.line(first).from, insert: '${each.insert.join('\n')}\n'));
            }
          }
        }
        view.dispatch(TransactionSpec(changes: specs, userEvent: ganttUserEvent, annotations: isolateHistory.of('full')));
      }
      for (final ticket in change.tickets) {
        String put(String text) => ticket.fields.entries.fold<String>(text, (body, field) => withProperty(body, field.key, field.value));
        if (ticket.ticket.noteId == options?.noteId) {
          final text = view.state.doc.toString();
          final next = put(text);
          if (next != text) view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: text.length, insert: next), userEvent: ganttUserEvent));
        } else {
          options?.write(ticket.ticket.noteId, put);
        }
      }
      return null;
    }

    String? act(GanttChange Function(GanttBody body, GanttModel model) make) {
      final had = now();
      if (had == null) return null;
      return write(make(had.body, had.model));
    }

    final actions = !editable
        ? GanttActions(open: options == null ? null : (item) => options.open(item.ticket!.noteId, null))
        : GanttActions(
            move: (key, start, end, how) => act((body, model) => moveDays(body, model, key, start, end, how: how)),
            addWait: (key, on) => act((body, model) => addWait(body, model, key, on, tickets: tickets)),
            removeWait: (key, on) => act((body, model) => removeWait(body, model, key, on)),
            add: ({String? afterKey, int? group, required String start, String? end}) {
              final had = now();
              if (had == null) return null;
              final change = addTask(had.body, had.model, afterKey: afterKey, group: group, start: start, end: end);
              write(change);
              return change.select == null ? null : ganttLineKey(change.select!);
            },
            delete: (key) => act((body, model) => deleteTask(body, model, key)),
            moveRow: (key, group, before) => act((body, model) => moveRow(body, model, key, group: group, beforeKey: before)),
            rename: (key, name) => act((body, model) => renameTask(body, model, key, name)),
            setPeople: (key, people) => act((body, model) => setPeople(body, model, key, people)),
            setProgress: (key, progress) => act((body, model) => setProgress(body, model, key, progress)),
            setColour: (key, colour) => act((body, model) => setColour(body, model, key, colour)),
            setMilestone: (key, milestone) => act((body, model) => setMilestone(body, model, key, milestone)),
            setWaits: (key, names) => act((body, model) => setWaits(body, model, key, names, tickets: tickets)),
            setFront: (key, value) => act((body, _) => setFront(body, key, value)),
            open: options == null ? null : (item) => options.open(item.ticket!.noteId, null),
            onText: () {
              view.focus();
              view.dispatch(TransactionSpec(selection: EditorSelection.single(widget.at), scrollIntoView: true));
            },
            undo: () => undoNote(view),
            redo: () => redoNote(view),
          );
    final look = QueryLook.of(context, view is EditorView ? view.look : null);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: look.bleed, vertical: look.blockEnds),
      child: GanttChart(look: look, model: model, actions: actions, simple: preferences.value.simple, label: model.title == null ? 'Gantt chart' : 'Gantt chart: ${model.title}'),
    );
  }
}

class _Drawn {
  const _Drawn(this.stamp, this.today, this.decorations);
  final int stamp;
  final String today;
  final DecorationSet decorations;
}

String _today(EditorState state) => state.facet(fieldsToday)?.call() ?? todayIs();

DecorationSet _decorate(EditorState state, int stamp, String today, QueryOptions? Function() options) {
  final fences = ganttFencesOf(state.doc);
  if (fences.isEmpty) return Decoration.none;
  final ranges = <Range<Decoration>>[];
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  for (final fence in fences) {
    final from = state.doc.line(fence.from).from;
    final to = state.doc.line(fence.to).to;
    // The caret in the fence: its lines, to type. Elsewhere, and in a view with no caret, the chart.
    if (editable && caretIn(state, from, to)) continue;
    final at = state.doc.line(fence.from + 1 < fence.to ? fence.from + 1 : fence.to).from;
    ranges.add(Decoration.replace(widget: GanttWidget(body: fence.body, from: from, at: at, stamp: stamp, today: today, canEdit: editable, options: options), block: true).range(from, to));
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

/// Every ```gantt fence drawn as its chart where the caret is not in it; [options] is the library its tickets are
/// read from, the queries' own (none, and a `[[ticket]]` is a task like any other).
Extension drawnGantt([QueryOptions? Function()? options]) {
  QueryOptions? read() => options?.call();
  final field = StateField.define<_Drawn>(
    create: (state) {
      final today = _today(state);
      return _Drawn(0, today, _decorate(state, 0, today, read));
    },
    update: (value, tr) {
      final refreshed = tr.effects.any((effect) => effect.isOf(refreshQueries));
      if (!refreshed && !tr.docChanged && tr.selection == null && !tr.reconfigured && !focusMoved(tr)) return value;
      final today = _today(tr.state);
      // A note with no chart draws none, whatever was typed.
      if (!refreshed && !tr.reconfigured && today == value.today && identical(value.decorations, Decoration.none) && ganttFencesOf(tr.state.doc).isEmpty) return value;
      final stamp = value.stamp + (refreshed ? 1 : 0);
      return _Drawn(stamp, today, _decorate(tr.state, stamp, today, read));
    },
    provide: (field) => EditorViewLike.decorations.from<_Drawn>(field, (value) => value.decorations),
  );
  return Extension.list(<Extension>[trackFocus, field]);
}
