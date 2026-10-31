/// My tickets: one page of every ticket assigned to you, in your own notes and every team's, across all notebooks
/// (Matt, 2026-10-31: "One page of everything assigned to you … Grouped by Overdue / Today / This week / Later / No
/// date, sorted by due then priority"). The pure half: which tickets, in which group, in what order; the page is
/// lib/tickets/ui/tickets_screen.dart.
///
/// It is a query, run by the query engine as any ```query fence is (lib/core/query/run.dart), never a second engine:
///
///     from: tickets
///     where: assignee = me and checked = no
///     sort: due, priority
///
/// `me` is the account's handle (lib/core/query/values.dart [queryMe]), so the same lines in a note list the same
/// tickets. A ticket that is done is not in the inbox; one with no due day is under No date, at the end.
///
/// The groups are by its due day against today: before it Overdue, on it Today, after it up to the Sunday that ends
/// this week This week, after that Later. Inside each the query's own order holds: the soonest due first, then the
/// most urgent (a priority's none between medium and low, as everywhere).
///
/// Pure: the library and the day are handed in, and every rule is a test (test/tickets/inbox_test.dart).
library;

import '../core/days.dart' show dateOfDay, isoDayAfter;
import '../core/properties.dart' show StatusCategory;
import '../core/query/query.dart';
import 'labels.dart' show componentOf, labelsOf;

/// The inbox's query, as a fence would say it.
const String myTicketsLines = 'from: tickets\nwhere: assignee = me and checked = no\nsort: due, priority';

/// What the inbox's rows are under, in the order they are shown.
enum InboxBucket { overdue, today, thisWeek, later, noDate }

/// Each bucket's heading.
const Map<InboxBucket, String> inboxBucketLabels = {
  InboxBucket.overdue: 'Overdue',
  InboxBucket.today: 'Today',
  InboxBucket.thisWeek: 'This week',
  InboxBucket.later: 'Later',
  InboxBucket.noDate: 'No date',
};

/// A ticket as the inbox and the triage list show it: what its row says and what its quick changes need.
class TicketLine {
  const TicketLine({
    required this.noteId,
    required this.key,
    required this.title,
    required this.status,
    required this.category,
    required this.workflow,
    required this.notebook,
    required this.team,
    required this.due,
    required this.priority,
    required this.assignee,
    required this.labels,
    required this.component,
    required this.overdue,
  });

  final String noteId;

  /// Its key, `GHO-12`; null for a ticket with none.
  final String? key;
  final String title;
  final String? status;
  final StatusCategory category;

  /// The workflow its status moves through: its notebook's, or the default.
  final List<String> workflow;

  /// The notebook it is a page of, by title; null for none.
  final String? notebook;

  /// The organization whose notes it is among, by name; null for your own.
  final String? team;
  final String? due;
  final String? priority;
  final String? assignee;
  final List<String> labels;
  final String? component;

  /// Due before today and not done.
  final bool overdue;

  /// Where it is, as its row says it: "HelloTrade · Waitlist", "Waitlist", or nothing.
  String get place => [?team, ?notebook].join(' · ');

  @override
  String toString() => 'TicketLine(${key ?? noteId} $title)';
}

/// One heading of the inbox and its tickets.
class InboxGroup {
  const InboxGroup(this.bucket, this.tickets);
  final InboxBucket bucket;
  final List<TicketLine> tickets;

  String get label => inboxBucketLabels[bucket]!;
}

/// The bucket a due day is in on [today].
InboxBucket bucketOf(String? due, String today) {
  if (due == null) return InboxBucket.noDate;
  final order = due.compareTo(today);
  if (order < 0) return InboxBucket.overdue;
  if (order == 0) return InboxBucket.today;
  return due.compareTo(weekEnd(today)) <= 0 ? InboxBucket.thisWeek : InboxBucket.later;
}

/// The Sunday that ends [today]'s week (a week from Monday), [today] itself on a Sunday.
String weekEnd(String today) {
  final date = dateOfDay(today);
  if (date == null) return today;
  return isoDayAfter(today, DateTime.sunday - date.weekday) ?? today;
}

/// A ticket record as a [TicketLine]. [teamOf] names the organization a note is among, or null for one's own.
TicketLine ticketLineOf(QueryRecord record, String today, {String? Function(String noteId)? teamOf, String? body}) {
  final ticket = record.ticket;
  final due = ticket?.due;
  final done = ticket?.category == StatusCategory.done;
  return TicketLine(
    noteId: record.noteId,
    key: ticket?.id,
    title: record.title.isEmpty ? 'Untitled' : record.title,
    status: ticket?.status,
    category: ticket?.category ?? StatusCategory.todo,
    workflow: record.workflow,
    notebook: record.notebook,
    team: teamOf?.call(record.noteId),
    due: due,
    priority: ticket?.priority,
    assignee: ticket?.assignee,
    labels: body != null ? labelsOf(body) : (ticket?.labels ?? const []),
    component: body != null ? componentOf(body) : record.props['component'],
    overdue: due != null && due.compareTo(today) < 0 && !done,
  );
}

/// Each ticket record of [library] by its note's id.
Map<String, QueryRecord> ticketRecords(QueryLibrary library) => {
      for (final record in library.records)
        if (record.kind == RecordKind.ticket) record.noteId: record,
    };

/// The tickets assigned to you in [library] on [today], by [myTicketsLines], in their buckets: only the buckets
/// that have any, in [InboxBucket]'s order. [teamOf] names a team note's organization.
List<InboxGroup> myTickets(QueryLibrary library, String today, {String? Function(String noteId)? teamOf}) {
  final query = readQuery(myTicketsLines).query!;
  final result = runQuery(query, library, today);
  final records = ticketRecords(library);
  final buckets = <InboxBucket, List<TicketLine>>{};
  for (final group in result.groups) {
    for (final row in group.rows) {
      final record = records[row.noteId];
      if (record == null) continue;
      final line = ticketLineOf(record, today, teamOf: teamOf);
      buckets.putIfAbsent(bucketOf(line.due, today), () => []).add(line);
    }
  }
  return [
    for (final bucket in InboxBucket.values)
      if (buckets[bucket] case final tickets? when tickets.isNotEmpty) InboxGroup(bucket, tickets),
  ];
}

/// How many tickets the inbox holds, and how many of them are overdue: the sidebar's count.
({int all, int overdue}) myTicketCount(List<InboxGroup> groups) {
  var all = 0, overdue = 0;
  for (final group in groups) {
    all += group.tickets.length;
    if (group.bucket == InboxBucket.overdue) overdue += group.tickets.length;
  }
  return (all: all, overdue: overdue);
}
