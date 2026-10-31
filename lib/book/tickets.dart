/// A notebook's tickets: the library-wide half of tickets as notes (Matt asked what Notion- and Jira-like features
/// custom Markdown could give the app, "like tickets and such", and then "Do 1, 2 and 3 in parallel"; tauri/
/// docs/DESIGN.md §157, docs/TICKETS.md). A port of `src/app/book/tickets.ts`. What one ticket's front matter says is
/// lib/core/properties.dart, the grammar the three features share (§156); this is what needs the other notes: which
/// notebook a ticket is in and so which workflow its status moves through, the key the next one gets, the people the
/// library already names, which tickets a ticket waits on, and the ticket a `[[GHO-12]]` means.
///
/// A notebook gives its tickets a key, `key: GHO`, and every new ticket in it is `GHO-` and the next number, as Jira
/// numbers a project's issues. Nothing stores the number: it is one more than the highest any note still names
/// (properties.dart `nextIssueId`), read across the whole library and the Trash, so a ticket deleted and restored
/// never meets a second of its number. The notebook may name its own workflow, `statuses: [Ideas, Building, Live]`,
/// and a ticket's status is placed in it; a ticket in no notebook, or in one that names none, moves through the
/// default.
///
/// A ticket is in a notebook as any page is, by a line of its index; one made elsewhere with a notebook's key (a Bug
/// report from the blank page, a ticket Claude wrote) is that notebook's by its key, so its status still reads by
/// that notebook's workflow.
///
/// Pure: it imports nothing that draws or stores, and every rule here is a test (test/book_core/tickets_test.dart).
///
/// What differs: [newTicketBody]'s options are named parameters; [ticketFinder] and a `find` handed to [waitingOn]
/// answer null where the page's answer `undefined`, and what `find` answers is [Placed], the page's `{category}`; [peopleIn] takes the notes' bodies, which is all it reads; names
/// are put in order by lib/core/query/collate.dart, which stands in for the browser's collation.
library;

import '../core/book.dart' show bookIndex, placeOf;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/item_syntax.dart' show jsTrim;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/properties.dart';
import '../core/query/collate.dart' show localeCompare;
import '../core/task_fields.dart' show FieldKind, fieldsIn, personKey;
import '../core/title_key.dart' show titleKey;
import 'ticket_watchers.dart' show ticketCreator, watchersOf, withWatcher;

// ---- the notebook's key -------------------------------------------------------------------------------------------

final RegExp _startsWithLetter = RegExp('^[A-Z]');
final RegExp _notKeyChar = RegExp('[^A-Z0-9]');

/// What is wrong with a key as typed in the notebook's settings, in a sentence; null for a key that will do, or for
/// nothing typed, which takes the key off.
String? keyProblem(String typed) {
  final key = jsTrim(typed).toUpperCase();
  if (key.isEmpty || projectKey.hasMatch(key)) return null;
  if (!_startsWithLetter.hasMatch(key)) return 'A key starts with a letter, like GHO.';
  if (_notKeyChar.hasMatch(key)) return 'Only letters and digits, like GHO or WEB2.';
  return key.length < 2 ? 'Two letters at least, like GHO.' : 'Ten letters and digits at most.';
}

/// The notebook with its key set, upper case, or taken off for nothing typed; a key that will not do leaves it as it
/// was.
String withNotebookKey(String body, String typed) {
  final key = jsTrim(typed).toUpperCase();
  if (key.isEmpty) return withProperty(body, 'key', null);
  return projectKey.hasMatch(key) ? withProperty(body, 'key', key) : body;
}

/// The key the notebook's next ticket gets, `GHO-13`, among [bodies]: every note there is, archived and in the Trash
/// too, so no number is given twice. Null for a notebook with no key.
String? nextTicketId(String notebook, Iterable<String> bodies) {
  final key = notebookKey(notebook);
  return key != null ? nextIssueId(key, bodies) : null;
}

// ---- statuses -----------------------------------------------------------------------------------------------------

/// Statuses a new ticket waits in rather than starts in: a backlog is where a ticket goes when it is not yet to do.
const Set<String> _waiting = {'backlog', 'icebox', 'triage', 'inbox', 'later', 'someday'};

/// The status a new ticket starts in: the workflow's first that is not started and not a waiting room, To do in the
/// default, after Backlog; `[Ideas, Building, Live]` starts in Ideas. A workflow whose open statuses are all waiting
/// rooms starts in its first.
String firstOpenStatus(List<String> statuses) {
  for (final status in statuses) {
    if (statusCategory(status, statuses) == StatusCategory.todo && !_waiting.contains(jsTrim(status).toLowerCase())) return status;
  }
  return statuses.isNotEmpty ? statuses.first : 'To do';
}

/// Whether [status] is one of the workflow's, compared as a person would say it.
bool _inWorkflow(String status, List<String> statuses) => statuses.any((each) => jsTrim(each).toLowerCase() == jsTrim(status).toLowerCase());

/// A new ticket's body as it is written: `type: ticket`, its id where there is one to give, and a status in the
/// workflow it is made in. [words] is what it starts with: a ticket's template, filled (lib/notes/note_templates.dart),
/// whose status stands where the workflow has it and is the workflow's first open one where it has not; or, absent,
/// the title as its heading. Keys the template wrote stay as it wrote them.
String newTicketBody(String title, {required String? id, required List<String> statuses, String? words}) {
  var body = words ?? '# ${jsTrim(title)}\n\n';
  final type = frontMatterValue(body, 'type');
  if (!isTicketType(type)) body = withProperty(body, 'type', 'ticket');
  if (id != null && id.isNotEmpty && ticketIdOf(body) == null) body = withTicketKey(body, id);
  final status = jsTrim(frontMatterValue(body, 'status') ?? '');
  if (status.isEmpty || !_inWorkflow(status, statuses)) body = withProperty(body, 'status', firstOpenStatus(statuses));
  // Its maker watches it (lib/book/ticket_watchers.dart; Matt, 2026-10-31), where the template named nobody.
  final creator = ticketCreator.value;
  if (creator != null && watchersOf(body).isEmpty) body = withWatcher(body, creator, true);
  return body;
}

// ---- the library's tickets ----------------------------------------------------------------------------------------

/// A ticket in the library: its note, its title, what its front matter says, and the notebook whose workflow it moves
/// through.
class TicketEntry {
  const TicketEntry({required this.note, required this.title, required this.ticket, required this.statuses, required this.notebook});
  final Note note;
  final String title;
  final Ticket ticket;

  /// Its notebook's workflow, or the default.
  final List<String> statuses;

  /// The notebook it is a page of, or whose key it carries; null for neither.
  final Note? notebook;
}

/// The notebook a note is in, by the notes it is among: the one whose index lists it (book.dart `placeOf`), else, for
/// a ticket, the one whose key its id carries. Built once for a library, asked once per note.
Note? Function(Note note) notebookFinder(Iterable<Note> notes) {
  final index = bookIndex(notes);
  final keyed = <String, Note>{};
  for (final note in notes) {
    if (!NoteFacts.of(note).isBook) continue;
    final key = notebookKey(note.body);
    if (key != null) keyed.putIfAbsent(key, () => note);
  }
  return (note) {
    final place = placeOf(index, note);
    if (place != null) return place.book;
    final id = issueKeyOf(NoteFacts.of(note).ticketKey);
    return id != null ? keyed[id.substring(0, id.lastIndexOf('-'))] : null;
  };
}

/// The workflow of a ticket in no notebook, or in one that names none: one list for all of them.
final List<String> _noWorkflow = List<String>.unmodifiable(statusesOf(null));

/// Every ticket among [notes], in the order given, each read in its notebook's workflow. [skip] leaves notes out
/// that are tickets in shape only: a ticket's template page (lib/notes/own_templates.dart) makes tickets and is not
/// one.
///
/// Read through what is kept of each note (lib/core/note_facts.dart): whether it is a notebook or a ticket, its
/// title, its ticket, its notebook's workflow. This found each note's front matter four times over and read every
/// ticket's from its words, and it is asked again whenever the library is (every time a note is left for the home
/// page, which reads the notes again): two to three milliseconds of the next note's opening, over 354 notes on a Mac.
List<TicketEntry> ticketsIn(Iterable<Note> notes, [bool Function(Note note)? skip]) {
  final notebookOf = notebookFinder(notes);
  final entries = <TicketEntry>[];
  for (final note in notes) {
    final facts = NoteFacts.of(note);
    if (!facts.isTicket || facts.isBook || (skip != null && skip(note))) continue;
    final notebook = notebookOf(note);
    final statuses = notebook == null ? _noWorkflow : NoteFacts.of(notebook).statuses;
    entries.add(TicketEntry(note: note, title: facts.title, ticket: facts.ticketIn(statuses)!, statuses: statuses, notebook: notebook));
  }
  return entries;
}

/// Something whose status stands somewhere: what [waitingOn] asks of what it finds.
abstract interface class Placed {
  StatusCategory get category;
}

/// A ticket as a picker and a key's title show it: its key, its title, and where its status stands.
class TicketChoice implements Placed {
  const TicketChoice({required this.key, required this.title, required this.status, required this.category});
  final String? key;
  final String title;
  final String? status;
  @override
  final StatusCategory category;

  @override
  bool operator ==(Object other) => other is TicketChoice && other.key == key && other.title == title && other.status == status && other.category == category;

  @override
  int get hashCode => Object.hash(key, title, status, category);

  @override
  String toString() => 'TicketChoice($key, $title, $status, ${category.name})';
}

/// An entry as a picker shows it.
TicketChoice ticketChoice(TicketEntry entry) => TicketChoice(key: entry.ticket.id, title: entry.title, status: entry.ticket.status, category: entry.ticket.category);

/// What a `[[link]]` or a `blocked-by:` names, found: the ticket with that key in any case (`[[gho-12]]`), else the
/// ticket with that title as a link matches it. Null for neither. The first of two with one key, as a list reads.
TicketEntry? Function(String target) ticketFinder(Iterable<TicketEntry> entries) {
  final byKey = <String, TicketEntry>{};
  final byTitle = <String, TicketEntry>{};
  for (final entry in entries) {
    final id = entry.ticket.id;
    if (id != null && id.isNotEmpty) byKey.putIfAbsent(id, () => entry);
    final key = titleKey(entry.title);
    if (key.isNotEmpty) byTitle.putIfAbsent(key, () => entry);
  }
  return (target) {
    final key = issueKeyOf(target);
    return (key != null ? byKey[key] : null) ?? byTitle[titleKey(target)];
  };
}

/// One ticket's wait on another: what its `blocked-by:` names, and the ticket that is.
class Wait<T> {
  const Wait({required this.target, required this.found});
  final String target;
  final T found;

  @override
  bool operator ==(Object other) => other is Wait<T> && other.target == target && other.found == found;

  @override
  int get hashCode => Object.hash(target, found);

  @override
  String toString() => 'Wait($target, $found)';
}

/// What a ticket waits on that is not finished: each `blocked-by:` that names a ticket whose status is not done, by
/// [find] ([ticketFinder] through [ticketChoice], or the screen's own lookup). A target that names no ticket is not a
/// wait, since nothing can say it is done; the panel still lists it under Blocked by.
List<Wait<T>> waitingOn<T extends Placed>(Ticket ticket, T? Function(String target) find) {
  final waits = <Wait<T>>[];
  for (final target in ticket.blockedBy) {
    final found = find(target);
    if (found != null && found.category != StatusCategory.done) waits.add(Wait(target: target, found: found));
  }
  return waits;
}

// ---- people -------------------------------------------------------------------------------------------------------

final RegExp _ats = RegExp(r'^@+');

/// The people the library already names, the most named first: every ticket's `assignee:` and every `@person` in the
/// words of a note (task_fields.dart), each person once however they are written (`@sam`, "Sam"). A name is shown as
/// it was written most, an assignee's spelling before a handle's, so "Sam Ortiz" rather than `Sam-Ortiz`. What the
/// Assignee picker offers before anything is typed.
List<String> peopleIn(Iterable<String> bodies) {
  final counts = <String, ({List<int> count, Map<String, int> names})>{};
  void meet(String name, int weight) {
    final clean = jsTrim(name).replaceFirst(_ats, '');
    final key = personKey(clean);
    if (key.isEmpty) return;
    final person = counts.putIfAbsent(key, () => (count: [0], names: <String, int>{}));
    person.count[0] += 1;
    person.names[clean] = (person.names[clean] ?? 0) + weight;
  }

  for (final body in bodies) {
    final assignee = frontMatterValue(body, 'assignee');
    if (assignee != null && assignee.isNotEmpty) meet(assignee, 2);
    if (!body.contains('@')) continue;
    for (final field in fieldsIn(body)) {
      if (field.kind == FieldKind.person) meet(field.value, 1);
    }
  }
  final people = <({int count, String name, int at})>[];
  for (final person in counts.values) {
    // The spelling met most, the first in the alphabet of two met as often, and of two the alphabet cannot part the
    // one met first: what the page's sort, which leaves ties as they came, answers.
    final spelt = person.names.entries.toList();
    final order = [for (var i = 0; i < spelt.length; i += 1) i]
      ..sort((a, b) {
        if (spelt[b].value != spelt[a].value) return spelt[b].value - spelt[a].value;
        final by = localeCompare(spelt[a].key, spelt[b].key);
        return by != 0 ? by : a - b;
      });
    final names = [for (final i in order) spelt[i]];
    people.add((count: person.count[0], name: names.first.key, at: people.length));
  }
  people.sort((a, b) {
    if (b.count != a.count) return b.count - a.count;
    final by = localeCompare(a.name, b.name);
    return by != 0 ? by : a.at - b.at;
  });
  return [for (final person in people) person.name];
}
