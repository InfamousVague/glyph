/// Sub-tickets and what a ticket waits on, across the library (Matt, 2026-10-30, of a list of plain-Markdown features:
/// "add all 12"). A ticket names its parent, `parent: "[[GHO-3]]"`, and what blocks it, `blocked-by: "[[GHO-9]]"` or a
/// list of them, in its own front matter (lib/core/properties.dart); nothing else keeps either. This reads them back
/// the other way: a parent's children and how many of them are done, a ticket's blockers that are not done yet (the
/// lock, which goes as soon as they are), and the one thing the two fields may never make, a ring: a ticket that waits,
/// through any number of others, on itself, or that is its own ancestor.
///
/// Pure: every rule here is a test (test/book_core/ticket_links_test.dart).
library;

import '../core/properties.dart';
import '../core/title_key.dart' show titleKey;
import 'tickets.dart';

/// How many of a parent's sub-tickets are done, of how many.
class TicketProgress {
  const TicketProgress({required this.done, required this.total});
  final int done;
  final int total;

  /// None of them: no bar to draw.
  bool get isEmpty => total == 0;

  /// Done over total, 0 for none.
  double get fraction => total == 0 ? 0 : done / total;

  /// "2 of 5 done".
  String get words => '$done of $total done';

  @override
  bool operator ==(Object other) => other is TicketProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);

  @override
  String toString() => 'TicketProgress($done/$total)';
}

/// Whether [target], as a `parent:` or a `blocked-by:` writes it, names [entry]: its key in any case, or its title as
/// a link matches it.
bool namesTicket(String target, TicketEntry entry) {
  final id = entry.ticket.id;
  final key = issueKeyOf(target);
  if (key != null && id != null && key == id) return true;
  return titleKey(target).isNotEmpty && titleKey(target) == titleKey(entry.title);
}

/// The sub-tickets of [parent]: every ticket whose `parent:` names it, in the order given.
List<TicketEntry> subTicketsOf(TicketEntry parent, Iterable<TicketEntry> entries) => [
  for (final entry in entries)
    if (entry.note.id != parent.note.id && entry.ticket.parent != null && namesTicket(entry.ticket.parent!, parent)) entry,
];

/// How many of [children] are done.
TicketProgress progressOf(Iterable<TicketEntry> children) {
  var done = 0, total = 0;
  for (final child in children) {
    total += 1;
    if (child.ticket.category == StatusCategory.done) done += 1;
  }
  return TicketProgress(done: done, total: total);
}

/// Every parent's progress at once, by note id, for a board or a query that draws many: one walk of the library.
Map<String, TicketProgress> progressByParent(List<TicketEntry> entries) {
  final find = ticketFinder(entries);
  final done = <String, int>{}, total = <String, int>{};
  for (final entry in entries) {
    final parent = entry.ticket.parent;
    if (parent == null || parent.isEmpty) continue;
    final found = find(parent);
    if (found == null || found.note.id == entry.note.id) continue;
    final id = found.note.id;
    total[id] = (total[id] ?? 0) + 1;
    if (entry.ticket.category == StatusCategory.done) done[id] = (done[id] ?? 0) + 1;
  }
  return {for (final id in total.keys) id: TicketProgress(done: done[id] ?? 0, total: total[id]!)};
}

/// What blocks [entry] that is not done, found among [entries]: its lock. A blocker done takes itself off, so the lock
/// clears the moment the last one is; a target that names no ticket is not counted, since nothing can say it is done.
List<TicketEntry> openBlockers(TicketEntry entry, TicketEntry? Function(String target) find) => [
  for (final wait in waitingOn<_Found>(entry.ticket, (target) => _Found.of(find(target)))) wait.found.entry,
];

class _Found implements Placed {
  _Found(this.entry);
  final TicketEntry entry;

  static _Found? of(TicketEntry? entry) => entry == null ? null : _Found(entry);

  @override
  StatusCategory get category => entry.ticket.category;
}

/// How a ticket is said in a sentence: its key, else its title in quotes.
String ticketWords(TicketEntry entry) => entry.ticket.id ?? '“${entry.title}”';

/// Why [targets] cannot be [self]'s `blocked-by:`, in a sentence; null where they can. A ticket cannot wait on itself,
/// nor on one that waits on it however far round: GHO-9 waiting on GHO-12 means GHO-12 can never wait on GHO-9.
String? blockedByProblem(TicketEntry self, List<String> targets, List<TicketEntry> entries) {
  final find = ticketFinder(entries);
  for (final target in targets) {
    final found = find(target);
    if (found == null) continue;
    if (found.note.id == self.note.id) return 'A ticket can’t wait on itself.';
    final path = _pathTo(found, self, (entry) => entry.ticket.blockedBy, find);
    if (path != null) {
      final ring = [self, ...path].map(ticketWords).join(' → ');
      return '${ticketWords(found)} already waits on ${ticketWords(self)}, so this would go round in a circle: $ring.';
    }
  }
  return null;
}

/// Why [target] cannot be [self]'s `parent:`, in a sentence; null where it can. A ticket cannot be its own parent, nor
/// the parent of anything above it.
String? parentProblem(TicketEntry self, String? target, List<TicketEntry> entries) {
  if (target == null || target.isEmpty) return null;
  final find = ticketFinder(entries);
  final found = find(target);
  if (found == null) return null;
  if (found.note.id == self.note.id) return 'A ticket can’t be its own parent.';
  final path = _pathTo(found, self, (entry) => [?entry.ticket.parent], find);
  if (path != null) return '${ticketWords(found)} is already under ${ticketWords(self)}, so it can’t be its parent too.';
  return null;
}

/// The tickets from [from] to [to] by [next]'s links, [from] first and [to] last, or null where [to] cannot be reached.
/// Each ticket is visited once, so a ring already written by hand ends the walk rather than looping it.
List<TicketEntry>? _pathTo(TicketEntry from, TicketEntry to, List<String> Function(TicketEntry entry) next, TicketEntry? Function(String target) find) {
  final came = <String, TicketEntry?>{from.note.id: null};
  final queue = <TicketEntry>[from];
  for (var at = 0; at < queue.length; at += 1) {
    final here = queue[at];
    if (here.note.id == to.note.id) {
      final path = <TicketEntry>[];
      TicketEntry? step = here;
      while (step != null) {
        path.insert(0, step);
        step = came[step.note.id];
      }
      return path;
    }
    for (final target in next(here)) {
      final found = find(target);
      if (found == null || came.containsKey(found.note.id)) continue;
      came[found.note.id] = here;
      queue.add(found);
    }
  }
  return null;
}

/// Whether moving [entry] to [status] wants a word first: the status is done and something it waits on is not.
bool doneWhileBlocked(TicketEntry entry, String status, TicketEntry? Function(String target) find) =>
    statusCategory(status, entry.statuses) == StatusCategory.done && openBlockers(entry, find).isNotEmpty;

/// The confirmation's sentence for moving a blocked ticket to done: what still blocks it.
String doneWhileBlockedWords(List<TicketEntry> blockers) {
  final named = blockers.map(ticketWords).toList();
  final list = named.length <= 1 ? named.join() : '${named.sublist(0, named.length - 1).join(', ')} and ${named.last}';
  return named.length == 1 ? 'It still waits on $list, which isn’t done.' : 'It still waits on $list, which aren’t done.';
}

/// A sub-ticket's body for [parent]: a ticket's own front matter (lib/book/tickets.dart [newTicketBody]) with its
/// parent named by key, or by title where the parent has none. [words] is a template's, filled, as New ticket takes.
String subTicketBody(String title, TicketEntry parent, {required String? id, required List<String> statuses, String? words}) {
  final body = newTicketBody(title, id: id, statuses: statuses, words: words);
  return withProperty(body, 'parent', '[[${parent.ticket.id ?? parent.title}]]');
}
