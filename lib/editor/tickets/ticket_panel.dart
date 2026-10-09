/// A ticket's properties, drawn over its words in place of its front matter (tickets.dart; docs/DESIGN.md §157):
/// Matt asked for tickets as notes, with "the quiet front matter" becoming "a Notion-style properties panel with
/// pickers for status, person and date". Ports `src/app/editor/TicketPanel.tsx` and `TicketPanel.module.css`.
///
/// Its key heads it; each row is a property's name and its value, and a tap on the value picks a new one and
/// writes it into the front matter ([TicketPanel.write]), which is the only place any of it is kept. A ticket
/// waiting on one that is not done says so first, with a lock. Read, with nothing to pick, where the note cannot be
/// edited.
///
/// What differs:
/// - **A status, a person, a priority and a day are picked in the app's one field sheet** (fields/field_picker.dart
///   [FieldPicker]), the sheet a query's cell and a notebook's index open, where the page's panel had three sheets
///   of its own with dots for marks. So a status is offered with its mark (a ring, a dot, an eye, a tick) and
///   "No status" after the workflow, a person with their initial in their hue, and a day as Today, Tomorrow, Next
///   week, Pick a date and Remove. Each pick is one write.
/// - **A day** had the phone's own date field laid unseen over its words on the page. Here a tap on the day opens
///   the day's sheet, whose Pick a date is the app's calendar ([TicketPanel.dayPicker]); the cross beside it still
///   takes the day off.
/// - **An estimate and labels** were typed in place, in a field in the panel. A field of its own inside the
///   editor has to be hung beside the editor's keyboard (boards/composer.dart says how); here a tap on the value
///   opens a sheet with the field in it, and the keyboard's done key, or leaving the sheet, writes what was typed,
///   and nothing for a field left as it was.
/// - `:hover` grounds and `title=` tooltips are a pointer's and are left out.
library;

import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../book/tickets.dart' show TicketChoice, waitingOn;
import '../../core/properties.dart';
import '../../core/task_fields.dart' show priorityOf;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../fields/field_picker.dart';
import '../fields/field_picks.dart';
import '../items/field_chips.dart' show priorityIcon;
import '../items/field_menu.dart' show DayPicker;
import '../looks/look.dart' show layoutUnitFloor;
import '../queries/query_layout.dart';
import '../queries/query_look.dart';
import 'ticket_rows.dart';

/// What the screen hands the editor for a ticket's panel and its keys: the library's tickets, read when they are
/// drawn (`TicketOptions`).
class TicketOptions {
  const TicketOptions({required this.statuses, required this.people, required this.choices, required this.find, required this.open, this.nextId});

  /// The workflow this note's status moves through: its notebook's (lib/book/tickets.dart), or the default.
  final List<String> Function() statuses;

  /// The people the library already names, the most named first (lib/book/tickets.dart `peopleIn`).
  final List<String> Function() people;

  /// Every other ticket, for Blocked by and Parent.
  final List<TicketChoice> Function() choices;

  /// The ticket a key or a title names, or null.
  final TicketChoice? Function(String target) find;

  /// Opens the ticket a key or a title names.
  final void Function(String target) open;

  /// The key this note would get from its notebook, for a ticket that has none yet (lib/book/tickets.dart
  /// `nextTicketId`).
  final String? Function()? nextId;
}

/// A property's name, as the panel says it (lib/core/properties.dart `ticketProperties`).
String labelOf(String key) {
  for (final property in ticketProperties) {
    if (property.key == key) return property.label;
  }
  return key;
}

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key, required this.look, required this.front, required this.options, required this.editable, required this.write, required this.openLines, required this.today, this.locale, this.dayPicker});

  final QueryLook look;

  /// The front matter's lines, fences and all.
  final String front;

  /// The library's tickets and people; null draws the ticket from its own lines alone.
  final TicketOptions? options;

  /// Whether the note can be changed here.
  final bool editable;

  /// Writes one property: a value, a list, or null to take it off.
  final void Function(String key, Object? value) write;

  /// Shows the front matter as its lines, the caret in them.
  final VoidCallback openLines;
  final String today;
  final String? locale;

  /// The app's calendar, for a day's sheet's Pick a date.
  final DayPicker? dayPicker;

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  bool _more = false;

  /// The key whose sheet is open.
  String? _picking;

  QueryLook get look => widget.look;
  TextStyle get _words => look.sans(look.em);

  String _raw(String key) {
    for (final property in propertiesOf(widget.front)) {
      if (property.key.toLowerCase() == key) return property.value;
    }
    return '';
  }

  void _pick(String key) {
    fireMotor(HapticKind.selection);
    setState(() => _picking = key);
  }

  Widget _tap({required String label, required VoidCallback? onTap, required Widget child, bool button = true}) {
    if (onTap == null) return child;
    return Semantics(container: true, button: button, label: label, onTap: onTap, excludeSemantics: true, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child));
  }

  // .dot { flex: none; inline-size: 0.6em; block-size: 0.6em; border-radius: 50%; background: var(--app-ink-4) }
  // .dot[data-category='doing'] { background: var(--glacier-blue-9) }  [data-category='done'] { … green-9 }
  Widget _dot(StatusCategory category) {
    final size = layoutUnitFloor(0.6 * look.em);
    final color = switch (category) {
      StatusCategory.doing => look.t.color('glacier-blue-9'),
      StatusCategory.done => look.t.color('glacier-green-9'),
      StatusCategory.todo => look.ink4,
    };
    return Part('dot', child: Container(width: size, height: size, decoration: ShapeDecoration(color: color, shape: const CircleBorder())));
  }

  /// `.chip`: a value's words on a quiet ground a tap shows, stepped out so its words line up with the column.
  // .chip { display: inline-flex; align-items: center; gap: var(--glacier-space-2); max-inline-size: 100%;
  //   min-block-size: 1.9em; margin: 0 0 0 calc(var(--glacier-space-2) * -1); padding: 0 var(--glacier-space-2);
  //   border-radius: var(--glacier-radius-md); white-space: nowrap; overflow: hidden; text-overflow: ellipsis }
  // .chip[data-empty] { color: var(--app-ink-4) }
  // .chip[data-due='overdue'] { color: var(--glacier-red-11) }  [data-due='today'] { color: var(--glacier-amber-11) }
  Widget _chip(String text, {Widget? mark, bool empty = false, String? due, String? property, VoidCallback? onPress, bool tight = false}) {
    final color = empty
        ? look.ink4
        : switch (due) {
            'overdue' => look.t.color('glacier-red-11'),
            'today' => look.t.color('glacier-amber-11'),
            _ => look.ink,
          };
    final chip = Part(
      'chip',
      child: Container(
        constraints: BoxConstraints(minHeight: layoutUnitFloor(1.9 * look.em)),
        padding: EdgeInsets.only(left: look.space(2), right: tight ? 0 : look.space(2)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (mark != null) ...<Widget>[mark, SizedBox(width: look.space(2))],
            Flexible(child: Part('chipWords', child: PageWords(text, look.sans(look.em, color: color), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
        ),
      ),
    );
    return _tap(label: property == null ? text : '$property: $text. Change it', onTap: onPress, child: chip);
  }

  /// A value's row of pieces, its first stepped out by its own padding (`margin-inline-start` of `-space-2`).
  Widget _stepped(List<Widget> pieces, {double gap = 0}) => Transform.translate(
    offset: Offset(-look.space(2), 0),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (index, piece) in pieces.indexed) ...<Widget>[if (index > 0) SizedBox(width: gap), index == pieces.length - 1 ? Flexible(child: piece) : piece],
      ],
    ),
  );

  /// Small round buttons with an icon: `.asText, .clear, .edit`.
  // .asText, .clear, .edit { display: inline-flex; align-items: center; justify-content: center;
  //   gap: var(--glacier-space-1); padding: var(--glacier-space-1); border-radius: var(--glacier-radius-full);
  //   background: transparent; color: var(--app-ink-3) }  .edit { padding-inline: var(--glacier-space-2) }
  Widget _round(String name, LucideIcon icon, double size, {required String label, required VoidCallback onTap, String? words, bool wide = false}) => _tap(
    label: label,
    onTap: onTap,
    child: Part(
      name,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: look.space(wide ? 2 : 1), vertical: look.space(1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppIcon(icon, size: size, color: look.ink3),
            if (words != null) ...<Widget>[SizedBox(width: look.space(1)), PageWords(words, look.sans(look.em, color: look.ink3), line: look.line, softWrap: false)],
          ],
        ),
      ),
    ),
  );

  /// Another ticket, as a property links it: its status's dot, its key and its title; a lock where this one waits on
  /// it (`LinkChip`).
  // .link { display: inline-flex; align-items: center; gap: var(--glacier-space-1);
  //   max-inline-size: calc(100% - 3em); overflow: hidden; min-block-size: 1.75em;
  //   padding: 0 var(--glacier-space-2); border: 1px solid var(--app-rule);
  //   border-radius: var(--glacier-radius-full); background: var(--app-paper) }
  // .link[data-waiting] { border-color: color-mix(in oklch, var(--glacier-amber-9) 45%, transparent);
  //   color: var(--glacier-amber-11) }
  Widget _link(TicketChoice choice, {required bool waiting, VoidCallback? onOpen, required double room}) {
    final amber = look.t.color('glacier-amber-11');
    final ink = waiting ? amber : look.ink;
    final key = choice.key;
    final title = key != null && choice.title == key ? '' : choice.title;
    final link = Part(
      'link',
      child: Container(
        constraints: BoxConstraints(minHeight: layoutUnitFloor(1.75 * look.em), maxWidth: room),
        padding: EdgeInsets.symmetric(horizontal: look.space(2)),
        decoration: ShapeDecoration(
          color: look.paper,
          shape: StadiumBorder(side: BorderSide(color: waiting ? look.t.colorOf('color-mix(in oklch, var(--glacier-amber-9) 45%, transparent)') : look.rule)),
        ),
        child: CssRow(
          gap: look.space(1),
          shrinkWrap: true,
          children: <Widget>[
            // `<Lock size={12} strokeWidth={2.2} />`
            if (waiting) CssItem(least: 0, child: Semantics(label: 'Waiting on it', child: AppIcon(Lucide.lock, size: 12, strokeWidth: 2.2, color: amber))) else CssItem(shrink: 0, child: _dot(choice.category)),
            // .linkKey { flex: none; font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-xs);
            //   color: var(--app-ink-3) }  .link[data-waiting] .linkKey { color: inherit }
            if (key != null) CssItem(shrink: 0, child: Part('linkKey', child: PageWords(key, look.mono(look.xs, color: waiting ? amber : look.ink3), line: look.lineXs, softWrap: false))),
            // .linkTitle { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }  :empty { display: none }
            if (title.isNotEmpty) CssItem(least: 0, child: Part('linkTitle', child: PageWords(title, look.sans(look.em, color: ink), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
        ),
      ),
    );
    return _tap(label: key == null ? title : '$key $title'.trim(), onTap: onOpen, child: link);
  }

  Widget _value(String key, Ticket ticket, List<({String target, TicketChoice found})> waits) {
    final options = widget.options;
    final editable = widget.editable;
    VoidCallback? pick(String what) => editable && options != null ? () => _pick(what) : null;
    TicketChoice find(String target) => options?.find(target) ?? TicketChoice(key: null, title: target, status: null, category: StatusCategory.todo);
    switch (key) {
      case 'status':
        final status = ticket.status;
        return _stepped(<Widget>[_chip(status ?? 'Empty', mark: _dot(ticket.category), empty: status == null, property: 'Status', onPress: pick('status'))]);
      case 'assignee':
        final assignee = ticket.assignee;
        // .avatar { inline-size: 1.5em; block-size: 1.5em; border-radius: 50%;
        //   background: color-mix(in oklch, var(--glacier-teal-9) 22%, transparent); color: var(--glacier-teal-11);
        //   font-size: var(--glacier-font-size-xs); font-weight: var(--glacier-font-weight-semibold) }
        final ring = layoutUnitFloor(1.5 * look.xs);
        final avatar = assignee == null || assignee.isEmpty
            ? null
            : Part(
                'avatar',
                child: Container(
                  width: ring,
                  height: ring,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(color: look.t.colorOf('color-mix(in oklch, var(--glacier-teal-9) 22%, transparent)'), shape: const CircleBorder()),
                  child: PageWords(String.fromCharCode(assignee.runes.first).toUpperCase(), look.sans(look.xs, weight: 'semibold', color: look.t.color('glacier-teal-11')), line: look.lineXs, softWrap: false),
                ),
              );
        return _stepped(<Widget>[_chip(assignee ?? 'Empty', mark: avatar, empty: assignee == null, property: 'Assignee', onPress: pick('assignee'))]);
      case 'priority':
        final priority = priorityOf(ticket.priority);
        // .priority[data-tone] …: the kit's chevrons, coloured as a to-do's chip colours them. `size={16}
        //   strokeWidth={2.6}`
        final mark = priority == null
            ? null
            : Part(
                'priority',
                child: AppIcon(
                  priorityIcon[priority.name]!,
                  size: 16,
                  strokeWidth: 2.6,
                  color: switch (priority.name) {
                    'highest' || 'high' => look.t.color('glacier-red-11'),
                    'medium' => look.t.color('glacier-amber-11'),
                    'low' => look.t.color('glacier-blue-11'),
                    _ => look.ink3,
                  },
                ),
              );
        return _stepped(<Widget>[_chip(priority?.label ?? 'Empty', mark: mark, empty: priority == null, property: 'Priority', onPress: pick('priority'))]);
      case 'due' || 'start':
        final day = key == 'due' ? ticket.due : ticket.start;
        final written = _raw(key);
        final said = day != null ? dayLabel(day, widget.today, widget.locale) : (written.isEmpty ? 'Empty' : written);
        final empty = day == null && written.isEmpty;
        final state = key == 'due' ? dueState(day, widget.today, ticket.category) : null;
        final label = labelOf(key);
        if (!editable) return _stepped(<Widget>[_chip(said, empty: empty, due: state)]);
        // .day { display: inline-flex; align-items: center; gap: var(--glacier-space-1); min-inline-size: 0 }
        return _stepped(gap: look.space(1), <Widget>[
          // Alone in its `.day`, the page's chip is no wider than that box, which its own negative margin made a
          // padding narrower: its words run to its edge.
          _chip(said, empty: empty, due: state, property: label, onPress: () => _pick(key), tight: empty),
          // `<X size={12} />`
          if (!empty) _round('clear', Lucide.x, 12, label: 'Take ${label.toLowerCase()} off', onTap: () => widget.write(key, null)),
        ]);
      case 'estimate' || 'labels':
        final value = key == 'estimate' ? _raw('estimate') : propertyList(_raw('labels')).join(', ');
        final label = labelOf(key);
        if (!editable) return _stepped(<Widget>[_chip(value.isEmpty ? 'Empty' : value, empty: value.isEmpty)]);
        // .typed { inline-size: 100%; min-block-size: 1.9em; margin: 0 0 0 calc(var(--glacier-space-2) * -1);
        //   padding: 0 var(--glacier-space-2); border-radius: var(--glacier-radius-md) }
        // .typed::placeholder { color: var(--app-ink-4) }
        return _tap(
          label: '$label: ${value.isEmpty ? 'Empty' : value}. Change it',
          onTap: () => _pick(key),
          child: Transform.translate(
            offset: Offset(-look.space(2), 0),
            child: Part(
              'typed',
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(minHeight: layoutUnitFloor(1.9 * look.em)),
                padding: EdgeInsets.symmetric(horizontal: look.space(2)),
                alignment: Alignment.centerLeft,
                child: PageWords(value.isEmpty ? 'Empty' : value, look.sans(look.em, color: value.isEmpty ? look.ink4 : look.ink), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        );
      default:
        // Blocked by, and Parent: other tickets.
        final parent = ticket.parent;
        final targets = key == 'parent' ? <String>[if (parent != null && parent.isNotEmpty) parent] : ticket.blockedBy;
        final label = labelOf(key);
        // .links { flex: 1; display: flex; flex-wrap: wrap; align-items: center; gap: var(--glacier-space-1) }
        return LayoutBuilder(
          builder: (context, constraints) => Part(
            'links',
            child: CssWrap(
              gap: look.space(1),
              rowGap: look.space(1),
              align: CssAlign.center,
              children: <Widget>[
                for (final target in targets)
                  _link(
                    find(target),
                    waiting: key == 'blocked-by' && waits.any((wait) => wait.target == target),
                    onOpen: options == null ? null : () => options.open(target),
                    // Room left beside the last for its pencil, so a long title is cut rather than putting the pencil on
                    // a line alone.
                    room: constraints.maxWidth - 3 * look.em,
                  ),
                if (editable)
                  // `<Pencil size={13} />`, or `<Plus size={13} />` and "Add".
                  _round('edit', targets.isEmpty ? Lucide.plus : Lucide.pencil, 13, label: 'Change $label', words: targets.isEmpty ? 'Add' : null, wide: true, onTap: () => _pick(key))
                else if (targets.isEmpty)
                  // .empty { color: var(--app-ink-4) }
                  Part('empty', child: PageWords('Empty', look.sans(look.em, color: look.ink4), line: look.line, softWrap: false)),
              ],
            ),
          ),
        );
    }
  }

  Widget? _sheet(Ticket ticket, List<String> statuses) {
    final key = _picking;
    final options = widget.options;
    if (key == null || options == null) return null;
    void close() => setState(() => _picking = null);
    final record = ticket.id ?? '';
    switch (key) {
      case 'status':
        return FieldPicker(pick: StatusPick(value: ticket.status, workflow: statuses), label: 'Status', record: record, onClose: close, onPick: (value) => widget.write('status', value));
      case 'priority':
        return FieldPicker(pick: PriorityPick(value: ticket.priority), label: 'Priority', record: record, onClose: close, onPick: (value) => widget.write('priority', value));
      case 'assignee':
        return FieldPicker(pick: PersonPick(value: ticket.assignee, people: options.people()), label: 'Assignee', record: record, onClose: close, onPick: (value) => widget.write('assignee', value));
      case 'due' || 'start':
        final day = key == 'due' ? ticket.due : ticket.start;
        return FieldPicker(pick: DayPick(value: day, today: widget.today), label: labelOf(key), record: record, dayPicker: widget.dayPicker, onClose: close, onPick: (value) => widget.write(key, value));
      case 'estimate':
        return TypedSheet(label: 'Estimate', value: _raw('estimate'), number: true, onClose: close, onCommit: (typed) => widget.write('estimate', typed.isEmpty ? null : typed));
      case 'labels':
        return TypedSheet(label: 'Labels', value: propertyList(_raw('labels')).join(', '), number: false, onClose: close, onCommit: (typed) => widget.write('labels', propertyList(typed)));
      default:
        return TicketsSheet(what: key, ticket: ticket, options: options, write: widget.write, onClose: close);
    }
  }

  /// The least the panel is laid out at: a small phone's page less its gutters. On the page its grid of names and
  /// values does not shrink past its own words, and a pane narrower than that cuts it: between a docked sidebar and
  /// a docked aside on the Fold the note is 164px wide and the Example project's panel 196 (measured on the page,
  /// 2026-10-09), its right edge under the aside. The page's least is its words'; this is one width for every
  /// ticket, under which its rows are not laid out at all.
  static const double _least = 300;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final panel = _panel(context);
          if (!box.hasBoundedWidth || box.maxWidth >= _least) return panel;
          return ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(width: _least, child: panel),
            ),
          );
        },
      );

  Widget _panel(BuildContext context) {
    final options = widget.options;
    final editable = widget.editable;
    final statuses = options?.statuses() ?? defaultStatuses;
    final ticket = ticketOf(widget.front, statuses);
    if (ticket == null) return const SizedBox.shrink();
    final rows = panelRows(widget.front, _more);
    final hidden = editable && !_more ? hiddenRows(widget.front) : const <String>[];
    final others = otherKeys(widget.front);
    final waits = <({String target, TicketChoice found})>[
      if (options != null)
        for (final wait in waitingOn<TicketChoice>(ticket, options.find)) (target: wait.target, found: wait.found),
    ];
    // A ticket made with no key (a Bug report from the blank page) takes its notebook's next, a tap away.
    final id = ticket.id;
    final offered = (id == null || id.isEmpty) && editable ? options?.nextId?.call() : null;
    final amber = look.t.color('glacier-amber-11');
    final sheet = _sheet(ticket, statuses);

    // .rows { display: grid; grid-template-columns: minmax(5.5em, max-content) minmax(0, 1fr);
    //   column-gap: var(--glacier-space-3) }
    var names = layoutUnitFloor(5.5 * look.em);
    for (final key in rows) {
      final painter = TextPainter(text: TextSpan(text: labelOf(key), style: _words), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout();
      if (painter.width > names) names = painter.width;
      painter.dispose();
    }

    return Padding(
      // '.cm-ticketPanel': { paddingInline: 'var(--app-gutter, 0)', paddingBlock: '0.2em 0.6em' }
      // .panel { margin-block: var(--glacier-space-1) var(--glacier-space-3) }
      padding: EdgeInsets.fromLTRB(look.bleed, layoutUnitFloor(0.2 * look.note) + look.space(1), look.bleed, layoutUnitFloor(0.6 * look.note) + look.space(3)),
      child: Semantics(
        container: true,
        label: id != null && id.isNotEmpty ? 'Ticket $id' : 'Ticket',
        child: Part(
          'panel',
          // .panel { padding: var(--glacier-space-3) var(--glacier-space-4) var(--glacier-space-2);
          //   border: 1px solid var(--app-rule); border-radius: var(--glacier-radius-lg);
          //   background: var(--app-paper-2) }
          child: Container(
            padding: EdgeInsets.fromLTRB(look.space(4), look.space(3), look.space(4), look.space(2)),
            decoration: BoxDecoration(color: look.paper2, border: Border.all(color: look.rule), borderRadius: BorderRadius.circular(look.cardRadius)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // .head { display: flex; align-items: center; gap: var(--glacier-space-2);
                //   margin-block-end: var(--glacier-space-2); color: var(--app-ink-3) }
                Padding(
                  padding: EdgeInsets.only(bottom: look.space(2)),
                  child: Part(
                    'head',
                    child: CssRow(
                      gap: look.space(2),
                      children: <Widget>[
                        // `<TicketMark size={14} strokeWidth={2.1} />`
                        CssItem(shrink: 0, child: AppIcon(Lucide.ticket, size: 14, strokeWidth: 2.1, color: look.ink3)),
                        // .key { font-family: var(--glacier-font-mono); font-weight: var(--glacier-font-weight-semibold);
                        //   letter-spacing: 0.02em; color: var(--app-ink-2) }
                        CssItem(least: 0, child: Part('key', child: PageWords(id != null && id.isNotEmpty ? id : 'Ticket', look.mono(look.em, weight: 'semibold', color: look.ink2, tracking: 0.02 * look.em), line: look.line, softWrap: false, maxLines: 1))),
                        if (offered != null)
                          // .give { padding: 0 var(--glacier-space-2); border: 1px solid var(--app-rule);
                          //   border-radius: var(--glacier-radius-full); background: var(--app-paper);
                          //   color: var(--app-ink-2); font-size: var(--glacier-font-size-xs) }
                          CssItem(
                            shrink: 0,
                            child: _tap(
                              label: 'Give it $offered',
                              onTap: () => widget.write('id', offered),
                              child: Part(
                                'give',
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: look.space(2)),
                                  decoration: ShapeDecoration(color: look.paper, shape: StadiumBorder(side: BorderSide(color: look.rule))),
                                  child: PageWords('Give it $offered', look.sans(look.xs, color: look.ink2), line: look.lineXs, softWrap: false),
                                ),
                              ),
                            ),
                          ),
                        // .asText { margin-inline-start: auto }  `<Braces size={14} />`
                        if (editable) CssItem(shrink: 0, pushed: true, child: _round('asText', Lucide.braces, 14, label: 'Show the properties as text', onTap: widget.openLines)),
                      ],
                    ),
                  ),
                ),
                if (waits.isNotEmpty)
                  // .waiting { display: flex; flex-wrap: wrap; align-items: center;
                  //   gap: var(--glacier-space-1) var(--glacier-space-2); margin: 0 0 var(--glacier-space-2);
                  //   padding: var(--glacier-space-1) var(--glacier-space-2); border-radius: var(--glacier-radius-md);
                  //   background: color-mix(in oklch, var(--glacier-amber-9) 14%, transparent);
                  //   color: var(--glacier-amber-11) }
                  Padding(
                    padding: EdgeInsets.only(bottom: look.space(2)),
                    child: Part(
                      'waiting',
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: look.space(2), vertical: look.space(1)),
                        decoration: BoxDecoration(color: look.t.colorOf('color-mix(in oklch, var(--glacier-amber-9) 14%, transparent)'), borderRadius: BorderRadius.circular(look.t.radius('md'))),
                        child: CssWrap(
                          gap: look.space(2),
                          rowGap: look.space(1),
                          align: CssAlign.center,
                          children: <Widget>[
                            // `<Lock size={13} strokeWidth={2.2} />`
                            AppIcon(Lucide.lock, size: 13, strokeWidth: 2.2, color: amber),
                            PageWords('Waiting on', look.sans(look.em, color: amber), line: look.line, softWrap: false),
                            for (final wait in waits)
                              // .waitOn { display: inline-flex; align-items: baseline; gap: var(--glacier-space-1);
                              //   font-weight: var(--glacier-font-weight-semibold) }
                              // .waitTitle { font-weight: var(--glacier-font-weight-regular); overflow: hidden;
                              //   text-overflow: ellipsis; white-space: nowrap }
                              _tap(
                                label: '${wait.found.key ?? wait.found.title}${wait.found.key != null && wait.found.title.isNotEmpty ? ' ${wait.found.title}' : ''}',
                                onTap: () => options?.open(wait.target),
                                child: Part(
                                  'waitOn',
                                  child: CssRow(
                                    align: CssAlign.baseline,
                                    gap: look.space(1),
                                    shrinkWrap: true,
                                    children: <Widget>[
                                      CssItem(shrink: 0, child: PageWords(wait.found.key ?? wait.found.title, look.sans(look.em, weight: 'semibold', color: amber), line: look.line, softWrap: false)),
                                      if (wait.found.key != null && wait.found.title.isNotEmpty)
                                        CssItem(least: 0, child: Part('waitTitle', child: PageWords(wait.found.title, look.sans(look.em, color: amber), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis))),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Part(
                  'rows',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final key in rows)
                        Row(
                          children: <Widget>[
                            // .name { align-self: center; color: var(--app-ink-3) }
                            SizedBox(width: names, child: Part('name', child: PageWords(labelOf(key), look.sans(look.em, color: look.ink3), line: look.line, softWrap: false))),
                            SizedBox(width: look.space(3)),
                            // .value { display: flex; align-items: center; min-inline-size: 0; min-block-size: 2.25em }
                            Expanded(
                              child: Part(
                                'value',
                                child: Container(constraints: BoxConstraints(minHeight: layoutUnitFloor(2.25 * look.em)), alignment: Alignment.centerLeft, child: _value(key, ticket, waits)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (hidden.isNotEmpty || (others.isNotEmpty && editable))
                  // .foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
                  //   gap: var(--glacier-space-1) var(--glacier-space-3); margin-block-start: var(--glacier-space-1);
                  //   padding-block-start: var(--glacier-space-2); border-block-start: 1px solid var(--app-rule) }
                  Padding(
                    padding: EdgeInsets.only(top: look.space(1)),
                    child: Part(
                      'foot',
                      child: Container(
                        padding: EdgeInsets.only(top: look.space(2)),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: look.rule))),
                        child: CssWrap(
                          gap: look.space(3),
                          rowGap: look.space(1),
                          align: CssAlign.center,
                          spread: true,
                          children: <Widget>[
                            // .more, .others { display: inline-flex; align-items: center; gap: var(--glacier-space-1);
                            //   padding: var(--glacier-space-1) 0; color: var(--app-ink-3);
                            //   font-size: var(--glacier-font-size-xs) }
                            if (hidden.isNotEmpty)
                              _tap(
                                label: hidden.map(labelOf).join(', '),
                                onTap: () => setState(() => _more = true),
                                child: Part(
                                  'more',
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: look.space(1)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        // `<Plus size={13} />`, a space, and the names.
                                        AppIcon(Lucide.plus, size: 13, color: look.ink3),
                                        SizedBox(width: look.space(1)),
                                        Flexible(child: PageWords(hidden.map(labelOf).join(', '), look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            // .others { font-family: var(--glacier-font-mono); overflow: hidden; text-overflow: ellipsis }
                            if (others.isNotEmpty && editable)
                              _tap(
                                label: 'Show the properties as text',
                                onTap: widget.openLines,
                                child: Part(
                                  'others',
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: look.space(1)),
                                    child: PageWords(others.join(' · '), look.mono(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ?sheet,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A value typed in a sheet, a number or a list with commas, written when the keyboard's done key is pressed or
/// the sheet is left, and nothing for a field left as it was (`TypedValue`, which typed in place on the page).
class TypedSheet extends StatefulWidget {
  const TypedSheet({super.key, required this.label, required this.value, required this.number, required this.onCommit, required this.onClose});

  final String label;
  final String value;
  final bool number;
  final void Function(String typed) onCommit;
  final VoidCallback onClose;

  @override
  State<TypedSheet> createState() => _TypedSheetState();
}

class _TypedSheetState extends State<TypedSheet> {
  late String _draft = widget.value;

  void _leave() {
    final onCommit = widget.onCommit;
    final typed = _draft.trim();
    widget.onClose();
    if (typed != widget.value.trim()) onCommit(typed);
  }

  @override
  Widget build(BuildContext context) => Sheet(
    label: widget.label,
    onClose: _leave,
    children: <Widget>[
      SheetTitle.text(widget.label),
      SheetField(
        label: widget.label,
        value: _draft,
        placeholder: 'Empty',
        autoFocus: true,
        // `inputMode="decimal"`, `enterKeyHint="done"`
        inputMode: widget.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        enterKeyHint: TextInputAction.done,
        onChange: (text) => setState(() => _draft = text),
        onSubmitted: (_) => _leave(),
      ),
    ],
  );
}

/// The sheet another ticket, or several, is picked from: found by its key or its title as it is typed (the last
/// branch of the page's `Picker`).
class TicketsSheet extends StatefulWidget {
  const TicketsSheet({super.key, required this.what, required this.ticket, required this.options, required this.write, required this.onClose});

  /// `blocked-by`, which holds several, or `parent`, which holds one.
  final String what;
  final Ticket ticket;
  final TicketOptions options;
  final void Function(String key, Object? value) write;
  final VoidCallback onClose;

  @override
  State<TicketsSheet> createState() => _TicketsSheetState();
}

class _TicketsSheetState extends State<TicketsSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final ticket = widget.ticket;
    final many = widget.what == 'blocked-by';
    final parent = ticket.parent;
    final current = many ? ticket.blockedBy : <String>[if (parent != null && parent.isNotEmpty) parent];
    bool names(String target, TicketChoice choice) => (choice.key != null && target.toUpperCase() == choice.key) || target.toLowerCase() == choice.title.toLowerCase();
    bool holds(TicketChoice choice) => current.any((target) => names(target, choice));
    final needle = _typed.trim().toLowerCase();
    final choices = <TicketChoice>[
      for (final choice in options.choices())
        if (needle.isEmpty || '${choice.key ?? ''} ${choice.title}'.toLowerCase().contains(needle)) choice,
    ];
    void chose(String key, Object? value) {
      final write = widget.write;
      widget.onClose();
      write(key, value);
    }

    void toggle(TicketChoice choice) {
      final kept = <String>[for (final target in current) if (!names(target, choice)) target];
      final links = <String>[
        for (final target in holds(choice) ? kept : <String>[...kept, choice.key ?? choice.title])
          linkTo(options.find(target) ?? TicketChoice(key: null, title: target, status: null, category: StatusCategory.todo)),
      ];
      widget.write('blocked-by', linksValue(links));
    }

    final label = labelOf(widget.what);
    return Sheet(
      label: label,
      onClose: widget.onClose,
      children: <Widget>[
        SheetTitle.text(label),
        SheetField(label: 'Find a ticket', value: _typed, placeholder: 'Its key or its title', onChange: (text) => setState(() => _typed = text)),
        SheetGroup(
          children: <Widget>[
            if (choices.isEmpty) SheetRow(label: needle.isNotEmpty ? 'No ticket by that key or title.' : 'No other tickets yet.'),
            for (final choice in choices.take(40))
              SheetRow(
                key: ValueKey<String>('ticket:${choice.key ?? ''}-${choice.title}'),
                icon: StatusIcon(look: statusLook(choice.status ?? '', options.statuses())),
                label: choice.key != null ? '${choice.key}  ${choice.title}' : choice.title,
                hint: choice.status,
                chosen: holds(choice),
                onPress: () => many ? toggle(choice) : chose('parent', holds(choice) ? null : linkTo(choice)),
              ),
            if (!many && current.isNotEmpty) SheetRow(label: 'No parent', onPress: () => chose('parent', null)),
          ],
        ),
      ],
    );
  }
}
