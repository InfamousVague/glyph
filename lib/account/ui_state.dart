/// What the account's screens are handed: the account on this device, the sync that runs for it, its
/// organizations and their keys, the notifications' feed and the shared links, as one object ([AccountServices]),
/// and the widget that hands it down ([AccountScope]).
///
/// The web's pages reach for these as modules (`useAccount`, `useSyncStatus`, `useOrgs`, `useNotifications`,
/// `onShares`, and the functions beside them); here each is an object whoever wires the app made
/// (lib/account/account.dart, lib/sync/engine.dart, lib/orgs/orgs.dart, lib/orgs/org_keys.dart, lib/sync/feed.dart,
/// lib/share/share.dart), and the screens take the bundle. **With no bundle at all a screen draws what it drew
/// before there was an account**: the signed-out pages, whose way in is `SettingsFeatures.onWayIn`. With one, a
/// screen asks [AccountServices.signedIn]; any part may be missing, and what needs it then reads as nothing (no
/// organizations, no rows, no links) rather than failing.
///
/// The functions here are the ones the web's pages call that are more than one object's doing:
/// - [AccountServices.wayIn] is `useWayIn`'s submit (settings/AccountPane.tsx): the early checks, the flow, then a
///   sync.
/// - [AccountServices.answerInvite] is `InviteActions`' answer (settings/InviteActions.tsx): the feed's own answer,
///   a pass of the notifications, and the words when the answer is still queued after it.
/// - [AccountServices.signOut] and [AccountServices.deleteAccount] are `signOutHere` and `deleteAccountHere`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/note.dart';
import '../core/notifications.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../core/workspaces.dart';
import '../mail/mail_in.dart';
import '../meet/meet_in.dart';
import '../orgs/org_keys.dart';
import '../orgs/orgs.dart';
import '../share/share.dart';
import '../share/sites.dart';
import '../sync/engine.dart';
import '../sync/feed.dart';
import '../sync/phone.dart';
import 'account.dart';

/// The words a failure is said in on a page (core/failure.ts `failureText`): an [ApiError]'s or a [ShareError]'s
/// own message, a string as it is, anything else as it prints without Dart's "Exception: ".
String accountFailureText(Object failure) {
  if (failure is String) return failure;
  if (failure is ShareError) return failure.message;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'ApiError: ', 'FormatException: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}

/// A failure thrown as its words, so a page shows the sentence and not the type.
class SaidFailure implements Exception {
  const SaidFailure(this.words);
  final String words;

  @override
  String toString() => words;
}

/// The account and everything that runs for it, as the screens take it.
class AccountServices {
  /// [account] is this device's; the rest are what was made for it, and any may be left out. [prefs] and
  /// [workspaces] are the app's own unless given (a test's). [listNotes] reads this device's notes, not the trash
  /// (`listNotes`), for the count of recordings that stayed and a shared link's title. [liveTyping] is the Live
  /// typing switch on Account (`core/live/enabled.ts`, on unless turned off): the app's is this device's own flag (lib/root/account_wiring.dart
  /// over lib/live/enabled.dart); one that nothing reads is made here when none is given. [kept] is this device's memory, for the gate's "seen".
  AccountServices({
    required this.account,
    this.engine,
    this.orgs,
    this.orgKeys,
    this.feed,
    this.shares,
    this.sites,
    this.mailIn,
    this.meetIn,
    this.listNotes,
    this.phoneNotices,
    PreferencesStore? prefs,
    WorkspaceStore? workspaces,
    ValueNotifier<bool>? liveTyping,
    Stored? kept,
    int Function()? now,
  })  : _prefs = prefs,
        _workspaces = workspaces,
        liveTyping = liveTyping ?? ValueNotifier<bool>(true),
        _kept = kept,
        _now = now;

  final Account account;
  final SyncEngine? engine;
  final Orgs? orgs;
  final OrgKeys? orgKeys;
  final NotificationFeed? feed;
  final Shares? shares;

  /// The account's published sites (lib/share/sites.dart); null where they are not offered.
  final Sites? sites;

  /// Email to a note's setting (lib/mail/mail_in.dart); null where it is not offered.
  final MailIn? mailIn;

  /// Ghost in meetings' setting (lib/meet/meet_in.dart); null where it is not offered.
  final MeetIn? meetIn;
  final Future<List<Note>> Function()? listNotes;

  /// The bell's rows as the phone's own notifications (lib/sync/phone.dart): Settings › Notifications › On this
  /// phone. Null where nothing was made to post them.
  final PhoneNotices? phoneNotices;
  final ValueNotifier<bool> liveTyping;
  final PreferencesStore? _prefs;
  final WorkspaceStore? _workspaces;
  final Stored? _kept;
  final int Function()? _now;

  /// The preferences the screens read and write.
  PreferencesStore get prefs => _prefs ?? preferences;

  /// The workspaces the organizations are reconciled against; null when neither given nor the organizations'.
  WorkspaceStore? get workspaces => _workspaces ?? orgs?.workspaces;

  /// This device's memory.
  Stored get kept => _kept ?? stored;

  /// This moment, in ms.
  int now() => (_now ?? () => DateTime.now().millisecondsSinceEpoch)();

  // --- what the screens read ----------------------------------------------------------------------------------------

  Session? get session => account.session;
  bool get signedIn => account.session != null;

  /// Whether the account key is on this device (`account.unlocked`).
  bool get unlocked => account.value.unlocked;

  /// Where the sync stands (`useSyncStatus`); off with no engine.
  SyncStatus get status => engine?.status.value ?? const SyncStatus();

  /// The organizations as the service last listed them, and the account's own colour (`useOrgs`).
  OrgState get orgState => orgs?.orgsState() ?? OrgState.none;

  /// The organizations the person has joined.
  List<OrgRow> get joined => [for (final row in orgState.list) if (row.state == 'member') row];

  /// The feed as the drawer lists it (`useNotifications`).
  List<FeedNotification> get notifications => feed?.notifications() ?? const [];

  /// An organization's own news, newest first (`feed.filter((n) => n.org?.id === orgId && NEWS.has(n.kind))`).
  List<FeedNotification> newsOf(String orgId) => [for (final n in notifications) if (n.org?.id == orgId && orgKinds.contains(n.kind)) n];

  /// Tells a screen whenever anything it reads here changes.
  late final Listenable changes = Listenable.merge([account, engine?.status, orgs, orgKeys, feed, shares, sites, mailIn, meetIn, liveTyping]);

  // --- what the screens do ------------------------------------------------------------------------------------------

  /// A whole pass (`syncNow`); nothing without an engine.
  Future<void> syncNow() => engine?.syncNow() ?? Future<void>.value();

  /// The notifications and the organizations' list alone (`syncNotificationsNow`).
  Future<void> syncNotificationsNow() => engine?.syncNotificationsNow() ?? Future<void>.value();

  /// The way in, as the form's submit runs it (AccountPane.tsx `useWayIn`): [mode] is `in`, `up` or `recover`.
  /// Answers the recovery codes of a new or recovered account, or null for a plain sign-in, and throws what went
  /// wrong as its words ([SaidFailure]). A sync follows a way in without being waited for.
  Future<List<String>?> wayIn({required String mode, required String handle, required String password, String? code}) async {
    final early = handleProblem(handle) ?? (mode != 'in' ? passwordProblem(password) : null);
    if (early != null) throw SaidFailure(early);
    final List<String>? codes;
    try {
      if (mode == 'up') {
        codes = (await account.signUp(handle, password)).codes;
      } else if (mode == 'recover') {
        codes = (await account.recover(handle, code ?? '', password)).codes;
      } else {
        await account.signIn(handle, password);
        codes = null;
      }
    } catch (failure) {
      throw SaidFailure(accountFailureText(failure));
    }
    unawaited(syncNow());
    return codes;
  }

  /// Off this device, with what the sync kept of the account forgotten (`signOutHere`).
  Future<void> signOut() => engine?.signOutHere() ?? account.signOut();

  /// The account deleted from the service, then signed out here (`deleteAccountHere`).
  Future<void> deleteAccount(String password) async {
    final engine = this.engine;
    if (engine != null) return engine.deleteAccountHere(password);
    await account.deleteAccount(password);
  }

  /// An invitation answered (InviteActions.tsx `answer`): applied here at once by the feed, replayed by a pass of
  /// the notifications and the organizations, and then looked for in the queue. Answers null when the answer was
  /// delivered, and otherwise the words to show under Accept and Decline: the sync's own, or that it goes with the
  /// next one.
  Future<String?> answerInvite(String orgId, bool accept) async {
    final feed = this.feed;
    if (feed == null) return 'Not sent yet. It goes with the next sync.';
    feed.answerInvite(orgId, accept);
    await syncNotificationsNow();
    final session = account.session;
    final left = session != null && feed.feedState(session.accountId).marks.any((mark) => mark is InviteMark && mark.org == orgId);
    if (!left) return null;
    return status.message ?? 'Not sent yet. It goes with the next sync.';
  }
}

/// Hands the [AccountServices] to every screen under it. Whoever wires the app puts one over the shell; a screen
/// drawn outside one finds none, and draws as it did before there was an account.
class AccountScope extends InheritedWidget {
  const AccountScope({super.key, required this.services, required super.child});

  final AccountServices? services;

  static AccountServices? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AccountScope>()?.services;

  @override
  bool updateShouldNotify(AccountScope old) => old.services != services;
}

/// Builds again whenever anything the screens read of the account changes; with no services, once.
class AccountBuilder extends StatelessWidget {
  const AccountBuilder({super.key, required this.services, required this.builder});

  final AccountServices? services;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    if (services == null) return builder(context);
    return ListenableBuilder(listenable: services.changes, builder: (context, _) => builder(context));
  }
}
