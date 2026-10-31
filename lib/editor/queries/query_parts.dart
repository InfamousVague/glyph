/// A record's own pieces in a drawn query: its box, its name, its key, and each cell drawn as what it holds. Ports
/// the middle of `src/app/editor/QueryView.tsx` (`Box`, `Name`, `KeyLine`, `withTags`, `Chip`, `StatusCell`,
/// `Picked`, `CellView`, `Meta`, `GroupHead`, `Totals`) with their rules of `QueryView.module.css`, and the chip's of
/// `editor/fieldChips.ts` (`fieldChipTheme`) as it falls on a chip in the app's own face.
///
/// A cell is drawn as what it holds: a due day by when it is ("Tomorrow", red once it has passed), a priority as
/// Jira's chevrons, a person with their initial in a ring, a status with its category's mark, the same looks a
/// field has on its line (items/field_chips.dart) and a ticket has in a list (notes/ticket_mark.dart), so a thing
/// reads the same wherever it is shown. The name of a record is the button that opens it; a to-do's box ticks it.
///
/// What differs:
/// - **A chip here is its own widget** ([QueryChip]), not items/field_chips.dart's `FieldChip`: that one takes its
///   type from the note's line it stands in, and a query's chip stands in the app's face at the card's size. The
///   look it draws is the same [ChipLook], from the same [chipLook].
/// - **A value that opens its sheet** (`.picked`) is as big as the value it holds. On the page its button has the
///   value's own width too (its `max-inline-size: 100%` is of a box its negative margins made no wider), with its
///   padding's ground showing only under a pointer; a finger gets a little more room round it here.
/// - `title=` tooltips are a pointer's; what each says is the widget's label for a screen reader.
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/properties.dart' show StatusCategory;
import '../../core/query/query.dart';
import '../../core/tags.dart' show tagsIn;
import '../../core/task_fields.dart' show FieldKind, FieldSpan;
import '../../sheet/css.dart' show snapBorder;
import '../../tickets/ui/bulk_bar.dart' show QuerySelectable, QuerySelection;
import '../../tickets/ui/label_chips.dart' show LabelChips;
import '../fields/field_picker.dart' show StatusIcon;
import '../fields/field_picks.dart';
import '../items/field_chips.dart' show ChipLook, FieldMenu, chipLook, dayLabel, daySaid;
import '../looks/look.dart' show layoutUnitFloor;
import 'query_layout.dart';
import 'queries.dart' show TicketMarks;
import 'query_look.dart';

/// " priority" at the end of a chip's label, which a chip in a query's row leaves unsaid.
final RegExp _priorityWord = RegExp(r' priority$');

/// What a row and a cell need from the query's drawing to act and to name days (`Acts`).
class QueryActs {
  const QueryActs({required this.today, required this.locale, required this.editable, required this.onOpen, required this.onTick, required this.onMove, required this.pickable, required this.pick, this.onAdd, this.onControl, this.onSet, this.onOpenTitle, this.marks, this.selection, this.order, this.labelColours});

  final String today;
  final String? locale;
  final bool editable;
  final void Function(QueryRow row) onOpen;
  final void Function(QueryRow row) onTick;
  final void Function(QueryRow row, String? value) onMove;

  /// Whether a record's field opens a sheet to pick it from; and opening it.
  final bool Function(QueryRow row, String field) pickable;
  final void Function(QueryRow row, QueryColumn column, Cell cell) pick;

  /// A ticket made in a board's lane; absent where the board makes none.
  final void Function(String? lane, String title)? onAdd;

  /// A pointer went down on a control of a thing that can be carried (its box, a value's button): the press is the
  /// control's, and the thing is not lifted by it (`event.stopPropagation()` on the page).
  final void Function(int pointer)? onControl;

  /// A ticket's lock and its sub-tickets' progress, for its card and its row (ticket_marks.dart); absent, neither.
  final TicketMarks Function(QueryRow row)? marks;

  /// One field of a record set, or taken off with null: a day carried on a calendar, a bar's ends on a timeline (the
  /// port's own). Absent where nothing it lists can be changed.
  final void Function(QueryRow row, String field, String? value)? onSet;

  /// Opens the note a relation's chip names, by its title (the port's own). Absent, a chip is words.
  final void Function(String title)? onOpenTitle;

  /// The tickets picked for a bulk edit, and every pickable row's key in the order drawn (lib/tickets/ui/bulk_bar.dart;
  /// Matt, 2026-10-31). Absent, nothing is picked.
  final QuerySelection? selection;
  final List<String> Function()? order;

  /// The colours a ticket's notebook gives its labels (lib/tickets/labels.dart); absent, each its own.
  final Map<String, String> Function(QueryRow row)? labelColours;

  /// [child], a ticket's card or row, as one that can be picked where anything is.
  Widget selectable(QueryRow row, Widget child, {double radius = 0, bool boxed = true, bool drawn = true}) {
    final picked = selection;
    if (picked == null || !QuerySelectable.can(row)) return child;
    return QuerySelectable(selection: picked, row: row, order: order ?? () => const <String>[], radius: radius, boxed: boxed, drawn: drawn, child: child);
  }
}

/// A press that is a control's own, said to whoever might lift the thing it is on.
class _Control extends StatelessWidget {
  const _Control({required this.acts, required this.child});

  final QueryActs acts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(onPointerDown: (event) => acts.onControl?.call(event.pointer), child: child);
}

/// A to-do's box, ticked where it is written; nothing for a note or a ticket (`Box`).
class QueryBox extends StatelessWidget {
  const QueryBox({super.key, required this.look, required this.row, required this.acts, this.drop});

  final QueryLook look;
  final QueryRow row;
  final QueryActs acts;

  /// The margin above it; a list's row's where none is given.
  final double? drop;

  /// Whether [row] has a box at all.
  static bool has(QueryRow row) => row.kind == RecordKind.task && row.done != null;

  // .box { inline-size: 1.15em; block-size: 1.15em; margin: calc(var(--glacier-space-1) + 0.15em) 0 0;
  //   border: 1.5px solid var(--app-ink-3); border-radius: var(--glacier-radius-sm); background: transparent;
  //   color: var(--app-paper) }  (a button's own 13.333px)
  static double size() => 1.15 * buttonType;

  @override
  Widget build(BuildContext context) {
    final done = row.done ?? false;
    final edge = snapBorder(context, 1.5);
    final size = QueryBox.size();
    final square = Part(
      'box',
      child: Container(
        width: size,
        height: size,
        // .box[data-done] { border-color: var(--app-ink-2); background: var(--app-ink-2) }
        decoration: BoxDecoration(
          color: done ? look.ink2 : null,
          border: Border.all(color: done ? look.ink2 : look.ink3, width: edge),
          borderRadius: BorderRadius.circular(look.t.radius('sm')),
        ),
        // `<Check size="0.8em" strokeWidth={3} />`
        child: done ? Center(child: AppIcon(Lucide.check, size: 0.8 * buttonType, strokeWidth: 3, color: look.paper, wash: false)) : null,
      ),
    );
    final can = acts.editable;
    return Padding(
      padding: EdgeInsets.only(top: drop ?? rowDrop(look)),
      child: Semantics(
        container: true,
        checked: done,
        enabled: can,
        label: done ? 'Clear ${row.name}' : 'Tick ${row.name}',
        onTap: can ? () => acts.onTick(row) : null,
        excludeSemantics: true,
        child: _Control(acts: acts, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: can ? () => acts.onTick(row) : null, child: square)),
      ),
    );
  }

  /// The margin above a box on a list's row.
  static double rowDrop(QueryLook look) => look.space(1) + 0.15 * buttonType;
}

/// The room round a to-do's box that ticks it too (`.box::after { inset: calc(-1 * var(--glacier-space-2)) }`: "the
/// target is bigger than the square, so a finger finds it"). Laid over the row or the card the box is in, from its
/// corner to [reach] past the box's far edges: a box cannot take a press outside its own bounds here, so the room
/// is the row's to give, and stops at the row's own edge where the page's ran a little past it.
class QueryBoxReach extends StatelessWidget {
  const QueryBoxReach({super.key, required this.look, required this.row, required this.acts, required this.drop});

  final QueryLook look;
  final QueryRow row;
  final QueryActs acts;

  /// How far under the top of what it is laid over the box stands.
  final double drop;

  @override
  Widget build(BuildContext context) {
    final reach = look.space(2);
    return Positioned(
      left: 0,
      top: 0,
      width: QueryBox.size() + reach,
      height: drop + QueryBox.size() + reach,
      child: ExcludeSemantics(
        child: _Control(acts: acts, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: acts.editable ? () => acts.onTick(row) : null)),
      ),
    );
  }
}

/// Words with their tags drawn as the editor draws a tag (items/tags.dart), so `Milk #dairy` reads as it does on
/// its line (`withTags`).
InlineSpan withTags(QueryLook look, String words, TextStyle style) {
  final tags = tagsIn(words);
  if (tags.isEmpty) return TextSpan(text: words);
  final parts = <InlineSpan>[];
  var at = 0;
  for (final tag in tags) {
    if (tag.from > at) parts.add(TextSpan(text: words.substring(at, tag.from)));
    parts.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: QueryTag(look: look, text: words.substring(tag.from, tag.to), parent: style.fontSize!)));
    at = tag.to;
  }
  if (at < words.length) parts.add(TextSpan(text: words.substring(at)));
  return TextSpan(children: parts);
}

/// `.cm-tag`: a small quiet chip, the `#` kept (editor/tags.ts).
class QueryTag extends StatelessWidget {
  const QueryTag({super.key, required this.look, required this.text, required this.parent});

  final QueryLook look;
  final String text;

  /// The type of the words it stands in.
  final double parent;

  @override
  Widget build(BuildContext context) {
    // '.cm-tag': { padding: '0 0.3em', borderRadius: '0.35em',
    //   background: 'color-mix(in srgb, currentColor 9%, transparent)', color: 'var(--app-ink-2, inherit)',
    //   fontSize: '0.92em', whiteSpace: 'nowrap' }
    final em = 0.92 * parent;
    final style = look.sans(em, color: look.ink2);
    final glyph = glyphBox(style);
    return Part(
      'cm-tag',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 0.3 * em),
        decoration: BoxDecoration(color: QueryLook.mix(look.ink2, 0.09), borderRadius: BorderRadius.circular(0.35 * em)),
        child: Text(text, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(height: (glyph.ascent + glyph.descent) / em)),
      ),
    );
  }
}

/// A note a relation names, as a chip: a tag's ground under its title, a little wider (the port's own).
class QueryLinkChip extends StatelessWidget {
  const QueryLinkChip({super.key, required this.look, required this.title, required this.parent});

  final QueryLook look;
  final String title;

  /// The type of the words it stands in.
  final double parent;

  @override
  Widget build(BuildContext context) {
    final em = 0.92 * parent;
    final style = look.sans(em, color: look.ink2);
    final glyph = glyphBox(style);
    return Part(
      'relationChip',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 0.35 * em),
        decoration: BoxDecoration(color: QueryLook.mix(look.ink2, 0.09), borderRadius: BorderRadius.circular(0.35 * em)),
        // Words alone, as a tag's chip is: a table lays its cells out on their baselines, which a drawn mark has not got.
        child: Text(title, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(height: (glyph.ascent + glyph.descent) / em)),
      ),
    );
  }
}

/// A record's name, the button that opens it: its tags as tags, a finished one struck through, a ticket's key before
/// it unless [hideKey] (`Name`).
class QueryName extends StatelessWidget {
  const QueryName({super.key, required this.look, required this.row, required this.acts, this.hideKey = false, this.wrap = true});

  final QueryLook look;
  final QueryRow row;
  final QueryActs acts;
  final bool hideKey;

  /// Whether the words may run on to more lines; a table's name is on one.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final done = row.category == StatusCategory.done || (row.done ?? false);
    // .name[data-done] .nameWords { color: var(--app-ink-3); text-decoration: line-through;
    //   text-decoration-color: var(--app-ink-4) }
    final style = look.sans(look.em, color: done ? look.ink3 : look.ink, struck: done, strike: look.ink4);
    final said = row.name.isEmpty ? 'Untitled' : row.name;
    final id = row.id;
    final words = Part('nameWords', child: PageWords.rich(withTags(look, said, style), style, line: look.line, softWrap: wrap, maxLines: wrap ? null : 1));
    // .name { display: inline-flex; align-items: baseline; gap: var(--glacier-space-2); max-inline-size: 100% }
    final Widget inner = !hideKey && id != null && id.isNotEmpty
        ? CssRow(
            align: CssAlign.baseline,
            gap: look.space(2),
            shrinkWrap: true,
            children: <Widget>[
              // .key { flex: none; font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-xs);
              //   letter-spacing: 0.02em; color: var(--app-ink-3) }
              CssItem(shrink: 0, child: Part('key', child: PageWords(id, look.mono(look.xs, color: look.ink3, tracking: 0.02 * look.xs), line: look.lineXs, softWrap: false))),
              CssItem(least: 0, child: words),
            ],
          )
        : words;
    return Semantics(
      container: true,
      button: true,
      label: said,
      onTap: () => acts.onOpen(row),
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => acts.onOpen(row), child: Part('name', child: inner)),
    );
  }
}

/// A ticket's key on a line of its own, above the title on a list's row and a board's card (`KeyLine`).
class QueryKeyLine extends StatelessWidget {
  const QueryKeyLine({super.key, required this.look, required this.id});

  final QueryLook look;
  final String id;

  // .cardKey { flex-basis: 100%; font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-xs);
  //   letter-spacing: 0.02em; line-height: 1.2; color: var(--app-ink-3) }
  @override
  Widget build(BuildContext context) => Part(
    'cardKey',
    child: SizedBox(width: double.infinity, child: PageWords(id, look.mono(look.xs, color: look.ink3, tracking: 0.02 * look.xs), line: pageLine(look.xs, 1.2), softWrap: false, maxLines: 1)),
  );
}

/// A field's chip, as its line draws it (`Chip`, editor/fieldChips.ts): its icon or its initial, and its words.
class QueryChip extends StatelessWidget {
  const QueryChip({super.key, required this.look, required this.chip, required this.parent});

  final QueryLook look;
  final ChipLook chip;

  /// The type of what it stands in: a chip is 0.92 of it.
  final double parent;

  /// The chip's own type.
  double get em => 0.92 * parent;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    // '.cm-field': { display: 'inline-block', padding: '0 0.35em', borderRadius: '0.35em',
    //   background: 'color-mix(in srgb, currentColor 9%, transparent)', color: 'var(--app-ink-2, inherit)',
    //   fontSize: '0.92em', lineHeight: '1.35', whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }
    final em = this.em;
    final mark = chip.text.isEmpty;
    final person = chip.initial != null;
    var color = look.ink2;
    Color? ground = QueryLook.mix(color, 0.09);
    Color? hairline;
    switch (chip.tone) {
      case 'overdue':
        color = t.color('glacier-red-11');
        ground = t.colorOf('color-mix(in oklch, var(--glacier-red-9) 16%, transparent)');
      case 'today':
        color = t.color('glacier-amber-11');
        ground = t.colorOf('color-mix(in oklch, var(--glacier-amber-9) 18%, transparent)');
      // '.cm-field[data-tone="quiet"], .cm-field[data-tone="done"]': { color: 'var(--app-ink-3, inherit)',
      //   background: 'none', boxShadow: 'inset 0 0 0 1px color-mix(in srgb, currentColor 22%, transparent)' }
      case 'quiet' || 'done':
        color = look.ink3;
        ground = null;
        hairline = mark ? null : QueryLook.mix(look.ink3, 0.22);
      case 'highest' || 'high':
        color = t.color('glacier-red-11');
      case 'medium':
        color = t.color('glacier-amber-11');
      case 'low':
        color = t.color('glacier-blue-11');
      case 'lowest':
        color = look.ink3;
    }
    // '.cm-field[data-mark]': { padding: '0 0.1em', background: 'none' }
    if (mark) ground = null;
    final style = look.sans(em, color: color, tabular: true);
    final height = pageLine(em, 1.35);
    final baseline = pageBaseline(style, height);
    final glyph = glyphBox(style);
    Widget dropped(double top, Widget child) => Padding(padding: EdgeInsets.only(top: top < 0 ? 0 : top), child: child);

    final children = <Widget>[];
    final icon = chip.icon;
    if (icon != null) {
      // '.cm-field > svg': { inlineSize: '0.95em', blockSize: '0.95em', verticalAlign: '-0.14em' }
      // '.cm-field[data-mark] > svg': { inlineSize: '1.1em', blockSize: '1.1em', verticalAlign: '-0.2em' }
      final size = (mark ? 1.1 : 0.95) * em, drop = (mark ? 0.2 : 0.14) * em;
      children.add(dropped(baseline + drop - size, AppIcon(icon, size: size, strokeWidth: chip.menu == FieldMenu.priority ? 2.6 : 2.2, color: color)));
      // '.cm-field > svg + .cm-fieldWords': { marginInlineStart: '0.25em' }
      if (!mark) children.add(SizedBox(width: 0.25 * em));
    }
    if (person) {
      // '.cm-fieldInitial': { display: 'inline-block', inlineSize: '1.25em', blockSize: '1.25em',
      //   marginInlineEnd: '0.28em', borderRadius: '50%',
      //   background: 'color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)',
      //   color: 'var(--glacier-purple-11)', fontSize: '0.78em', fontWeight: '700', lineHeight: '1.25em',
      //   textAlign: 'center', verticalAlign: '0.08em' }
      final size = 0.78 * em, ring = 1.25 * size;
      final done = chip.tone == 'done';
      final ringStyle = look.sans(size, weight: 'bold', color: done ? color : t.color('glacier-purple-11'));
      final ringGlyph = glyphBox(ringStyle);
      // The ring's own baseline, in its one line of 1.25em: the half-leading taken toward nothing, then the ascent.
      final ringBaseline = ((ring - ringGlyph.ascent - ringGlyph.descent) / 2).truncateToDouble() + ringGlyph.ascent;
      children.add(
        Padding(
          padding: EdgeInsets.only(right: 0.28 * size),
          child: dropped(
            baseline - 0.08 * size - ringBaseline,
            Part(
              'cm-fieldInitial',
              child: Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  // '.cm-field[data-tone="done"] .cm-fieldInitial': { background: 'color-mix(in srgb, currentColor
                  //   12%, transparent)', color: 'inherit' }
                  color: done ? QueryLook.mix(color, 0.12) : t.colorOf('color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)'),
                  shape: BoxShape.circle,
                ),
                child: OverflowBox(
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Text(chip.initial!, softWrap: false, textScaler: TextScaler.noScaling, style: ringStyle.copyWith(height: (ringGlyph.ascent + ringGlyph.descent) / size)),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (chip.text.isNotEmpty) {
      children.add(
        dropped(
          baseline - glyph.ascent,
          Part('cm-fieldWords', child: Text(chip.text, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(height: (glyph.ascent + glyph.descent) / em))),
        ),
      );
    }
    // '.cm-field[data-person]': { paddingInlineStart: '0.12em', borderRadius: '999px' }
    final radius = person ? height / 2 : 0.35 * em;
    return Semantics(
      label: chip.label,
      image: true,
      child: ExcludeSemantics(
        child: Baselined(
          baseline: baseline,
          child: Part(
            'cm-field',
            child: Container(
              height: height,
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(left: (mark ? 0.1 : (person ? 0.12 : 0.35)) * em, right: (mark ? 0.1 : 0.35) * em),
              decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(radius)),
              foregroundDecoration: hairline == null ? null : BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: hairline)),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// A status as a pill in its category's colour, with its mark (`StatusCell`, FieldPicker.tsx `statusLook`).
class QueryStatus extends StatelessWidget {
  const QueryStatus({super.key, required this.look, required this.cell, this.workflow, required this.parent});

  final QueryLook look;
  final StatusCell cell;
  final List<String>? workflow;

  /// The type it is drawn in: the card's in a table and a heading, a small part's on a list's line.
  final double parent;

  /// The pill's colours, the rules in the stylesheet's order, a later one over an earlier:
  /// `[data-category='doing']`, `[data-look='review']`, `[data-category='done']`.
  static (Color ink, Color ground) colours(QueryLook look, StatusCategory category, StatusLook mark) {
    final t = look.t;
    if (category == StatusCategory.done) return (t.color('glacier-green-11'), t.colorOf('color-mix(in srgb, var(--glacier-green-9) 14%, transparent)'));
    if (mark == StatusLook.review) return (t.color('glacier-purple-11'), t.colorOf('color-mix(in srgb, var(--glacier-purple-9) 14%, transparent)'));
    if (category == StatusCategory.doing) return (t.color('glacier-blue-11'), t.colorOf('color-mix(in srgb, var(--glacier-blue-9) 14%, transparent)'));
    return (look.ink2, t.colorOf('color-mix(in srgb, var(--app-ink-4) 18%, transparent)'));
  }

  @override
  Widget build(BuildContext context) {
    final em = parent;
    final mark = statusLook(cell.text, workflow);
    final (ink, ground) = colours(look, cell.category, mark);
    // .status { display: inline-flex; align-items: center; gap: 0.35em; padding: 0.1em 0.55em 0.1em 0.4em;
    //   border-radius: var(--glacier-radius-full); white-space: nowrap }
    final line = pageLine(em, QueryLook.leading);
    // `<StatusIcon size="0.95em" />`
    final icon = 0.95 * em;
    final ends = layoutUnitFloor(0.1 * em);
    final height = line + 2 * ends;
    return Baselined(
      // A flex container's baseline is its first item's, and the mark has none of its own: its foot.
      baseline: (height - icon) / 2 + icon,
      child: Part(
        'status',
        child: Container(
          height: height,
          padding: EdgeInsets.only(left: 0.4 * em, right: 0.55 * em),
          decoration: ShapeDecoration(color: ground, shape: const StadiumBorder()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatusIcon(look: mark, size: icon),
              SizedBox(width: 0.35 * em),
              Part('statusWords', child: PageWords(cell.text, look.sans(em, color: ink), line: line, softWrap: false, maxLines: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

String _said(Cell cell) => switch (cell) {
  EmptyCell() => 'none',
  StatusCell(:final text) => text,
  PriorityCell(:final name) => name,
  PeopleCell(:final names) => names.join(', '),
  DayCell(:final day) => day,
  _ => '',
};

/// A value that opens its sheet where it can be picked (`Acts.pick`), drawn as itself inside a quiet button; drawn
/// as itself alone where it cannot (`Picked`). Its press is its own: it never starts a board's card being carried.
class QueryPicked extends StatelessWidget {
  const QueryPicked({super.key, required this.look, required this.row, required this.column, required this.cell, required this.acts, required this.child});

  final QueryLook look;
  final QueryRow row;
  final QueryColumn column;
  final Cell cell;
  final QueryActs acts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!acts.pickable(row, column.field)) return child;
    return Semantics(
      container: true,
      button: true,
      label: '${column.label}: ${_said(cell)}. Change it',
      onTap: () => acts.pick(row, column, cell),
      excludeSemantics: true,
      child: _Control(acts: acts, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => acts.pick(row, column, cell), child: child)),
    );
  }
}

/// A cell, drawn as what it holds (`CellView`). [quiet] is a row that is finished with, whose days are not late;
/// [brief] is a list's or a card's line of them, where a priority is its mark alone and an empty cell is nothing at
/// all. [parent] is the type it stands in.
Widget? cellView(QueryLook look, Cell cell, {required String field, required QueryActs acts, required bool quiet, required bool brief, List<String>? workflow, required double parent, QueryRow? row}) {
  final line = pageLine(parent, QueryLook.leading);
  switch (cell) {
    case EmptyCell():
      // .none { color: var(--app-ink-4) }
      return brief ? null : Semantics(label: 'None', excludeSemantics: true, child: Part('none', child: PageWords('–', look.sans(parent, color: look.ink4), line: line, softWrap: false)));
    case TextCell(:final text):
      // A ticket's key in the mono face it is written in, as everywhere a key is shown.
      // .keyCell { font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-xs);
      //   letter-spacing: 0.02em; color: var(--app-ink-2) }
      if (field == 'id') return Part('keyCell', child: _onLine(look, parent, PageWords(text, look.mono(look.xs, color: look.ink2, tracking: 0.02 * look.xs), line: look.lineXs, softWrap: false)));
      return Part('text', child: PageWords(text, look.sans(parent, color: quiet && !brief ? look.ink3 : null), line: line, softWrap: false));
    case NumberCell(:final text):
      return Part('number', child: PageWords(text, look.sans(parent, color: quiet && !brief ? look.ink3 : null, tabular: true), line: line, softWrap: false));
    case DayCell(:final day, :final tone):
      // .day[data-tone='overdue'] { color: var(--glacier-red-11) }  .day[data-tone='today'] { color: var(--glacier-amber-11) }
      final shown = quiet ? null : tone;
      final color = switch (shown) {
        DayTone.overdue => look.t.color('glacier-red-11'),
        DayTone.today => look.t.color('glacier-amber-11'),
        null => quiet && !brief ? look.ink3 : null,
      };
      return Semantics(
        label: daySaid(day, acts.today, acts.locale),
        excludeSemantics: true,
        child: Part('day', child: PageWords(dayLabel(day, acts.today, acts.locale), look.sans(parent, color: color ?? (brief ? look.ink2 : null), tabular: true), line: line, softWrap: false)),
      );
    case PriorityCell(:final name):
      final chip = chipLook(FieldSpan(kind: FieldKind.priority, from: 0, to: 0, key: 'priority', value: name), today: acts.today, done: quiet, locale: acts.locale);
      if (chip == null) return null;
      final mark = QueryChip(look: look, chip: chip, parent: parent);
      // .priority { display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: var(--glacier-space-1) }
      return Part(
        'priority',
        child: brief
            ? mark
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  mark,
                  SizedBox(width: look.space(1)),
                  PageWords(chip.label.replaceFirst(_priorityWord, ''), look.sans(parent, color: quiet ? look.ink3 : null), line: line, softWrap: false),
                ],
              ),
      );
    case StatusCell():
      return QueryStatus(look: look, cell: cell, workflow: workflow, parent: parent);
    case PeopleCell(:final names):
      final chips = <Widget>[];
      for (final name in names) {
        final chip = chipLook(FieldSpan(kind: FieldKind.person, from: 0, to: 0, key: 'assignee', value: name), today: acts.today, done: quiet, locale: acts.locale);
        if (chip == null) continue;
        if (chips.isNotEmpty) chips.add(SizedBox(width: look.space(1)));
        chips.add(QueryChip(look: look, chip: chip, parent: parent));
      }
      // .people { display: inline-flex; align-items: baseline; gap: var(--glacier-space-1) }
      return Part('people', child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: chips));
    case ListCell(:final items, :final links) when links:
      // A relation, `project: [[Kiln]]`: each note it names a chip, as a tag is, that opens it (the port's own).
      final style = look.sans(parent, color: brief ? look.ink2 : (quiet ? look.ink3 : null));
      final open = acts.onOpenTitle;
      final chips = <Widget>[];
      for (final item in items) {
        if (chips.isNotEmpty) chips.add(SizedBox(width: look.space(1)));
        final chip = PageWords.rich(TextSpan(children: <InlineSpan>[WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: QueryLinkChip(look: look, title: item, parent: parent))]), style, line: line, softWrap: false);
        chips.add(
          open == null
              ? chip
              : Semantics(container: true, button: true, label: 'Open $item', onTap: () => open(item), excludeSemantics: true, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => open(item), child: chip)),
        );
      }
      return Part('relation', child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: chips));
    case ListCell(:final items) when field == 'labels':
      // A ticket's labels in their colours (lib/tickets/ui/label_chips.dart; Matt, 2026-10-31).
      return Part('labels', child: _onLine(look, parent, LabelChips(labels: items, colours: row == null ? const {} : acts.labelColours?.call(row) ?? const {}, size: 0.92 * parent)));
    case ListCell(:final items, :final tags):
      // .list { display: inline-flex; align-items: baseline; gap: var(--glacier-space-1) }
      // .item + .item::before { content: ', '; margin-inline-start: -0.25em }
      final style = look.sans(parent, color: brief ? look.ink2 : (quiet ? look.ink3 : null));
      final parts = <Widget>[];
      for (final (index, item) in items.indexed) {
        if (parts.isNotEmpty) parts.add(SizedBox(width: look.space(1)));
        if (tags) {
          parts.add(PageWords.rich(TextSpan(children: <InlineSpan>[WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: QueryTag(look: look, text: '#$item', parent: parent))]), style, line: line, softWrap: false));
        } else {
          parts.add(Transform.translate(offset: Offset(index > 0 ? -0.25 * parent : 0, 0), child: PageWords(index > 0 ? ', $item' : item, style, line: line, softWrap: false)));
        }
      }
      return Part('list', child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: parts));
    case BoolCell(:final on):
      // `<Check size="1em" strokeWidth={2.6} />`  .yes { vertical-align: -0.15em; color: var(--app-ink-2) }
      if (on) return Semantics(label: 'Yes', child: Part('yes', child: _onLine(look, parent, Baselined(baseline: 0.85 * parent, child: AppIcon(Lucide.check, size: parent, strokeWidth: 2.6, color: look.ink2, wash: false)))));
      return brief ? null : Part('none', child: PageWords('No', look.sans(parent, color: look.ink4), line: line, softWrap: false));
  }
}

/// [child] on a line of the type it stands in, set on that line's baseline: an inline box in a line box, whose
/// height is the line's however small the box.
Widget _onLine(QueryLook look, double parent, Widget child) => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.baseline,
  textBaseline: TextBaseline.alphabetic,
  children: <Widget>[PageWords('', look.sans(parent), line: pageLine(parent, QueryLook.leading)), child],
);

/// The cells a list's row or a card shows beside its name: every column but the name, nothing where they are empty
/// (`Meta`).
class QueryMeta extends StatelessWidget {
  const QueryMeta({super.key, required this.look, required this.row, required this.result, required this.acts, this.fills = false});

  final QueryLook look;
  final QueryRow row;
  final QueryResult result;
  final QueryActs acts;

  /// Whether it is as wide as its room (a card's, a grid's item) or as its cells (a list's line's).
  final bool fills;

  /// What [row] shows on its line: the name is the row's own; a ticket's key is before it already; the note a to-do
  /// is in says itself last; and the field it is grouped by is its group's heading, which a card under it need not
  /// say again.
  static List<(QueryColumn, Cell)> shown(QueryRow row, QueryResult result) => <(QueryColumn, Cell)>[
    for (final (index, column) in result.columns.indexed)
      if (index != result.opens && column.field != 'id' && column.field != 'note' && column.field != result.group && row.cells[index] is! EmptyCell) (column, row.cells[index]),
  ];

  static String? inNote(QueryRow row, QueryResult result) {
    if (result.kind != QueryKind.tasks) return null;
    final at = result.columns.indexWhere((column) => column.field == 'note');
    final cell = at < 0 ? null : row.cells[at];
    return cell is TextCell ? cell.text : null;
  }

  /// Whether [row] has a line of them at all.
  static bool has(QueryRow row, QueryResult result) => shown(row, result).isNotEmpty || (result.kind == QueryKind.tasks && result.columns.any((column) => column.field == 'note'));

  @override
  Widget build(BuildContext context) {
    final quiet = row.category == StatusCategory.done || row.done == true;
    final cells = <Widget>[];
    for (final (column, cell) in shown(row, result)) {
      final drawn = cellView(look, cell, field: column.field, acts: acts, quiet: quiet, brief: true, workflow: row.workflow, parent: look.xs, row: row);
      if (drawn == null) continue;
      cells.add(Part('metaCell', child: QueryPicked(look: look, row: row, column: column, cell: cell, acts: acts, child: drawn)));
    }
    final note = inNote(row, result);
    // .inNote { color: var(--app-ink-3) }
    if (note != null) cells.add(Part('inNote', child: PageWords(note, look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)));
    // .meta { display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: var(--glacier-space-2);
    //   font-size: var(--glacier-font-size-xs); color: var(--app-ink-2) }
    return Part('meta', child: CssWrap(gap: look.space(2), rowGap: look.space(2), align: CssAlign.baseline, shrinkWrap: !fills, children: cells));
  }
}

/// A ticket's labels and its component in their colours, on its card or its list's row, where the query has no
/// column of its own for them (lib/tickets/ui/label_chips.dart; Matt, 2026-10-31: "shown on cards and rows").
class QueryLabelLine extends StatelessWidget {
  const QueryLabelLine({super.key, required this.look, required this.row, required this.result, required this.acts});

  final QueryLook look;
  final QueryRow row;
  final QueryResult result;
  final QueryActs acts;

  static bool _column(QueryResult result, String field) => result.columns.any((column) => column.field == field);

  static List<String> _labels(QueryRow row, QueryResult result) => _column(result, 'labels') ? const [] : row.labels;
  static String? _component(QueryRow row, QueryResult result) => _column(result, 'component') || result.group == 'component' ? null : row.component;

  /// Whether [row] has any to draw: only in the app's own drawing, which hands the labels' colours
  /// ([QueryActs.labelColours]); a query drawn without them is the page's card to the letter.
  static bool has(QueryRow row, QueryResult result, QueryActs acts) => acts.labelColours != null && LabelChips.has(_labels(row, result), _component(row, result));

  @override
  Widget build(BuildContext context) => Part(
    'labelLine',
    child: LabelChips(labels: _labels(row, result), component: _component(row, result), colours: acts.labelColours?.call(row) ?? const {}, size: 0.92 * look.xs),
  );
}

/// A group's heading, for a list or a table grouped by a field: its value, how many, and its totals (`GroupHead`).
class QueryGroupHead extends StatelessWidget {
  const QueryGroupHead({super.key, required this.look, required this.group, this.onAdd});

  final QueryLook look;
  final QueryGroup group;

  /// A lane's +, where the lane makes tickets.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final cell = group.cell;
    final add = onAdd;
    // .groupHead { display: flex; align-items: center; flex-wrap: wrap; gap: var(--glacier-space-2);
    //   padding-block: var(--glacier-space-1); color: var(--app-ink-2) }
    final words = <Widget>[
      if (cell is StatusCell)
        QueryStatus(look: look, cell: cell, parent: look.em)
      else
        // .groupLabel { font-weight: var(--glacier-font-weight-semibold) }
        Part('groupLabel', child: PageWords(group.label, look.sans(look.em, weight: 'semibold', color: look.ink2), line: look.line)),
      Part('count', child: PageWords('${group.rows.length}', look.sans(look.xs, color: look.ink3, tabular: true), line: look.lineXs, softWrap: false)),
      // .groupTotal { font-size: var(--glacier-font-size-xs); font-variant-numeric: tabular-nums; color: var(--app-ink-3) }
      for (final total in group.totals) Part('groupTotal', child: PageWords('${total.label} ${total.text}', look.sans(look.xs, color: look.ink3, tabular: true), line: look.lineXs, softWrap: false)),
    ];
    final Widget head;
    if (add == null) {
      head = CssWrap(gap: look.space(2), rowGap: look.space(2), align: CssAlign.center, children: words);
    } else {
      // .laneAdd { margin-inline-start: auto; inline-size: 2em; block-size: 2em; border-radius: 999px;
      //   background: color-mix(in oklch, currentColor 8%, transparent); color: var(--app-ink-2) }
      final size = 2 * buttonType;
      head = CssRow(
        gap: look.space(2),
        children: <Widget>[
          for (final word in words) CssItem(least: 0, child: word),
          CssItem(
            shrink: 0,
            pushed: true,
            child: Semantics(
              container: true,
              button: true,
              label: 'Add a ticket to ${group.label}',
              onTap: add,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: add,
                child: Part(
                  'laneAdd',
                  child: Container(
                    width: size,
                    height: size,
                    decoration: ShapeDecoration(color: QueryLook.mix(look.ink2, 0.08), shape: const CircleBorder()),
                    // `<Plus size="1.05em" strokeWidth={2.2} />`
                    child: Center(child: AppIcon(Lucide.plus, size: 1.05 * buttonType, strokeWidth: 2.2, color: look.ink2, wash: false)),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Part('groupHead', child: Padding(padding: EdgeInsets.symmetric(vertical: look.space(1)), child: head));
  }
}

/// The totals under a list, a board or a month (`Totals`).
class QueryTotals extends StatelessWidget {
  const QueryTotals({super.key, required this.look, required this.totals});

  final QueryLook look;
  final List<Total> totals;

  @override
  Widget build(BuildContext context) {
    // .totals { display: flex; flex-wrap: wrap; gap: var(--glacier-space-4); margin: var(--glacier-space-2) 0 0;
    //   color: var(--app-ink-3) }
    // .totals strong { color: var(--app-ink); font-weight: var(--glacier-font-weight-semibold);
    //   font-variant-numeric: tabular-nums }
    final quiet = look.sans(look.em, color: look.ink3);
    return Padding(
      padding: EdgeInsets.only(top: look.space(2)),
      child: Part(
        'totals',
        child: CssWrap(
          gap: look.space(4),
          rowGap: look.space(4),
          align: CssAlign.start,
          children: <Widget>[
            for (final total in totals)
              Part(
                'total',
                child: PageWords.rich(
                  TextSpan(children: <InlineSpan>[TextSpan(text: '${total.label} '), TextSpan(text: total.text, style: look.sans(look.em, weight: 'semibold', color: look.ink, tabular: true))]),
                  quiet,
                  line: look.line,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
