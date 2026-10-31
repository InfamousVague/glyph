/// A ticket's watchers told in their bell what changed on it (Matt, 2026-10-31: "Watchers are told in their bell when
/// status, assignee or due changes, when a comment is added, or when it's closed. Notifications are batched per ticket
/// within ~2 minutes and sent once across devices, the same way mentions are"). The mentions' road
/// (lib/mentions/mention_notices.dart), taken by a kind of its own:
///
/// **Who tells.** The device whose own change it was, and no other: a team note's document hears what was made here
/// and never what the log brought (lib/team/doc.dart `TeamDocs.onMade`), and [TicketEventLedger.made] reads the
/// ticket before and after it. What another member, or this account's other device, changed arrives by the log and is
/// that device's to tell.
///
/// **A batch per ticket.** The first change to a ticket opens a batch, and every change after it within
/// [batchWindow] joins it: a status moved In progress → In review → Done is told once, as In progress → Done; one
/// moved and moved back is not told at all. The batch is sent by the first organization pass after the window has
/// closed ([ticketEventsAfter]), so the note the bell opens already has the words.
///
/// **To whom.** Its watchers as the note has them then (lib/book/ticket_watchers.dart), and a new assignee besides,
/// who may have been picked from a board rather than the panel: never the person who made the change. The service
/// writes a row only for those who have joined the organization (server/src/notifications.rs `ticket_event`).
///
/// **Once.** A batch is known by the organization, the note, what it says and the window it opened in
/// ([ticketEventId]), the same on every device, so the service, which writes a row in a member's feed by that id only
/// once, never tells them twice: a retry after a lost answer, or the same change owed on two devices. The ids told
/// are kept here too (`glyph-ticket-events-<account>`), since the team's document has nowhere beside its words.
///
/// **Sealed.** What the bell says - the ticket, what changed, who changed it - is sealed under the organization key
/// at the pass's generation as `ticket:<org>:<id>`; the service sees who sent it, to whom and the organization.
///
/// **A service without the route** (an older glyph-api) answers 404: the batch waits, a week at most, as a mention
/// does, so deploying the service after the app loses nothing.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../comments/format.dart' show readComments;
import '../core/bytes.dart';
import '../core/properties.dart';
import '../core/stored.dart';
import '../mentions/mention_syntax.dart' show handleKey;
import '../sync/engine.dart' show TeamNotesPass, TeamPass;
import 'ticket_watchers.dart';

/// How long a ticket's changes gather before they are told together.
const Duration batchWindow = Duration(minutes: 2);

/// How long a batch may wait for its sending: a service without the route yet, or a device that stays offline.
const Duration ticketOwedFor = Duration(days: 7);

/// How many ids of batches told a device keeps, per account.
const int keptTold = 2000;

/// The longest comment a notice quotes.
const int quoted = 80;

/// One property's change in a batch: what it was when the batch opened, and what it is now.
typedef Moved = ({String? from, String? to});

/// One ticket's changes made here and not told yet.
@immutable
class TicketBatch {
  const TicketBatch({required this.orgId, required this.noteId, required this.opened, this.status, this.assignee, this.due, this.comments = 0, this.comment, this.closed = false});

  static TicketBatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final org = raw['org'], note = raw['note'], opened = raw['opened'];
    if (org is! String || note is! String || opened is! num) return null;
    Moved? moved(Object? value) => value is Map ? (from: value['from'] is String ? value['from'] as String : null, to: value['to'] is String ? value['to'] as String : null) : null;
    return TicketBatch(
      orgId: org,
      noteId: note,
      opened: opened.toInt(),
      status: moved(raw['status']),
      assignee: moved(raw['assignee']),
      due: moved(raw['due']),
      comments: raw['comments'] is num ? (raw['comments'] as num).toInt() : 0,
      comment: raw['comment'] is String ? raw['comment'] as String : null,
      closed: raw['closed'] == true,
    );
  }

  final String orgId;
  final String noteId;

  /// When its first change was made, in ms.
  final int opened;
  final Moved? status;
  final Moved? assignee;
  final Moved? due;

  /// How many comments and replies were written, and the last one's words.
  final int comments;
  final String? comment;

  /// Whether the status moved into a done one.
  final bool closed;

  bool get empty => status == null && assignee == null && due == null && comments == 0;

  Map<String, Object?> toJson() {
    Map<String, Object?>? moved(Moved? value) => value == null ? null : {'from': value.from, 'to': value.to};
    return {
      'org': orgId,
      'note': noteId,
      'opened': opened,
      if (status != null) 'status': moved(status),
      if (assignee != null) 'assignee': moved(assignee),
      if (due != null) 'due': moved(due),
      if (comments > 0) 'comments': comments,
      if (comment != null) 'comment': comment,
      if (closed) 'closed': true,
    };
  }

  /// What it says, in a fixed order: what its id is made from, so the same batch has the same id anywhere.
  String get signature => jsonEncode([status?.from, status?.to, assignee?.from, assignee?.to, due?.from, due?.to, comments, closed]);

  @override
  String toString() => 'TicketBatch($noteId ${toJson()})';
}

/// A batch's id: the same on every device for the same organization, note, changes and window; 32 characters of
/// base64url (the service takes 1 to 64).
String ticketEventId(TicketBatch batch) {
  final window = batch.opened ~/ batchWindow.inMilliseconds;
  final digest = hashes.sha256.convert(utf8.encode('ticket\u0000${batch.orgId}\u0000${batch.noteId}\u0000${batch.signature}\u0000$window')).bytes;
  return toBase64Url(digest.sublist(0, 24));
}

/// The context a batch's words are sealed under: the organization and the id, so a blob moved to another row or
/// another organization does not open (lib/sync/feed.dart opens `<kind>:<org>:<id>`).
String ticketEventContext(String orgId, String id) => 'ticket:$orgId:$id';

/// Moved [was] to [now] after [before] had moved it: the first `from`, the last `to`, and null where it is back where
/// it began.
Moved? _joined(Moved? before, String? was, String? now) {
  final from = before == null ? was : before.from;
  if ((from ?? '') == (now ?? '')) return null;
  return (from: from, to: now);
}

String? _clean(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

/// What a change from [before] to [after] did to the ticket, joined to the batch [into] (null to open one at [at]);
/// null where it did nothing a watcher is told of and there was no batch.
TicketBatch? joinChange(TicketBatch? into, {required String orgId, required String noteId, required String before, required String after, required int at}) {
  final was = ticketOf(before), now = ticketOf(after);
  if (now == null) return into;
  final status = _joined(into?.status, _clean(was?.status), _clean(now.status));
  final assignee = _joined(into?.assignee, _clean(was?.assignee), _clean(now.assignee));
  final due = _joined(into?.due, _clean(was?.due), _clean(now.due));
  var comments = into?.comments ?? 0;
  var comment = into?.comment;
  if (after.contains('comments')) {
    final had = _commentsOf(before), has = _commentsOf(after);
    if (has.length > had.length) {
      comments += has.length - had.length;
      comment = has.last;
    }
  }
  final closed = status != null && statusCategory(status.to) == StatusCategory.done && statusCategory(status.from) != StatusCategory.done;
  final batch = TicketBatch(orgId: orgId, noteId: noteId, opened: into?.opened ?? at, status: status, assignee: assignee, due: due, comments: comments, comment: comment, closed: closed);
  if (batch.empty) return into == null ? null : batch;
  return batch;
}

/// Every comment's words in the note, threads and replies, in order.
List<String> _commentsOf(String body) {
  final read = readComments(body);
  return [
    for (final thread in read.threads) ...[thread.head.words, for (final reply in thread.replies) reply.words],
  ];
}

/// What this device keeps of its tickets' batches, for one account.
@immutable
class TicketEventState {
  const TicketEventState({this.owed = const [], this.told = const []});

  static const TicketEventState empty = TicketEventState();

  static TicketEventState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final owed = raw['owed'], told = raw['told'];
    return TicketEventState(
      owed: [
        if (owed is List)
          for (final each in owed) ?TicketBatch.fromJson(each),
      ],
      told: [
        if (told is List)
          for (final id in told)
            if (id is String) id,
      ],
    );
  }

  final List<TicketBatch> owed;

  /// The ids told, oldest first.
  final List<String> told;

  Map<String, Object?> toJson() => {'owed': [for (final each in owed) each.toJson()], 'told': told};
}

String _key(int accountId) => 'glyph-ticket-events-$accountId';

/// The tickets' changes this device made and what it has told of them, per account.
class TicketEventLedger {
  TicketEventLedger({Stored? kept, int Function()? now})
      : _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Stored? _kept;
  final int Function() _now;
  Stored get _device => _kept ?? stored;
  final Map<int, TicketEventState> _held = {};

  int now() => _now();

  TicketEventState state(int accountId) => _held[accountId] ??= _device.read<TicketEventState>(_key(accountId), TicketEventState.empty, TicketEventState.fromJson);

  void _save(int accountId, TicketEventState next) {
    _held[accountId] = next;
    _device.write(_key(accountId), next.toJson());
  }

  /// A change made here to a team note of [orgId]'s, from [before] to [after]: joined to the ticket's open batch, or
  /// a batch opened for it. Nothing is read where the note is no ticket either side, or the words are the same.
  void made(int accountId, String orgId, String noteId, String before, String after) {
    if (before == after || (!isTicket(after) && !isTicket(before))) return;
    final held = state(accountId);
    final at = _now();
    TicketBatch? open;
    for (final each in held.owed) {
      if (each.orgId == orgId && each.noteId == noteId && at - each.opened < batchWindow.inMilliseconds) open = each;
    }
    final next = joinChange(open, orgId: orgId, noteId: noteId, before: before, after: after, at: at);
    if (identical(next, open)) return;
    final owed = [
      for (final each in held.owed)
        if (!identical(each, open)) each,
      if (next != null && !next.empty) next,
    ];
    _save(accountId, TicketEventState(owed: owed, told: held.told));
  }

  /// The batches of [orgId]'s tickets still owed.
  List<TicketBatch> owedIn(int accountId, String orgId) => [for (final each in state(accountId).owed) if (each.orgId == orgId) each];

  /// A batch settled: told under [id], or dropped (null).
  void settle(int accountId, TicketBatch batch, String? id) {
    final held = state(accountId);
    final told = [...held.told, ?id];
    _save(accountId, TicketEventState(owed: [for (final each in held.owed) if (!identical(each, batch) && !(each.noteId == batch.noteId && each.opened == batch.opened)) each], told: told.length > keptTold ? told.sublist(told.length - keptTold) : told));
  }

  bool told(int accountId, String id) => state(accountId).told.contains(id);

  /// Forgets an account's: for signing out.
  void forget(int accountId) {
    _held.remove(accountId);
    _device.write(_key(accountId), null);
  }
}

/// What a batch's notice says under its sentence: each change, in words.
String batchWords(TicketBatch batch) {
  final parts = <String>[];
  final status = batch.status, assignee = batch.assignee, due = batch.due;
  if (status != null) parts.add('${status.from ?? 'No status'} → ${status.to ?? 'no status'}');
  if (assignee != null) parts.add(assignee.to == null ? 'Unassigned' : 'Assigned to ${assignee.to}');
  if (due != null) parts.add(due.to == null ? 'Due date taken off' : 'Due ${due.to}');
  if (batch.comments > 0) {
    final words = (batch.comment ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final said = words.length > quoted ? '${words.substring(0, quoted - 1)}…' : words;
    parts.add(batch.comments == 1 ? (said.isEmpty ? 'A comment' : '“$said”') : '${batch.comments} comments${said.isEmpty ? '' : ': “$said”'}');
  }
  return parts.join(' · ');
}

/// What the batch's notice is, in a word: `closed`, `commented` (only comments), or `changed`.
String batchWhat(TicketBatch batch) {
  if (batch.closed) return 'closed';
  if (batch.status == null && batch.assignee == null && batch.due == null) return 'commented';
  return 'changed';
}

/// The payload a batch is sealed from: what the watcher's bell says and the note it opens.
Map<String, Object?> ticketEventPayload(TicketBatch batch, {required String title, required String by}) => {
      'kind': 'ticket',
      'noteId': batch.noteId,
      'title': title,
      'by': by,
      'first': batchWords(batch),
      'what': batchWhat(batch),
    };

/// What a pass over one organization's owed batches is handed.
class TicketEventSend {
  const TicketEventSend({
    required this.accountId,
    required this.token,
    required this.orgId,
    required this.key,
    required this.generation,
    required this.api,
    required this.crypto,
    required this.me,
    required this.words,
    required this.title,
  });

  final int accountId;
  final String token;
  final String orgId;
  final SealKey key;
  final int generation;
  final Api api;
  final AccountCrypto crypto;

  /// This account's handle: who changed it, in the notice, and never one told.
  final String me;

  /// A note's words on this device now, or null where it is gone.
  final Future<String?> Function(String noteId) words;

  /// What the notice calls the ticket: its key and title, `GHO-12 Fix the login loop`.
  final String Function(String noteId, String words) title;
}

/// Who a batch is told to: the ticket's watchers now and a new assignee, as handles, never [me].
List<String> recipientsOf(TicketBatch batch, String words, String me) {
  final out = <String>[];
  void add(String? handle) {
    final who = handleOf(handle);
    if (who == null || handleKey(who) == handleKey(me) || out.any((each) => handleKey(each) == handleKey(who))) return;
    out.add(who);
  }

  watchersOf(words).forEach(add);
  add(batch.assignee?.to);
  return out.length > 20 ? out.sublist(0, 20) : out;
}

/// Every batch owed in one organization whose window has closed, told: each sealed and posted to the ticket's
/// watchers, each with nobody to tell dropped. Answers how many were told. Stops quietly at a service without the
/// route (the batches wait, up to [ticketOwedFor]) and at the minute's limit; never throws.
Future<int> sendTicketEvents(TicketEventLedger ledger, TicketEventSend ctx) async {
  var told = 0;
  final now = ledger.now();
  for (final batch in ledger.owedIn(ctx.accountId, ctx.orgId)) {
    if (now - batch.opened < batchWindow.inMilliseconds) continue;
    try {
      final words = await ctx.words(batch.noteId);
      if (words == null || !isTicket(words)) {
        ledger.settle(ctx.accountId, batch, null);
        continue;
      }
      final to = recipientsOf(batch, words, ctx.me);
      final id = ticketEventId(batch);
      if (to.isEmpty || ledger.told(ctx.accountId, id)) {
        ledger.settle(ctx.accountId, batch, null);
        continue;
      }
      final payload = ticketEventPayload(batch, title: ctx.title(batch.noteId, words), by: ctx.me);
      final blob = await ctx.crypto.seal(ctx.key, payload, ticketEventContext(ctx.orgId, id));
      await ctx.api.call('POST', 'orgs/${Uri.encodeComponent(ctx.orgId)}/ticket-events', token: ctx.token, body: {'id': id, 'to': to, 'blob': blob, 'generation': ctx.generation});
      ledger.settle(ctx.accountId, batch, id);
      told += 1;
    } on ApiError catch (failure) {
      if (failure.status == 429) break;
      if (failure.status == 404 && notYet(failure)) {
        if (now - batch.opened > ticketOwedFor.inMilliseconds) ledger.settle(ctx.accountId, batch, null);
        break;
      }
      if (failure.status >= 400 && failure.status < 500) {
        ledger.settle(ctx.accountId, batch, null);
        continue;
      }
      break;
    } catch (_) {
      break;
    }
  }
  return told;
}

/// The organization's pass, then its tickets' owed batches told (see the header): wrapped round the pass the engine
/// is handed, as the mentions' is. A re-sealing after a turn tells nothing; a pass that throws tells nothing either.
TeamNotesPass ticketEventsAfter(TeamNotesPass pass, TicketEventLedger ledger, {required String? Function() me, required Future<String?> Function(String noteId) words, required String Function(String noteId, String words) title}) {
  return (TeamPass team) async {
    final outcome = await pass(team);
    final handle = me();
    if (!team.reseal && handle != null && handle.isNotEmpty && ledger.owedIn(team.accountId, team.org.id).isNotEmpty) {
      await sendTicketEvents(
        ledger,
        TicketEventSend(accountId: team.accountId, token: team.token, orgId: team.org.id, key: team.key, generation: team.generation, api: team.api, crypto: team.crypto, me: handle, words: words, title: title),
      );
    }
    return outcome;
  };
}

/// What the notice calls a ticket: its key, then its title.
String ticketNoticeTitle(String words, String title) {
  final key = ticketIdOf(words);
  return key == null ? title : (title.isEmpty || title == key ? key : '$key $title');
}
