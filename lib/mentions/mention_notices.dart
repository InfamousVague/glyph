/// A member named in a team note is told, through the organization's notifications (the bell), once (Matt,
/// 2026-10-30: "add all 12", @mentions of people).
///
/// **Who tells.** The device whose own change wrote the mention, and no other: a team note's document hears every
/// change made here - a key pressed in its editor, words that reached the note without it, an undo - apart from
/// what the log brought (lib/team/doc.dart `TeamDocs.onMade`), and [MentionLedger.made] counts each person's
/// mentions before and after it. A count that grew is a mention owed its notice. What another member, or this
/// account's other device, wrote arrives by the log and is never this device's to tell.
///
/// **When.** After the organization's pass that sent the change (lib/team/sync.dart), so the note the notice opens
/// already has the words ([mentionsAfter]). An owed mention is checked against the note as it is then: one typed and
/// taken back (`@sa` on the way to `@sam`, or a name deleted) is not there, and is dropped untold.
///
/// **Once.** A mention is known by the organization, the note, the person and which of their mentions in the note it
/// is - the first `@sam`, the second ([mentionId]) - the same on every device, so the service, which writes a row in
/// the person's feed by that id only once (server/src/notifications.rs), never tells them twice, from a retry or from
/// two devices; and the ids sent are kept here too, so a mention deleted and typed again is not posted again. The
/// team's document has no metadata beside its words to keep them in, so they are this device's own, per account
/// (`glyph-mentions-<account>`).
///
/// **Sealed.** The words - the note, its title, the line, who wrote it - are sealed under the organization key at the
/// generation the pass holds, as `mention:<org>:<id>`, which every member holds and the service does not; the
/// service sees who sent it, who it is for and the organization, as it already does for a team's notes.
///
/// A day mentioned is remembered as this device's own writing too ([MentionLedger.wroteDay]), so its reminder is the
/// writer's (lib/mentions/mention_reminders.dart).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/bytes.dart';
import '../core/stored.dart';
import '../sync/engine.dart' show TeamNotesPass, TeamPass;
import 'mention_syntax.dart';

/// How long a mention may wait for its notice: a service without the route yet, or a device that stays offline.
const Duration owedFor = Duration(days: 7);

/// How many ids a device keeps of mentions it has told, per account: the oldest go past it.
const int keptSent = 2000;

/// The longest line a notice carries.
const int lineShown = 120;

/// A person's mention made here and not told yet.
@immutable
class OwedMention {
  const OwedMention({required this.orgId, required this.noteId, required this.handle, required this.n, required this.made});

  static OwedMention? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final org = raw['org'], note = raw['note'], handle = raw['handle'], n = raw['n'], made = raw['made'];
    if (org is! String || note is! String || handle is! String || n is! num || made is! num) return null;
    return OwedMention(orgId: org, noteId: note, handle: handle, n: n.toInt(), made: made.toInt());
  }

  final String orgId;
  final String noteId;

  /// As [handleKey] keeps it: lower case.
  final String handle;

  /// Which of the person's mentions in the note it is, counting from 1.
  final int n;

  /// When it was written, in ms.
  final int made;

  Map<String, Object?> toJson() => {'org': orgId, 'note': noteId, 'handle': handle, 'n': n, 'made': made};

  @override
  bool operator ==(Object other) => other is OwedMention && other.orgId == orgId && other.noteId == noteId && other.handle == handle && other.n == n;

  @override
  int get hashCode => Object.hash(orgId, noteId, handle, n);

  @override
  String toString() => 'OwedMention(@$handle #$n in $noteId)';
}

/// A mention's id: the same on every device, for the same organization, note, person and place among their mentions
/// there; 32 characters of base64url (the service takes 1 to 64).
String mentionId(String orgId, String noteId, String handle, int n) {
  final digest = hashes.sha256.convert(utf8.encode('mention\u0000$orgId\u0000$noteId\u0000${handleKey(handle)}\u0000$n')).bytes;
  return toBase64Url(digest.sublist(0, 24));
}

/// The context a mention's words are sealed under: the organization and the id, so a blob moved to another row or
/// another organization does not open.
String mentionContext(String orgId, String id) => 'mention:$orgId:$id';

/// Each person's mentions in [words], by [handleKey], and each day's.
({Map<String, int> people, Map<String, int> days}) _counts(String words) {
  final people = <String, int>{}, days = <String, int>{};
  for (final found in mentionsInBody(words)) {
    final mention = found.mention;
    if (mention.person) {
      people.update(handleKey(mention.value), (n) => n + 1, ifAbsent: () => 1);
    } else if (dayWords.contains(mention.value.toLowerCase()) == false) {
      days.update(mention.value, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return (people: people, days: days);
}

/// What this device keeps of its mentions, for one account.
@immutable
class MentionState {
  const MentionState({this.owed = const [], this.sent = const [], this.days = const {}});

  static const MentionState empty = MentionState();

  static MentionState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final owed = raw['owed'], sent = raw['sent'], days = raw['days'];
    return MentionState(
      owed: [
        if (owed is List)
          for (final each in owed) ?OwedMention.fromJson(each),
      ],
      sent: [
        if (sent is List)
          for (final id in sent)
            if (id is String) id,
      ],
      days: {
        if (days is Map)
          for (final MapEntry(:key, :value) in days.entries)
            if (key is String && value is List) key: [for (final day in value) if (day is String) day],
      },
    );
  }

  final List<OwedMention> owed;

  /// The ids told, oldest first.
  final List<String> sent;

  /// The days this device wrote as mentions, by note.
  final Map<String, List<String>> days;

  Map<String, Object?> toJson() => {'owed': [for (final each in owed) each.toJson()], 'sent': sent, 'days': days};
}

String _key(int accountId) => 'glyph-mentions-$accountId';

/// The mentions this device made and what it has told of them, per account.
class MentionLedger {
  MentionLedger({Stored? kept, int Function()? now})
      : _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Stored? _kept;
  final int Function() _now;
  Stored get _device => _kept ?? stored;
  final Map<int, MentionState> _held = {};

  /// The time, in ms, by this ledger's clock.
  int now() => _now();

  MentionState state(int accountId) => _held[accountId] ??= _device.read<MentionState>(_key(accountId), MentionState.empty, MentionState.fromJson);

  void _save(int accountId, MentionState next) {
    _held[accountId] = next;
    _device.write(_key(accountId), next.toJson());
  }

  /// A change made here to a team note of [orgId]'s, from [before] to [after]: each person's mention that the change
  /// added is owed its notice, and each day it added is this device's writing. Nothing is read where the change could
  /// not have added one: no at sign after it, or the words the same.
  void made(int accountId, String orgId, String noteId, String before, String after) {
    if (before == after || !after.contains('@')) return;
    final was = _counts(before), now = _counts(after);
    final owed = <OwedMention>[];
    final at = _now();
    for (final MapEntry(key: handle, value: count) in now.people.entries) {
      final had = was.people[handle] ?? 0;
      for (var n = had + 1; n <= count; n += 1) {
        owed.add(OwedMention(orgId: orgId, noteId: noteId, handle: handle, n: n, made: at));
      }
    }
    final days = [
      for (final MapEntry(key: day, value: count) in now.days.entries)
        if (count > (was.days[day] ?? 0)) day,
    ];
    if (owed.isEmpty && days.isEmpty) return;
    final held = state(accountId);
    final written = {...held.days};
    if (days.isNotEmpty) written[noteId] = {...?written[noteId], ...days}.toList();
    _save(accountId, MentionState(owed: [...held.owed.where((each) => !owed.contains(each)), ...owed], sent: held.sent, days: written));
  }

  /// The mentions of [orgId]'s notes still owed their notice.
  List<OwedMention> owedIn(int accountId, String orgId) => [for (final each in state(accountId).owed) if (each.orgId == orgId) each];

  /// Whether this device wrote [day] as a mention in [noteId].
  bool wroteDay(int accountId, String noteId, String day) => state(accountId).days[noteId]?.contains(day) ?? false;

  /// An owed mention settled: told, under [id], or dropped (null) as no longer there.
  void settle(int accountId, OwedMention owed, String? id) {
    final held = state(accountId);
    final sent = [...held.sent, ?id];
    _save(accountId, MentionState(owed: [for (final each in held.owed) if (each != owed) each], sent: sent.length > keptSent ? sent.sublist(sent.length - keptSent) : sent, days: held.days));
  }

  bool told(int accountId, String id) => state(accountId).sent.contains(id);

  /// Forgets an account's: for signing out.
  void forget(int accountId) {
    _held.remove(accountId);
    _device.write(_key(accountId), null);
  }
}

/// What a pass over one organization's owed mentions is handed.
class MentionSend {
  const MentionSend({
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

  /// This account's handle: whoever wrote it, in the notice.
  final String me;

  /// A note's words on this device now, or null where it is gone.
  final Future<String?> Function(String noteId) words;
  final String Function(String noteId, String words) title;
}

/// The payload a mention is sealed from: what the person's bell says and where it opens the note.
Map<String, Object?> mentionPayload({required String noteId, required String title, required String by, required String line, required int lineNo}) {
  final first = line.trim();
  return {
    'kind': 'mention',
    'noteId': noteId,
    'title': title,
    'by': by,
    'first': first.length > lineShown ? '${first.substring(0, lineShown - 1)}…' : first,
    'at': 'line:$lineNo',
  };
}

/// Every mention owed in one organization, told: each still in its note sealed and posted, each gone dropped. Answers
/// how many were told. Stops quietly at a service without the route (the mentions wait, up to [owedFor]) and at the
/// minute's limit (the rest go with the next pass); never throws.
Future<int> sendMentions(MentionLedger ledger, MentionSend ctx) async {
  var told = 0;
  final now = ledger.now();
  for (final owed in ledger.owedIn(ctx.accountId, ctx.orgId)) {
    try {
      final words = await ctx.words(owed.noteId);
      final mine = owed.handle == handleKey(ctx.me);
      final found = words == null || mine ? null : [for (final each in mentionsInBody(words)) if (each.mention.person && handleKey(each.mention.value) == owed.handle) each];
      if (words == null || found == null || found.length < owed.n) {
        ledger.settle(ctx.accountId, owed, null);
        continue;
      }
      final id = mentionId(ctx.orgId, owed.noteId, owed.handle, owed.n);
      if (ledger.told(ctx.accountId, id)) {
        ledger.settle(ctx.accountId, owed, null);
        continue;
      }
      final at = found[owed.n - 1];
      final payload = mentionPayload(noteId: owed.noteId, title: ctx.title(owed.noteId, words), by: ctx.me, line: at.text, lineNo: at.line);
      final blob = await ctx.crypto.seal(ctx.key, payload, mentionContext(ctx.orgId, id));
      await ctx.api.call('POST', 'orgs/${Uri.encodeComponent(ctx.orgId)}/mentions', token: ctx.token, body: {
        'id': id,
        'to': [at.mention.value],
        'blob': blob,
        'generation': ctx.generation,
      });
      ledger.settle(ctx.accountId, owed, id);
      told += 1;
    } on ApiError catch (failure) {
      if (failure.status == 429) break;
      // Not yet on the service: kept for a later pass, a week at most.
      if (failure.status == 404 && notYet(failure)) {
        if (now - owed.made > owedFor.inMilliseconds) ledger.settle(ctx.accountId, owed, null);
        break;
      }
      // Refused in the service's words (no longer a member, the organization gone): nothing to tell.
      if (failure.status >= 400 && failure.status < 500) {
        ledger.settle(ctx.accountId, owed, null);
        continue;
      }
      break;
    } catch (_) {
      // Offline, or the seal would not make: tried again with the next pass.
      break;
    }
  }
  return told;
}

/// The organization's pass, then its owed mentions told (see the header): what the engine is handed in place of the
/// channel's own pass. A re-sealing after a turn tells nothing; a pass that throws tells nothing either.
TeamNotesPass mentionsAfter(TeamNotesPass pass, MentionLedger ledger, {required String? Function() me, required Future<String?> Function(String noteId) words, required String Function(String noteId, String words) title}) {
  return (TeamPass team) async {
    final outcome = await pass(team);
    final handle = me();
    if (!team.reseal && handle != null && handle.isNotEmpty && ledger.owedIn(team.accountId, team.org.id).isNotEmpty) {
      await sendMentions(
        ledger,
        MentionSend(accountId: team.accountId, token: team.token, orgId: team.org.id, key: team.key, generation: team.generation, api: team.api, crypto: team.crypto, me: handle, words: words, title: title),
      );
    }
    return outcome;
  };
}
