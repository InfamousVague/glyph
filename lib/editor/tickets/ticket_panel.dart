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
/// - **A person and a priority are picked in the app's one field sheet** (fields/field_picker.dart [FieldPicker]),
///   the sheet a query's cell and a notebook's index open, where the page's panel had sheets of its own: a person
///   with their initial in their hue. A status has the panel's own sheet, as on the page: the workflow and no
///   more, each status with its category's dot ([StatusSheet]). Each pick is one write.
/// - **A day** had the phone's own date field laid unseen over its words on the page, so a tap on the day opened
///   the phone's calendar. Here the tap asks the app's calendar ([TicketPanel.dayPicker], the phone's own date
///   picker on Android) for a day at the chip, and writes what is picked; the cross beside it takes the day off.
///   Only where the app has no calendar to ask does the day's sheet open instead (Today, Tomorrow, Next week,
///   Remove).
/// - **An estimate and labels** are typed in place, as on the page ([TypedField]): a field in the panel, written
///   when it is left or the keyboard's done key is pressed, nothing for a field left as it was, and Escape puts
///   back what it had. A field of its own inside the editor is hung beside the editor's keyboard, not under it
///   (boards/composer.dart says why and how). Until it is tapped it is drawn as the page's words are.
/// - `:hover` grounds and `title=` tooltips are a pointer's and are left out.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show GlacierTextSelectionControls, GlacierTextSelectionToolbar, HapticKind, fireMotor;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../book/tickets.dart' show TicketChoice, Wait, waitingOn;
import '../../core/days.dart' show isIsoDay;
import '../../core/properties.dart';
import '../../activity/job_mark.dart' show activityCalm;
import '../../core/planning/cycles.dart' show cycleDaysWords;
import '../../core/planning/planning.dart' show EpicProgress, ticketPriorityLabel;
import '../../core/preferences.dart' show preferences;
import '../../core/query/planning.dart' show TicketPlanning;
import '../../core/task_fields.dart' show priorityOf;
import '../../sheet/ask_first.dart';
import '../../sheet/css.dart' show snapBorder;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../boards/composer.dart' show ownTextKeys;
import '../fields/field_picker.dart';
import '../fields/field_picks.dart';
import '../items/field_chips.dart' show priorityIcon;
import '../items/field_menu.dart' show DayPicker;
import '../looks/look.dart' show layoutUnitFloor;
import '../queries/query_layout.dart';
import '../queries/plan_marks.dart' show PriorityChip, StaleMark, TicketPrioritySheet;
import '../queries/query_look.dart';
import 'ticket_follow.dart';
import 'ticket_planning.dart';
import 'ticket_rows.dart';
import 'ticket_work.dart';

/// What the screen hands the editor for a ticket's panel and its keys: the library's tickets, read when they are
/// drawn (`TicketOptions`).
class TicketOptions {
  const TicketOptions({required this.statuses, required this.people, required this.choices, required this.find, required this.open, this.nextId, this.subTickets, this.addSubTicket, this.problem, this.planning, this.follow, this.work});

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

  /// The tickets whose `parent:` is this one (lib/book/ticket_links.dart; Matt, 2026-10-30): its Sub-tickets and their
  /// progress. Absent, none are shown.
  final List<TicketChoice> Function()? subTickets;

  /// Add sub-ticket: a ticket of that title made with this one as its parent. Absent, no Add.
  final void Function(String title)? addSubTicket;

  /// Why a value cannot be written for Blocked by or Parent, in a sentence, or null where it can: a ring, a ticket
  /// waiting on itself however far round (lib/book/ticket_links.dart `blockedByProblem`, `parentProblem`).
  final String? Function(String key, Object? value)? problem;

  /// Its time and its pull requests, under its rows (ticket_work.dart; Matt, 2026-10-31). Absent, neither is shown.
  final TicketWorkOptions? work;
  /// Its planning (lib/core/query/planning.dart; Matt, 2026-10-31): its cycle and the cycles it could move to, how
  /// long it has sat, an epic's progress, the milestones. Absent, its Cycle and Milestone rows are the words written.
  final TicketPlanning? Function()? planning;

  /// Its watchers, its history, its possible duplicates and Merge into… (ticket_follow.dart; Matt, 2026-10-31). Absent,
  /// none of them are shown.
  final TicketFollow? follow;
}

/// A property's name, as the panel says it (lib/core/properties.dart `ticketProperties`).
String labelOf(String key) {
  for (final property in ticketProperties) {
    if (property.key == key) return property.label;
  }
  return key;
}

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key, required this.look, required this.front, required this.options, required this.editable, required this.write, required this.openLines, required this.today, this.locale, this.dayPicker, this.simple});

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

  /// The app's calendar, which a tap on a day asks (the page's `<input type="date">` and its `showPicker`).
  final DayPicker? dayPicker;

  /// Simple mode (GHST-103), whose advanced rows wait behind More; the preference where unsaid.
  final bool? simple;

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

  /// A day's chip pressed: the phone's calendar at the chip, and what is picked written (`DayValue`'s date field,
  /// `showPicker` on its click, `onChange` its write). With no calendar to ask, the day's sheet.
  void _pickDay(BuildContext chip, String key, String? day) {
    final picker = widget.dayPicker;
    if (picker == null) return _pick(key);
    fireMotor(HapticKind.selection);
    final box = chip.findRenderObject();
    final at = box is RenderBox && box.attached ? box.localToGlobal(box.size.center(Offset.zero)) : MediaQuery.sizeOf(context).center(Offset.zero);
    final write = widget.write;
    picker(at, day != null && isIsoDay(day) ? day : null).then<void>((picked) {
      if (picked != null && isIsoDay(picked) && picked != day) write(key, picked);
    }, onError: (Object _) {});
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
        // The mark keeps its size (`flex: none`) and the words are cut; in no room at all the chip is drawn in what
        // there is, where a Row said its mark did not fit. Cut, with no ellipsis: the chip is a flex row, whose
        // words are an item of their own that the chip's `text-overflow` does not reach (the page's "Fri, O" where
        // this drew "Fri…").
        child: CssRow(
          gap: look.space(2),
          shrinkWrap: true,
          children: <Widget>[
            if (mark != null) CssItem(shrink: 0, child: mark),
            CssItem(least: 0, child: Part('chipWords', child: ClipRect(child: PageWords(text, look.sans(look.em, color: color), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.clip)))),
          ],
        ),
      ),
    );
    return _tap(label: property == null ? text : '$property: $text. Change it', onTap: onPress, child: chip);
  }

  /// A value's row of pieces, its first stepped out by its own padding (`margin-inline-start` of `-space-2`).
  ///
  /// One piece is the page's chip in its value: no wider than the column (`max-inline-size: 100%`), stepped out.
  /// Several are a `.day`, a flex row as wide as the column: its chip gives way and is cut (`overflow: hidden`, so
  /// its least is nothing) while the cross after it keeps its size, and the chip's negative margin is room it has
  /// besides (on the Fold's narrowest pane a day of 84px is 50.5 beside its cross in a column of 67). A Row gave
  /// the chip all the room and the cross 6.5px of it, which it overflowed by 5.5.
  Widget _stepped(List<Widget> pieces, {double gap = 0}) {
    if (pieces.length == 1) {
      return Transform.translate(
        offset: Offset(-look.space(2), 0),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Flexible(child: pieces.single)]),
      );
    }
    return CssRow(
      gap: gap,
      shrinkWrap: true,
      children: <Widget>[
        CssItem(least: 0, before: -look.space(2), child: pieces.first),
        for (final piece in pieces.skip(1)) CssItem(shrink: 0, child: piece),
      ],
    );
  }

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
        child: CssRow(
          gap: look.space(1),
          shrinkWrap: true,
          children: <Widget>[
            CssItem(shrink: 0, child: AppIcon(icon, size: size, color: look.ink3)),
            if (words != null) CssItem(shrink: 0, child: PageWords(words, look.sans(look.em, color: look.ink3), line: look.line, softWrap: false)),
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
        if (options?.planning == null) {
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
        }
        // Where the host draws its planning, a ticket's priority is its coloured chip (Matt, 2026-10-31: urgent, high,
        // medium, low; queries/plan_marks.dart), where the page drew the kit's chevrons beside its name.
        if (priority == null) return _stepped(<Widget>[_chip('Empty', empty: true, property: 'Priority', onPress: pick('priority'))]);
        final label = ticketPriorityLabel(priority.name);
        return _stepped(<Widget>[
          _tap(
            label: 'Priority: $label. Change it',
            onTap: pick('priority'),
            child: Container(
              constraints: BoxConstraints(minHeight: layoutUnitFloor(1.9 * look.em)),
              padding: EdgeInsets.symmetric(horizontal: look.space(2)),
              alignment: Alignment.centerLeft,
              child: PriorityChip(look: look, name: priority.name, size: look.em),
            ),
          ),
        ]);
      case 'cycle':
        final planning = options?.planning?.call();
        final cycle = planning?.cycle;
        final written = linkTargets(_raw('cycle')).firstOrNull;
        final said = cycle != null ? cycleChipWords(cycle, planning?.current) : (written ?? 'Empty');
        final days = cycle == null ? '' : cycleDaysWords(cycle);
        return _stepped(<Widget>[_chip(days.isEmpty ? said : '$said · $days', mark: Part('cycleMark', child: AppIcon(Lucide.refreshCw, size: 13, strokeWidth: 2.2, color: look.ink3)), empty: cycle == null && written == null, property: 'Cycle', onPress: planning == null ? null : pick('cycle'))]);
      case 'milestone':
        final planning = options?.planning?.call();
        final own = linkTargets(_raw('milestone')).firstOrNull;
        final shown = own ?? planning?.milestone;
        final day = planning?.milestoneDay;
        final said = shown == null ? 'Empty' : (day == null ? shown : '$shown · ${dayLabel(day, widget.today, widget.locale)}');
        return _stepped(<Widget>[_chip(own == null && shown != null ? '$said (its epic’s)' : said, mark: shown == null ? null : Part('milestoneMark', child: AppIcon(Lucide.flag, size: 13, strokeWidth: 2.2, color: look.ink3)), empty: shown == null, property: 'Milestone', onPress: planning == null ? null : pick('milestone'))]);
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
          Builder(builder: (chip) => _chip(said, empty: empty, due: state, property: label, onPress: () => _pickDay(chip, key, day), tight: empty)),
          // `<X size={12} />`
          if (!empty) _round('clear', Lucide.x, 12, label: 'Take ${label.toLowerCase()} off', onTap: () => widget.write(key, null)),
        ]);
      case 'estimate' || 'labels':
        final value = key == 'estimate' ? _raw('estimate') : propertyList(_raw('labels')).join(', ');
        final label = labelOf(key);
        if (!editable) return _stepped(<Widget>[_chip(value.isEmpty ? 'Empty' : value, empty: value.isEmpty)]);
        return TypedField(
          key: ValueKey<String>('typed:$key'),
          look: look,
          label: label,
          value: value,
          number: key == 'estimate',
          onCommit: (typed) => widget.write(key, key == 'estimate' ? (typed.isEmpty ? null : typed) : propertyList(typed)),
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
        return StatusSheet(look: look, value: ticket.status, statuses: statuses, onClose: close, onPick: (value) => unawaited(_writeStatus(ticket, value, statuses)));
      case 'sub-ticket':
        return SubTicketSheet(onClose: close, onAdd: (title) => options.addSubTicket?.call(title), similar: options.follow?.similar, onOpen: (choice) => options.open(choice.key ?? choice.title));
      case 'priority' when options.planning == null:
        return FieldPicker(pick: PriorityPick(value: ticket.priority), label: 'Priority', record: record, onClose: close, onPick: (value) => widget.write('priority', value));
      case 'priority':
        return TicketPrioritySheet(look: look, value: ticket.priority, record: record.isEmpty ? null : record, onClose: close, onPick: (written) => widget.write('priority', written));
      case 'cycle':
        final planning = options.planning?.call();
        if (planning == null) return null;
        return CycleSheet(planning: planning, onClose: close, onPick: (written) => widget.write('cycle', written));
      case 'milestone':
        final planning = options.planning?.call();
        if (planning == null) return null;
        return MilestoneSheet(planning: planning, own: linkTargets(_raw('milestone')).firstOrNull, onClose: close, onPick: (written) => widget.write('milestone', written));
      case 'assignee':
        return FieldPicker(pick: PersonPick(value: ticket.assignee, people: options.people()), label: 'Assignee', record: record, onClose: close, onPick: (value) => widget.write('assignee', value));
      case 'due' || 'start':
        final day = key == 'due' ? ticket.due : ticket.start;
        return FieldPicker(pick: DayPick(value: day, today: widget.today), label: labelOf(key), record: record, dayPicker: widget.dayPicker, onClose: close, onPick: (value) => widget.write(key, value));
      default:
        return TicketsSheet(what: key, ticket: ticket, options: options, write: widget.write, onClose: close);
    }
  }

  /// Its sub-tickets: a bar of how many are done, each one a tap away, and Add sub-ticket (Matt, 2026-10-30, of a
  /// list of plain-Markdown features: "add all 12"). Under the rows, ruled off as the foot is.
  Widget _subTickets(List<TicketChoice> children, {required bool adds, EpicProgress? epic}) {
    final done = children.where((child) => child.category == StatusCategory.done).length;
    // An epic's bar is by its tickets' points where they have them (lib/core/planning/planning.dart).
    final fraction = epic != null && !epic.isEmpty ? epic.fraction : (children.isEmpty ? 0.0 : done / children.length);
    final heading = epic != null ? 'In this epic' : 'Sub-tickets';
    final words = epic != null && !epic.isEmpty ? epic.words : '$done of ${children.length} done';
    final options = widget.options;
    return Padding(
      padding: EdgeInsets.only(top: look.space(1), bottom: look.space(1)),
      child: Part(
        'subTickets',
        child: Container(
          padding: EdgeInsets.only(top: look.space(2)),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: look.rule))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                container: true,
                label: '$heading, $words',
                excludeSemantics: true,
                child: Row(
                  children: <Widget>[
                    Expanded(child: PageWords(heading, look.sans(look.em, color: look.ink3), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Part('progressWords', child: PageWords(words, look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false)),
                  ],
                ),
              ),
              SizedBox(height: look.space(1)),
              Part('progress', child: TicketProgressBar(look: look, fraction: fraction)),
              SizedBox(height: look.space(2)),
              LayoutBuilder(
                builder: (context, constraints) => CssWrap(
                  gap: look.space(1),
                  rowGap: look.space(1),
                  align: CssAlign.center,
                  children: <Widget>[
                    for (final child in children) _link(child, waiting: false, onOpen: options == null ? null : () => options.open(child.key ?? child.title), room: constraints.maxWidth),
                    if (adds) _round('addSub', Lucide.plus, 13, label: 'Add sub-ticket', words: 'Add', wide: true, onTap: () => _pick('sub-ticket')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A status picked: written, unless it is a done one while the ticket still waits on another, which asks first
  /// (Matt, 2026-10-30: a blocked ticket "can't be moved to done without a confirmation").
  Future<void> _writeStatus(Ticket ticket, String status, List<String> statuses) async {
    final write = widget.write;
    final options = widget.options;
    final waits = options == null ? <Wait<TicketChoice>>[] : waitingOn<TicketChoice>(ticket, options.find);
    if (statusCategory(status, statuses) == StatusCategory.done && waits.isNotEmpty) {
      final named = [for (final wait in waits) wait.found.key ?? '“${wait.found.title}”'];
      final list = named.length == 1 ? named.single : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
      final yes = await askFirst(
        context,
        FirstAsk(title: 'Move ${ticket.id ?? 'it'} to $status?', note: 'It still waits on $list, which ${named.length == 1 ? 'isn’t' : 'aren’t'} done.', yes: 'Move it anyway'),
      );
      if (!yes) return;
    }
    write('status', status);
  }

  /// The widest single letter of [text]: what words that break anywhere come to at their narrowest.
  static double _widestGlyph(String text, TextStyle style) {
    var widest = 0.0;
    for (final rune in text.runes.toSet()) {
      final painter = TextPainter(text: TextSpan(text: String.fromCharCode(rune), style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  static double _wide(String text, TextStyle style) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling, maxLines: 1)..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The least the panel is laid out at, its gutters with it: the page's own, which is its narrowest content's. A
  /// pane narrower than that cuts it, as the page's does: between a docked sidebar and a docked aside on the Fold
  /// the note is 164px wide and the Example project's third ticket is a panel of 196.15 (measured on the page,
  /// 2026-10-09), its right edge under the aside.
  ///
  /// What the page's narrowest comes to, part by part (TicketPanel.module.css, with the editor's `overflow-wrap:
  /// anywhere`, under which words that may wrap are one letter at their narrowest):
  /// - the rows: the names' column and the gap, the values' `minmax(0, 1fr)` being nothing when the grid is asked
  ///   how narrow it can be (the third ticket's rows: 75.18 and 14.24);
  /// - what it waits on: a ticket's key at one letter, the gap, and its title whole, which is `white-space:
  ///   nowrap` (EX-2's 8.9, 4.75 and 124, in a box padded by 9.49 each side: the 156.65 that made the panel 196);
  /// - the head: the mark, the key at one letter, the button to its lines, and the offer of a key;
  /// - the foot: the keys a ticket does not have, whole (`nowrap`), or the plus and a letter.
  double _least(List<String> rows, double names, List<({String target, TicketChoice found})> waits, {required double line, required String? id, required String? offered, required List<String> hidden, required List<String> others}) {
    final editable = widget.editable;
    var least = names + look.space(3);
    for (final wait in waits) {
      final key = wait.found.key, title = wait.found.title;
      final first = _widestGlyph(key ?? title, look.sans(look.em, weight: 'semibold'));
      final on = key != null && title.isNotEmpty ? first + look.space(1) + _wide(title, look.sans(look.em)) : first;
      least = math.max(least, on + 2 * look.space(2));
    }
    var head = 14 + look.space(2) + _widestGlyph(id != null && id.isNotEmpty ? id : 'Ticket', look.mono(look.em, weight: 'semibold', tracking: 0.02 * look.em));
    if (offered != null) head += look.space(2) + 2 * look.space(2) + 2 + _widestGlyph('Give it $offered', look.sans(look.xs));
    if (editable) head += look.space(2) + 14 + 2 * look.space(1);
    least = math.max(least, head);
    if (others.isNotEmpty && editable) least = math.max(least, _wide(others.join(' · '), look.mono(look.xs)));
    if (hidden.isNotEmpty) least = math.max(least, 13 + look.space(1) + _widestGlyph(hidden.map(labelOf).join(', '), look.sans(look.xs)));
    // `.panel { padding-inline: var(--glacier-space-4); border: 1px }` and `.cm-ticketPanel { padding-inline:
    // var(--app-gutter) }`.
    return least + 2 * look.space(4) + 2 * line + 2 * look.bleed;
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final statuses = options?.statuses() ?? defaultStatuses;
    final ticket = ticketOf(widget.front, statuses);
    if (ticket == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final (:panel, :least) = _panel(context, ticket, statuses);
        if (!box.hasBoundedWidth || box.maxWidth >= least) return panel;
        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(width: least, child: panel),
          ),
        );
      },
    );
  }

  ({Widget panel, double least}) _panel(BuildContext context, Ticket ticket, List<String> statuses) {
    final options = widget.options;
    final editable = widget.editable;
    final simple = widget.simple ?? preferences.value.simple;
    final planned = options?.planning != null;
    final rows = panelRows(widget.front, _more, simple, planned);
    final hidden = editable && !_more ? hiddenRows(widget.front, simple, planned) : const <String>[];
    final planning = options?.planning?.call();
    final others = otherKeys(widget.front);
    final waits = <({String target, TicketChoice found})>[
      if (options != null)
        for (final wait in waitingOn<TicketChoice>(ticket, options.find)) (target: wait.target, found: wait.found),
    ];
    // Its sub-tickets (lib/book/ticket_links.dart): how many are done, and Add sub-ticket.
    final children = options?.subTickets?.call() ?? const <TicketChoice>[];
    final adds = editable && options?.addSubTicket != null;
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

    // `border: 1px`, which a phone's browser draws in whole device pixels (two of them at 2.625, 0.76px).
    final line = snapBorder(context, 1);
    final least = _least(rows, names, waits, line: line, id: id, offered: offered, hidden: hidden, others: others);
    final panel = Padding(
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
            decoration: BoxDecoration(color: look.paper2, border: Border.all(color: look.rule, width: line), borderRadius: BorderRadius.circular(look.cardRadius)),
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
                        // An epic says so, and a ticket left in its status too long says how long (planning.dart).
                        if (ticket.epic) CssItem(shrink: 0, child: Part('epic', child: PageWords('Epic', look.sans(look.xs, weight: 'semibold', color: activityCalm(look.t) ? look.ink2 : look.t.color('glacier-purple-11'), tracking: 0.02 * look.xs), line: look.lineXs, softWrap: false))),
                        if (planning?.staleDays case final days?) CssItem(least: 0, child: StaleMark(look: look, days: days)),
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
                                      // The key gives way with its title, each in proportion to its width, and
                                      // breaks where it must, as the note's words do (`overflow-wrap: anywhere`,
                                      // the editor's): "EX-" over "2" in a box too narrow for both.
                                      CssItem(
                                        least: _widestGlyph(wait.found.key ?? wait.found.title, look.sans(look.em, weight: 'semibold')),
                                        child: PageWords(wait.found.key ?? wait.found.title, look.sans(look.em, weight: 'semibold', color: amber), line: look.line),
                                      ),
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
                if (options?.work case final work?) TicketWork(look: look, front: widget.front, editable: editable, options: work, names: names),
                if (children.isNotEmpty) _subTickets(children, adds: adds, epic: ticket.epic ? planning?.progress : null),
                // Who watches it, its history, its possible duplicates and Merge into… (ticket_follow.dart).
                if (options?.follow case final follow?)
                  TicketFollowPart(look: look, front: widget.front, follow: follow, editable: editable, write: widget.write, choices: options!.choices, open: options.open, self: id),
                if (hidden.isNotEmpty || (others.isNotEmpty && editable) || (adds && children.isEmpty))
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
                            // Add sub-ticket, where the ticket has none yet: a quiet word at the foot, as More's is.
                            if (adds && children.isEmpty)
                              _tap(
                                label: 'Add sub-ticket',
                                onTap: () => _pick('sub-ticket'),
                                child: Part(
                                  'addSub',
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: look.space(1)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        AppIcon(Lucide.listTree, size: 13, color: look.ink3),
                                        SizedBox(width: look.space(1)),
                                        Flexible(child: PageWords('Sub-ticket', look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1)),
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
    return (panel: panel, least: least);
  }
}

/// The sheet a status is picked from (the page's `Picker`, `what === 'status'`): the workflow and no more, each
/// status with its category's dot, the one the ticket has ticked.
class StatusSheet extends StatelessWidget {
  const StatusSheet({super.key, required this.look, required this.value, required this.statuses, required this.onPick, required this.onClose});

  final QueryLook look;
  final String? value;
  final List<String> statuses;
  final void Function(String status) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final has = value?.toLowerCase();
    return Sheet(
      label: 'Status',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text('Status'),
        SheetGroup(
          children: <Widget>[
            for (final status in statuses)
              SheetRow(
                key: ValueKey<String>('status:$status'),
                icon: StatusDot(look: look, category: statusCategory(status, statuses)),
                label: status,
                chosen: has != null && has.isNotEmpty && has == status.toLowerCase(),
                onPress: () {
                  // The callbacks as they are now: closing may take this sheet down before the choice is written.
                  final pick = onPick;
                  onClose();
                  pick(status);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// `.dot`: a status's colour, as a dot (`TodoDot`, `DoingDot`, `DoneDot`).
// .dot { flex: none; inline-size: 0.6em; block-size: 0.6em; border-radius: 50%; background: var(--app-ink-4) }
// .dot[data-category='doing'] { background: var(--glacier-blue-9) }  [data-category='done'] { … green-9 }
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.look, required this.category});

  final QueryLook look;
  final StatusCategory category;

  @override
  Widget build(BuildContext context) {
    final size = layoutUnitFloor(0.6 * look.em);
    final color = switch (category) {
      StatusCategory.doing => look.t.color('glacier-blue-9'),
      StatusCategory.done => look.t.color('glacier-green-9'),
      StatusCategory.todo => look.ink4,
    };
    return Part('dot', child: Container(width: size, height: size, decoration: ShapeDecoration(color: color, shape: const CircleBorder())));
  }
}

/// A value typed in place, a number or a list with commas, written when the field is left or the keyboard's done
/// key is pressed, and nothing for a field left as it was; Escape puts back what it had (`TypedValue`).
///
/// Until it is tapped it is the page's words on the page's box (`.typed`), drawn as every other value's are. The
/// tap puts the field in their place, focused, with the keyboard: a field of its own inside the editor, hung from
/// the page's focus scope and not from the editor's, for the reasons boards/composer.dart gives.
class TypedField extends StatefulWidget {
  const TypedField({super.key, required this.look, required this.label, required this.value, required this.number, required this.onCommit});

  final QueryLook look;
  final String label;
  final String value;

  /// `inputMode="decimal"`: an estimate's keyboard.
  final bool number;
  final void Function(String typed) onCommit;

  @override
  State<TypedField> createState() => TypedFieldState();
}

class TypedFieldState extends State<TypedField> implements TextSelectionGestureDetectorBuilderDelegate {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'A ticket\'s value');
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);

  /// The page's `draft !== null`: the field is being typed in.
  bool _typing = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_focusMoved);
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  /// The tap: the field in the words' place, with what it has to be changed, and the keyboard.
  void _begin() {
    if (_typing) return;
    fireMotor(HapticKind.selection);
    controller.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    setState(() => _typing = true);
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _typing) editableTextKey.currentState?.requestKeyboard();
    });
  }

  /// `onBlur={commit}`: what was typed is written where it is not what was there, and the words are back.
  void _focusMoved() {
    if (focusNode.hasFocus || !_typing) return;
    final typed = controller.text.trim();
    if (mounted) setState(() => _typing = false);
    if (typed != widget.value.trim()) widget.onCommit(typed);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // `setDraft(null)` and a blur: left as it was.
      setState(() => _typing = false);
      focusNode.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final value = widget.value;
    final style = look.sans(look.em, color: look.ink);
    // .typed { inline-size: 100%; min-block-size: 1.9em; margin: 0 0 0 calc(var(--glacier-space-2) * -1);
    //   padding: 0 var(--glacier-space-2); border-radius: var(--glacier-radius-md) }
    // .typed::placeholder { color: var(--app-ink-4) }
    Widget box(Widget child) => Transform.translate(
          offset: Offset(-look.space(2), 0),
          child: Part(
            'typed',
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: layoutUnitFloor(1.9 * look.em)),
              padding: EdgeInsets.symmetric(horizontal: look.space(2)),
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
    if (!_typing) {
      return Semantics(
        container: true,
        textField: true,
        label: widget.label,
        value: value,
        hint: value.isEmpty ? 'Empty' : null,
        onTap: _begin,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _begin,
          child: box(PageWords(value.isEmpty ? 'Empty' : value, look.sans(look.em, color: value.isEmpty ? look.ink4 : look.ink), line: look.line, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ),
      );
    }
    final t = look.t;
    final field = EditableText(
      key: editableTextKey,
      controller: controller,
      focusNode: focusNode,
      style: style.copyWith(height: look.line / look.em, leadingDistribution: TextLeadingDistribution.even),
      cursorColor: look.ink,
      cursorWidth: 1,
      backgroundCursorColor: look.ink3,
      selectionColor: t.color('glacier-selection'),
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      // `inputMode`, `enterKeyHint="done"`, `autoComplete="off"`
      keyboardType: widget.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: null,
      maxLines: 1,
      // The done key leaves the field, and leaving it writes.
      onEditingComplete: focusNode.unfocus,
      onTapOutside: (_) => focusNode.unfocus(),
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
      textScaler: TextScaler.noScaling,
    );
    return Semantics(
      container: true,
      textField: true,
      label: widget.label,
      child: box(
        // Hung from the page's focus scope, not from the editor the panel is built in (boards/composer.dart).
        Focus(
          parentNode: FocusScope.of(context),
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _key,
          child: _gestures.buildGestureDetector(
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                if (controller.text.isEmpty) IgnorePointer(child: PageWords('Empty', look.sans(look.em, color: look.ink4), line: look.line, softWrap: false, maxLines: 1)),
                Actions(actions: ownTextKeys, child: field),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

  /// Why the last pick was not written: a ring (Matt, 2026-10-30: "Cycles are refused with a clear message").
  String? _refused;

  /// [value] written for [key], unless it would make a ring, which is said and not written.
  bool _wrote(String key, Object? value) {
    final problem = widget.options.problem?.call(key, value);
    if (problem != null) {
      setState(() => _refused = problem);
      return false;
    }
    if (_refused != null) setState(() => _refused = null);
    widget.write(key, value);
    return true;
  }

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
      final problem = widget.options.problem?.call(key, value);
      if (problem != null) return setState(() => _refused = problem);
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
      _wrote('blocked-by', linksValue(links));
    }

    final label = labelOf(widget.what);
    return Sheet(
      label: label,
      onClose: widget.onClose,
      children: <Widget>[
        SheetTitle.text(label),
        SheetField(label: 'Find a ticket', value: _typed, placeholder: 'Its key or its title', onChange: (text) => setState(() => _typed = text)),
        if (_refused != null) SheetNote(_refused!),
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

/// A sub-ticket's progress: a thin track, filled in the done colour as far as its sub-tickets are done.
class TicketProgressBar extends StatelessWidget {
  const TicketProgressBar({super.key, required this.look, required this.fraction, this.height = 4});

  final QueryLook look;
  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: look.t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)')),
            FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fraction.clamp(0.0, 1.0), child: ColoredBox(color: look.t.color('glacier-green-9'))),
          ],
        ),
      ),
    );
  }
}

/// Add sub-ticket's sheet: its title typed, and Add, which makes it with this ticket as its parent.
class SubTicketSheet extends StatefulWidget {
  const SubTicketSheet({super.key, required this.onAdd, required this.onClose, this.similar, this.onOpen});

  final void Function(String title) onAdd;
  final VoidCallback onClose;

  /// The tickets the title typed may duplicate, shown under it (ticket_follow.dart [DuplicateHints]).
  final List<LikelyDuplicate> Function(String title)? similar;
  final void Function(TicketChoice ticket)? onOpen;

  @override
  State<SubTicketSheet> createState() => _SubTicketSheetState();
}

class _SubTicketSheetState extends State<SubTicketSheet> {
  String _title = '';

  void _add() {
    final title = _title.trim();
    if (title.isEmpty) return;
    final add = widget.onAdd;
    widget.onClose();
    add(title);
  }

  @override
  Widget build(BuildContext context) {
    return Sheet(
      key: const ValueKey('sub-ticket-sheet'),
      label: 'Add sub-ticket',
      onClose: widget.onClose,
      children: <Widget>[
        SheetTitle.text('Add sub-ticket'),
        SheetGroup(
          children: <Widget>[
            SheetField(label: 'Title', value: _title, autoFocus: true, placeholder: 'What it is', onChange: (text) => setState(() => _title = text), onSubmitted: (_) => _add()),
            SheetRow(key: const ValueKey('sub-ticket-add'), label: 'Add', hint: 'A ticket of its own, under this one.', disabled: _title.trim().isEmpty, onPress: _add),
          ],
        ),
        // Likely duplicates of what is typed, a tap away (Matt, 2026-10-31).
        if (widget.similar != null && _title.trim().length > 2)
          DuplicateHints(
            likely: widget.similar!(_title),
            onOpen: widget.onOpen == null
                ? null
                : (ticket) {
                    final open = widget.onOpen!;
                    widget.onClose();
                    open(ticket);
                  },
          ),
      ],
    );
  }
}
