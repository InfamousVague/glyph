/// The account's notifications on this device (docs/TEAMS.md, D4): the rows by id, how far along the account's feed
/// this device has read, and what the person did here that the service has not confirmed yet. A port of
/// `src/app/core/notifications/feed.ts`, on the kinds and the list's rules already in lib/core/notifications.dart.
///
/// The feed rides the account's one revision counter, as the notes do: every change to a row - read, hidden, an
/// invitation answered - takes a new revision on the service and the row is fed again, hidden rows included, and a
/// device takes a fed row only when its revision is above the copy it holds. So reading a row on the phone reaches
/// the Mac by the next pass, and nothing is ever fed twice at the same revision.
///
/// What the person does here is applied at once and queued as a MARK, replayed at the start of the next pass
/// ([syncNotifications]) and dropped once the service confirms it. While a mark is pending, the local state wins
/// over any fed row that still lacks it: a page fetched before the mark landed would otherwise undo it. "Mark all
/// read" carries the cursor it was pressed at, so it marks only what this device had shown. A self row this device
/// recorded (record.dart) is shown at once with revision 0 and listed as UNSENT until its post lands, which the next
/// pass tries again; the post is idempotent, so a lost answer costs nothing.
///
/// A sealed row is opened LAZILY, at draw time ([NotificationFeed.openDetails]), memoised by id, and never in the
/// pass: a row that will not open - sealed by a newer build, say - is drawn by its kind alone and never stalls the
/// feed or moves the cursor short. The unread count reads the plaintext fields only, so the bell is right before
/// anything is opened.
///
/// What differs:
/// - The page's module is [NotificationFeed], made with the account ([AccountSource]), the crypto and this device's
///   memory, and a [Listenable] where the page has `onNotifications`. The state's rules (`withMark`, `withFed`,
///   `withSelfRow`) are functions here too, and the pass is [syncNotifications] over a [NotificationsContext].
/// - `listed`, `isWanted` and `unreadCount` were ported with the kinds (lib/core/notifications.dart) and take the
///   rows; [NotificationFeed.notifications] is what the page passes them by default.
/// - An invitation's answer goes to the service through the context's `answerInvite`. On the page that is
///   `postInviteAnswer` (core/orgs/orgs.ts), which also keeps the organization's row and makes its workspace; the
///   organizations are not ported yet (docs/STAGE7.md, piece H), so by default it is the bare call, and H hands in
///   its own.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/session.dart';
import '../core/notifications.dart';
import '../core/stored.dart';

// --- what this device keeps ------------------------------------------------------------------------------------------

/// Something the person did here, not yet confirmed by the service (`Mark`).
@immutable
sealed class Mark {
  const Mark();

  /// A mark as kept, or null for a shape that is none (`asMark`).
  static Mark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], org = raw['org'], answer = raw['answer'], before = raw['before'];
    if (id is String) return RowMark(id, read: raw['read'] == true, hidden: raw['hidden'] == true);
    if (raw['all'] == true && before is num) return AllMark(before.toInt());
    if (org is String && answer is bool) return InviteMark(org, answer: answer);
    return null;
  }

  Map<String, Object?> toJson();
}

/// One row read, or hidden (`{ id, read?, hidden? }`).
class RowMark extends Mark {
  const RowMark(this.id, {this.read = false, this.hidden = false});
  final String id;
  final bool read;
  final bool hidden;

  @override
  Map<String, Object?> toJson() => {'id': id, if (read) 'read': true, if (hidden) 'hidden': true};

  @override
  bool operator ==(Object other) => other is RowMark && other.id == id && other.read == read && other.hidden == hidden;

  @override
  int get hashCode => Object.hash(id, read, hidden);

  @override
  String toString() => 'RowMark($id${read ? ', read' : ''}${hidden ? ', hidden' : ''})';
}

/// Every row this device had been fed by [before] read (`{ all, before }`).
class AllMark extends Mark {
  const AllMark(this.before);
  final int before;

  @override
  Map<String, Object?> toJson() => {'all': true, 'before': before};

  @override
  bool operator ==(Object other) => other is AllMark && other.before == before;

  @override
  int get hashCode => Object.hash(AllMark, before);

  @override
  String toString() => 'AllMark(before $before)';
}

/// An invitation to an organization answered (`{ org, answer }`).
class InviteMark extends Mark {
  const InviteMark(this.org, {required this.answer});
  final String org;
  final bool answer;

  @override
  Map<String, Object?> toJson() => {'org': org, 'answer': answer};

  @override
  bool operator ==(Object other) => other is InviteMark && other.org == org && other.answer == answer;

  @override
  int get hashCode => Object.hash(org, answer);

  @override
  String toString() => 'InviteMark($org, ${answer ? 'accepted' : 'declined'})';
}

/// The feed as this device keeps it for one account (`FeedState`). Replaced, never changed in place.
@immutable
class FeedState {
  const FeedState({this.cursor = 0, this.items = const {}, this.marks = const [], this.unsent = const []});

  /// Nothing read yet (`emptyFeed`).
  static const FeedState empty = FeedState();

  /// A feed as kept, or null for something that is not one (`asFeed`). A row of a shape this build does not read is
  /// left out; a row of a kind it does not know is kept, and not drawn.
  static FeedState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final items = <String, FeedNotification>{};
    final held = raw['items'];
    if (held is Map) {
      for (final each in held.values) {
        final item = FeedNotification.fromJson(each);
        if (item != null) items[item.id] = item;
      }
    }
    final marks = raw['marks'], unsent = raw['unsent'], cursor = raw['cursor'];
    return FeedState(
      cursor: cursor is num ? cursor.toInt() : 0,
      items: items,
      marks: [
        if (marks is List)
          for (final each in marks) ?Mark.fromJson(each),
      ],
      unsent: [
        if (unsent is List)
          for (final id in unsent)
            if (id is String && items.containsKey(id)) id,
      ],
    );
  }

  /// The last revision of the account's feed this device has read.
  final int cursor;
  final Map<String, FeedNotification> items;

  /// Oldest first.
  final List<Mark> marks;

  /// Self rows made here whose post has not landed, by id.
  final List<String> unsent;

  FeedState copyWith({int? cursor, Map<String, FeedNotification>? items, List<Mark>? marks, List<String>? unsent}) =>
      FeedState(cursor: cursor ?? this.cursor, items: items ?? this.items, marks: marks ?? this.marks, unsent: unsent ?? this.unsent);

  Map<String, Object?> toJson() => {
        'cursor': cursor,
        'items': {for (final MapEntry(:key, :value) in items.entries) key: value.toJson()},
        'marks': [for (final mark in marks) mark.toJson()],
        'unsent': unsent,
      };
}

String _stateKey(int accountId) => 'glyph-sync-$accountId-notifications';

/// A row at another revision: the one field `FeedNotification.copyWith` does not change.
FeedNotification _atRev(FeedNotification n, int rev) =>
    FeedNotification(id: n.id, rev: rev, kind: n.kind, at: n.at, readAt: n.readAt, hidden: n.hidden, from: n.from, org: n.org, body: n.body, blob: n.blob, state: n.state);

// --- the rules, as functions of a state ------------------------------------------------------------------------------

/// Whether a mark covers a row: what the local state says about it that the service has not confirmed (`covers`).
bool _covers(Mark mark, FeedNotification item) => switch (mark) {
      RowMark(:final id) => id == item.id,
      AllMark(:final before) => item.rev <= before,
      InviteMark(:final org) => item.kind == 'invite' && item.org?.id == org && item.state == 'pending',
    };

/// The row with a mark applied (`marked`).
FeedNotification _marked(FeedNotification item, Mark mark, int now) => switch (mark) {
      InviteMark(:final answer) => item.copyWith(state: answer ? 'accepted' : 'declined', readAt: () => item.readAt ?? now),
      AllMark() => item.copyWith(readAt: () => item.readAt ?? now),
      RowMark(:final read, :final hidden) => item.copyWith(readAt: read && item.readAt == null ? () => now : null, hidden: hidden ? true : null),
    };

/// Whether two marks say the same thing, so the later replaces the earlier (`sameMark`).
bool _sameMark(Mark a, Mark b) => switch ((a, b)) {
      (RowMark(), RowMark()) => a == b,
      (AllMark(), AllMark()) => true,
      (InviteMark(org: final one), InviteMark(org: final other)) => one == other,
      _ => false,
    };

/// The state with a mark applied to every row it covers, and queued for the service (`withMark`).
FeedState withMark(FeedState state, Mark mark, int now) {
  final items = {...state.items};
  for (final item in state.items.values) {
    if (_covers(mark, item)) items[item.id] = _marked(item, mark, now);
  }
  return state.copyWith(items: items, marks: [...state.marks.where((m) => !_sameMark(m, mark)), mark]);
}

/// The state without a mark the service has confirmed, or answered for (`withoutMark`): that very mark, not one
/// like it made since.
FeedState _withoutMark(FeedState state, Mark mark) => state.copyWith(marks: [for (final m in state.marks) if (!identical(m, mark)) m]);

/// The state with a fed row (`withFed`): taken when its revision is above the copy held, with every pending mark
/// laid over it again, so a page fetched before a mark landed cannot undo it. A self row it answers for is no
/// longer unsent. The same state, itself, when the row is not taken.
FeedState withFed(FeedState state, FeedNotification item, int now) {
  final held = state.items[item.id];
  if (held != null && held.rev >= item.rev) return state;
  var next = item;
  for (final mark in state.marks) {
    if (_covers(mark, next)) next = _marked(next, mark, now);
  }
  return state.copyWith(items: {...state.items, item.id: next}, unsent: [for (final id in state.unsent) if (id != item.id) id]);
}

/// The state with a self row made here, shown now and sent by the next pass if the post does not land first
/// (`withSelfRow`).
FeedState withSelfRow(FeedState state, FeedNotification item) =>
    state.copyWith(items: {...state.items, item.id: item}, unsent: [for (final id in state.unsent) if (id != item.id) id, item.id]);

/// The state with a self row's post landed at [rev]: no longer unsent. The state as it is when the row has gone.
FeedState withPosted(FeedState state, String id, int rev) {
  final held = state.items[id];
  if (held == null) return state;
  return state.copyWith(items: {...state.items, id: _atRev(held, rev)}, unsent: [for (final other in state.unsent) if (other != id) other]);
}

/// A state's rows as the page lists them: of a kind this build knows, not hidden, newest first (`listed(state)`).
List<FeedNotification> listedIn(FeedState state) => listed(state.items.values);

// --- what the page reads ---------------------------------------------------------------------------------------------

/// The feed of whoever is signed in, kept on this device, and what the person does to it here (`feedState`,
/// `saveFeed`, `notifications`, `markRead`, `openDetails` and the rest). Tells its listeners after every change to
/// the feed, after a sealed row opens, and after the account changes (`onNotifications`).
class NotificationFeed extends ChangeNotifier {
  /// [kept] is this device's memory, the app's own unless given; [now] the time in ms.
  NotificationFeed({required this.account, required this.crypto, Stored? kept, int Function()? now})
      : _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    account.addListener(notifyListeners);
  }

  final AccountSource account;
  final AccountCrypto crypto;
  final Stored? _kept;
  final int Function() _now;
  Stored get _device => _kept ?? stored;

  ({int accountId, FeedState state})? _cache;
  ({FeedState state, List<FeedNotification> list})? _snapshot;

  /// The feed this device keeps for an account: read from storage once, then held (`feedState`).
  FeedState feedState(int accountId) {
    final cache = _cache;
    if (cache != null && cache.accountId == accountId) return cache.state;
    final state = _device.read<FeedState>(_stateKey(accountId), FeedState.empty, FeedState.fromJson);
    _cache = (accountId: accountId, state: state);
    return state;
  }

  /// Keeps the feed for an account: on this device for the next launch, and for everything watching it now
  /// (`saveFeed`).
  void saveFeed(int accountId, FeedState state) {
    _cache = (accountId: accountId, state: state);
    _device.write(_stateKey(accountId), state.toJson());
    notifyListeners();
  }

  /// The feed changed by [change], which runs on the state as it is at that moment, so nothing done meanwhile is
  /// lost (`updateFeed`).
  void updateFeed(int accountId, FeedState Function(FeedState state) change) => saveFeed(accountId, change(feedState(accountId)));

  /// Forgets the feed this device kept of an account: for signing out (`forgetNotifications`).
  void forgetNotifications(int accountId) {
    if (_cache?.accountId == accountId) _cache = null;
    _device.write(_stateKey(accountId), null);
    notifyListeners();
  }

  /// The rows of the account signed in now, as the page lists them; none signed out. The same list until something
  /// changes (`notifications`).
  List<FeedNotification> notifications() {
    final session = account.session;
    if (session == null) return const [];
    final state = feedState(session.accountId);
    final snapshot = _snapshot;
    if (snapshot != null && identical(snapshot.state, state)) return snapshot.list;
    final list = List<FeedNotification>.unmodifiable(listedIn(state));
    _snapshot = (state: state, list: list);
    return list;
  }

  /// A change made here, for the account signed in now; nothing signed out (`markHere`).
  void _markHere(Mark mark) {
    final session = account.session;
    if (session == null) return;
    updateFeed(session.accountId, (state) => withMark(state, mark, _now()));
  }

  void markRead(String id) => _markHere(RowMark(id, read: true));

  /// Every row this device holds read: those at or below the highest revision it has been fed, which is what the
  /// drawer shows (`markAllRead`). It was the cursor alone, and a row held above the cursor - fed by a page whose
  /// cursor never landed - stayed unread through every press (Matt: "I cant clear out old notifications from 17
  /// mins ago and older").
  void markAllRead() {
    final session = account.session;
    if (session == null) return;
    final state = feedState(session.accountId);
    var highest = state.cursor;
    for (final item in state.items.values) {
      if (item.rev > highest) highest = item.rev;
    }
    _markHere(AllMark(highest));
  }

  /// One row cleared out of the list: hidden here at once, and on every device once the service has the mark
  /// (`hide`).
  void hide(String id) => _markHere(RowMark(id, hidden: true));

  /// Rows cleared out of the list together, as one change: the drawer's Clear all (`hideAll`). The service hides a
  /// row at a time (`PUT notifications/{id}`), so each is its own mark, replayed by the next pass.
  void hideAll(List<String> ids) {
    final session = account.session;
    if (session == null || ids.isEmpty) return;
    final now = _now();
    updateFeed(session.accountId, (state) => ids.fold(state, (next, id) => withMark(next, RowMark(id, hidden: true), now)));
  }

  /// The invitation to an organization answered: its row says so at once, and the answer is replayed by the next
  /// pass (`answerInvite`). Answered from another device already, the service's 404 is read as done.
  void answerInvite(String orgId, bool accept) => _markHere(InviteMark(orgId, answer: accept));

  // --- opening a sealed row ----------------------------------------------------------------------------------------

  /// What each sealed row opened to, by id: null for one that would not open, and is drawn by its kind.
  final Map<String, NotificationDetails?> _opened = {};
  final Set<String> _opening = {};
  int _openings = 0;

  /// Remembers what a row made here was sealed from, so it is never opened again (`rememberDetails`).
  void rememberDetails(String id, NotificationDetails details) => _opened[id] = details;

  Future<NotificationDetails?> _open(String id, String blob) async {
    try {
      final key = await account.accountKey();
      if (key == null) return null;
      return NotificationDetails.fromJson(await crypto.open(key, blob, 'notification:$id'));
    } catch (_) {
      // Sealed by a newer build, moved from another id, or no key here: drawn by its kind.
      return null;
    }
  }

  /// A sealed row's details, once this device has opened it; null before then, or for a row that will not open
  /// (`openDetails`). The first ask starts the open and the feed's listeners hear when it lands, so a row drawn by
  /// its kind is redrawn with its words a moment later. Never throws, never waits.
  NotificationDetails? openDetails(FeedNotification n) {
    final blob = n.blob;
    if (blob == null || blob.isEmpty) return null;
    if (_opened.containsKey(n.id)) return _opened[n.id];
    if (_opening.add(n.id)) {
      final round = _openings;
      unawaited(() async {
        final details = await _open(n.id, blob);
        // Forgotten while it was opening (signed out): what it opened to is nobody's now.
        if (round != _openings || _disposed) return;
        _opened[n.id] = details;
        _opening.remove(n.id);
        notifyListeners();
      }());
    }
    return null;
  }

  /// A sealed row's details, waited for: what [openDetails] starts, for a caller that needs the words now - a phone
  /// notification posted for the row (`detailsFor`). Null for a plaintext row or one that will not open.
  Future<NotificationDetails?> detailsFor(FeedNotification n) async {
    final blob = n.blob;
    if (blob == null || blob.isEmpty) return null;
    if (_opened.containsKey(n.id)) return _opened[n.id];
    final details = await _open(n.id, blob);
    _opened[n.id] = details;
    return details;
  }

  /// Forgets what was opened: for a test, or for signing out (`forgetOpened`).
  void forgetOpened() {
    _opened.clear();
    _opening.clear();
    _openings += 1;
  }

  // --- the pass, for the account signed in -------------------------------------------------------------------------

  /// What [syncNotifications] is handed to pass over [accountId]'s feed as this device keeps it.
  NotificationsContext contextFor(int accountId, {required String token, required Api api, int? limit, InviteAnswer? answerInvite}) => NotificationsContext(
        token: token,
        api: api,
        read: () => feedState(accountId),
        update: (change) => updateFeed(accountId, change),
        now: _now,
        limit: limit,
        answerInvite: answerInvite,
      );

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    account.removeListener(notifyListeners);
    super.dispose();
  }
}

// --- the pass --------------------------------------------------------------------------------------------------------

/// Sends an invitation's answer to the service: `POST orgs/{id}/invite` (`postInviteAnswer`, core/orgs/orgs.ts).
typedef InviteAnswer = Future<void> Function(String orgId, bool accept);

/// What one pass works with (`NotificationsContext`).
class NotificationsContext {
  const NotificationsContext({required this.token, required this.api, required this.read, required this.update, this.now, this.limit, this.answerInvite});
  final String token;
  final Api api;

  /// The feed as it is now: read again at every step, since the page may have marked a row meanwhile.
  final FeedState Function() read;

  /// The feed changed by a function, run on the state as it is at that moment.
  final void Function(FeedState Function(FeedState state) change) update;

  /// The time, in ms: swapped in by the tests.
  final int Function()? now;

  /// Rows per page, 1 to 200.
  final int? limit;

  /// How an invitation's answer reaches the service; the bare call when none is given (see the header).
  final InviteAnswer? answerInvite;
}

/// A self row posted: the service's revision for it, which is the one it already has if the id was posted before
/// (`postSelfRow`).
Future<int> postSelfRow(Api api, String token, FeedNotification item) async {
  final answer = await api.callMap('POST', 'notifications', token: token, body: {'id': item.id, 'kind': item.kind, 'blob': item.blob});
  final rev = answer['rev'];
  return rev is num ? rev.toInt() : 0;
}

/// A mark sent to the service as the route it stands for (`send`).
Future<void> _send(NotificationsContext ctx, Mark mark) async {
  switch (mark) {
    case InviteMark(:final org, :final answer):
      final custom = ctx.answerInvite;
      if (custom != null) return custom(org, answer);
      await ctx.api.call('POST', 'orgs/${Uri.encodeComponent(org)}/invite', token: ctx.token, body: {'accept': answer});
    case AllMark(:final before):
      await ctx.api.call('POST', 'notifications/read', token: ctx.token, body: {'all': true, 'before': before});
    case RowMark(:final id, :final read, :final hidden):
      await ctx.api.call('PUT', 'notifications/${Uri.encodeComponent(id)}', token: ctx.token, body: {if (read) 'read': true, if (hidden) 'hidden': true});
  }
}

/// The service does not have the route yet, which ends the pass quietly.
class _NotYet implements Exception {
  const _NotYet();
}

/// Runs [ask]; a refusal that is the route missing becomes [_NotYet], and every other failure is thrown as it is
/// (`.catch(surfaced)`).
Future<T> _surfaced<T>(Future<T> Function() ask) async {
  try {
    return await ask();
  } catch (failure) {
    if (notYet(failure)) throw const _NotYet();
    rethrow;
  }
}

/// One pass over the feed (`syncNotifications`): every pending mark replayed, every unsent self row posted, then
/// the feed read from the cursor to its head. Answers whether the service has the routes: false, and nothing
/// changed, when it does not yet. A 404 in the service's words for a mark - "You were not invited.", an answer
/// given elsewhere - drops the mark and goes on; every other failure is thrown as it is, with the marks and the
/// unsent rows kept for the next pass.
Future<bool> syncNotifications(NotificationsContext ctx) async {
  final now = ctx.now ?? () => DateTime.now().millisecondsSinceEpoch;
  try {
    for (final mark in [...ctx.read().marks]) {
      try {
        await _send(ctx, mark);
      } catch (failure) {
        if (notYet(failure)) throw const _NotYet();
        if (failure is! ApiError || failure.status != 404) rethrow;
      }
      ctx.update((state) => _withoutMark(state, mark));
    }
    for (final id in [...ctx.read().unsent]) {
      final item = ctx.read().items[id];
      if (item == null) {
        ctx.update((state) => state.copyWith(unsent: [for (final held in state.unsent) if (held != id) held]));
        continue;
      }
      final rev = await _surfaced(() => postSelfRow(ctx.api, ctx.token, item));
      ctx.update((state) => withPosted(state, id, rev));
      // Read or hidden here before the post landed: the service learns that too, or its copy would come back unread.
      final sent = ctx.read().items[id];
      if (sent != null && (sent.readAt != null || sent.hidden)) {
        await _surfaced(() => _send(ctx, RowMark(id, read: sent.readAt != null, hidden: sent.hidden)));
      }
    }
    for (;;) {
      final since = ctx.read().cursor;
      final limit = (ctx.limit ?? 100).clamp(1, 200);
      final page = await _surfaced(() => ctx.api.callMap('GET', 'notifications?since=$since&limit=$limit', token: ctx.token));
      final rev = page['rev'];
      ctx.update((state) {
        var next = state;
        final items = page['items'];
        if (items is List) {
          for (final raw in items) {
            final item = FeedNotification.fromJson(raw);
            if (item != null) next = withFed(next, item, now());
          }
        }
        return rev is num && rev > next.cursor ? next.copyWith(cursor: rev.toInt()) : next;
      });
      if (page['more'] != true) return true;
    }
  } on _NotYet {
    return false;
  }
}
