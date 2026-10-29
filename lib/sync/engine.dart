/// Sync as the app runs it: when, against which of this device's stores, and what the Account page shows about it.
/// A port of `src/app/core/sync/engine.ts`.
///
/// A sync runs when the app starts signed in, when it comes back to the front, a moment after a note or a setting
/// changes, and every few minutes while it is open. One runs at a time; a request while one is running queues
/// exactly one more. Nothing runs without an account key on the device, or with "Nothing leaves the phone" on.
///
/// A pass is these steps in this order: the notifications, the organizations' list, the notes, the settings, then
/// the organizations' keys and each one's team notes (docs/TEAMS.md, D4). Notifications before notes, so that a note
/// a notification names has arrived by the time its row is drawn; the list before the notes, so an organization made
/// on another device shows here even while a note will not sync, and outside `applyingRemote`, so the workspace it
/// makes or drops goes with this pass's settings. Each step is caught on its own: the first failure is the status,
/// named by its step ("Notes: …"), and the others still run; only a lapsed session ends the pass. The organization
/// steps are quiet against a service that does not have their routes yet.
///
/// What differs:
/// - The page's module is [SyncEngine], made once with everything it reaches for as a module there: the account
///   ([SyncAccount]), the [Api] and the crypto, the key store, the preferences, this device's notes and files, the
///   notifications feed, the organizations and their keys. Nothing has a default that talks to a service
///   (docs/STAGE7.md).
/// - `useSyncStatus` is [SyncEngine.status], a [ValueListenable].
/// - The page listens for `NOTE_SAVED` on the window and for `visibilitychange` on the document; here the first is
///   the [Listenable] the engine is given as `touched` (`CoreLibrary.touched`), and the second is
///   [SyncEngine.resumed], which whoever holds the app's lifecycle calls.
/// - `announceNotesChanged` is the `onNotesChanged` the engine is given (`NoteLibrary.refresh`).
/// - The settings go through a [PrefsBridge] (prefs.dart), so nothing the typed preferences do not model is lost
///   on the way through.
/// - **The settings step carries the keys too** (sealed_keys.dart; Matt, 2026-10-26: the Claude key and the rest kept
///   the same on every device): just before the settings' pass, this device's changed keys are sealed into them
///   ([SealedKeys.gather]); just after it, what another device changed is written into this device's own stores
///   ([SealedKeys.apply]). A key changed here asks for a sync soon, as a setting does ([SealedKeys.changes]).
/// - **Step 5's second half is a hook.** The organizations' keys are seen to here (lib/orgs/org_keys.dart), and each
///   organization's own channel (`core/team/sync.ts`) is the [TeamNotesPass] the engine is given: team notes wait
///   for the CRDT (docs/STAGE7.md, pieces I and J). Without one, the keys are still read, made and filled, and
///   **no key is turned**: a turn is followed at once by the team's notes sealed again under the new key, and a
///   device that cannot do the second must not do the first.
/// - The phone's own notifications for what the feed brought (`core/notifications/phone.ts`) are not here; whoever
///   posts them hears the same rows through `onArrived` (lib/sync/arrived.dart).
/// - `nativeReady` asks whether the binary has `store_apply` and `sync_put_file`; this app's core is built with it,
///   so it is the `ready` the engine is given, true unless said otherwise.
/// - [syncedWhen] writes a time past the hour as "7 Oct, 18:05", where the page asks the device's language for it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account.dart';
import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/enc_key.dart';
import '../account/keystore.dart';
import '../core/locale_dates.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../core/workspaces.dart';
import '../integrations/webhooks/incoming.dart' show HookPass, HookPassContext;
import '../mail/mail_in.dart' show MailPass, MailPassContext;
import '../meet/meet_in.dart' show MeetPass, MeetPassContext;
import '../orgs/org_keys.dart';
import '../orgs/orgs.dart';
import '../team/folders.dart';
import 'arrived.dart';
import 'feed.dart';
import 'notes.dart';
import 'prefs.dart';
import 'record.dart';
import 'sealed_keys.dart';

/// How long after the last change a sync follows (`QUIET_MS`).
const Duration quietWait = Duration(seconds: 4);

/// How often a sync runs while the app is open (`EVERY_MS`).
const Duration everyWait = Duration(minutes: 5);

// --- status ----------------------------------------------------------------------------------------------------------

/// Where the sync stands, as the Account page shows it (`SyncStatus`).
@immutable
class SyncStatus {
  const SyncStatus({this.phase = 'off', this.lastAt, this.message, this.conflicts = 0, this.unsent = 0, this.unsentReason});

  /// `off`, `idle`, `syncing` or `error`.
  final String phase;

  /// When the last sync finished cleanly, in ms.
  final int? lastAt;
  final String? message;

  /// Notes kept twice by the last sync because both sides had changed them.
  final int conflicts;

  /// Notes the last sync could not send, and the first reason why: sent again next time.
  final int unsent;
  final String? unsentReason;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus && other.phase == phase && other.lastAt == lastAt && other.message == message && other.conflicts == conflicts && other.unsent == unsent && other.unsentReason == unsentReason;

  @override
  int get hashCode => Object.hash(phase, lastAt, message, conflicts, unsent, unsentReason);

  @override
  String toString() => 'SyncStatus($phase, lastAt: $lastAt, message: $message, conflicts: $conflicts, unsent: $unsent, unsentReason: $unsentReason)';
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// How long ago a sync finished, as the Account page says it (`syncedWhen`). [now] is the clock's unless given.
/// Past the hour it is the day and the time in the phone's own order and clock once it has said (core/locale_dates.dart:
/// "Oct 9, 4:05 PM", "9 Oct, 16:05"), and the day first on a 24-hour clock until then.
String syncedWhen(int ms, {int? now}) {
  final minutes = (((now ?? DateTime.now().millisecondsSinceEpoch) - ms) / 60000 + 0.5).floor();
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  return toldDate(at, DateForm.MMMdhm) ?? '${at.day} ${_months[at.month - 1]}, ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
}

/// "3 notes not synced": what the last pass could not send (`unsentLine`).
String unsentLine(int unsent) => unsent == 1 ? '1 note not synced' : '$unsent notes not synced';

/// The Account row's second line (`syncSummary`).
String syncSummary(String? signedIn, SyncStatus status, {int? now}) {
  if (signedIn == null || signedIn.isEmpty) return 'Not signed in';
  if (status.phase == 'syncing') return '$signedIn · syncing';
  if (status.phase == 'error') return '$signedIn · not synced';
  if (status.unsent != 0) return '$signedIn · ${unsentLine(status.unsent)}';
  final lastAt = status.lastAt;
  return lastAt != null && lastAt != 0 ? '$signedIn · synced ${syncedWhen(lastAt, now: now)}' : signedIn;
}

// --- what the engine is given ----------------------------------------------------------------------------------------

/// The account as the engine uses it: who is signed in and the key ([AccountSource]), and the three flows it runs
/// (`resume`, `signOut`, `deleteAccount` of core/account/account.ts).
abstract interface class SyncAccount implements AccountSource {
  Future<void> resume();
  Future<void> signOut();
  Future<void> deleteAccount(String password);
}

/// [Account] as a [SyncAccount].
class AccountDoor implements SyncAccount {
  const AccountDoor(this.account);
  final Account account;

  @override
  Session? get session => account.session;

  @override
  Future<SealKey?> accountKey() => account.accountKey();

  @override
  void addListener(VoidCallback listener) => account.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => account.removeListener(listener);

  @override
  Future<void> resume() => account.resume();

  @override
  Future<void> signOut() => account.signOut();

  @override
  Future<void> deleteAccount(String password) => account.deleteAccount(password);
}

/// The four steps the engine runs, each a function so a test can stand in for one.
typedef NotesPass = Future<Outcome> Function(SyncContext ctx);
typedef PrefsPass = Future<bool> Function(PrefsContext ctx);
typedef FeedPass = Future<bool> Function(NotificationsContext ctx);
typedef OrgsPass = Future<List<OrgRow>?> Function(OrgsContext ctx);

/// How one organization's channel went (`TeamOutcome` of core/team/sync.ts).
class TeamOutcome {
  const TeamOutcome({this.changed = 0, this.sent = 0, this.unsent = 0, this.reason});

  /// Notes written, removed or copied on this device.
  final int changed;

  /// Rows or updates written to the organization: its other devices are told to fetch now.
  final int sent;
  final int unsent;
  final String? reason;
}

/// What one organization's channel is handed (`TeamSyncContext` of core/team/sync.ts): everything the engine knows
/// that the channel needs, and nothing of the CRDT, which is the channel's own.
class TeamPass {
  const TeamPass({
    required this.token,
    required this.accountId,
    required this.org,
    required this.key,
    required this.generation,
    required this.olderKey,
    required this.notes,
    required this.files,
    required this.api,
    required this.crypto,
    required this.loadState,
    required this.saveState,
    required this.isTeamNote,
    this.leftTeam,
    this.keptOut,
    this.agreed,
    this.leftAt,
    required this.file,
    this.folders,
    required this.pulled,
    this.meetings,
    this.syncMeetingRecordings,
    this.reseal = false,
  });

  final String token;
  final int accountId;

  /// The organization, as the list last said it.
  final OrgRow org;

  /// The organization key this device holds, and its generation (docs/SHARED.md, S2, S11).
  final SealKey key;
  final int generation;

  /// The key at an older generation, for a row sealed before a turn that no device has re-sealed yet; null where
  /// this account has no encryption pair in hand.
  final Future<SealKey?> Function(int generation)? olderKey;
  final LocalNotes notes;
  final LocalFiles files;
  final Api api;
  final AccountCrypto crypto;

  /// What the channel kept of this organization (`glyph-sync-<account>-team-<org>`), as JSON; null for nothing yet.
  final Object? Function() loadState;
  final void Function(Object? state) saveState;

  /// Whether a note on this device is this team's: filed in the organization's workspace, or in a folder under it
  /// (GHST-107).
  final bool Function(String noteId) isTeamNote;

  /// Whether a note on this device has left the organization, as far as this device can tell: filed in a workspace
  /// it knows that is not the organization's nor under it. A note unfiled, or in a folder this device cannot place,
  /// has not (lib/team/sync.dart `_push`).
  final bool Function(String noteId)? leftTeam;

  /// Told of a note that stays on this device as its team's row goes (lib/team/sync.dart `keptOut`): the engine
  /// keeps it from an old build's deletion for a while ([LeftTeams]).
  final void Function(String noteId)? keptOut;

  /// The words this device and the account last both acknowledged for a note, and the account's revision they were
  /// at (lib/sync/notes.dart [agreedOf]): what a note it had of its own is merged from when the team's row first lands
  /// (lib/team/sync.dart `_ownWords`).
  final ({String words, int rev})? Function(String noteId)? agreed;

  /// The account's revision a note's words were at when this device took it out of the account's feed for the team
  /// ([SyncState.teams]), which its team's row carries for the account's other devices; null where it did not.
  final int? Function(String noteId)? leftAt;

  /// Files a note that arrived from the team in the organization's workspace.
  final void Function(String noteId) file;

  /// The organization's folders on this device (lib/team/folders.dart): a note that arrived is filed by the path
  /// its row carries, and a folder the pass emptied is dropped. None, and every note is filed by [file].
  final TeamFolders? folders;

  /// The rows are in, before their histories and pictures: the list may be drawn.
  final void Function() pulled;

  /// Which notes are meetings, and whether their recordings go (the person's Sync meeting recordings): a team's
  /// note's recording travels to every member unless it is a meeting's and that is off (GHST-112). None, it goes.
  final Map<String, num> Function()? meetings;
  final bool Function()? syncMeetingRecordings;

  /// False: one pass of the channel (`syncTeamNotes`). True: the key has just turned, [key] and [generation] are
  /// the new ones, and every note of the team's is to be sealed again under them (`resealTeamNotes`).
  final bool reseal;
}

/// One organization's channel, or its re-sealing. May throw [KeyTurned] (the key turned under this device: the next
/// pass reads the new wrap) or an [ApiError]; a 401 ends the whole pass.
typedef TeamNotesPass = Future<TeamOutcome> Function(TeamPass pass);

/// What a pass covers: everything, or only the notifications and the organizations, which an inline answer changes.
enum _Parts { all, team, notifications }

_Parts _widen(_Parts? was, _Parts asked) {
  if (was == _Parts.all || asked == _Parts.all) return _Parts.all;
  return was == _Parts.team || asked == _Parts.team ? _Parts.team : _Parts.notifications;
}

String _stateKey(int accountId, String part) => 'glyph-sync-$accountId-$part';

/// Sync for the life of the app.
class SyncEngine {
  /// [touched] is told after this device changes a note (`CoreLibrary.touched`); [onNotesChanged] reads the list
  /// again after a pass changed notes here (`NoteLibrary.refresh`). [record] records a note kept twice in the feed.
  /// [ready] answers whether this device's store can take a sync. [sharedLive] says a note is live with another
  /// device right now. [teamNotes] is one organization's channel (see the header), [forgetTeams] forgets what the
  /// channels hold in memory on signing out (`forgetTeamDocs`), and [tellChanged] tells an organization's other
  /// devices that this one has just written (core/live/nudge.ts). The four passes are the real ones unless a test
  /// gives its own.
  SyncEngine({
    required this.account,
    required this.api,
    required this.crypto,
    required this.keys,
    required this.prefs,
    required this.notes,
    required this.files,
    required this.feed,
    required this.orgs,
    required this.orgKeys,
    this.record,
    Stored? kept,
    int Function()? now,
    this.touched,
    this.onNotesChanged,
    this.ready,
    this.sharedLive,
    this.teamNotes,
    this.forgetTeams,
    this.tellChanged,
    this.mailIn,
    this.meetIn,
    this.hooksIn,
    this.sealedKeys,
    NotesPass? notesPass,
    PrefsPass? prefsPass,
    FeedPass? feedPass,
    OrgsPass? orgsPass,
  })  : _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _notesPass = notesPass ?? syncNotes,
        _prefsPass = prefsPass ?? syncPrefs,
        _feedPass = feedPass ?? syncNotifications,
        _orgsPass = orgsPass ?? orgs.syncOrgs {
    final session = account.session;
    if (session != null) _bridgeFor(session.accountId);
  }

  final SyncAccount account;
  final Api api;
  final AccountCrypto crypto;
  final KeyStore keys;
  final PreferencesStore prefs;
  final LocalNotes notes;
  final LocalFiles files;
  final NotificationFeed feed;
  final Orgs orgs;
  final OrgKeys orgKeys;
  final SelfNotifications? record;
  final Listenable? touched;
  final FutureOr<void> Function()? onNotesChanged;
  final Future<bool> Function()? ready;
  final bool Function(String id)? sharedLive;
  final TeamNotesPass? teamNotes;
  final void Function()? forgetTeams;
  final void Function(String orgId)? tellChanged;

  /// Email to a note (lib/mail/mail_in.dart `syncMail`): what was mailed to the account's address, filed as notes
  /// just before the notes step, which then sends them on. Null where the feature is not offered.
  final MailPass? mailIn;

  /// Ghost in a Google Meet (lib/meet/meet_in.dart `syncMeet`): each meeting Ghost recorded, filed as a note and
  /// handed to this device's write-up, just before the notes step, which then sends the notes on. Null where it is
  /// not offered.
  final MeetPass? meetIn;

  /// Incoming webhooks (lib/integrations/webhooks/incoming.dart `syncHooks`): what was posted to the account's hooks,
  /// put into its notes just before the notes step, which then sends them on. Null where it is not offered.
  final HookPass? hooksIn;

  /// The keys and connections that follow the account (sealed_keys.dart), gathered and applied around the settings'
  /// pass. Null where none travel.
  final SealedKeys? sealedKeys;

  final Stored? _kept;
  final int Function() _now;
  final NotesPass _notesPass;
  final PrefsPass _prefsPass;
  final FeedPass _feedPass;
  final OrgsPass _orgsPass;

  Stored get _device => _kept ?? stored;
  WorkspaceStore get _workspaces => orgs.workspaces;

  // --- status -------------------------------------------------------------------------------------------------------

  final ValueNotifier<SyncStatus> _status = ValueNotifier<SyncStatus>(const SyncStatus());

  /// Where the sync stands (`useSyncStatus`, `syncStatusNow`).
  ValueListenable<SyncStatus> get status => _status;

  void _phase(String phase, {String? message}) {
    final was = _status.value;
    _status.value = SyncStatus(phase: phase, lastAt: was.lastAt, message: message, conflicts: was.conflicts, unsent: was.unsent, unsentReason: was.unsentReason);
  }

  // --- what this device remembers -----------------------------------------------------------------------------------

  SyncState _loadNotes(int accountId) => _device.read<SyncState>(_stateKey(accountId, 'notes'), emptyState(), SyncState.fromJson);

  PrefsBridge? _bridge;
  int? _bridgeAccount;

  /// The settings' bridge for an account: what the account holds is kept per account, so a second account on this
  /// device never sends the first one's.
  PrefsBridge _bridgeFor(int accountId) {
    final bridge = _bridge;
    if (bridge != null && _bridgeAccount == accountId) return bridge;
    bridge?.dispose();
    _bridgeAccount = accountId;
    return _bridge = PrefsBridge(store: prefs, kept: _device, key: _stateKey(accountId, 'prefs-held'));
  }

  /// The synced settings as the account holds them, as far as this device has seen (lib/sync/prefs.dart
  /// [PrefsBridge.held]): what the last pass of the settings sent or took, never a change made here since. Null signed
  /// out, or with Local only on, where nothing is synced. A claim on a meeting's summary is read here once a sync has
  /// run (lib/ai/summary_handoff.dart): it is the account's only once it is in this.
  Map<String, Object?>? get accountPrefs {
    final session = account.session;
    if (session == null || prefs.value.localOnly) return null;
    return _bridgeFor(session.accountId).held;
  }

  /// Whether this device's copy of a note has changes the pass sync has not sent: its fingerprint against the one
  /// kept at its last sync, or no record of it at all (`hasUnsyncedChanges`). Live sync asks when a device joins a
  /// note another device already has open: a device that was only behind adopts the room's words; one with changes
  /// of its own keeps them as a copy. Signed out, nothing is pending.
  bool hasUnsyncedChanges(Note note) {
    final session = account.session;
    if (session == null) return false;
    final known = _loadNotes(session.accountId).notes[note.id];
    return known == null || known.mark != mark(note);
  }

  /// Forgets what this device knew of an account's sync: for signing out (`forgetSync`).
  void _forgetSync(int accountId) {
    for (final part in ['notes', 'prefs', 'left-teams']) {
      _device.write(_stateKey(accountId, part), null);
    }
    _bridgeFor(accountId).forget();
    // The keys this device took, and the sealed entries in the settings here: the next account never sends them.
    sealedKeys?.forget(accountId);
    // And each organization's channel, kept under `team-<org id>`: read before the organizations go.
    for (final row in orgs.orgRowsOf(accountId)) {
      _device.write(_stateKey(accountId, 'team-${row.id}'), null);
    }
    forgetTeams?.call();
    feed.forgetNotifications(accountId);
    orgs.forgetOrgs(accountId);
    orgKeys.forgetOrgKeys();
  }

  /// Signs out and forgets this device's sync bookkeeping for the account (`signOutHere`). The notes stay.
  Future<void> signOutHere() async {
    final session = account.session;
    await account.signOut();
    if (session != null) _forgetSync(session.accountId);
    _status.value = const SyncStatus();
  }

  /// Deletes the account, then forgets it here as signing out does, and the links shared from it too, which read
  /// nothing now (`deleteAccountHere`). The notes stay.
  Future<void> deleteAccountHere(String password) async {
    final session = account.session;
    await account.deleteAccount(password);
    if (session != null) _forgetSync(session.accountId);
    prefs.update((now) => now.copyWith(shares: const {}));
    _status.value = const SyncStatus();
  }

  // --- running ------------------------------------------------------------------------------------------------------

  Future<void>? _running;

  /// The pass asked for while one was running, if any: one more, covering the most anybody asked.
  _Parts? _queued;

  /// One pass of [parts] now, or right after the pass already running.
  Future<void> _run(_Parts parts) {
    final running = _running;
    if (running != null) {
      _queued = _widen(_queued, parts);
      return running;
    }
    final done = Completer<void>();
    _running = done.future;
    unawaited(() async {
      try {
        _Parts? next = parts;
        while (next != null) {
          await _once(next);
          next = _queued;
          _queued = null;
        }
      } catch (failure) {
        _phase('error', message: failureText(failure));
      } finally {
        _running = null;
        _queued = null;
        done.complete();
      }
    }());
    return done.future;
  }

  /// Syncs now, or right after the sync already running (`syncNow`).
  Future<void> syncNow() => _run(_Parts.all);

  /// The organizations' notes now, and nothing of the account's own: when another device says it has just written
  /// to one, or a key has just come to hand (`syncTeamsNow`).
  Future<void> syncTeamsNow() => _run(_Parts.team);

  /// The notifications and the organizations now, through the same one-at-a-time door: after an invitation is
  /// answered inline, and when the Notifications page opens (`syncNotificationsNow`). The notes are not swept, which
  /// on a phone with a thousand of them is the cost of a pass.
  Future<void> syncNotificationsNow() => _run(_Parts.notifications);

  /// A sync, waited for [wait] at most: a pull to refresh holds its ring that long and no longer, on a slow
  /// connection too (`syncWithin`). The sync goes on after it, and its notes arrive as it lands.
  Future<void> syncWithin([Duration wait = const Duration(seconds: 5)]) => Future.any([syncNow(), Future<void>.delayed(wait)]);

  /// The sync running now, finished, and the one it queued; at once when none is (`syncSettled`). For a reset, which
  /// signs out first and then waits here: a sync already under way holds the session it began with and the
  /// bookkeeping it read, and would send every note wiped under it as a deletion. Signed out, a queued one ends as
  /// it starts.
  Future<void> syncSettled() => _running ?? Future<void>.value();

  Future<void> _changed() async {
    try {
      await onNotesChanged?.call();
    } catch (_) {
      // The list could not be read again: its own trouble, and the next read's.
    }
  }

  Future<void> _resume() async {
    try {
      await account.resume();
    } catch (_) {
      // Not renewed: the next pass says so.
    }
  }

  Future<void> _once(_Parts parts) async {
    final session = account.session;
    SealKey? key;
    if (session != null) {
      try {
        key = await account.accountKey();
      } catch (_) {
        key = null;
      }
    }
    if (session == null || key == null || prefs.value.localOnly) {
      _phase('off');
      return;
    }
    final accountKey = key;
    // The notes lately out of a team here, kept from an old build's deletion and put again for it (lib/sync/notes.dart
    // [LeftTeams]): told by the team's channels, read by the account's own sync.
    final leftTeams = _LeftTeamsKept(_device, _stateKey(session.accountId, 'left-teams'), _now);
    final token = session.token, accountId = session.accountId;
    final call = CallContext(token: token);

    // And after each look at the feed, what it brought is told to whatever listens for new rows (arrived.dart).
    Future<bool> fed() async {
      final before = feed.feedState(accountId).cursor;
      final answer = await _feedPass(feed.contextFor(accountId, token: token, api: api, answerInvite: orgs.inviteAnswerWith(call)));
      tellArrived(before, listedIn(feed.feedState(accountId)));
      return answer;
    }

    Future<List<OrgRow>?> listed() => _orgsPass(OrgsContext(token: token, save: (state) => orgs.saveOrgs(accountId, state), now: _now));

    // And the keys the organizations need (docs/SHARED.md, S2, S3): this account's pair, and each organization's key
    // read, made or filled. Best effort: a failure here is the next pass's, and never the sync's status.
    Future<EncryptionKey?> teamKeys(List<OrgRow> list) async {
      try {
        final kept = await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto));
        await orgKeys.syncOrgKeys(OrgKeysContext(token: token, pair: kept.pair, list: list));
        return kept.pair;
      } catch (_) {
        // Left for the next pass.
        return null;
      }
    }

    // The organizations' own channels: the keys seen to, then each organization joined whose key this device holds
    // synced, its key turned when a member has gone. A whole pass ends with it; a `team` pass is it alone.
    Future<void> teams(List<OrgRow> list, Outcome outcome) async {
      final pair = await teamKeys(list);
      final channel = teamNotes;
      // No channel yet (see the header): the keys are in hand for when there is one, and none is turned.
      if (channel == null) return;
      for (final row in list) {
        if (row.state != 'member') continue;
        final orgKey = orgKeys.orgKeyOf(row.id);
        if (orgKey == null) continue;
        final teamKey = _stateKey(accountId, 'team-${row.id}');
        final workspace = orgWorkspaceId(row.id);
        TeamPass pass({required SealKey key, required int generation, bool reseal = false}) => TeamPass(
              token: token,
              accountId: accountId,
              org: row,
              key: key,
              generation: generation,
              olderKey: pair != null ? (older) => orgKeys.orgKeyAt(OrgKeysContext(token: token, pair: pair), row.id, older) : null,
              notes: notes,
              files: files,
              api: api,
              crypto: crypto,
              loadState: () => _device.read<Object?>(teamKey, null),
              saveState: (state) => _device.write(teamKey, state),
              // Filed in the organization's workspace or a folder under it (GHST-107).
              isTeamNote: (id) => _workspaces.orgOf(_workspaces.workspaceOf(id)?.id ?? '') == row.id,
              // Out of the team only where it is filed somewhere this device knows outside the organization: never
              // because its folder cannot be placed (2026-10-26, 108 team notes deleted by a build that read the
              // organizations' folders as personal).
              leftTeam: (id) {
                final filed = _workspaces.workspaceOf(id);
                return filed != null && _workspaces.orgOf(filed.id) != row.id;
              },
              keptOut: leftTeams.keep,
              // Read as the note's row lands: the account's step of this pass may have answered a deletion with it.
              agreed: (id) {
                final state = _loadNotes(accountId);
                return agreedOf(state.notes[id]) ?? state.teams[id]?.agreed;
              },
              leftAt: (id) => _loadNotes(accountId).teams[id]?.rev,
              file: (id) => _workspaces.fileNote(id, workspace),
              folders: OrgFolders(_workspaces, row.id),
              // Drawn as soon as the rows are in, before their histories and pictures.
              pulled: () => unawaited(_changed()),
              // A team's note's recording goes to every member (GHST-112), under the same switch as the account's.
              meetings: () => prefs.value.meetings,
              syncMeetingRecordings: () => prefs.value.syncMeetingRecordings,
              reseal: reseal,
            );
        try {
          final team = await channel(pass(key: orgKey, generation: orgKeys.orgKeyGeneration(row.id)));
          if (team.changed > 0) await _changed();
          // Written to the organization: its other devices fetch now, not at their next pass.
          if (team.sent > 0) tellChanged?.call(row.id);
          outcome.unsent += team.unsent;
          outcome.reason ??= team.reason;
          // A member has gone (docs/SHARED.md, S11): with the team's notes brought up to date under the old key,
          // this device makes the next generation and puts every note again under it.
          if (orgKeys.turnDue(row)) {
            final org = await orgs.fetchOrg(row.id, ctx: call);
            final turned = await orgKeys.turnOrgKey(row.id, org.members, token: token);
            final next = orgKeys.orgKeyOf(row.id);
            if (turned != null && next != null) {
              final resealed = await channel(pass(key: next, generation: turned, reseal: true));
              outcome.unsent += resealed.unsent;
              outcome.reason ??= resealed.reason;
            }
          }
        } catch (failure) {
          // The key turned under this device: its wrap at the new generation is read on the next pass, and the
          // organization's notes are sealed under it then.
          if (failure is KeyTurned) continue;
          // A lapsed session ends the pass, as anywhere. Anything else is this organization's alone: counted and
          // said, and the account's own sync and the other organizations stand.
          if (failure is ApiError && failure.status == 401) rethrow;
          outcome.unsent += 1;
          outcome.reason ??= '${row.name}: ${failureText(failure)}';
        }
      }
    }

    Future<bool> isReady() async => await ready?.call() ?? true;

    if (parts == _Parts.team) {
      // The account's own notes are not swept: this is the feed, the list, the keys and the organizations' notes.
      try {
        if (!await isReady()) return;
        await fed();
        final list = await listed();
        if (list != null) await teams(list, Outcome());
        _mergeTwins();
      } catch (failure) {
        if (failure is ApiError && failure.status == 401) await _resume();
      }
      return;
    }
    if (parts == _Parts.notifications) {
      // The notes' status stands: this is the feed and the list, and says nothing on the Account row unless it
      // fails.
      try {
        await fed();
        final list = await listed();
        // The keys too, when the list says there is something to do (docs/SHARED.md, S2): a member who has just
        // joined is wrapped for by the first device of anyone's to hear of it, and reads their wrap as soon as it is
        // there, rather than at somebody's next whole pass.
        if (list != null && list.any(_keysOwed)) {
          int inHand() => list.where((row) => orgKeys.orgKeyOf(row.id) != null).length;
          final held = inHand();
          await teamKeys(list);
          // A key newly in hand: the team's notes are fetched right after this pass.
          if (inHand() > held) unawaited(_run(_Parts.team));
        }
      } catch (failure) {
        if (failure is ApiError && failure.status == 401) await _resume();
        _phase('error', message: failureText(failure));
      }
      return;
    }
    if (!await isReady()) {
      _phase('error', message: 'Sync needs the newest Ghost.md. Install it from attack.fm/glyph.');
      return;
    }
    _phase('syncing');
    // Each step stands on its own: a note that will not go no longer keeps the preferences, the organizations and
    // the team's notes from theirs. The first failure is the status's, named by its step; a lapsed session still
    // ends the pass, as every step after it would be refused too.
    String? failed;
    Future<T?> step<T>(String name, Future<T> Function() run) async {
      try {
        return await run();
      } catch (failure) {
        if (failure is ApiError && failure.status == 401) rethrow;
        debugPrint('[sync] $name failed: $failure');
        failed ??= '$name: ${failureText(failure)}';
        return null;
      }
    }

    try {
      await step('Notifications', fed);
      // The list before the notes: an organization made on another device shows here even while a note will not
      // sync.
      final list = await step('Organizations', listed);

      // Mail sent to the account's address, filed as notes before the notes step sends them on (docs/MAIL.md).
      final mail = mailIn;
      if (mail != null) {
        final filed = await step(
          'Mail',
          () => mail(MailPassContext(
            token: token,
            api: api,
            crypto: crypto,
            pair: () async => (await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto))).pair,
            notes: notes,
            files: files,
            now: _now,
          )),
        );
        if ((filed ?? 0) > 0) await _changed();
      }

      // Each meeting Ghost was in, filed as a note for this device to write up (docs/MEET.md, "On the device").
      final meet = meetIn;
      if (meet != null) {
        final filed = await step(
          'Meetings',
          () => meet(MeetPassContext(
            token: token,
            api: api,
            crypto: crypto,
            pair: () async => (await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto))).pair,
            notes: notes,
            prefs: prefs,
            kept: _device,
            now: _now,
          )),
        );
        if ((filed ?? 0) > 0) await _changed();
      }

      // What was posted to the account's incoming webhooks, put into its notes (docs/INTEGRATIONS.md, §1).
      final hooks = hooksIn;
      if (hooks != null) {
        final added = await step(
          'Webhooks',
          () => hooks(HookPassContext(
            token: token,
            api: api,
            crypto: crypto,
            pair: () async => (await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto))).pair,
            notes: notes,
            now: _now,
            prefs: () => prefs.value,
            kept: _device,
          )),
        );
        if ((added ?? 0) > 0) await _changed();
      }

      final notesKey = _stateKey(accountId, 'notes');
      final synced = await step(
        'Notes',
        () => _notesPass(SyncContext(
          token: token,
          key: accountKey,
          notes: notes,
          files: files,
          state: _loadNotes(accountId),
          save: (state) => _device.write(notesKey, state.toJson()),
          api: api,
          crypto: crypto,
          now: _now,
          // Which notes are meetings, and whether their audio may go. Read when each recording is decided, not when
          // the pass began: a meeting finished during a pass is listed as it is made, and a snapshot from before it
          // would send its audio.
          meetings: () => prefs.value.meetings,
          syncMeetingRecordings: () => prefs.value.syncMeetingRecordings,
          // A note kept twice is worth a row in the feed: the person has two copies to look at.
          onConflict: (copy) => unawaited(record?.record('sync-conflict', {'noteId': copy.noteId, 'title': copy.title})),
          // A note filed in an organization's workspace, or a folder under it, is the team's (docs/SHARED.md, S1):
          // the channel's below.
          teamNote: (id) {
            final space = _workspaces.workspaceOf(id);
            return space != null && _workspaces.orgOf(space.id) != null;
          },
          sharedLive: sharedLive,
          leftTeams: leftTeams,
        )),
      );
      if ((synced?.changed ?? 0) > 0) await _changed();
      final outcome = Outcome(conflicts: synced?.conflicts ?? 0, unsent: synced?.unsent ?? 0, reason: synced?.reason);

      final prefsKey = _stateKey(accountId, 'prefs');
      await step('Preferences', () async {
        final bridge = _bridgeFor(accountId);
        final sealed = sealedKeys;
        final keysCtx = KeysContext(key: accountKey, crypto: crypto, accountId: accountId);
        bridge.applying = true;
        try {
          // The keys changed here, sealed into the settings before they go; a key that will not seal is left for the
          // next pass, and the settings go all the same.
          if (sealed != null) await _keys('gathered', () => sealed.gather(keysCtx));
          await _prefsPass(PrefsContext(
            token: token,
            key: accountKey,
            read: bridge.read,
            write: bridge.write,
            state: _device.read<PrefsState>(prefsKey, const PrefsState(), PrefsState.fromJson),
            save: (state) {
              _device.write(prefsKey, state.toJson());
              bridge.saved(state);
            },
            api: api,
            crypto: crypto,
            carried: bridge.carried,
            carry: bridge.carry,
          ));
        } finally {
          bridge.applying = false;
        }
        // And another device's keys, into this device's own stores.
        if (sealed != null) await _keys('applied', () => sealed.apply(keysCtx));
      });
      // The settings in, and the team's notes filed: folders made twice are made one (lib/core/workspaces.dart
      // `mergeTwinFolders`), outside the settings' own write, so what it changes goes with the next pass.
      _mergeTwins();
      if (list != null) await teams(list, outcome);
      _mergeTwins();
      _status.value = failed != null
          ? SyncStatus(phase: 'error', lastAt: _status.value.lastAt, message: failed, conflicts: outcome.conflicts, unsent: outcome.unsent, unsentReason: outcome.reason)
          : SyncStatus(phase: 'idle', lastAt: _now(), conflicts: outcome.conflicts, unsent: outcome.unsent, unsentReason: outcome.reason);
    } catch (failure) {
      // The session lapsed mid-sync: renew it (with this device's key if need be) and go again next time.
      if (failure is ApiError && failure.status == 401) await _resume();
      _phase('error', message: failureText(failure));
    }
  }

  /// A move of the sealed keys, its failure said by its kind alone (what a key held is never said) and not the
  /// settings' own.
  Future<void> _keys(String move, Future<int> Function() run) async {
    try {
      await run();
    } catch (failure) {
      debugPrint('[sync] the keys were not $move: ${failure.runtimeType}');
    }
  }

  /// Folders made twice, made one again (lib/core/workspaces.dart `mergeTwinFolders`; Matt, 2026-10-23: "fix the
  /// duplicate folders"): twins come in with another device's settings, or are made by a team pass before the
  /// settings that hold the folder have landed, so both are where they are healed. Quiet: a folder that will not
  /// merge stays as it was, and the pass goes on.
  void _mergeTwins() {
    try {
      final gone = _workspaces.mergeTwinFolders();
      if (gone > 0) debugPrint('[sync] $gone folder${gone == 1 ? '' : 's'} made twice, made one again');
    } catch (failure) {
      debugPrint('[sync] the twin folders stayed: $failure');
    }
  }

  /// Whether an organization's key wants seeing to now: none made yet, a wrap waiting that this device has not read,
  /// or a member this device could wrap for (`keysOwed`). An organization with nothing to do costs the notifications
  /// pass nothing.
  bool _keysOwed(OrgRow row) => keyWork(row, held: orgKeys.orgKeyOf(row.id) != null);

  // --- the schedule -------------------------------------------------------------------------------------------------

  Timer? _quiet;
  Timer? _launch;
  Timer? _beat;
  bool _started = false;

  bool get _active => account.session != null;

  /// A sync a moment from now, pushed back by every change in between (`syncSoon`).
  void _syncSoon() {
    _quiet?.cancel();
    _quiet = Timer(quietWait, () {
      _quiet = null;
      unawaited(syncNow());
    });
  }

  void _onChanged() {
    if (_active) _syncSoon();
  }

  void _onKeys() {
    if (_active) _syncSoon();
  }

  void _onPrefs() {
    final session = account.session;
    if (session == null) return;
    // The settings another device sent are not a change made here.
    if (!_bridgeFor(session.accountId).applying) _syncSoon();
  }

  /// The app came back to the front (`visibilitychange`): a sync, signed in.
  void resumed() {
    if (_started && _active) unawaited(syncNow());
  }

  /// Starts syncing for the life of the app (`startSync`): renews the session, syncs, and then syncs on the
  /// triggers above. Answers the way to stop. Safe to call more than once: the second answers a stop that does
  /// nothing.
  void Function() start() {
    if (_started) return () {};
    _started = true;
    // Nothing at all for a device that was never signed in; for one that was, all of it after the first frame, and
    // nothing it does can throw into the launch.
    final session = account.session;
    if (session != null) {
      _bridgeFor(session.accountId);
      _launch = Timer(Duration.zero, () => unawaited(_resume().then((_) => syncNow())));
    }
    touched?.addListener(_onChanged);
    prefs.addListener(_onPrefs);
    sealedKeys?.start();
    sealedKeys?.changes.addListener(_onKeys);
    _beat = Timer.periodic(everyWait, (_) {
      if (_active) unawaited(syncNow());
    });
    return stop;
  }

  /// Stops what [start] started. A pass already running finishes.
  void stop() {
    if (!_started) return;
    _started = false;
    touched?.removeListener(_onChanged);
    prefs.removeListener(_onPrefs);
    sealedKeys?.changes.removeListener(_onKeys);
    _launch?.cancel();
    _quiet?.cancel();
    _beat?.cancel();
    _launch = _quiet = _beat = null;
  }

  /// Stops, and lets go of what it listens to.
  void dispose() {
    stop();
    _bridge?.dispose();
    _bridge = null;
    _status.dispose();
  }
}

/// [LeftTeams] kept on the device, per account (`glyph-sync-<account>-left-teams`): each note's id with when it left a
/// team here and when its row last went to the account, as `{id: [left, sent]}`, both in ms. One left longer ago than
/// [leftTeamsKept] is let go as the record is read.
class _LeftTeamsKept implements LeftTeams {
  _LeftTeamsKept(this._kept, this._key, this._now);

  final Stored _kept;
  final String _key;
  final int Function() _now;

  Map<String, List<int>> _read() {
    final raw = _kept.read<Object?>(_key, null);
    final now = _now();
    final out = <String, List<int>>{};
    if (raw is! Map) return out;
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || value is! List || value.length != 2 || value[0] is! num || value[1] is! num) continue;
      final left = (value[0] as num).toInt(), sent = (value[1] as num).toInt();
      if (now - left < leftTeamsKept.inMilliseconds) out[key] = [left, sent];
    }
    return out;
  }

  void _write(Map<String, List<int>> all) => _kept.write(_key, all.isEmpty ? null : all);

  /// [id] has just left a team here: kept from now, its row owed again in [leftTeamsAgain].
  void keep(String id) {
    final now = _now();
    _write(_read()..[id] = [now, now]);
  }

  @override
  bool kept(String id) => _read().containsKey(id);

  @override
  bool owed(String id) {
    final at = _read()[id];
    return at != null && _now() - at[1] >= leftTeamsAgain.inMilliseconds;
  }

  @override
  void sent(String id) {
    final all = _read();
    final at = all[id];
    if (at == null) return;
    _write(all..[id] = [at[0], _now()]);
  }
}
