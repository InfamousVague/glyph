/// A member's page, the pure half (docs/TEAMSPACES.md, "Members"; Matt, 2026-10-31: "A member's page is drawn, not
/// stored: their tickets, the docs they own (`owner:` or verified `by:`), their recent edits (from versions), their
/// colour. Reached from the members strip, `@mentions` and the presence avatars"). Everything here is read from what
/// the device already holds: the organization's notes, their versions (each saying who kept it), and who the
/// organization's room says is in the app now. Nothing is written, and nothing is kept.
///
/// The page is lib/orgs/ui/member_page.dart; every rule is a test (test/team/members_test.dart).
library;

import 'package:flutter/foundation.dart';

import '../book/ticket_watchers.dart' show handleOf;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/properties.dart';
import '../core/task_fields.dart' show priorityRank;
import '../core/versions_log.dart';
import '../home/home_organizations.dart' show OrgPresence;
import '../mentions/mention_syntax.dart' show handleKey;
import '../verified/verified.dart' show verifiedOf;

/// One of a member's open tickets.
typedef MemberTicket = ({Note note, String title, Ticket ticket});

/// One of a member's recent edits: the change, and its page's title.
typedef MemberEdit = ({Change change, String title});

/// How many of a member's recent edits the page shows.
const int memberEditsShown = 12;

/// What a member's page says of them.
@immutable
class MemberFacts {
  const MemberFacts({required this.handle, this.tickets = const [], this.owned = const [], this.edits = const [], this.online = false, this.editing});

  final String handle;

  /// Their tickets not done, the soonest due first, then the most urgent, then by title.
  final List<MemberTicket> tickets;

  /// The pages they own: `owner:` names them, or they vouch for it (`verified: {by: …}`), by title.
  final List<Note> owned;

  /// Their newest changes to the organization's pages, newest first, one line per page (its newest).
  final List<MemberEdit> edits;

  /// Whether a device of theirs is in the app now, and the page it is editing where it says.
  final bool online;
  final String? editing;
}

/// Whether the page names [handle] as its owner (`owner: "@sam"`, `owner: sam`, or one of a list).
bool ownedBy(String body, String handle) {
  final key = handleKey(handle);
  for (final item in propertyList(frontMatterValue(body, 'owner'))) {
    final who = handleOf(item);
    if (who != null && handleKey(who) == key) return true;
  }
  final verified = verifiedOf(body);
  return verified != null && handleKey(verified.by) == key;
}

String _titleOf(Note note) {
  final title = NoteFacts.of(note).title.trim();
  return title.isEmpty ? 'Untitled' : title;
}

/// [handle]'s page over [notes] (the organization's, out of the trash), [changes] (their versions, any order) and
/// [seen] (who the organization's room says is here, by device; an AI is never the member).
MemberFacts memberFacts({required String handle, required Iterable<Note> notes, Iterable<Change> changes = const [], Iterable<OrgPresence> seen = const []}) {
  final key = handleKey(handle);
  final tickets = <MemberTicket>[];
  final owned = <Note>[];
  final titles = <String, String>{};
  for (final note in notes) {
    if (note.inTrash || (note.archivedAt ?? 0) != 0) continue;
    titles[note.id] = _titleOf(note);
    final body = note.body;
    if (isTicket(body)) {
      final ticket = ticketOf(body);
      final assignee = ticket?.assignee;
      if (ticket != null && assignee != null && handleKey(handleOf(assignee) ?? assignee) == key && ticket.category != StatusCategory.done) {
        tickets.add((note: note, title: titles[note.id]!, ticket: ticket));
      }
    }
    if (ownedBy(body, handle)) owned.add(note);
  }
  tickets.sort((a, b) {
    final ad = a.ticket.due, bd = b.ticket.due;
    if (ad != bd) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    final p = priorityRank(a.ticket.priority).compareTo(priorityRank(b.ticket.priority));
    return p != 0 ? p : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  owned.sort((a, b) => _titleOf(a).toLowerCase().compareTo(_titleOf(b).toLowerCase()));

  final theirs = [for (final change in changes) if (titles.containsKey(change.noteId) && handleKey(change.by) == key) change]..sort(newestFirst);
  final pages = <String>{};
  final edits = <MemberEdit>[
    for (final change in theirs)
      if (pages.add(change.noteId)) (change: change, title: titles[change.noteId]!),
  ];

  OrgPresence? at;
  var online = false;
  for (final device in seen) {
    if (device.ai || handleKey(device.handle) != key) continue;
    online = true;
    if (device.editingNote != null) {
      at = device;
      break;
    }
  }
  final editing = at == null ? null : ((at.editingTitle ?? '').isNotEmpty ? at.editingTitle : titles[at.editingNote] ?? 'an untitled note');
  return MemberFacts(handle: handle, tickets: List.unmodifiable(tickets), owned: List.unmodifiable(owned), edits: List.unmodifiable(edits.take(memberEditsShown)), online: online, editing: editing);
}
