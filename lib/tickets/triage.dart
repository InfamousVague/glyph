/// Triage: the new tickets nobody has looked at yet, in one list (Matt, 2026-10-31: "New tickets that nobody has
/// looked at yet are collected in one list: created by a form, mail, the connector, or Slack, or with `status: new` /
/// `triage: true`, or no assignee", "Done triaging moves a ticket out (it clears `triage`)"). The pure half: which
/// tickets wait, what each key does, and the words a choice writes; the list is lib/tickets/ui/triage_list.dart.
///
/// A ticket waits to be looked at when it is not done and
///
/// - it says so: `triage: true`, or a status that is a triage's waiting room (`new`, `triage`, `inbox`, `untriaged`);
/// - or it came from somewhere other than the person's own typing: `via: form` (lib/forms), `via: mail` or a `from:`
///   with an address (lib/mail), `via: slack`, `via: connector` (or `claude`, `mcp`, `api`);
/// - or nobody is assigned to it;
///
/// and it has not been looked at: no `triaged:` day, and no `triage: false`. Looked at ([triagedBody]) takes
/// `triage:` off and writes `triaged:` and the day, plain front matter like the rest, so a ticket with nobody on it
/// that was looked at and left that way stays out. A triage's own status (`new`) moves on to the workflow's first
/// open one as it goes (lib/book/tickets.dart `firstOpenStatus`): Backlog's To do, by default.
///
/// The keys (on a phone, swipes in their place): J and K move down and up, A assigns (the person picker), P sets the
/// priority, L the labels, S the status, D closes it as a duplicate of a ticket picked (`duplicate-of: "[[GHO-9]]"`
/// and a closed status; finding and merging duplicates is another feature's), E opens it, and T (or Enter) is done
/// triaging. A swipe to the right is done; to the left, its actions.
///
/// `priority:` is read and written as plain front matter (lib/core/properties.dart reads it as everywhere).
///
/// Pure, so every rule is a test (test/tickets/triage_test.dart).
library;

import '../book/tickets.dart' show firstOpenStatus;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart' show StatusCategory, statusCategory, withProperty, withStatus;
import '../core/query/query.dart';
import 'inbox.dart';

/// Where a ticket came from when it was not typed by the person: `via:`'s words.
const Set<String> triageArrivals = {'form', 'mail', 'email', 'slack', 'connector', 'claude', 'mcp', 'api', 'ai', 'zapier', 'webhook'};

/// Statuses that are a triage's waiting room.
const Set<String> triageStatuses = {'new', 'triage', 'inbox', 'untriaged', 'needs triage'};

const Set<String> _yes = {'true', 'yes', 'y', '1', 'on'};
const Set<String> _no = {'false', 'no', 'n', '0', 'off'};

final RegExp _address = RegExp(r'[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+');

String _said(Map<String, String> props, String key) => jsTrim(props[key] ?? '').toLowerCase();

/// Why a ticket's front matter puts it in triage, or null where it is not there: what a row's hint says.
String? triageReason(Map<String, String> props, {required StatusCategory category, required String? assignee}) {
  if (category == StatusCategory.done) return null;
  final triage = _said(props, 'triage');
  if (_no.contains(triage) || jsTrim(props['triaged'] ?? '').isNotEmpty) return null;
  if (_yes.contains(triage)) return 'Marked for triage';
  final status = _said(props, 'status');
  if (triageStatuses.contains(status)) return 'New';
  final via = _said(props, 'via');
  if (triageArrivals.contains(via)) {
    return switch (via) {
      'form' => 'From a form',
      'mail' || 'email' => 'From mail',
      'slack' => 'From Slack',
      'connector' || 'claude' || 'mcp' || 'ai' => 'From the connector',
      _ => 'From $via',
    };
  }
  if (_address.hasMatch(props['from'] ?? '')) return 'From mail';
  if (assignee == null || jsTrim(assignee).isEmpty) return 'No one assigned';
  return null;
}

/// Whether a ticket record waits in triage.
bool needsTriage(QueryRecord record) {
  final ticket = record.ticket;
  if (record.kind != RecordKind.ticket || ticket == null) return false;
  return triageReason(record.props, category: ticket.category, assignee: ticket.assignee) != null;
}

/// A ticket in the triage list: its line, and why it is there.
class TriageTicket {
  const TriageTicket(this.line, this.reason, {required this.created});
  final TicketLine line;
  final String reason;

  /// The day it was made, for its row and the order.
  final String created;
}

/// The tickets waiting in triage in [library], the newest first; in [notebook] alone (by title, as a ticket's
/// notebook names it) where one is given, across all where not. [teamOf] names a team note's organization.
List<TriageTicket> triageList(QueryLibrary library, String today, {String? notebook, String? Function(String noteId)? teamOf}) {
  final waiting = <({TriageTicket ticket, int at})>[];
  for (final record in library.records) {
    final ticket = record.ticket;
    if (record.kind != RecordKind.ticket || ticket == null) continue;
    if (notebook != null && (record.notebook ?? '').toLowerCase() != notebook.toLowerCase()) continue;
    final reason = triageReason(record.props, category: ticket.category, assignee: ticket.assignee);
    if (reason == null) continue;
    waiting.add((ticket: TriageTicket(ticketLineOf(record, today, teamOf: teamOf), reason, created: record.created), at: waiting.length));
  }
  // The newest first; of two made on one day, the one the library has first.
  waiting.sort((a, b) {
    final by = b.ticket.created.compareTo(a.ticket.created);
    return by != 0 ? by : a.at - b.at;
  });
  return [for (final each in waiting) each.ticket];
}

/// The notebooks the triage list can be narrowed to: those its tickets are in, by title, in the order met.
List<String> triageNotebooks(QueryLibrary library) {
  final names = <String>[];
  for (final record in library.records) {
    final name = record.notebook;
    if (name == null || record.kind != RecordKind.ticket || !needsTriage(record)) continue;
    if (!names.any((each) => each.toLowerCase() == name.toLowerCase())) names.add(name);
  }
  return names;
}

// ---- what a choice writes -----------------------------------------------------------------------------------------

/// The ticket looked at: `triage:` taken off, `triaged:` and [today] written, and a triage's own status moved on to
/// [workflow]'s first open one.
String triagedBody(String body, String today, List<String> workflow) {
  var out = withProperty(body, 'triage', null);
  out = withProperty(out, 'triaged', today);
  final status = jsTrim(frontMatterValue(out, 'status') ?? '');
  if (triageStatuses.contains(status.toLowerCase())) {
    final next = firstOpenStatus([for (final each in workflow) if (!triageStatuses.contains(each.toLowerCase())) each]);
    out = withStatus(out, next, today: today, workflow: workflow);
  }
  return out;
}

/// The status a duplicate is closed with: one of [workflow]'s that says so (Duplicate, Won't do, Cancelled), else
/// its last that is done, else Done.
String duplicateStatus(List<String> workflow) {
  const closing = ['duplicate', 'won’t do', "won't do", 'wont do', 'cancelled', 'canceled', 'closed'];
  for (final word in closing) {
    for (final status in workflow) {
      if (status.toLowerCase() == word) return status;
    }
  }
  for (final status in workflow.reversed) {
    if (statusCategory(status, workflow) == StatusCategory.done) return status;
  }
  return 'Done';
}

/// The ticket closed as a duplicate of [target] (a key, `GHO-9`, or a title): `duplicate-of: "[[GHO-9]]"`, its
/// workflow's closing status, and looked at.
String duplicateBody(String body, String target, String today, List<String> workflow) {
  final name = jsTrim(target);
  if (name.isEmpty) return body;
  var out = withProperty(body, 'duplicate-of', '[[$name]]');
  out = withStatus(out, duplicateStatus(workflow), today: today, workflow: workflow);
  return triagedBody(out, today, workflow);
}

// ---- the keys -----------------------------------------------------------------------------------------------------

/// What a key or a swipe does in the triage list.
enum TriageAction { next, previous, assign, priority, labels, status, duplicate, open, done, actions }

/// The key's action, by its letter in any case; null for a key the list does not take.
TriageAction? triageKey(String key) => switch (key.toLowerCase()) {
      'j' || 'arrow down' => TriageAction.next,
      'k' || 'arrow up' => TriageAction.previous,
      'a' => TriageAction.assign,
      'p' => TriageAction.priority,
      'l' => TriageAction.labels,
      's' => TriageAction.status,
      'd' => TriageAction.duplicate,
      'e' => TriageAction.open,
      't' || 'enter' => TriageAction.done,
      _ => null,
    };

/// What a swipe across a row does: to the right, done triaging; to the left, its actions.
TriageAction triageSwipe({required bool right}) => right ? TriageAction.done : TriageAction.actions;

/// Where the cursor goes for [action] in a list of [count] from [at]; [at] for an action that does not move it.
int triageMove(TriageAction action, int at, int count) {
  if (count == 0) return 0;
  return switch (action) {
    TriageAction.next => at + 1 < count ? at + 1 : at,
    TriageAction.previous => at > 0 ? at - 1 : 0,
    _ => at.clamp(0, count - 1),
  };
}

/// The keys as the list's foot says them.
const List<(String, String)> triageKeyHints = [('J K', 'move'), ('A', 'assign'), ('P', 'priority'), ('L', 'labels'), ('S', 'status'), ('D', 'duplicate'), ('E', 'open'), ('T', 'done')];
