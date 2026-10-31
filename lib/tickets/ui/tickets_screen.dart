/// My tickets and Triage, a page of their own (Matt, 2026-10-31): the tickets assigned to you across every notebook
/// and team, by when they are due (lib/tickets/inbox.dart), and the new tickets nobody has looked at, worked through
/// from the keyboard or by swipes (lib/tickets/triage.dart). A place as the Tags page is (lib/shell/screen.dart
/// [ScreenTickets]): the tab row over it and the sidebar beside it on a wide window, its way out home. Reached from
/// the sidebar's My tickets row, the palette's "My tickets" and "Triage", and the same lines in any ```query fence.
///
/// **My tickets.** Overdue, Today, This week, Later and No date, each row its status, key, title, labels, where it is
/// (the team and the notebook) and when it is due. The status mark is a button: the workflow's statuses in a sheet,
/// one written. A row opens its ticket.
///
/// **Triage.** Every ticket waiting, the newest first, across all notebooks or one (the words over the list). One
/// row is the current one: J and K move it, A assigns, P sets the priority, L the labels, S the status, D closes it
/// as a duplicate of a ticket picked, E opens it, and T is done triaging, which takes it out of the list with an
/// Undo. On a phone a swipe right is done and a swipe left offers the same actions; the keys' line is not drawn.
///
/// Simple mode (GHST-103): My tickets is as it is; Triage is there, but its keys go unsaid.
///
/// Nothing here writes a note itself: every change is the screen's [TicketsScreen.write], the root's one writer for
/// another note's words, so a team's note goes through its sync as every edit does.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../book/tickets.dart' show TicketChoice;
import '../../core/properties.dart' show StatusCategory, withProperty;
import '../../core/query/query.dart' show QueryLibrary;
import '../../editor/fields/field_picker.dart';
import '../../editor/fields/field_picks.dart';
import '../../editor/items/field_chips.dart' show dayLabel, priorityIcon;
import '../../home/home_text.dart' show pageText, tabular;
import '../../notes/swipe_row.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../../shell/header_pane.dart';
import '../../shell/page_dock.dart';
import '../inbox.dart';
import '../labels.dart';
import '../triage.dart';
import 'label_chips.dart';
import 'label_picker.dart';

/// Which of the two pages is up.
enum TicketsPage { mine, triage }

/// A change to a note's words, as the root's writer takes it: null, or the same words, for nothing to write.
typedef TicketChange = String? Function(String body);

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({
    super.key,
    required this.page,
    required this.library,
    required this.today,
    required this.onPage,
    required this.onBack,
    required this.onOpen,
    required this.write,
    this.teamOf,
    this.coloursOf,
    this.onColour,
    this.people,
    this.labels,
    this.choices,
    this.simple = false,
    this.dock,
  });

  final TicketsPage page;

  /// The library as a query reads it (lib/core/query/records.dart `libraryOf`).
  final QueryLibrary library;
  final String today;
  final ValueChanged<TicketsPage> onPage;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  /// The root's writer: the note as the store has it, changed, and saved.
  final Future<void> Function(String noteId, TicketChange change) write;

  /// The organization a team's note is among, by name; null for your own.
  final String? Function(String noteId)? teamOf;

  /// The colours a ticket's notebook gives its labels.
  final Map<String, String> Function(String noteId)? coloursOf;

  /// A label's colour kept in the ticket's notebook; null where it is in none.
  final void Function(String noteId, String label, String? hue)? onColour;

  /// The people the library names, for A; the labels it uses, for L; every ticket, for D.
  final List<String> Function()? people;
  final List<String> Function()? labels;
  final List<TicketChoice> Function()? choices;

  /// Simple mode: the triage keys go unsaid.
  final bool simple;
  final PageDockSeam? dock;

  @override
  State<TicketsScreen> createState() => TicketsScreenState();
}

/// What sheet is up, and for which ticket.
enum _Sheet { status, assignee, priority, labels, duplicate, actions }

class TicketsScreenState extends State<TicketsScreen> {
  final FocusNode _keys = FocusNode(debugLabel: 'Triage keys');
  final Map<String, GlobalKey> _rowKeys = {};

  /// The triage list's current ticket, by note id, and where it stood.
  String? _current;
  int _at = 0;

  /// The notebook the triage list is narrowed to, by title; null for all.
  String? _notebook;

  ({_Sheet sheet, TicketLine line})? _sheet;

  List<TriageTicket>? _triage;
  QueryLibrary? _triageOf;
  String? _triageIn;

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  List<TriageTicket> get triage {
    if (_triage == null || !identical(_triageOf, widget.library) || _triageIn != _notebook) {
      _triageOf = widget.library;
      _triageIn = _notebook;
      _triage = triageList(widget.library, widget.today, notebook: _notebook, teamOf: widget.teamOf);
    }
    return _triage!;
  }

  /// The current ticket's place in the list: where it is, or where it was where it has gone.
  int _currentIndex(List<TriageTicket> list) {
    if (list.isEmpty) return 0;
    final at = list.indexWhere((each) => each.line.noteId == _current);
    return at >= 0 ? at : math.min(_at, list.length - 1);
  }

  Map<String, String> _colours(String noteId) => widget.coloursOf?.call(noteId) ?? const {};

  void _say(String words, {VoidCallback? undo}) {
    GlacierToastController? toasts;
    try {
      toasts = GlacierToast.of(context);
    } on FlutterError {
      toasts = null;
    }
    toasts?.toast(message: Text(words), action: undo == null ? null : GlacierToastAction(label: 'Undo', onPress: undo));
  }

  /// [change] written to [line]'s note, with an Undo where [undoable]: the words before put back while the note
  /// still says what the change left.
  Future<void> _change(TicketLine line, TicketChange change, {String? said, bool undoable = false}) async {
    String? before, after;
    await widget.write(line.noteId, (body) {
      before = body;
      return after = change(body);
    });
    if (said == null || !mounted) return;
    _say(
      said,
      undo: !undoable
          ? null
          : () {
              fireMotor(HapticKind.selection);
              final was = before, wrote = after;
              if (was == null || wrote == null) return;
              unawaited(widget.write(line.noteId, (body) => body == wrote ? was : null));
            },
    );
  }

  String _name(TicketLine line) => line.key != null ? '${line.key} · ${line.title}' : line.title;

  void _open(_Sheet sheet, TicketLine line) {
    fireMotor(HapticKind.selection);
    setState(() => _sheet = (sheet: sheet, line: line));
  }

  void _closeSheet() {
    setState(() => _sheet = null);
    if (widget.page == TicketsPage.triage) _keys.requestFocus();
  }

  void _done(TicketLine line) {
    fireMotor(HapticKind.selection);
    unawaited(_change(line, (body) => triagedBody(body, widget.today, line.workflow), said: 'Triaged ${line.key ?? line.title}', undoable: true));
  }

  /// What a key or a swipe asks of [line].
  void act(TriageAction action, TicketLine line) {
    switch (action) {
      case TriageAction.next || TriageAction.previous:
        break;
      case TriageAction.assign:
        _open(_Sheet.assignee, line);
      case TriageAction.priority:
        _open(_Sheet.priority, line);
      case TriageAction.labels:
        _open(_Sheet.labels, line);
      case TriageAction.status:
        _open(_Sheet.status, line);
      case TriageAction.duplicate:
        _open(_Sheet.duplicate, line);
      case TriageAction.open:
        widget.onOpen(line.noteId);
      case TriageAction.done:
        _done(line);
      case TriageAction.actions:
        _open(_Sheet.actions, line);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (widget.page != TicketsPage.triage || _sheet != null) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) return KeyEventResult.ignored;
    final action = triageKey(event.logicalKey.keyLabel);
    if (action == null) return KeyEventResult.ignored;
    final list = triage;
    if (list.isEmpty) return KeyEventResult.handled;
    final at = _currentIndex(list);
    if (action == TriageAction.next || action == TriageAction.previous) {
      final next = triageMove(action, at, list.length);
      setState(() {
        _at = next;
        _current = list[next].line.noteId;
      });
      _reveal(list[next].line.noteId, down: action == TriageAction.next);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    act(action, list[at].line);
    return KeyEventResult.handled;
  }

  /// The current row scrolled into view: its foot for a move down, its head for a move up.
  void _reveal(String noteId, {required bool down}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rowKeys[noteId]?.currentContext;
      if (row == null || !row.mounted) return;
      final policy = down ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart;
      unawaited(Scrollable.ensureVisible(row, alignmentPolicy: policy, duration: const Duration(milliseconds: 120)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final safeTop = t.len('app-safe-top');
    final hairline = t.len('glacier-hairline');
    final bar = safeTop + t.space(2) * 2 + t.space(8) + hairline * 2;
    final top = bar.roundToDouble() + t.space(4);
    final dock = widget.dock;
    final foot = t.len('app-safe-bottom') + (dock == null ? t.space(10) : math.max(t.space(10), pageDockRoom(t, dock.rings)));
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final triaging = widget.page == TicketsPage.triage;
    final slivers = triaging ? _triageSlivers(t, wide) : _mineSlivers(t);
    final page = CustomScrollView(
      key: ValueKey('tickets-scroll-${widget.page.name}'),
      slivers: [SliverPadding(padding: EdgeInsetsDirectional.fromSTEB(gutterStart, top, gutterEnd, foot), sliver: SliverMainAxisGroup(slivers: slivers))],
    );
    return Focus(
      focusNode: _keys,
      autofocus: triaging,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: dock == null ? page : PageDockFrame(seam: dock, child: page)),
              HeaderPane(
                child: Padding(
                  key: const ValueKey('tickets-bar'),
                  padding: EdgeInsetsDirectional.fromSTEB(gutterStart - t.space(2), t.space(2), gutterEnd, t.space(2)),
                  child: Row(
                    spacing: t.space(2),
                    children: [
                      GlacierPressable(
                        key: const ValueKey('tickets-back'),
                        onPressed: widget.onBack,
                        semanticLabel: 'Back to home',
                        builder: (context, state) => GlacierFocusRing(
                          visible: state.focused,
                          child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(triaging ? 'Triage' : 'My tickets', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                        ),
                      ),
                      _Word(key: const ValueKey('tickets-tab-mine'), label: 'Mine', on: !triaging, onPressed: () => widget.onPage(TicketsPage.mine)),
                      _Word(key: const ValueKey('tickets-tab-triage'), label: 'Triage', count: triage.length, on: triaging, onPressed: () => widget.onPage(TicketsPage.triage)),
                    ],
                  ),
                ),
              ),
              if (_sheet != null) _sheetFor(_sheet!.sheet, _sheet!.line),
            ],
          ),
        ),
      ),
    );
  }

  // ---- My tickets -------------------------------------------------------------------------------------------------

  List<Widget> _mineSlivers(Tokens t) {
    final groups = myTickets(widget.library, widget.today, teamOf: widget.teamOf);
    if (groups.isEmpty) {
      return [SliverToBoxAdapter(child: _empty(t, 'Nothing assigned to you.', 'A ticket whose assignee is you is here, from every notebook and every team, by when it is due.'))];
    }
    final count = myTicketCount(groups);
    return [
      SliverToBoxAdapter(child: _tally(t, '${count.all} ${count.all == 1 ? 'ticket' : 'tickets'}${count.overdue > 0 ? ' · ${count.overdue} overdue' : ''}')),
      for (final group in groups) ...[
        SliverToBoxAdapter(child: _heading(t, group.label, group.tickets.length, key: ValueKey('inbox-group-${group.bucket.name}'), tone: group.bucket == InboxBucket.overdue ? 'glacier-red-11' : null)),
        SliverList.builder(
          itemCount: group.tickets.length,
          itemBuilder: (context, i) {
            final line = group.tickets[i];
            return TicketRowView(
              key: ValueKey('inbox-row-${line.noteId}'),
              line: line,
              today: widget.today,
              colours: _colours(line.noteId),
              first: i == 0,
              onOpen: () => widget.onOpen(line.noteId),
              onStatus: () => _open(_Sheet.status, line),
            );
          },
        ),
      ],
    ];
  }

  // ---- Triage -----------------------------------------------------------------------------------------------------

  List<Widget> _triageSlivers(Tokens t, bool wide) {
    final list = triage;
    final notebooks = triageNotebooks(widget.library);
    final at = _currentIndex(list);
    final current = list.isEmpty ? null : list[at].line.noteId;
    final hints = wide && !widget.simple;
    return [
      if (notebooks.length > 1 || _notebook != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.space(3)),
            child: Wrap(
              spacing: t.space(1),
              runSpacing: t.space(1),
              children: [
                _Word(key: const ValueKey('triage-in-all'), label: 'All notebooks', on: _notebook == null, onPressed: () => setState(() => _notebook = null)),
                for (final name in notebooks) _Word(key: ValueKey('triage-in-$name'), label: name, on: _notebook?.toLowerCase() == name.toLowerCase(), onPressed: () => setState(() => _notebook = name)),
              ],
            ),
          ),
        ),
      if (list.isEmpty)
        SliverToBoxAdapter(child: _empty(t, 'Nothing to triage.', 'New tickets wait here until someone looks at them: from a form, mail, the connector or Slack, marked new, or with nobody on them.'))
      else ...[
        SliverToBoxAdapter(child: _tally(t, '${list.length} waiting${_notebook == null ? '' : ' in $_notebook'}')),
        if (hints) SliverToBoxAdapter(child: _KeyHints(key: const ValueKey('triage-keys'))),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final each = list[i];
            final line = each.line;
            final row = TicketRowView(
              key: _rowKeys.putIfAbsent(line.noteId, () => GlobalKey(debugLabel: 'triage ${line.noteId}')),
              line: line,
              today: widget.today,
              colours: _colours(line.noteId),
              first: i == 0,
              current: line.noteId == current,
              hint: each.reason,
              onOpen: () {
                setState(() {
                  _current = line.noteId;
                  _at = i;
                });
                _keys.requestFocus();
              },
              onStatus: () => _open(_Sheet.status, line),
              onDone: () => _done(line),
            );
            return SwipeRow(
              key: ValueKey('triage-row-${line.noteId}'),
              start: const [SwipeAction(id: 'done', label: 'Triaged', icon: SwipeIcon.check, tone: SwipeTone.accent, detent: 0.22, removes: true)],
              end: const [SwipeAction(id: 'actions', label: 'Actions', icon: SwipeIcon.more, tone: SwipeTone.neutral, detent: 0.22)],
              onAction: (id) => act(triageSwipe(right: id == 'done'), line),
              child: row,
            );
          },
        ),
      ],
    ];
  }

  // ---- the sheets -------------------------------------------------------------------------------------------------

  Widget _sheetFor(_Sheet sheet, TicketLine line) {
    final record = _name(line);
    switch (sheet) {
      case _Sheet.status:
        return FieldPicker(
          pick: StatusPick(value: line.status, workflow: line.workflow),
          label: 'Status',
          record: record,
          onClose: _closeSheet,
          onPick: (value) => unawaited(_change(line, (body) => withProperty(body, 'status', value))),
        );
      case _Sheet.assignee:
        return FieldPicker(
          pick: PersonPick(value: line.assignee, people: widget.people?.call() ?? const []),
          label: 'Assignee',
          record: record,
          onClose: _closeSheet,
          onPick: (value) => unawaited(_change(line, (body) => withProperty(body, 'assignee', value))),
        );
      case _Sheet.priority:
        return FieldPicker(
          pick: PriorityPick(value: line.priority),
          label: 'Priority',
          record: record,
          onClose: _closeSheet,
          // Plain front matter, written whether or not anything else reads it yet.
          onPick: (value) => unawaited(_change(line, (body) => withProperty(body, 'priority', value))),
        );
      case _Sheet.labels:
        final onColour = widget.onColour;
        return LabelPicker(
          chosen: line.labels,
          known: widget.labels?.call() ?? const [],
          colours: _colours(line.noteId),
          record: record,
          onClose: _closeSheet,
          onToggle: (label, on) => unawaited(_change(line, (body) => on ? withLabelsChanged(body, add: [label]) : withLabelsChanged(body, remove: [label]))),
          onColour: onColour == null || line.notebook == null ? null : (label, hue) => onColour(line.noteId, label, hue),
        );
      case _Sheet.duplicate:
        final choices = [for (final choice in widget.choices?.call() ?? const <TicketChoice>[]) if (choice.key == null || choice.key != line.key) if (choice.title != line.title || choice.key != line.key) choice];
        return TicketPickSheet(
          title: 'Duplicate of',
          note: '$record is closed, and links the ticket it repeats.',
          choices: choices,
          workflow: line.workflow,
          onClose: _closeSheet,
          onPick: (choice) => unawaited(_change(line, (body) => duplicateBody(body, choice.key ?? choice.title, widget.today, line.workflow), said: 'Closed as a duplicate of ${choice.key ?? choice.title}', undoable: true)),
        );
      case _Sheet.actions:
        void then(TriageAction action) {
          setState(() => _sheet = null);
          act(action, line);
        }
        return Sheet(
          label: record,
          onClose: _closeSheet,
          children: [
            SheetTitle.text(line.title),
            if (line.key != null) SheetNote(line.place.isEmpty ? line.key! : '${line.key} · ${line.place}'),
            SheetGroup(
              children: [
                SheetRow(key: const ValueKey('triage-act-assign'), label: 'Assign', hint: line.assignee, onPress: () => then(TriageAction.assign)),
                SheetRow(key: const ValueKey('triage-act-priority'), label: 'Priority', hint: line.priority, onPress: () => then(TriageAction.priority)),
                SheetRow(key: const ValueKey('triage-act-labels'), label: 'Labels', hint: line.labels.isEmpty ? null : line.labels.join(', '), onPress: () => then(TriageAction.labels)),
                SheetRow(key: const ValueKey('triage-act-status'), label: 'Status', hint: line.status, onPress: () => then(TriageAction.status)),
                SheetRow(key: const ValueKey('triage-act-duplicate'), label: 'Close as duplicate…', onPress: () => then(TriageAction.duplicate)),
                SheetRow(key: const ValueKey('triage-act-open'), label: 'Open', onPress: () => then(TriageAction.open)),
              ],
            ),
            SheetGroup(children: [SheetRow(key: const ValueKey('triage-act-done'), label: 'Done triaging', hint: 'Takes it out of this list.', onPress: () => then(TriageAction.done))]),
          ],
        );
    }
  }

  // ---- the parts --------------------------------------------------------------------------------------------------

  Widget _tally(Tokens t, String words) => Padding(
        padding: EdgeInsets.only(bottom: t.space(3)),
        child: Text(words, key: const ValueKey('tickets-tally'), style: tabular(pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
      );

  Widget _heading(Tokens t, String label, int count, {Key? key, String? tone}) => Padding(
        key: key,
        padding: EdgeInsets.only(top: t.space(4), bottom: t.space(1)),
        child: Row(
          spacing: t.space(2),
          children: [
            Text(label.toUpperCase(), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color(tone ?? 'app-ink-3'), tracking: 0.06 * t.fontSize('xs'))),
            Text('$count', style: tabular(pageText(t, t.fontSize('xs'), color: t.color('app-ink-4')))),
          ],
        ),
      );

  Widget _empty(Tokens t, String lead, String hint) => Padding(
        padding: EdgeInsets.only(top: t.space(6)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space(1),
          children: [
            Text(lead, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
            Text(hint, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ],
        ),
      );
}

/// One ticket's row: its status (a button), its title, and under it its key, where it is, when it is due, its
/// priority and its labels; in the triage list why it waits, the current row grounded, and its Done.
class TicketRowView extends StatelessWidget {
  const TicketRowView({
    super.key,
    required this.line,
    required this.today,
    required this.onOpen,
    this.onStatus,
    this.onDone,
    this.colours = const {},
    this.first = false,
    this.current = false,
    this.hint,
  });

  final TicketLine line;
  final String today;
  final VoidCallback onOpen;
  final VoidCallback? onStatus;
  final VoidCallback? onDone;
  final Map<String, String> colours;
  final bool first;
  final bool current;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final quiet = pageText(t, xs, color: t.color('app-ink-3'));
    final done = line.category == StatusCategory.done;
    final due = line.due;
    final meta = <Widget>[
      if (line.key != null) Text(line.key!, style: t.textAt(xs, mono: true, color: t.color('app-ink-3'), tracking: 0.02 * xs)),
      if (line.place.isNotEmpty) Text(line.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
      if (due != null)
        Text(
          dayLabel(due, today),
          key: ValueKey('ticket-due-${line.noteId}'),
          style: tabular(pageText(t, xs, weight: line.overdue || due == today ? 'medium' : 'regular', color: line.overdue ? t.color('glacier-red-11') : (due == today ? t.color('glacier-amber-11') : t.color('app-ink-3')))),
        ),
      if (line.priority != null && priorityIcon[line.priority] != null)
        Semantics(label: '${line.priority} priority', child: AppIcon(priorityIcon[line.priority]!, size: xs + 2, strokeWidth: 2.4, color: t.color(line.priority == 'highest' || line.priority == 'high' ? 'glacier-red-11' : 'app-ink-3'))),
      if (hint != null) Text(hint!, style: pageText(t, xs, color: t.color('glacier-accent-11'))),
      if (LabelChips.has(line.labels, line.component)) LabelChips(labels: line.labels, colours: colours, component: line.component),
    ];
    final status = Semantics(
      button: onStatus != null,
      label: 'Status: ${line.status ?? 'none'}${onStatus != null ? '. Change it' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('ticket-status-${line.noteId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onStatus,
        child: Padding(padding: EdgeInsets.all(t.space(1)), child: StatusIcon(look: statusLook(line.status ?? '', line.workflow), size: sm + 2)),
      ),
    );
    return Semantics(
      container: true,
      selected: current,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
        decoration: BoxDecoration(
          color: current ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : t.color('glacier-bg'),
          borderRadius: current ? BorderRadius.circular(t.radius('md')) : null,
          border: first || current ? null : Border(top: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline'))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space(2),
          children: [
            status,
            Expanded(
              child: GestureDetector(
                key: ValueKey('ticket-open-${line.noteId}'),
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: t.space(1),
                  children: [
                    Text(
                      line.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: pageText(t, t.fontSize('md'), weight: 'medium', color: done ? t.color('app-ink-3') : t.color('app-ink')),
                    ),
                    if (meta.isNotEmpty) Wrap(spacing: t.space(2), runSpacing: t.space(1), crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                  ],
                ),
              ),
            ),
            if (onDone != null && current)
              GlacierPressable(
                key: ValueKey('triage-done-${line.noteId}'),
                onPressed: onDone,
                semanticLabel: 'Done triaging ${line.key ?? line.title}',
                builder: (context, state) => GlacierFocusRing(
                  visible: state.focused,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                    decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: BorderRadius.circular(t.radius('full'))),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: t.space(1), children: [AppIcon(Lucide.check, size: xs + 2, strokeWidth: 2.4, color: t.color('app-ink-2')), Text('Done', style: pageText(t, xs, weight: 'medium', color: t.color('app-ink-2')))]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The keys, said once over the triage list: J K move, A assign…
class _KeyHints extends StatelessWidget {
  const _KeyHints({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(2)),
      child: Wrap(
        spacing: t.space(3),
        runSpacing: t.space(1),
        children: [
          for (final (keys, does) in triageKeyHints)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(1),
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 0.4 * xs),
                  decoration: BoxDecoration(border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')), borderRadius: BorderRadius.circular(0.3 * xs)),
                  child: Text(keys, style: t.textAt(xs, mono: true, color: t.color('app-ink-2'))),
                ),
                Text(does, style: pageText(t, xs, color: t.color('app-ink-3'))),
              ],
            ),
        ],
      ),
    );
  }
}

/// One of the bar's words: a page, or a notebook the list is narrowed to (as All notes draws its sorts).
class _Word extends StatelessWidget {
  const _Word({super.key, required this.label, required this.on, required this.onPressed, this.count});

  final String label;
  final bool on;
  final VoidCallback onPressed;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final color = on ? t.color('app-ink') : t.color('app-ink-2');
    return GlacierPressable(
      onPressed: onPressed,
      selected: on,
      haptic: HapticKind.selection,
      semanticLabel: count == null ? label : '$label, $count',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: 1),
          decoration: BoxDecoration(
            color: on ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
            border: Border.all(color: on ? t.color('glacier-border-subtle') : const Color(0x00000000), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Text.rich(
            TextSpan(children: [TextSpan(text: label), if (count != null && count! > 0) TextSpan(text: ' $count', style: tabular(pageText(t, sm, color: t.color('app-ink-3'))))]),
            maxLines: 1,
            softWrap: false,
            style: pageText(t, sm, weight: 'medium', color: color),
          ),
        ),
      ),
    );
  }
}
