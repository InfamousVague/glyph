/// A table as it is drawn in a note: what `TableWidget.toDOM` of `src/app/editor/tables.ts` builds, with the rules
/// of its `tableTheme` read off beside each thing they set.
///
///     .cm-glyphTableWrap     [DrawnTable]: the gutter, the room above and below, sideways scrolling, the press
///       table.cm-glyphTable  [GlyphTable]: the header, the rows and the hairline grid (table_layout.dart)
///       .cm-tableTools       the row of two buttons under it, only where the note can be changed
///         button.cm-tableGrow  [TableGrowButton]: "+ Column" and "+ Row"
///
/// What differs:
/// - A press is a tap, not the pointer going down: on the page `mousedown` only ever follows a finished tap on a
///   touch screen, so a finger that scrolls the table (or the note, starting on the table) never opens it. A
///   `GestureDetector`'s tap is that for a finger and a mouse alike.
/// - A table wider than the screen scrolls sideways inside its wrap, as tables.ts means it to. On the page the
///   growing editor (`Editor.tsx`'s `grow`) takes the table's width as its own least, so the whole note is as wide
///   as the table and it is the note that scrolls; the table and its cells are where the page has them all the
///   same.
/// - `:hover` on a button is its look while it is pressed here; `:focus-visible` has no counterpart yet (no
///   keyboard focus moves through the note's widgets).
/// - `cursor: text` on the wrap and `pointer` on a button are a `MouseRegion`'s.
/// - A table that does not parse (`wrap.textContent = this.text`) is its text in the note's face; the syntax tree
///   does not name such a thing a Table, so it is not expected.
/// - The blanks drawn in a cell and the Fill pill after the last row (`drawCell`, `tablePill` of editor/blanks.ts)
///   are the blanks' piece's, and not here yet.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../commands/inserts.dart' show Plan, applyPlan;
import '../commands/tables.dart';
import '../looks/look.dart';
import '../looks/peek_look.dart';
import '../state/change.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'table_layout.dart';

/// The user event of a table grown from its drawing: `userEvent: 'input.table'`.
const String tableUserEvent = 'input.table';

/// The table's text between `from` and `from + text.length` rewritten by `change`, as one undo. Answers whether it
/// was: a drawing that has not been built again since the note changed under it (a change and a press in one
/// frame) no longer knows where its table is, and writes nothing rather than over other words.
bool growTable(EditorViewLike view, int from, String text, String Function(String text) change) {
  final to = from + text.length;
  if (to > view.state.doc.length || view.state.doc.sliceString(from, to) != text) return false;
  final plan = Plan(changes: ChangeSpec(from: from, to: to, insert: change(text)));
  view.dispatch(applyPlan(view.state, plan, userEvent: tableUserEvent));
  return true;
}

TextStyle _faceAt(RunLook? base, Tokens t, double size, {double weight = 400, Color? color}) {
  if (base == null) return t.textAt(size, mono: true, weight: weight >= 700 ? 'bold' : 'regular', color: color ?? t.color('glacier-text')).copyWith(height: kTextHeightNone);
  return base.style.copyWith(
    fontSize: size,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: <FontVariation>[FontVariation('wght', weight), if (base.props.optical) FontVariation('opsz', size)],
    color: color,
    decorationColor: color,
  );
}

/// `.cm-glyphTableWrap`: a table drawn in place of its lines.
class DrawnTable extends StatelessWidget {
  const DrawnTable({super.key, required this.text, required this.from, required this.growable});

  /// The table's markdown, and where it starts in the note.
  final String text;
  final int from;

  /// Whether the note can be changed: the buttons are drawn, and a press opens the table's lines.
  final bool growable;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    // The sizes the editor it is in was given (a card's preview sets its own).
    final env = look?.env;
    final body = env?.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(env?.gutter ?? t.len('app-gutter'));
    final base = look?.line(LookElement(null)).base;
    final ratio = env?.devicePixelRatio ?? MediaQuery.devicePixelRatioOf(context);
    // '.cm-glyphTableWrap': { overflowX: 'auto', margin: '0.35em 0', paddingInline: 'var(--app-gutter, 1rem)',
    //   cursor: 'text' }
    final margin = layoutUnitFloor(0.35 * body);
    final parsed = parseTable(text);
    final Widget Function(double room) inside;
    if (parsed == null) {
      final face = _faceAt(base, t, body).copyWith(height: 1.6, leadingDistribution: TextLeadingDistribution.even);
      inside = (room) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: room < 0 ? 0 : room),
        child: Text(text, style: face, textScaler: TextScaler.noScaling),
      );
    } else {
      // '.cm-glyphTable': { borderCollapse: 'collapse', fontSize: '0.92em', lineHeight: '1.35',
      //   minInlineSize: '60%' }
      final size = 0.92 * body;
      final lineHeight = blinkLineHeight(1.35, size);
      // `.peek .cm-editor .cm-glyphTable th { background: transparent }` (notes/NotePeek.module.css)
      final peek = look != null && look.sheets.any((sheet) => identical(sheet, peekLook()) || identical(sheet, peekLook(whole: true)));
      final tableLook = TableLook(
        // '.cm-glyphTable th': { whiteSpace: 'nowrap', fontWeight: '700',
        //   background: 'var(--app-paper-2, var(--glacier-surface-sunken, transparent))' }
        head: WordsFace(_faceAt(base, t, size, weight: 700), lineHeight),
        body: WordsFace(_faceAt(base, t, size), lineHeight),
        // '.cm-glyphTable th, .cm-glyphTable td': { padding: '0.35em 0.7em',
        //   border: '1px solid var(--glacier-border-subtle, rgba(127,127,127,0.3))', textAlign: 'start',
        //   verticalAlign: 'top', whiteSpace: 'pre-wrap', overflowWrap: 'normal', wordBreak: 'normal',
        //   maxInlineSize: '18em' }
        padX: layoutUnitFloor(0.7 * size),
        padY: layoutUnitFloor(0.35 * size),
        rule: 1,
        most: layoutUnitFloor(18 * size),
        ruleColor: t.color('glacier-border-subtle'),
        headGround: peek ? null : t.color('app-paper-2'),
        devicePixelRatio: ratio,
      );
      final rows = <List<String>>[
        <String>[for (final cell in parsed.header) plainCell(cell)],
        for (final row in parsed.rows) <String>[for (final cell in row) plainCell(cell)],
      ];
      // The table's room is the wrap's, however wide the table itself comes out.
      inside = (room) => GlyphTable(rows: rows, align: parsed.align, look: tableLook, room: room < 0 ? 0 : room);
    }
    Widget? tools;
    if (growable && parsed != null && view != null) {
      // '.cm-tableTools': { display: 'flex', gap: '0.4em', margin: '0.35em 0 0' }
      // '.cm-tableGrow': { padding: '0.2em 0.6em', border: '1px solid var(--glacier-border-subtle, ...)',
      //   borderRadius: 'var(--glacier-radius-full, 999px)', background: 'transparent',
      //   color: 'var(--app-ink-3, currentColor)', font: 'inherit', fontSize: '0.8em', whiteSpace: 'nowrap' }
      // '.cm-tableGrow:hover': { color: 'var(--app-ink, currentColor)',
      //   background: 'color-mix(in oklch, currentColor 8%, transparent)' }
      final size = 0.8 * body;
      final lineHeight = blinkLineHeight(1.6, size);
      final ink = t.color('app-ink-3'), pressedInk = t.color('app-ink');
      TableGrowButton grow(String label, String Function(String text) change) => TableGrowButton(
        label: label,
        face: WordsFace(_faceAt(base, t, size, color: ink), lineHeight),
        pressedFace: WordsFace(_faceAt(base, t, size, color: pressedInk), lineHeight),
        padX: layoutUnitFloor(0.6 * size),
        padY: layoutUnitFloor(0.2 * size),
        ruleColor: t.color('glacier-border-subtle'),
        pressedGround: t.colorOf('color-mix(in oklch, currentColor 8%, transparent)', current: pressedInk),
        onPressed: () => growTable(view, from, text, change),
      );
      tools = Padding(
        padding: EdgeInsets.only(top: margin),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            grow('+ Column', addTableColumn),
            SizedBox(width: layoutUnitFloor(0.4 * body)),
            grow('+ Row', addTableRow),
          ],
        ),
      );
    }
    Widget wrap = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final room = width - 2 * gutter;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  inside(room),
                  ?tools,
                ],
              ),
            ),
          ),
        );
      },
    );
    if (growable && view != null) {
      // `openOnPress(view, wrap, this.from)`
      wrap = MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => openOnPress(view, from), child: wrap),
      );
    }
    return Padding(padding: EdgeInsets.symmetric(vertical: margin), child: wrap);
  }
}

/// `table.cm-glyphTable`: the header, the rows and the grid.
class GlyphTable extends LeafRenderObjectWidget {
  const GlyphTable({super.key, required this.rows, required this.align, required this.look, required this.room});

  /// The header's cells, then each row's: the words as they are drawn.
  final List<List<String>> rows;
  final List<TableAlign?> align;
  final TableLook look;

  /// The width its wrap has for it. Not its constraints: inside a sideways scroll there is no width to be told,
  /// and the table may come out wider than its room.
  final double room;

  @override
  RenderGlyphTable createRenderObject(BuildContext context) => RenderGlyphTable(rows, align, look, room);

  @override
  void updateRenderObject(BuildContext context, RenderGlyphTable renderObject) => renderObject.update(rows, align, look, room);
}

/// The table's box: as wide and as tall as the page's `<table>`, which may be wider than the room it was given.
class RenderGlyphTable extends RenderBox {
  RenderGlyphTable(this._rows, this._align, this._look, this._room);

  List<List<String>> _rows;
  List<TableAlign?> _align;
  TableLook _look;
  double _room;
  TableLayout? _layout;

  void update(List<List<String>> rows, List<TableAlign?> align, TableLook look, double room) {
    if (identical(rows, _rows) && identical(align, _align) && look.same(_look) && room == _room) return;
    _rows = rows;
    _align = align;
    _look = look;
    _room = room;
    _drop();
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  void _drop() {
    _layout?.dispose();
    _layout = null;
  }

  /// The table as it was last laid out: its cells' boxes and their words', in this box's coordinates.
  TableLayout get table => _layout!;

  @override
  void performLayout() {
    final layout = _layout ??= TableLayout(_rows, _align, _look, _room);
    // Its own width, whatever the room: a table too wide for the room runs out of it, and its wrap scrolls.
    size = constraints.constrain(layout.size);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) => _layout?.paint(context.canvas, offset, screen: localToGlobal(Offset.zero) - offset);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = <String>[for (final row in _rows) row.join(', ')].join('\n');
  }

  @override
  void detach() {
    super.detach();
    _drop();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }
}

/// `button.cm-tableGrow`: one of the two quiet buttons under a drawn table.
class TableGrowButton extends StatefulWidget {
  const TableGrowButton({
    super.key,
    required this.label,
    required this.face,
    required this.pressedFace,
    required this.padX,
    required this.padY,
    required this.ruleColor,
    required this.pressedGround,
    required this.onPressed,
  });

  final String label;
  final WordsFace face;
  final WordsFace pressedFace;
  final double padX;
  final double padY;
  final Color ruleColor;
  final Color pressedGround;
  final VoidCallback onPressed;

  @override
  State<TableGrowButton> createState() => _TableGrowButtonState();
}

class _TableGrowButtonState extends State<TableGrowButton> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (mounted && pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Semantics(
      button: true,
      label: w.label,
      onTap: w.onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // The button keeps its press from the wrap, or it would open the pipes.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onTap: w.onPressed,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: _pressed ? w.pressedGround : null,
              shape: StadiumBorder(side: BorderSide(color: w.ruleColor)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 1 + w.padX, vertical: 1 + w.padY),
              child: TableWords(text: w.label, face: _pressed ? w.pressedFace : w.face),
            ),
          ),
        ),
      ),
    );
  }
}

/// A few words on one line, set as the page sets them: as wide as the words (up to the sixty-fourth) and as tall
/// as the face's line.
class TableWords extends LeafRenderObjectWidget {
  const TableWords({super.key, required this.text, required this.face});

  final String text;
  final WordsFace face;

  @override
  RenderTableWords createRenderObject(BuildContext context) => RenderTableWords(text, face);

  @override
  void updateRenderObject(BuildContext context, RenderTableWords renderObject) => renderObject.update(text, face);
}

class RenderTableWords extends RenderBox {
  RenderTableWords(this._text, this._face);

  String _text;
  WordsFace _face;
  SetWords? _words;

  void update(String text, WordsFace face) {
    if (text == _text && face.same(_face)) return;
    _text = text;
    _face = face;
    _words?.dispose();
    _words = null;
    markNeedsLayout();
  }

  /// The words' own box in this one, as a `Range` over them answers on the page.
  Rect get wordsBox => _words!.boxes.first;

  @override
  void performLayout() {
    final words = _words ??= SetWords(_text, _face);
    size = constraints.constrain(Size(layoutUnitCeil(words.width), _face.lineHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) => _words?.paint(context.canvas, offset, screen: localToGlobal(Offset.zero) - offset);

  @override
  void dispose() {
    _words?.dispose();
    _words = null;
    super.dispose();
  }
}
