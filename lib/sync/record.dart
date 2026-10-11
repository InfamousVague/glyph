/// A notification the app makes for itself (docs/TEAMS.md, D2): a meeting written up, a note kept twice by a sync.
/// A port of `src/app/core/notifications/record.ts`.
///
/// Sealed under the account key with the kind inside, as `notification:<id>`, and posted to the account so every
/// device lists it; the row is in the feed here before the post is made, and stays listed as unsent if the post
/// does not land - offline, or a service without the route yet - for the next pass to send again (feed.dart). The
/// post is idempotent, so a retry after a lost answer makes no second row.
///
/// Nothing is recorded without an account and its key: the feed is the account's. With "Nothing leaves the phone"
/// on, the row is kept here and never sent.
///
/// What differs: the page's `record(kind, details)` reads the account, the preferences and the feed as modules;
/// here it is [SelfNotifications.record], made with the feed (and through it the account and the crypto), the
/// [Api] and a way to ask whether nothing leaves the phone. The details are the map that is sealed, where the page
/// has a type per kind.
library;

import '../account/api.dart';
import '../core/ids.dart';
import '../core/notifications.dart';
import 'feed.dart';

/// Records the notifications this device makes for the account (`record`).
class SelfNotifications {
  /// [localOnly] answers the "Nothing leaves the phone" preference; [now] the time in ms.
  SelfNotifications({required this.feed, required this.api, bool Function()? localOnly, int Function()? now})
      : _localOnly = localOnly ?? (() => false),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NotificationFeed feed;
  final Api api;
  final bool Function() _localOnly;
  final int Function() _now;

  /// Records one self notification of [kind] (one of `selfKinds`) with what that kind says ([details]: `noteId`,
  /// `title`, and the kind's own fields). Never throws: a failure to post leaves the row unsent for the next pass.
  /// [api] and [now] stand in for the ones this was made with.
  Future<void> record(String kind, Map<String, Object?> details, {Api? api, int Function()? now}) async {
    final account = feed.account;
    final session = account.session;
    if (session == null) return;
    final payload = <String, Object?>{'kind': kind, ...details};
    final opened = NotificationDetails.fromJson(payload);
    // Not a kind this app makes, or no note and title to say: nothing any device could draw.
    if (opened == null) return;
    final String blob;
    final id = shortId();
    try {
      final key = await account.accountKey();
      if (key == null) return;
      blob = await feed.crypto.seal(key, payload, 'notification:$id');
    } catch (_) {
      return;
    }
    final item = FeedNotification(id: id, rev: 0, kind: kind, at: (now ?? _now)(), blob: blob);
    feed.rememberDetails(id, opened);
    feed.updateFeed(session.accountId, (state) => withSelfRow(state, item));
    if (_localOnly()) return;
    try {
      final rev = await postSelfRow(api ?? this.api, session.token, item);
      feed.updateFeed(session.accountId, (state) => withPosted(state, id, rev));
    } catch (_) {
      // Not sent: listed as unsent, and tried again by the next pass.
    }
  }
}
