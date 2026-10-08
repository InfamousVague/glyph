/// Tables, shown as tables. Ports `src/app/editor/tables.ts`.
///
/// A GFM table in a note is rows of pipes and dashes, which is how it is kept and how it is edited, but not how
/// anyone wants to read it on a phone. So a table the caret is not in is drawn as a real table: header, rows, a
/// hairline grid, scrolling sideways inside itself when it is wider than the screen. Tapping it puts the caret at
/// its start, the drawn table steps aside, and the pipes are there to edit; leaving it draws it again. In a view
/// that cannot be edited it simply stays drawn.
///
/// Block decorations have to come from a state field, not a view plugin, and a state field cannot ask the view
/// whether it has focus, so focus is kept in a field of its own, the one every drawn block shares
/// (`view/drawn_block.dart`).
///
/// The note screen adds [drawnTables] to its extensions (`noteExtensions(more: [drawnTables()])`), as Editor.tsx
/// lists `drawnTables()`.
///
/// What differs:
/// - The pure half of tables.ts (`parseTable`, `plainCell`, `cellSpans`, `addTableColumn`, `addTableRow`) is
///   `commands/tables.dart`; this is the widget, its field and the extension. `tableTheme` is not a stylesheet
///   here: its rules are read off beside what they set in `table_box.dart`, and the browser's table layout they
///   lean on is `table_layout.dart`.
/// - `TableWidget.editable` is [TableWidget.growable]: `EditorWidget.editable` already means something else (a
///   widget with a field of its own to type in).
/// - `TableWidget.stamp`, bumped as blanks change under the table, and `blanksRedraw` in the field's update wait
///   for the blanks' piece (editor/blanks.ts): cells are drawn from `plainCell` alone.
/// - `ensureSyntaxTree(state, state.doc.length, 40)` is `syntaxTree(state)`: the state's parse is whole.
/// - + Column and + Row dispatch through `applyPlan` (commands/inserts.dart) with the web's `input.table` user
///   event, which also isolates the step in the history: one undo each whatever was typed just before.
/// - `ignoreEvent`: see [TableWidget.takesPointer].
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/syntax_tree.dart';
import 'table_box.dart';

export 'table_box.dart' show DrawnTable, GlyphTable, RenderGlyphTable, RenderTableWords, TableGrowButton, TableWords, growTable, tableUserEvent;
export 'table_layout.dart' show DrawnCell, TableLayout, TableLook, WordsFace;

/// A table drawn in place of its lines.
class TableWidget extends EditorWidget implements ClassedBlockWidget {
  const TableWidget(this.text, this.from, this.growable);

  /// The table's markdown, first line to last.
  final String text;

  /// Where it starts in the note.
  final int from;

  /// Whether the + row and + column buttons are drawn, and a press opens the table: only where the note can be
  /// changed.
  final bool growable;

  @override
  String get className => 'cm-glyphTableWrap';

  @override
  bool eq(TableWidget other) => other.text == text && other.from == from && other.growable == growable;

  /// A guess before it is laid out: a line of 1.35 and its padding for each row, and the buttons.
  @override
  double get estimatedHeight {
    var rows = 0;
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) rows += 1;
    }
    return (rows > 1 ? rows - 1 : 1) * 34.0 + 13 + (growable ? 36 : 0);
  }

  @override
  Widget build(BuildContext context) => DrawnTable(text: text, from: from, growable: growable);

  /// `ignoreEvent(event) { return event.type !== 'mousedown' }`: scrolling a wide table sideways is the table's; a
  /// press is the note's, to open it for editing. Where the note can be changed the wrap answers that press itself
  /// (`openOnPress` prevented the event's default, so CodeMirror never saw it): the widget keeps it. Where it
  /// cannot, the press is the view's own.
  @override
  bool takesPointer(PointerEvent event) => growable || event is! PointerDownEvent;
}

DecorationSet _build(EditorState state) {
  final ranges = <Range<Decoration>>[];
  final editable = state.facet(EditorViewLike.editable);
  syntaxTree(state).iterate(
    enter: (node) {
      if (node.name != 'Table') return null;
      final from = state.doc.lineAt(node.from).from;
      final to = state.doc.lineAt(node.to).to;
      final inside = editable && caretIn(state, from, to);
      if (!inside) {
        ranges.add(Decoration.replace(widget: TableWidget(state.doc.sliceString(from, to), from, editable), block: true).range(from, to));
      }
      return false;
    },
  );
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

final StateField<DecorationSet> _tableField = StateField.define<DecorationSet>(
  create: _build,
  update: (decorations, tr) {
    final treeMoved = !identical(syntaxTree(tr.state), syntaxTree(tr.startState));
    if (tr.docChanged || tr.selection != null || treeMoved || focusMoved(tr) || tr.reconfigured) return _build(tr.state);
    return decorations;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The tables drawn in `state` now: one block replacement for each table the caret is not in. For a test to ask,
/// and for whoever needs to know whether a position is under a drawing.
DecorationSet drawnTablesIn(EditorState state) => state.fieldOrNull(_tableField) ?? Decoration.none;

/// Tables drawn as tables wherever the caret is not in them (`drawnTables()`).
Extension drawnTables() => Extension.list(<Extension>[trackFocus, _tableField]);
