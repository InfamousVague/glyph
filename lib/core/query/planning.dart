/// A query's planning of tickets (Matt, 2026-10-31, of the ticket features he chose; lib/core/planning): the fields
/// a query reads about a ticket's cycle, its age, its epic and its milestone, what `where: cycle = current` and
/// `where: stale` mean, a cycle's burndown and the cycles' velocity as charts the chart view draws
/// (lib/editor/queries/query_chart.dart), the roadmap's bars, and the one action that carries a cycle's unfinished
/// tickets on.
///
///     ```query                     ```query                  ```query
///     from: tickets [[Kiln]]       from: tickets [[Kiln]]    from: notes [[Kiln]]
///     where: cycle = current       show: burndown            show: roadmap
///     show: board                  ```                       ```
///     ```
///
/// The fields, read through the run's [FieldLook] like a rollup's, so they sort, group, filter and total as any
/// other, on a ticket (and `milestone`, the roadmap's days, on a milestone note too):
///
/// - `cycle`: the name of the cycle it is in (cycles.dart), however its `cycle:` writes it; `where: cycle = current`
///   (or `next`, `previous`) is a ticket in that cycle of its own notebook's.
/// - `stale` and `age`: whether it has sat in its status longer than its notebook's `stale-after:`, and how many days
///   it has (history.dart says where the days come from).
/// - `epic`: the epic it is under, however far up; `milestone`: its own, else its epic's; `progress`: how much of
///   what is under it is done, `40%`.
/// - `roadmap-start` and `roadmap-end`: an epic's span, its own `start:` and `due:` or else its tickets' first start
///   and last due, or its milestone's day; a milestone's day; any other ticket's start and due. A roadmap's bars.
///
/// Pure: the library is given, and so is what the tickets' versions say (test/query/planning_test.dart).
library;

import '../days.dart' show dateOfDay, daysBetween;
import '../item_syntax.dart' show jsTrim;
import '../planning/cycles.dart';
import '../planning/history.dart';
import '../planning/planning.dart';
import '../properties.dart' show StatusCategory, issueKeyOf, linkTargets;
import '../title_key.dart' show titleKey;
import 'chart.dart' show ChartBucket, ChartData, ChartPoint;
import 'read.dart';
import 'records.dart';
import 'rollup.dart' show FieldLook;
import 'values.dart';

/// The fields this answers; any other is the run's own.
const Set<String> planningFields = {'cycle', 'cycle:current', 'cycle:next', 'cycle:previous', 'stale', 'age', 'epic', 'milestone', 'progress', 'roadmap-start', 'roadmap-end', 'done-on'};

/// The words a `cycle =` may say for a cycle counted from today, and the field each is.
const Map<String, String> _cycleWords = {
  'current': 'cycle:current',
  'now': 'cycle:current',
  'this': 'cycle:current',
  'next': 'cycle:next',
  'previous': 'cycle:previous',
  'last': 'cycle:previous',
  'prev': 'cycle:previous',
};

/// [condition] with each `cycle = current` (`next`, `previous`; `!=` too) read as the test it means: whether the
/// ticket is in that cycle of its own notebook's, which differs from one notebook to the next. A quoted word is a
/// cycle's name, as anything quoted is words.
Condition? planningWhere(Condition? condition) => switch (condition) {
  null => null,
  Compare(:final field, :final op, value: WordsLiteral(:final text, quoted: false)) when (field == 'cycle' || field == 'sprint') && (op == Op.eq || op == Op.ne) && _cycleWords.containsKey(text.toLowerCase()) =>
    op == Op.eq ? Has(_cycleWords[text.toLowerCase()]!) : NotCondition(Has(_cycleWords[text.toLowerCase()]!)),
  NotCondition(:final of) => NotCondition(planningWhere(of)!),
  AndCondition(:final all) => AndCondition([for (final each in all) planningWhere(each)!]),
  OrCondition(:final any) => OrCondition([for (final each in any) planningWhere(each)!]),
  _ => condition,
};

/// Whether [query] is about cycles: a burndown, velocity, a `cycle:` line, a `where:` or a `group:` that names it.
bool asksCycles(Query query) => query.plan == PlanView.burndown || query.plan == PlanView.velocity || query.cycle != null || query.group == 'cycle' || fieldsNamed(query.where).any((field) => field == 'cycle' || field == 'sprint');

/// The library's planning, read once a run and kept for it: each notebook's cycles, each ticket's cycle, parent,
/// epic and age, and the milestones.
class PlanningIndex {
  PlanningIndex(this.library, this.today, {StatusPast? past}) : past = past ?? const NoPast();

  final QueryLibrary library;
  final String today;
  final StatusPast past;

  /// Each note's record by its id: notes and tickets, no to-dos.
  late final Map<String, QueryRecord> notes = () {
    final into = <String, QueryRecord>{};
    for (final record in library.records) {
      if (record.kind == RecordKind.note || record.kind == RecordKind.ticket) into.putIfAbsent(record.noteId, () => record);
    }
    return into;
  }();

  /// Every ticket.
  late final List<QueryRecord> tickets = [for (final record in notes.values) if (record.kind == RecordKind.ticket) record];

  QueryRecord? _titled(String target) {
    final id = library.byTitle[titleKey(target)]?.id ?? library.byTicket[issueKeyOf(target) ?? '']?.id;
    return id == null ? null : notes[id];
  }

  /// The notebook a record's `notebook` names, as a record.
  QueryRecord? notebookOf(String? title) => title == null ? null : _titled(title);

  final Map<String, CycleBook> _books = {};

  /// The cycles of the notebook called [notebook] (null for none): its `cycles:` and the cycle notes among its pages.
  CycleBook bookFor(String? notebook) => _books.putIfAbsent(titleKey(notebook ?? ''), () {
    final key = titleKey(notebook ?? '');
    final rule = cycleRuleFrom(notebookOf(notebook)?.props['cycles']);
    final made = <Cycle>[
      for (final record in notes.values)
        if (titleKey(record.notebook ?? '') == key)
          ?cycleNoteOf(id: record.noteId, title: record.title, props: record.props),
    ];
    return CycleBook(rule: rule, notes: made);
  });

  final Map<String, Cycle?> _cycles = {};

  /// The cycle a ticket is in; null for none.
  Cycle? cycleOf(QueryRecord record) => _cycles.putIfAbsent(record.noteId, () => record.kind == RecordKind.ticket ? bookFor(record.notebook).named(record.props['cycle'] ?? record.props['sprint']) : null);

  /// The cycle counted from today that [word] names in [record]'s notebook: `current`, `next` or `previous`.
  Cycle? cycleCounted(String? notebook, String word) {
    final book = bookFor(notebook);
    final now = book.current(today);
    if (now == null) return null;
    return switch (word) {
      'cycle:next' => book.after(now),
      'cycle:previous' => book.before(now),
      _ => now,
    };
  }

  /// The cycle a query's `cycle:` line names in [notebook]: the current where unsaid.
  Cycle? cycleWritten(String? notebook, String? written) {
    final word = _cycleWords[jsTrim(written ?? 'current').toLowerCase()];
    return word != null ? cycleCounted(notebook, word) : bookFor(notebook).named(written);
  }

  final Map<String, int?> _staleAfter = {};

  /// Days in one status before a ticket of [notebook] is stale; null for never.
  int? staleAfter(String? notebook) => _staleAfter.putIfAbsent(titleKey(notebook ?? ''), () {
    final said = notebookOf(notebook)?.props['stale-after'];
    return said == null ? defaultStaleDays : staleAfterOf('---\nstale-after: $said\n---\n');
  });

  /// The day a ticket took its status.
  HistoryDay sinceOf(QueryRecord record) => statusSince(past, record.noteId, record.ticket?.status, updated: record.updated);

  /// How many days a ticket has been stale; null where it is not.
  int? staleDaysOf(QueryRecord record) {
    final ticket = record.ticket;
    if (ticket == null) return null;
    return staleDays(category: ticket.category, since: sinceOf(record).day, today: today, after: staleAfter(record.notebook));
  }

  /// The day a ticket was finished; null for one that is not.
  HistoryDay? doneOf(QueryRecord record) {
    final ticket = record.ticket;
    if (ticket == null) return null;
    return finishedOn(past, record.noteId, _bodyFront(record), ticket.status, record.workflow, updated: record.updated);
  }

  /// Enough of a record's front matter for history.dart's `done:`: its props written back as lines.
  static String _bodyFront(QueryRecord record) {
    final lines = [for (final key in doneKeys) if (record.props[key] case final said?) '$key: $said'];
    return lines.isEmpty ? '' : '---\n${lines.join('\n')}\n---\n';
  }

  /// The ticket a `parent:` (or `epic:`) of [record] names.
  QueryRecord? parentOf(QueryRecord record) {
    final parent = record.ticket?.parent;
    if (parent == null || parent.isEmpty) return null;
    final found = _titled(parent);
    return found == null || found.noteId == record.noteId || found.kind != RecordKind.ticket ? null : found;
  }

  /// The epic [record] is under, however far up; null where none is.
  QueryRecord? epicOf(QueryRecord record) {
    final seen = <String>{record.noteId};
    var at = parentOf(record);
    while (at != null && seen.add(at.noteId)) {
      if (at.ticket?.epic ?? false) return at;
      at = parentOf(at);
    }
    return null;
  }

  /// Each ticket's tickets under it, by its id.
  late final Map<String, List<QueryRecord>> children = () {
    final into = <String, List<QueryRecord>>{};
    for (final record in tickets) {
      final parent = parentOf(record);
      if (parent != null) into.putIfAbsent(parent.noteId, () => []).add(record);
    }
    return into;
  }();

  /// How far what is under a ticket is done; null for nothing under it.
  EpicProgress? progressOf(QueryRecord record) {
    final under = children[record.noteId];
    if (under == null || under.isEmpty) return null;
    return epicProgressOf([for (final child in under) (category: child.ticket!.category, estimate: child.props['estimate'])]);
  }

  /// The milestone a record names, as written (its title), else its epic's.
  String? milestoneOf(QueryRecord record) {
    final own = linkTargets(record.props['milestone']);
    if (own.isNotEmpty) return own.first;
    final epic = record.kind == RecordKind.ticket ? epicOf(record) : null;
    final theirs = epic == null ? const <String>[] : linkTargets(epic.props['milestone']);
    return theirs.isEmpty ? null : theirs.first;
  }

  /// A milestone's day, by its title; null where no milestone note of that title has one.
  String? milestoneDay(String? title) {
    if (title == null) return null;
    final note = _titled(title);
    return note == null ? null : milestoneDayOf(note.props);
  }

  /// Every milestone note, the soonest first.
  late final List<QueryRecord> milestones = [for (final record in notes.values) if (isMilestoneType(record.props['type'])) record]
    ..sort((a, b) => (milestoneDayOf(a.props) ?? '9999').compareTo(milestoneDayOf(b.props) ?? '9999'));

  String? _day(String? said) {
    final clean = jsTrim(said ?? '');
    return dateOfDay(clean) != null ? clean : null;
  }

  /// Where a record's bar on a roadmap starts.
  String? roadmapStart(QueryRecord record) {
    if (isMilestoneType(record.props['type'])) return milestoneDayOf(record.props);
    final ticket = record.ticket;
    if (ticket == null) return _day(record.props['start']);
    if (ticket.start != null || !ticket.epic) return ticket.start;
    String? first;
    for (final child in children[record.noteId] ?? const <QueryRecord>[]) {
      final day = child.ticket?.start ?? child.ticket?.due;
      if (day != null && (first == null || day.compareTo(first) < 0)) first = day;
    }
    return first;
  }

  /// Where a record's bar on a roadmap ends.
  String? roadmapEnd(QueryRecord record) {
    if (isMilestoneType(record.props['type'])) return milestoneDayOf(record.props);
    final ticket = record.ticket;
    if (ticket == null) return _day(record.props['due'] ?? record.props['end']);
    if (ticket.due != null || !ticket.epic) return ticket.due;
    final target = milestoneDay(milestoneOf(record));
    if (target != null) return target;
    String? last;
    for (final child in children[record.noteId] ?? const <QueryRecord>[]) {
      final day = child.ticket?.due ?? child.ticket?.start;
      if (day != null && (last == null || day.compareTo(last) > 0)) last = day;
    }
    return last;
  }

  /// What a planning [field] says on [record].
  Value valueOf(QueryRecord record, String field) {
    switch (field) {
      case 'cycle':
        final cycle = cycleOf(record);
        return cycle == null ? emptyValue : TextValue(cycle.name);
      case 'cycle:current' || 'cycle:next' || 'cycle:previous':
        if (record.kind != RecordKind.ticket) return const BoolValue(on: false);
        return BoolValue(on: CycleBook.same(cycleOf(record), cycleCounted(record.notebook, field)));
      case 'stale':
        if (record.kind != RecordKind.ticket) return emptyValue;
        return BoolValue(on: staleDaysOf(record) != null);
      case 'age':
        final ticket = record.ticket;
        if (ticket == null || ticket.category == StatusCategory.done) return emptyValue;
        final count = daysBetween(sinceOf(record).day, today);
        return count == null ? emptyValue : NumberValue(count.toDouble(), '$count ${count == 1 ? 'day' : 'days'}');
      case 'epic':
        final epic = record.kind == RecordKind.ticket ? epicOf(record) : null;
        return epic == null ? emptyValue : TextValue(epic.title);
      case 'milestone':
        final milestone = milestoneOf(record);
        return milestone == null ? emptyValue : TextValue(milestone);
      case 'progress':
        final progress = progressOf(record);
        if (progress == null) return emptyValue;
        final share = 100 * progress.fraction;
        return NumberValue(share, '${share.round()}%');
      case 'roadmap-start':
        final day = roadmapStart(record);
        return day == null ? emptyValue : DayValue(day);
      case 'roadmap-end':
        final day = roadmapEnd(record);
        return day == null ? emptyValue : DayValue(day);
      case 'done-on':
        final done = doneOf(record);
        return done == null ? emptyValue : DayValue(done.day);
    }
    return emptyValue;
  }
}

/// How a run reads a field: [inner] for every field but the planning ones, which [plan] answers on a note or a
/// ticket. A rollup of one of those names is the rollup, as [own] names them.
FieldLook planningLook(FieldLook inner, PlanningIndex plan, {Set<String> own = const {}}) => (record, field) {
  if (!planningFields.contains(field) || own.contains(field) || record.kind == RecordKind.task || record.kind == RecordKind.event) return inner(record, field);
  return plan.valueOf(record, field);
};

// ---- what a card says -------------------------------------------------------------------------------------------

/// A ticket's planning, as its card and its row say it: stale, its estimate, its cycle, and how far what is under it
/// is done (the port's own, which a row's JSON leaves out).
class RowPlan {
  const RowPlan({this.staleDays, this.estimate, this.cycle, this.progress, this.epic = false});
  final int? staleDays;

  /// As written: `3`, `4h`.
  final String? estimate;
  final String? cycle;
  final EpicProgress? progress;
  final bool epic;

  /// Whether there is anything to draw.
  bool get isEmpty => staleDays == null && estimate == null && progress == null && !epic;

  @override
  bool operator ==(Object other) => other is RowPlan && other.staleDays == staleDays && other.estimate == estimate && other.cycle == cycle && other.progress == progress && other.epic == epic;

  @override
  int get hashCode => Object.hash(staleDays, estimate, cycle, progress, epic);

  @override
  String toString() => 'RowPlan(stale $staleDays, estimate $estimate, cycle $cycle, $progress${epic ? ', epic' : ''})';
}

/// [record]'s plan, or null for a record that is no ticket.
RowPlan? rowPlanOf(PlanningIndex plan, QueryRecord record) {
  final ticket = record.ticket;
  if (record.kind != RecordKind.ticket || ticket == null) return null;
  final estimate = jsTrim(record.props['estimate'] ?? '');
  return RowPlan(staleDays: plan.staleDaysOf(record), estimate: estimate.isEmpty ? null : estimate, cycle: plan.cycleOf(record)?.name, progress: ticket.epic ? plan.progressOf(record) : null, epic: ticket.epic);
}

// ---- the charts -------------------------------------------------------------------------------------------------

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A day as a burndown's foot names it: its date, the month with it on the first day shown and on a month's first.
String _dayLabel(String day, bool first) {
  final at = dateOfDay(day)!;
  return first || at.day == 1 ? '${at.day} ${_months[at.month - 1]}' : '${at.day}';
}

/// A cycle as a velocity bar's foot names it: `C45` for a year-and-week name, else its own name.
String cycleLabel(Cycle cycle) => isCycleName(cycle.name) ? cycle.name.substring(5).toUpperCase() : cycle.name;

/// Whether a chart of [tickets] is by points: `y: count` says not; else where any of them is estimated.
bool _byPoints(Query query, List<QueryRecord> tickets) => query.y?.fn != Aggregate.count && anyEstimated([for (final ticket in tickets) ticket.props['estimate']]);

/// A burndown, or why there is none.
typedef PlanChart = ({ChartData? chart, String? warning, Cycle? cycle});

/// The burndown of the cycle [query]'s `cycle:` names (the current where unsaid) in [notebook], over the tickets among
/// [records] in it: what remained on each day, and the ideal, as a line each.
PlanChart burndownChart(Query query, List<QueryRecord> records, PlanningIndex plan, String? notebook, String Function(QueryRecord record) keyOf) {
  final cycle = plan.cycleWritten(notebook, query.cycle);
  if (cycle == null || !cycle.dated) return (chart: null, warning: cycle == null ? 'This notebook has no cycles: its cycles: says off.' : 'The cycle “${cycle.name}” has no days.', cycle: cycle);
  final tickets = [for (final record in records) if (record.kind == RecordKind.ticket && CycleBook.same(plan.cycleOf(record), cycle)) record];
  final byPoints = _byPoints(query, tickets);
  final days = burndownOf(cycle, [for (final ticket in tickets) (key: keyOf(ticket), weight: weightOf(ticket.props['estimate'], byPoints: byPoints), done: plan.doneOf(ticket)?.day)], plan.today);
  return (
    chart: ChartData(
      kind: ChartKind.line,
      x: 'day',
      xLabel: 'Day',
      measure: byPoints ? const Measure(Aggregate.sum, 'estimate') : const Measure(Aggregate.count),
      yLabel: byPoints ? 'Points left' : 'Tickets left',
      seriesField: 'burndown',
      buckets: [for (final (index, day) in days.indexed) ChartBucket(key: day.day, label: _dayLabel(day.day, index == 0))],
      series: const [ChartBucket(key: 'remaining', label: 'Remaining'), ChartBucket(key: 'ideal', label: 'Ideal')],
      points: [
        for (final day in days)
          [
            ChartPoint(value: day.remaining, text: day.remaining == null ? '' : plainAmount(day.remaining!), keys: day.left),
            ChartPoint(value: day.ideal, text: plainAmount((day.ideal * 10).round() / 10), keys: const []),
          ],
      ],
    ),
    warning: tickets.isEmpty ? 'Nothing is in ${cycle.name} yet: give a ticket “cycle: ${cycle.written}”.' : null,
    cycle: cycle,
  );
}

/// What each of [notebook]'s last cycles finished, up to today's, as a bar each: the points (or the count) of its
/// tickets among [records] that are done.
PlanChart velocityChart(Query query, List<QueryRecord> records, PlanningIndex plan, String? notebook, String Function(QueryRecord record) keyOf) {
  final book = plan.bookFor(notebook);
  final now = book.current(plan.today);
  final cycles = [for (final cycle in book.around(plan.today)) if (now == null || cycle.start!.compareTo(now.start!) <= 0) cycle];
  if (cycles.isEmpty) return (chart: null, warning: 'This notebook has no cycles: its cycles: says off.', cycle: null);
  final tickets = [for (final record in records) if (record.kind == RecordKind.ticket && plan.cycleOf(record) != null) record];
  final byPoints = _byPoints(query, tickets);
  final bars = velocityOf(cycles, [
    for (final ticket in tickets) (key: keyOf(ticket), cycle: plan.cycleOf(ticket), weight: weightOf(ticket.props['estimate'], byPoints: byPoints), finished: ticket.ticket!.category == StatusCategory.done),
  ], CycleBook.same);
  return (
    chart: ChartData(
      kind: ChartKind.bar,
      x: 'cycle',
      xLabel: 'Cycle',
      measure: byPoints ? const Measure(Aggregate.sum, 'estimate') : const Measure(Aggregate.count),
      yLabel: byPoints ? 'Points finished' : 'Tickets finished',
      seriesField: null,
      buckets: [for (final bar in bars) ChartBucket(key: bar.cycle.key, label: cycleLabel(bar.cycle))],
      series: const [ChartBucket(key: '', label: '')],
      points: [
        for (final bar in bars) [ChartPoint(value: bar.finished, text: plainAmount(bar.finished), keys: bar.keys)],
      ],
    ),
    warning: null,
    cycle: now,
  );
}

// ---- carrying a cycle on ----------------------------------------------------------------------------------------

/// The offer a query of a cycle makes once that cycle has ended: its unfinished tickets, to move to the next.
class CarryOffer {
  const CarryOffer({required this.from, required this.to, required this.noteIds});
  final Cycle from;
  final Cycle to;
  final List<String> noteIds;

  /// "Move 4 unfinished to 2026-C47".
  String get words => carryWords(noteIds.length, to);

  @override
  bool operator ==(Object other) => other is CarryOffer && other.from == from && other.to == to && other.noteIds.join(',') == noteIds.join(',');

  @override
  int get hashCode => Object.hash(from, to, noteIds.join(','));

  @override
  String toString() => 'CarryOffer(${from.name} → ${to.name}: $noteIds)';
}

/// What [query] offers to carry on in [notebook]: where it is about cycles, the unfinished tickets of the cycle it
/// names, once that has ended (its `cycle:` line), or of the one before today's; each moved to the cycle after. Null
/// where nothing is left over.
CarryOffer? carryOfferOf(Query query, PlanningIndex plan, String? notebook) {
  if (!asksCycles(query)) return null;
  final book = plan.bookFor(notebook);
  final now = book.current(plan.today);
  final written = plan.cycleWritten(notebook, query.cycle);
  final from = written != null && written.endedBy(plan.today) ? written : (now == null ? null : book.before(now));
  if (from == null || !from.endedBy(plan.today)) return null;
  final to = book.after(from);
  if (to == null) return null;
  final key = titleKey(notebook ?? '');
  final left = [
    for (final ticket in plan.tickets)
      if (titleKey(ticket.notebook ?? '') == key && ticket.ticket!.category != StatusCategory.done && CycleBook.same(plan.cycleOf(ticket), from)) ticket.noteId,
  ];
  return left.isEmpty ? null : CarryOffer(from: from, to: to, noteIds: left);
}

// ---- a ticket's panel -------------------------------------------------------------------------------------------

/// What a ticket's panel says of its planning (lib/editor/tickets/ticket_panel.dart): the cycle it is in and those it
/// could be moved to, how long it has sat, how far its epic is, and the milestones it could be for.
class TicketPlanning {
  const TicketPlanning({this.cycle, this.current, this.cycles = const [], this.staleDays, this.progress, this.milestones = const [], this.milestone, this.milestoneDay});

  /// Its own cycle, and today's in its notebook.
  final Cycle? cycle;
  final Cycle? current;

  /// The cycles its notebook offers: the last two, today's and the next two.
  final List<Cycle> cycles;
  final int? staleDays;

  /// Where it is an epic: how far its tickets are.
  final EpicProgress? progress;

  /// The milestone notes, the soonest first, with their days.
  final List<({String title, String? day})> milestones;

  /// Its milestone (its own, else its epic's), and that milestone's day.
  final String? milestone;
  final String? milestoneDay;
}

/// The panel's planning for ticket [noteId]; null where it is no ticket the library has.
TicketPlanning? ticketPlanningOf(PlanningIndex plan, String noteId) {
  final record = plan.notes[noteId];
  if (record == null || record.kind != RecordKind.ticket) return null;
  final book = plan.bookFor(record.notebook);
  final now = book.current(plan.today);
  final offered = <Cycle>[];
  if (now != null) {
    final before = book.before(now);
    final earlier = before == null ? null : book.before(before);
    final next = book.after(now);
    final later = next == null ? null : book.after(next);
    offered.addAll([?earlier, ?before, now, ?next, ?later]);
  }
  final milestone = plan.milestoneOf(record);
  return TicketPlanning(
    cycle: plan.cycleOf(record),
    current: now,
    cycles: offered,
    staleDays: plan.staleDaysOf(record),
    progress: (record.ticket?.epic ?? false) ? plan.progressOf(record) : null,
    milestones: [for (final each in plan.milestones) (title: each.title, day: milestoneDayOf(each.props))],
    milestone: milestone,
    milestoneDay: plan.milestoneDay(milestone),
  );
}
