/// A ```query fence, drawn as what it finds (../glyph docs/QUERIES.md, docs/DESIGN.md §159). Ports
/// `src/app/editor/queries.ts`. Matt asked what "notion and jira like features" Markdown could give the app and took
/// the database view among the first three: a fence of a few lines, `from: tickets #bug`,
/// `where: status != Done`, `show: board`, which any other app shows as the lines it is.
///
/// The lines are read by lib/core/query/read.dart and run over the library by run.dart; this is where the result is
/// drawn, in place of the fence, the way a board, a table and a diagram are drawn in place of theirs
/// (view/drawn_block.dart): the caret in the fence steps the drawing aside so the lines can be typed, and the pencil
/// at its head puts the caret there. A query that cannot be read is drawn as its lines and the sentence that says
/// what is wrong and where.
///
/// **Live.** A query reads every note the screen hands it ([QueryOptions.notes]), the open note as its editor has
/// it, so a to-do typed under a query of to-dos is in it at once; and it is drawn again whenever the library changes
/// ([refreshQueries]), the note changes, and at midnight, when `today` moves. A note's reading is kept while its
/// words stay the same (lib/core/query/records.dart [RecordCache], one per editor), so a keystroke reads one note
/// again, not all.
///
/// **What a tap does.** A note or a ticket opens; a to-do opens its note at its line, or, in this note, puts the
/// caret there. A to-do's box ticks it where it is written: in this note with the same edit a tap on the box makes
/// (commands/task_toggle.dart `toggleBox`, its boards settled in the same undo), and in another through the screen
/// ([QueryOptions.write] with lib/core/query/tick.dart). A card dragged to another lane sets the field the board
/// groups by, and a value picked from its sheet (fields/field_picker.dart) sets that field: both through one writer,
/// into the editor for this note and through the screen for another (lib/core/query/move.dart). Nothing else in a
/// drawn query writes anything.
///
/// The note screen adds it to its extensions as Editor.tsx lists `queries(() => wikiRef.current?.queries ?? null)`:
///
///     noteExtensions(more: [queries(() => options)])
///
/// and dispatches [refreshQueries] when its library changes.
///
/// What differs:
/// - **One way to write another note.** The page's options had `tick(noteId, line, source, done)` and
///   `move(noteId, line, source, kind, field, value)`, each of which the screen answered by reading the note, making
///   the change (core/query/tick.ts, move.ts) and saving it. Here the options have the one [QueryOptions.write]: the
///   note's id and the change to make to its words, which is `tickedBody` or `movedBody` with the row's own line and
///   words already in it. The host reads the note as it stands, applies the change and keeps what comes back, and
///   leaves the note alone where the change answers null (the line is gone) or the same words.
/// - **The options are asked for by a function**, as on the page, and the day is the editor's own where it has one
///   (items/task_fields.dart `fieldsToday`), so a query and the chips on a line never disagree about today.
/// - **Where the fence is** was asked of the page when a control was pressed (`posAtDOM`); a widget here is told
///   where its fence starts when it is made, and it is made again on every change to the note.
/// - `boardRoom`'s `--cm-board-room` has no counterpart: a block is laid out in the editor's own width.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../book/tickets.dart' show peopleIn;
import '../../core/book.dart' show withChapter;
import '../../core/item_syntax.dart' show taskBox;
import '../../core/properties.dart' show withProperty;
import '../../core/query/query.dart';
import '../commands/task_toggle.dart' show toggleBox;
import '../editor.dart';
import '../items/field_menu.dart' show dayPicker, todayIs;
import '../items/task_fields.dart' show fieldsLocale, fieldsToday;
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import 'query_look.dart';
import 'query_view.dart';

export 'query_builder.dart';
export 'query_gantt.dart';
export 'query_layout.dart' show Part;
export 'query_look.dart' show QueryLook;
export 'query_view.dart';

/// A change to a note's words: the words as they stand in, the words to keep out; null, or the same words, where
/// there is nothing to write.
typedef NoteChange = String? Function(String body);

/// What the screen hands the editor for its queries: the library, and how to reach and write what a query lists.
class QueryOptions {
  const QueryOptions({required this.notes, required this.noteId, required this.open, required this.write, this.add});

  /// Every note a query reads: the library a screen shows, without the Trash, the archive, the Guide or templates'
  /// pages.
  final List<QueryNote> Function() notes;

  /// The open note's id, whose words are read as its editor has them; null for a note not yet in the store.
  final String? noteId;

  /// Opens another note, at a to-do's line (from 0), or where it opens with null.
  final void Function(String noteId, int? line) open;

  /// Changes another note's words: a to-do ticked or cleared, a field set or taken off. The host reads the note as
  /// it stands, applies [NoteChange] and saves what it answers, unless that is null or what was there.
  final void Function(String noteId, NoteChange change) write;

  /// Makes a ticket from a lane of a board (lib/core/query/draft.dart): the draft says what it must say to land in
  /// the lane, `from` is the note the board is drawn in. Answers true where that note is the notebook the ticket
  /// went in, whose index line is then this editor's to write, so the open note is never written under its own
  /// editor.
  final Future<bool> Function(TicketDraft draft, String title, String? from)? add;
}

/// The library changed: every query is run and drawn again.
final StateEffectType<Null> refreshQueries = StateEffect.define<Null>();

/// What a change a query makes to its own note is called in the note's history.
const String queryUserEvent = 'input.query';

/// The library read for each editor, kept while each note's words stay the same.
final Expando<RecordCache> _caches = Expando<RecordCache>('query records');

RecordCache _cacheOf(EditorViewLike view) => _caches[view] ??= recordCache();

/// The library with the open note read as it is typed, and added where the store has not got it yet.
List<QueryNote> _withOpen(List<QueryNote> notes, String? id, String body) {
  if (id == null || id.isEmpty) return <QueryNote>[...notes];
  final at = notes.indexWhere((note) => note.id == id);
  final now = DateTime.now().millisecondsSinceEpoch;
  if (at < 0) return <QueryNote>[...notes, QueryNote(id: id, body: body, createdAt: now, updatedAt: now)];
  final list = <QueryNote>[...notes];
  list[at] = QueryNote(id: id, body: body, createdAt: list[at].createdAt, updatedAt: list[at].updatedAt);
  return list;
}

/// A row's line in this editor: where the query read it, or where its words are now; null where it is gone.
int? _lineOf(EditorState state, QueryRow row) {
  final at = row.line + 1;
  if (at >= 1 && at <= state.doc.lines && state.doc.line(at).text == row.source) return at;
  for (var n = 1; n <= state.doc.lines; n += 1) {
    if (state.doc.line(n).text == row.source) return n;
  }
  return null;
}

String _today(EditorState state) => state.facet(fieldsToday)?.call() ?? todayIs();

/// A query drawn in place of its fence.
class QueryWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const QueryWidget({required this.body, required this.from, required this.at, required this.stamp, required this.today, required this.canEdit, required this.height, required this.options});

  final String body;

  /// Where the opening fence's line starts.
  final int from;

  /// Where the caret goes to show the fence's lines: its first line inside.
  final int at;

  /// Moves on every change to the note or the library, which is when a query's answer can.
  final int stamp;
  final String today;

  /// Whether the note can be changed here (the page's `editable`; the name is taken, [EditorWidget.editable]).
  final bool canEdit;

  /// A board's lanes' height from the fence, in their ems; null for the board's own.
  final double? height;
  final QueryOptions? Function() options;

  @override
  String get className => 'cm-query';

  @override
  bool eq(QueryWidget other) =>
      other.body == body && other.from == from && other.at == at && other.stamp == stamp && other.today == today && other.canEdit == canEdit && other.height == height;

  @override
  double get estimatedHeight => 220;

  @override
  Widget build(BuildContext context) => DrawnQuery(widget: this);

  /// Every press in a drawn query is its own: a row opened, a box ticked, a month turned. None of it moves the caret.
  @override
  bool takesPointer(PointerEvent event) => true;
}

/// The query run over the library as it is now, and drawn; what each press in it writes.
class DrawnQuery extends StatelessWidget {
  const DrawnQuery({super.key, required this.widget});

  final QueryWidget widget;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.of(context);
    final options = widget.options();
    final reading = readQuery(widget.body);
    final query = reading.query;
    final state = view.state;
    final editable = widget.canEdit;
    List<QueryNote> library() => _withOpen(options!.notes(), options.noteId, view.state.doc.toString());
    final result = query != null && options != null ? runQuery(query, libraryOf(library(), _cacheOf(view)), widget.today) : null;

    /// The opening fence's line, where the widget was told it is, if it is still a query's.
    Line? open() {
      final doc = view.state.doc;
      if (widget.from > doc.length) return null;
      final line = doc.lineAt(widget.from);
      return line.from == widget.from ? line : null;
    }

    void change(Object changes) => view.dispatch(TransactionSpec(changes: changes, userEvent: queryUserEvent));

    /// One field of a record set, or taken off with null: a card's lane, or a value picked from its sheet. In
    /// another note it goes through the screen as a tick does; in this one it is written into the editor, so the
    /// live doc and the drawing stay in step: a to-do's on its line (`withTaskField`, its person as `@name`), a
    /// note's or a ticket's in its front matter.
    void setField(QueryRow row, String field, String? value) {
      if (!editable) return;
      fireMotor(HapticKind.selection);
      if (row.noteId != options?.noteId) {
        options?.write(row.noteId, (body) => movedBody(body, row.line, row.source, row.kind, field, value));
        return;
      }
      if (row.kind == RecordKind.task) {
        final line = _lineOf(view.state, row);
        if (line == null) return;
        final text = view.state.doc.line(line);
        final next = withTaskField(text.text, field, value);
        if (next != text.text) change(ChangeSpec(from: text.from, to: text.to, insert: next));
        return;
      }
      final body = view.state.doc.toString();
      final next = withProperty(body, field, value);
      if (next != body) change(ChangeSpec(from: 0, to: body.length, insert: next));
    }

    final add = options?.add;
    final look = QueryLook.of(context, view is EditorView ? view.look : null);
    return QueryView(
      look: look,
      lines: widget.body,
      problem: reading.problem,
      result: result,
      editable: editable,
      today: widget.today,
      locale: state.facet(fieldsLocale),
      height: widget.height,
      dayPicker: state.facet(dayPicker),
      // Written into the opening fence, as a board's is (boards/card_edits.dart `writeHeight`): one change, one undo.
      onHeight: (height) {
        final line = open();
        if (line == null) return;
        final next = withQueryHeight(line.text, height);
        if (next != line.text) change(ChangeSpec(from: line.from, to: line.to, insert: next));
      },
      // The switcher and the builder write the body back, one clause changed: from: and where: are kept, and the
      // lines the builder does not offer stay. Found again on the live doc by the opening fence's line, so a change
      // made meanwhile does not write the wrong body.
      onBody: !editable
          ? null
          : (body) {
              final line = open();
              if (line == null) return;
              final doc = view.state.doc;
              final fence = queryFencesIn(doc.toString()).where((each) => each.from == line.number).firstOrNull;
              if (fence == null || fence.to <= fence.from + 1) return;
              final bodyFrom = doc.line(fence.from + 1).from;
              final bodyTo = doc.line(fence.to - 1).to;
              if (body != fence.body) change(ChangeSpec(from: bodyFrom, to: bodyTo, insert: body));
            },
      // Focused first, so the caret lands in a view that has the focus and the drawing steps aside at once.
      onEdit: () {
        view.focus();
        view.dispatch(TransactionSpec(selection: EditorSelection.single(widget.at), scrollIntoView: true));
      },
      onOpen: (row) {
        if (row.noteId == options?.noteId) {
          final line = row.kind == RecordKind.task ? _lineOf(view.state, row) : 1;
          if (line == null) return;
          view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.line(line).to), scrollIntoView: true));
          if (editable) view.focus();
          return;
        }
        options?.open(row.noteId, row.kind == RecordKind.task ? row.line : null);
      },
      onTick: (row) {
        final done = row.done;
        if (row.kind != RecordKind.task || done == null || !editable) return;
        fireMotor(HapticKind.selection);
        if (row.noteId != options?.noteId) {
          options?.write(row.noteId, (body) => tickedBody(body, row.line, row.source, !done));
          return;
        }
        final line = _lineOf(view.state, row);
        if (line == null) return;
        final text = view.state.doc.line(line);
        final box = taskBox(text.text);
        if (box != null) view.dispatch(toggleBox(view.state, (from: text.from + box.at, to: text.from + box.at + 3, done: box.done)));
      },
      // The field the board groups by, set to the lane the card was dropped in.
      onMove: (row, value) {
        final group = result?.group;
        if (group != null) setField(row, group, value);
      },
      onSet: setField,
      onAdd: editable && query != null && add != null && ticketDraft(query, null, null) != null
          ? (lane, title) {
              final draft = ticketDraft(query, result?.group, lane);
              if (draft == null) return;
              unawaited(
                add(draft, title, options?.noteId).then((here) {
                  // The ticket went into the notebook this board is drawn in: its page is put in the index here.
                  if (!here) return;
                  final body = view.state.doc.toString();
                  final next = withChapter(body, title);
                  if (next != body) change(ChangeSpec(from: 0, to: body.length, insert: next));
                }),
              );
            }
          : null,
      // Read when a person's sheet opens, not on every draw: it reads every note.
      people: () => options == null ? const <String>[] : peopleIn(library().map((note) => note.body)),
    );
  }
}

class _Drawn {
  const _Drawn(this.stamp, this.today, this.decorations);
  final int stamp;
  final String today;
  final DecorationSet decorations;
}

DecorationSet _decorate(EditorState state, int stamp, String today, QueryOptions? Function() options) {
  final ranges = <Range<Decoration>>[];
  final editable = state.facet(EditorViewLike.editable) && !state.readOnly;
  for (final fence in queryFencesIn(state.doc.toString())) {
    final from = state.doc.line(fence.from).from;
    final to = state.doc.line(fence.to).to;
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the answer.
    if (editable && caretIn(state, from, to)) continue;
    final at = state.doc.line(fence.from + 1 < fence.to ? fence.from + 1 : fence.to).from;
    ranges.add(
      Decoration.replace(
        widget: QueryWidget(body: fence.body, from: from, at: at, stamp: stamp, today: today, canEdit: editable, height: fence.height, options: options),
        block: true,
      ).range(from, to),
    );
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

/// How long until the next midnight on the device's clock, when `today` moves on.
Duration untilMidnight([DateTime? from]) {
  final now = from ?? DateTime.now();
  return DateTime(now.year, now.month, now.day + 1).difference(now) + const Duration(milliseconds: 500);
}

/// At midnight every query is run again: `today`, and every overdue and due-today with it, has moved.
class _Midnight extends PluginValue {
  _Midnight(this.view) {
    _arm();
  }

  final EditorViewLike view;
  Timer? _timer;

  void _arm() {
    _timer = Timer(untilMidnight(), () {
      view.dispatch(TransactionSpec(effects: refreshQueries.of(null)));
      _arm();
    });
  }

  @override
  void destroy() => _timer?.cancel();
}

/// Whether queries keep a clock for midnight: off for tests, which end before it would ring.
bool queriesWatchMidnight = true;

/// Every ```query fence in the note drawn as its answer, over the library `options` hands it; the lines as they are
/// where it answers null (a card's small note, a shared page), which is what any other app shows.
Extension queries(QueryOptions? Function() options) {
  final field = StateField.define<_Drawn>(
    create: (state) {
      final today = _today(state);
      return _Drawn(0, today, options() != null ? _decorate(state, 0, today, options) : Decoration.none);
    },
    update: (value, tr) {
      final refreshed = tr.effects.any((effect) => effect.isOf(refreshQueries));
      if (!refreshed && !tr.docChanged && tr.selection == null && !tr.reconfigured && !focusMoved(tr)) return value;
      final stamp = value.stamp + (refreshed || tr.docChanged ? 1 : 0);
      final today = _today(tr.state);
      return _Drawn(stamp, today, options() != null ? _decorate(tr.state, stamp, today, options) : Decoration.none);
    },
    provide: (field) => EditorViewLike.decorations.from<_Drawn>(field, (value) => value.decorations),
  );
  return Extension.list(<Extension>[trackFocus, field, if (queriesWatchMidnight) ViewPlugin.define<_Midnight>(_Midnight.new)]);
}
