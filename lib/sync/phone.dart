/// The bell's rows as the phone's own notifications (docs/TEAMS.md "On the phone"). A port of
/// `src/app/core/notifications/phone.ts`. Matt: "also send notifications as actual phone notifications too".
///
/// Two roads, one gate. While the app runs in the background, the rows a sync brings are posted from here
/// ([PhoneNotices.postNewRows]), in their own words, since the app holds the account key a Claude row is sealed
/// under. While the app is closed, the phone's own worker reads the feed every fifteen minutes or so with the
/// session this hands it ([PhoneNotices.syncWatch]), and words a sealed row by its kind. The phone posts each row
/// once whichever road reaches it first (notices/NoticeAlerts.kt `post`).
///
/// What comes to the phone is what the bell counts ([isWanted]): team news, invitations waiting for an answer, and
/// Claude's changes, by the same switches and mutes. A meeting written up already has its own phone notification
/// (Recording), and a note kept twice is this device's own doing, so neither is posted again here. Nothing is
/// posted with the app in front, where the bell is in view, nor from a device's first look at the feed, which would
/// post its whole history.
///
/// On or off per phone, not synced: the switch on Settings › Notifications says whether this phone posts them, on
/// unless it was turned off. Nothing here does anything on a desktop, an iPhone, or an Android build from before
/// the phone's half ([NoticesHost] answers null there).
///
/// What differs:
/// - The page's module is [PhoneNotices], made once with what the module reached for: the phone
///   ([NoticesHost]), the account, the feed, the preferences, this device's memory, and where the service is. There
///   is no default service: [PhoneNotices.base] is the one the build was given (`GHOST_API`), so a build with no
///   account service makes none of this, and a build that is not a release is never handed the real one
///   (lib/root/account_wiring.dart `accountBase`; the phone's half refuses it again, NoticeAlerts.kt `mayAsk`).
/// - The phone answers a moment later, not at once: the watch is handed one at a time in the order asked
///   ([PhoneNotices.syncWatch]), and `usePhoneNotices` is [PhoneNotices.shown], with the object itself a
///   [Listenable] for the switch.
/// - The engine does not name this module: it hears a pass's rows through `onArrived` (arrived.dart), and the
///   account and the preferences by listening ([PhoneNotices.start]), which is what `engine.ts` did by calling
///   `postNewRows` and `syncPhoneWatch` after each look at the feed, on a change of the switches, and on signing in
///   or out.
/// - `document.visibilityState` is [PhoneNotices.hidden], the app's own lifecycle unless given.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../account/session.dart';
import '../core/notifications.dart';
import '../core/phone_notices.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import 'arrived.dart';
import 'feed.dart';

/// Where this phone keeps the switch (`SWITCH_KEY`): absent is on, `off` is off.
const String phoneNoticesKey = 'glyph-phone-notices';

/// The kinds that come to the phone: the categories the bell counts, less the two with a notification of their own
/// (`PHONE_CATEGORIES`).
const Set<String> phoneCategories = {'invites', 'team', 'claude'};

/// Where tapping a row's notification goes: the note Claude changed, an organization while it is yours, or the
/// drawer (`linkFor`).
String linkFor(FeedNotification n, String? noteId) {
  if (noteId != null && noteId.isNotEmpty) return 'ghostmd://note/$noteId';
  final gone = n.kind == 'invite' || n.kind == 'org-deleted' || (n.kind == 'member-removed' && n.body?['handle'] is! String);
  final org = n.org;
  return org != null && !gone ? 'ghostmd://org/${org.id}' : 'ghostmd://notifications';
}

/// Whether a row is one the phone posts: wanted, unread, not hidden, of a kind that comes here, and not answered
/// (`postsToPhone`).
bool postsToPhone(FeedNotification n, NotificationPrefs prefs) {
  if (!isKind(n.kind) || n.readAt != null || n.hidden) return false;
  if (!phoneCategories.contains(categoryOf(n.kind))) return false;
  if (n.kind == 'invite' && n.state != null && n.state != 'pending') return false;
  return isWanted(n, prefs);
}

bool _behind() {
  final state = SchedulerBinding.instance.lifecycleState;
  return state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached;
}

/// The phone's notifications for the bell's rows, for this device and the account signed in on it.
class PhoneNotices extends ChangeNotifier {
  /// [base] is where the service is, as the account's own [Api] has it; [kept] this device's memory, the app's own
  /// unless given; [hidden] whether the app is behind another now.
  PhoneNotices({required this.host, required this.account, required this.feed, required this.prefs, required this.base, Stored? kept, bool Function()? hidden})
      : _kept = kept,
        hidden = hidden ?? _behind;

  final NoticesHost host;
  final AccountSource account;
  final NotificationFeed feed;
  final PreferencesStore prefs;
  final String base;
  final Stored? _kept;
  final bool Function() hidden;
  Stored get _device => _kept ?? stored;

  /// Whether this phone posts the bell's rows. On unless turned off here (`phoneNoticesOn`).
  bool get on => _device.readText(phoneNoticesKey) != 'off';

  final ValueNotifier<NoticesState?> _shown = ValueNotifier<NoticesState?>(null);

  /// The phone's row on Settings › Notifications: what Android said last, null until it has, and for good where
  /// the binary has no notices (`usePhoneNotices`).
  ValueListenable<NoticesState?> get shown => _shown;

  /// The switch turned, and the phone told at once (`setPhoneNoticesOn`).
  Future<void> setOn(bool on) {
    _device.writeText(phoneNoticesKey, on ? null : 'off');
    if (!_disposed) notifyListeners();
    return syncWatch();
  }

  /// What Android says of the phone's notices, read again: after the permission was answered, or the app came back
  /// (`readPhoneNotices`).
  Future<NoticesState?> read() async {
    final state = await host.state();
    if (!_disposed) _shown.value = state;
    return state;
  }

  /// Android asked to let Ghost.md notify, from Settings › Notifications' Allow (the page's `requestNotifications`),
  /// and what it says of the notices read again. The phone itself is asked, through the notices' own channel: no
  /// recorder and no meeting service has to be there. False where no prompt can change it.
  Future<bool> allow() async {
    final asked = await host.allow();
    await read();
    return asked;
  }

  String? _lastWatch;
  Future<void>? _door;
  bool _disposed = false;

  /// The phone told what to watch while the app is closed: the service, the session, the feed's cursor and the
  /// switches, or nothing when signed out or switched off. Called after every pass of the feed, on a change of the
  /// switches, and on signing in or out; the same watch twice is not handed again (`syncPhoneWatch`). One at a
  /// time, in the order asked, each reading what is true when its turn comes.
  Future<void> syncWatch() => _door = (_door ?? Future<void>.value()).then((_) => _syncWatch()).catchError((Object _) {});

  Future<void> _syncWatch() async {
    if (_disposed) return;
    final session = account.session;
    final settings = prefs.value;
    final notifications = settings.notifications;
    final watch = session != null && on && !settings.localOnly
        ? jsonEncode({
            'api': base,
            'token': session.token,
            'accountId': session.accountId,
            'cursor': feed.feedState(session.accountId).cursor,
            'team': notifications.team,
            'claude': notifications.claude,
            'mutedOrgs': notifications.mutedOrgs,
          })
        : '';
    if (watch == _lastWatch) return;
    final state = await host.watch(watch);
    // A binary that cannot answers nothing: nothing was handed, so the next call tries again.
    if (state == null) return;
    _lastWatch = watch;
    if (!_disposed) _shown.value = state;
  }

  /// Forgets the last watch handed: for a test (`forgetPhoneWatch`).
  @visibleForTesting
  void forgetWatch() {
    _lastWatch = null;
    _shown.value = null;
  }

  /// The rows a pass brought, posted to the phone: those above [before], the cursor the pass began at, while the
  /// app is not in front. [before] of 0 is a device's first look at the feed, which posts nothing (`postNewRows`).
  Future<int> postNewRows(int before, List<FeedNotification> rows) async {
    if (before <= 0 || !on) return 0;
    if (!hidden()) return 0;
    var posted = 0;
    // Oldest first, so the newest lands on top of the phone's list.
    final oldestFirst = [...rows]..sort((a, b) => a.rev.compareTo(b.rev));
    for (final n in oldestFirst) {
      if (n.rev <= before || !postsToPhone(n, prefs.value.notifications)) continue;
      final details = await feed.detailsFor(n);
      final under = detailOf(details);
      final org = n.org?.name;
      final text = under ?? (org != null && org.isNotEmpty ? org : null);
      if (await host.post((id: n.id, title: sentenceOf(n, details), text: text, link: linkFor(n, details?.noteId)))) posted += 1;
    }
    return posted;
  }

  void Function()? _unhear;

  void _watchAgain() => unawaited(syncWatch());

  /// Hears every pass of the feed, the switches and the account from now on, as the page's engine told its module
  /// (core/sync/engine.ts: after each look at the feed, `onPreferences`, `onAccount`). Once.
  void start() {
    if (_unhear != null || _disposed) return;
    _unhear = onArrived((before, rows) {
      unawaited(postNewRows(before, rows).then<void>((_) {}, onError: (Object _) {}));
      _watchAgain();
    });
    prefs.addListener(_watchAgain);
    account.addListener(_watchAgain);
  }

  @override
  void dispose() {
    _disposed = true;
    final unhear = _unhear;
    if (unhear != null) {
      unhear();
      prefs.removeListener(_watchAgain);
      account.removeListener(_watchAgain);
    }
    _unhear = null;
    _shown.dispose();
    super.dispose();
  }
}
