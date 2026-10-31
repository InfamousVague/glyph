/// The account, made for this device: what `App.tsx` gets by importing `core/account`, `core/sync`, `core/orgs`,
/// `core/notifications` and `share/`, put together once by whoever starts the app.
///
/// **A release build talks to the real service, and no other build ever does.** A release with nothing said is on
/// [realServiceBase], the address the Tauri app's page was built with (`src/app/core/account/api.ts`, `API_BASE`):
/// it is the app people sign in to (Matt, 2026-10-11: "release builds always talk to the real service"). A build
/// that is not a release has no default (docs/STAGE7.md: a development build never talks to ghostmarkdown.com): it
/// is given a base with `--dart-define=GHOST_API=http://…` ([ghostApiDefine]), and with none [accountBase] answers
/// null, nothing here is made, and the app has no account object at all: the signed-out screens, whose way in says
/// so ([noServiceWayIn]). A base that names the real service is refused in a build that is not a release here,
/// before an [Api] is made, and by the [Api]'s own assert after.
///
/// What is made ([WiredAccount.make]), each the real one: the crypto in the Rust core on a lane of its own for the
/// long calls ([CoreCrypto.withLane], made by `main`), the keys under the phone's Keystore ([DeviceKeyStore]), the
/// [Account], the notifications' feed, the organizations and their keys, the team notes' documents as files beside
/// the library (one folder to an account), the shares, and the [SyncEngine] over this device's own library and
/// files, with team notes as its fifth step; and live sync beside them (lib/live/live.dart [LiveServices]): the one
/// connection to the relay beside the service, held only while a room is (an organization's own, once signed in and
/// in one; a note's, while it is open), let go while the app is behind another, and what a note's desk opens a note
/// through ([WiredAccount.noteLive]). The engine is told which notes are live with another device and tells an
/// organization's other devices when it wrote. And the bell's rows as the phone's own notifications
/// (lib/sync/phone.dart [PhoneNotices]): made here with the same base and nowhere else, so a build with no account
/// service posts nothing and hands the phone's worker nothing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account.dart';
import '../account/api.dart';
import '../account/crypto.dart';
import '../account/crypto_api.dart' show rounds;
import '../account/device_keys.dart';
import '../account/ui_state.dart';
import '../ai/summary_handoff.dart' show thisDevice;
import '../core/native/core.dart';
import '../core/native/files.dart';
import '../core/note.dart';
import '../core/phone_notices.dart';
import '../core/phone_pictures.dart' show phoneJpegShrink;
import '../core/preferences.dart';
import '../core/stored.dart';
import '../core/versions_store.dart';
import '../core/workspaces.dart';
import '../forms/form_inbox.dart' show syncForms;
import '../integrations/webhooks/plugin.dart' show hooksWhileOn;
import '../live/live.dart';
import '../live/nudge.dart';
import '../live/open.dart';
import '../live/poke.dart';
import '../mail/mail_in.dart';
import '../meet/live_captions.dart';
import '../meet/meet_api.dart' show MeetApi;
import '../meet/meet_in.dart';
import '../book/ticket_events.dart';
import '../book/ticket_watchers.dart' show ticketCreator;
import '../mentions/mention_notices.dart';
import '../mentions/mention_reminders.dart';
import '../verified/verified_notices.dart';
import '../core/note_text.dart' show noteTitle;
import '../plugins/discord/calls.dart' show discordCallsFollowPlugin;
import '../orgs/org_keys.dart';
import '../orgs/orgs.dart';
import '../share/share.dart';
import '../share/share_recordings.dart' if (dart.library.js_interop) '../share/share_recordings_web.dart';
import '../share/sites.dart';
import '../sync/connections.dart';
import '../sync/device.dart';
import '../sync/engine.dart';
import '../sync/feed.dart';
import '../sync/local.dart';
import '../sync/phone.dart';
import '../sync/record.dart';
import '../sync/sealed_keys.dart';
import '../team/crdt.dart';
import '../team/doc.dart';
import '../team/docs.dart';
import '../team/sync.dart';

/// The base this build was given: `--dart-define=GHOST_API=http://10.0.2.2:<port>/api`. Empty in every build
/// that was not.
const String ghostApiDefine = String.fromEnvironment('GHOST_API');

/// The real service, as the Tauri app's page names it (`API_BASE`): what a release build is on when it is told
/// nothing else.
const String realServiceBase = 'https://ghostmarkdown.com/api';

/// The service's base for this build, or null for a build with no account. A release ([debug] false) with none
/// given is on [realServiceBase]. Null: none given in a build that is not a release, one that is not an address,
/// or, in a build that is not a release, one that names the real service.
String? accountBase(String given, {bool debug = !kReleaseMode}) {
  final base = given.trim();
  if (base.isEmpty) return debug ? null : realServiceBase;
  final uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  if (debug && isProductionHost(uri.host)) return null;
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

/// A row in the account's own feed, as the summary queue asks for one (`core/notifications/record.ts` `record`:
/// "A meeting was written up"): recorded by the sync engine's own recorder, read as each is asked, so an account
/// made or signed in to after voice was made is the one written to. Nothing in a build with no account.
Future<void> Function(String kind, Map<String, Object?> details) feedRecord(AccountServices? Function() services) =>
    (kind, details) async => services()?.engine?.record?.record(kind, details);

/// What a way in says in a build with no service to sign in to.
const String noServiceWords = 'This build has no account service. Notes stay on this device.';

/// The way in of a build with no account: it says so, whatever was typed.
Future<List<String>?> noServiceWayIn({required String mode, required String handle, required String password, String? code}) async => throw const SaidFailure(noServiceWords);

/// What `main` hands the app for an account: where the service is, the crypto, and the app's data folder.
@immutable
class AccountMaking {
  const AccountMaking({required this.base, required this.crypto, required this.dataDir, this.fetcher, this.secure, this.iterations = rounds, this.notices, this.jpeg, this.docsFor});

  final String base;
  final CoreCrypto crypto;
  final String dataDir;

  /// A test's; `dart:io`'s unless given.
  final Fetcher? fetcher;
  final SecureStore? secure;

  /// PBKDF2's rounds; the real 600,000 unless a test says otherwise.
  final int iterations;

  /// The phone, asked about its own notifications for the bell's rows; the device's unless a test says otherwise.
  final NoticesHost? notices;

  /// What writes a share's reading copy of a picture as a JPEG; the phone's unless a test says otherwise.
  final JpegShrink? jpeg;

  /// Where one account's team documents are kept: files under [dataDir] unless this says otherwise, which the web
  /// build does, having no folder (lib/web/web_core.dart `ShelfTeamDocs`).
  final TeamDocStore Function(int accountId)? docsFor;
}

/// The team notes' documents, in the folder of whoever is signed in: signed out, there are none to read and
/// nowhere to write.
class _AccountDocs implements TeamDocStore {
  _AccountDocs(this._dataDir, this._account, [this._docsFor]);

  final String _dataDir;
  final Account _account;
  final TeamDocStore Function(int accountId)? _docsFor;
  TeamDocStore? _docs;
  int? _for;

  TeamDocStore? get _now {
    final id = _account.session?.accountId;
    if (id == null) return null;
    if (_for != id) {
      _for = id;
      _docs = _docsFor?.call(id) ?? FileDocs.forAccount(_dataDir, id);
    }
    return _docs;
  }

  @override
  Future<TeamDocRecord?> read(String noteId) async => _now?.read(noteId);

  @override
  Future<void> write(String noteId, TeamDocRecord record) async => _now?.write(noteId, record);

  @override
  Future<void> remove(String noteId) async => _now?.remove(noteId);
}

/// The account's objects for this device, and their bundle for the screens.
class WiredAccount {
  WiredAccount._(this.services, this.engine, this._docs, this.live, this.noteLive, this.phone, this._saved, this._changed, [this.captions]);

  /// A meeting's live captions while Ghost is in it (lib/meet/live_captions.dart); none where meetings are not offered.
  final LiveCaptions? captions;
  VoidCallback? _stopCaptions;

  /// Makes everything over this device's own stores. [core] is the library's core; [touched] is told after this
  /// device changes a note and [refresh] reads the list again after a pass changed notes (`CoreLibrary`'s two);
  /// [versions] is the versions' own store, shared with the note's history; [onPicture] is told a picture's name
  /// once sync has kept it; [keepCopy] keeps words as a note of their own (a note of the account's own that met
  /// another device's while this one had changes unsent); [notesChanged] says the notes changed by any hand, a
  /// sync's too (the library itself, the page's `NOTES_CHANGED`), which with [touched] is what a shared link
  /// follows.
  factory WiredAccount.make({
    required AccountMaking making,
    required CoreInvoke core,
    required WorkspaceStore workspaces,
    required VersionsStore versions,
    required Listenable? touched,
    required FutureOr<void> Function() refresh,
    required List<Note> Function() shownNotes,
    Listenable? notesChanged,
    PreferencesStore? prefs,
    Stored? kept,
    void Function(String name)? onPicture,
    Future<void> Function(String words)? keepCopy,
  }) {
    final settings = prefs ?? preferences;
    final device = kept ?? stored;
    final crypto = making.crypto;
    final api = Api(base: making.base, fetcher: making.fetcher ?? ioFetcher());
    final keys = DeviceKeyStore(crypto: crypto, store: making.secure ?? deviceSecureStore());
    final account = Account(keys: keys, api: api, crypto: crypto, iterations: making.iterations, label: 'Ghost Flutter');
    final feed = NotificationFeed(account: account, crypto: crypto, kept: device);
    final orgs = Orgs(account: account, api: api, workspaces: workspaces, kept: device);
    final orgKeys = OrgKeys(crypto: crypto, api: api);
    final files = CoreFiles(core);
    final notes = LibraryNotes(core);
    // What this device's own changes to a team's notes owe: each person's mention typed, told once the edit has synced
    // (lib/mentions/mention_notices.dart; Matt, 2026-10-30: "add all 12").
    final mentions = MentionLedger(kept: device);
    // And each change to a team's ticket, told to its watchers in a batch (lib/book/ticket_events.dart; Matt, 2026-10-31).
    final ticketEvents = TicketEventLedger(kept: device);
    String? orgOfNote(String noteId) {
      final space = workspaces.workspaceOf(noteId);
      return space == null ? null : orgOfWorkspace(workspaces.value.list, space.id);
    }

    final docs = TeamDocs(
      crdt: Crdt(core),
      store: _AccountDocs(making.dataDir, account, making.docsFor),
      onMade: (noteId, before, after) {
        final session = account.session, org = orgOfNote(noteId);
        if (session != null && org != null) {
          mentions.made(session.accountId, org, noteId, before, after);
          ticketEvents.made(session.accountId, org, noteId, before, after);
        }
      },
    );
    // Whose a day mentioned is, for the reminders' plan (lib/mentions/mention_reminders.dart): kept up with the account.
    void who() {
      final session = account.session;
      mentionWho.value = MentionWho(
        me: session?.handle,
        team: (noteId) => orgOfNote(noteId) != null,
        wrote: (noteId, day) => session != null && mentions.wroteDay(session.accountId, noteId, day),
        key: '${session?.accountId ?? ''}:${session?.handle ?? ''}',
      );
      // Who a ticket made on this device names as its first watcher (lib/book/ticket_watchers.dart).
      ticketCreator.value = session?.handle;
    }

    who();
    account.addListener(who);
    // A member's mention is sealed under the organization key (lib/mentions/mention_notices.dart): opened with the one
    // this device holds, or an older generation's from this account's wrap.
    feed.orgKey = (orgId, generation) async {
      if (orgKeys.orgKeyGeneration(orgId) == generation) return orgKeys.orgKeyOf(orgId);
      final session = account.session, pair = await keys.encryptionKey();
      if (session == null || pair == null) return null;
      return orgKeys.orgKeyAt(OrgKeysContext(token: session.token, pair: pair), orgId, generation);
    };
    final live = LiveServices(base: making.base, account: account, crypto: crypto, crdt: Crdt(core), orgs: orgs, orgKeys: orgKeys, prefs: settings, kept: device);
    // A share's reading copies are JPEGs written by the phone (lib/core/phone_pictures.dart): nothing on a device with no half for it.
    // And a meeting's recording, read from where the core keeps it, for a share that carries one (lib/share/share_audio.dart).
    final shares = Shares(account: account, api: api, crypto: crypto, prefs: settings, pictures: CorePictures(files, jpeg: making.jpeg ?? phoneJpegShrink, onPicture: onPicture), listNotes: notes.list, recordings: CoreRecordings(files));
    // A note or a notebook published as a site, and email to a note (docs/SITES.md, docs/MAIL.md): not on the iPhone.
    final offered = publishingOffered();
    final sites = offered ? Sites(account: account, api: api, crypto: crypto, pictures: CorePictures(files, jpeg: making.jpeg ?? phoneJpegShrink, onPicture: onPicture), listNotes: notes.list) : null;
    final mailIn = offered ? MailIn(account: account, keys: keys, api: api, crypto: crypto) : null;
    // Ghost in a Google Meet (docs/MEET.md): its setting beside the mail's, which it is booked through; its takes
    // filed on every device, an iPhone's from the captions after a day left for one that keeps the sound.
    final meetIn = offered ? MeetIn(account: account, keys: keys, api: api, crypto: crypto, kept: device) : null;
    final record = SelfNotifications(feed: feed, api: api, localOnly: () => settings.value.localOnly);
    DateTime? expiriesAt;
    final engine = SyncEngine(
      account: AccountDoor(account),
      api: api,
      crypto: crypto,
      keys: keys,
      prefs: settings,
      notes: notes,
      files: KeptFiles(versions: versions, bytes: CoreDeviceBytes(files, onPicture: onPicture)),
      feed: feed,
      orgs: orgs,
      orgKeys: orgKeys,
      record: record,
      kept: device,
      touched: touched,
      onNotesChanged: refresh,
      // Which notes say they are meetings, beside the preferences (lib/meet/meeting_mark.dart).
      notesNow: shownNotes,
      // Each organization's channel, then the mentions this device typed in its notes told (lib/mentions).
      // And then its tickets' changes told to their watchers (lib/book/ticket_events.dart).
      teamNotes: ticketEventsAfter(
        mentionsAfter(teamNotesPass(docs), mentions, me: () => account.session?.handle, words: (id) async => (await notes.get(id))?.body, title: (id, words) => noteTitle(words)),
        ticketEvents,
        me: () => account.session?.handle,
        words: (id) async => (await notes.get(id))?.body,
        title: (id, words) => ticketNoticeTitle(words, noteTitle(words)),
      ),
      // The notifications, then the verified pages this account vouches for that ran out told in its bell
      // (lib/verified/verified_notices.dart).
      feedPass: (ctx) async {
        final fed = await syncNotifications(ctx);
        final session = account.session;
        // A day runs out a day at a time: looked for once an hour, not on every look at the bell.
        final now = DateTime.now();
        if (session != null && (expiriesAt == null || now.difference(expiriesAt!) > const Duration(hours: 1))) {
          expiriesAt = now;
          try {
            final held = await notes.list();
            await tellExpiredPages(record: record, accountId: session.accountId, me: session.handle, notes: [for (final note in held) (id: note.id, body: note.body, title: noteTitle(note.body))], kept: device);
          } catch (failure) {
            debugPrint('[verified] the pages that ran out were not told: $failure');
          }
        }
        return fed;
      },
      forgetTeams: docs.forget,
      sharedLive: live.shared.isShared,
      tellChanged: live.nudges.tellChanged,
      mailIn: offered ? syncMail : null,
      // And, before the takes, the Discord plugin's word to the service: off on this device, Ghost stops joining the
      // account's Discord calls (lib/plugins/discord/calls.dart).
      meetIn: (ctx) async {
        await discordCallsFollowPlugin(api: ctx.api, token: ctx.token, kept: ctx.kept);
        return syncMeet(ctx);
      },
      // What was posted to the account's incoming webhooks (docs/INTEGRATIONS.md, §1): on every device, while the
      // Webhooks plugin is on.
      hooksIn: hooksWhileOn,
      // Answers to a form shared by its link, filed as tickets (docs/FORMS.md): on every device, a claim on the service
      // keeping each to one of them.
      formsIn: syncForms,
      // Claude's key and choices, the Slack and Discord channels, the GitHub token: the same on every device, each
      // sealed on its own (lib/sync/sealed_keys.dart; Matt, 2026-10-26).
      sealedKeys: SealedKeys(items: connectionItems, prefs: settings, device: () => thisDevice(device).id, heard: connectionChanges(), kept: device),
    );
    final noteLive = NoteLive(
      live: live,
      docs: docs,
      workspaces: workspaces,
      // The saved note, not the editor's words: the saved one is what the pass sync compares.
      hasUnsynced: (id) async {
        final note = await notes.get(id);
        return note != null && engine.hasUnsyncedChanges(note);
      },
      keepCopy: keepCopy ?? (_) async {},
    );
    // Settings › Account's "Live typing": the switch is this device's own flag (`glyph-live`, on unless turned off),
    // so a note of the account's own opened while it is on is live, and one turned off elsewhere is shown off.
    final typing = ValueNotifier<bool>(live.enabled.value);
    typing.addListener(() => live.enabled.set(typing.value));
    live.enabled.addListener(() => typing.value = live.enabled.value);
    // The bell's rows on the phone itself: posted while the app is behind another, and the worker's watch for
    // while it is closed, against this build's own service and no other.
    final phone = PhoneNotices(host: making.notices ?? const PhoneNoticesHost(), account: account, feed: feed, prefs: settings, base: making.base, kept: device);
    final services = AccountServices(
      account: account,
      engine: engine,
      orgs: orgs,
      orgKeys: orgKeys,
      feed: feed,
      shares: shares,
      sites: sites,
      mailIn: mailIn,
      meetIn: meetIn,
      phoneNotices: phone,
      listNotes: () async => shownNotes(),
      prefs: settings,
      workspaces: workspaces,
      liveTyping: typing,
      kept: device,
    );
    // A meeting's captions while Ghost is in it, sealed to the account and opened here as they come
    // (lib/meet/live_captions.dart): the meeting's note made at the first, and its words live in its Transcript.
    final captions = meetIn == null
        ? null
        : LiveCaptions(
            hooks: LiveCaptionsHooks(
              open: (meeting, n, wrapped, data) async {
                final pair = await keys.encryptionKey();
                if (pair == null) throw StateError('this device has not got the account’s encryption key yet');
                return openLive(crypto, pair, meeting: meeting, n: n, wrapped: wrapped, data: data);
              },
              catchUp: (meeting, after) async {
                final session = account.session;
                return session == null ? null : MeetApi(api).live(session.token, meeting, after: after);
              },
              noteFor: (meeting) async {
                if (account.session == null) return null;
                final booked = meetIn.meetings?.where((m) => m.id == meeting).firstOrNull;
                return liveNoteFor(
                  meeting,
                  notes: notes,
                  prefs: settings,
                  kept: device,
                  title: booked?.title,
                  now: DateTime.now().millisecondsSinceEpoch,
                  made: () async {
                    await refresh();
                    unawaited(engine.syncNow().catchError((Object _) {}));
                  },
                );
              },
              ended: (noteId) => markLiveNoteEnded(device, noteId, DateTime.now().millisecondsSinceEpoch),
            ),
          );
    return WiredAccount._(services, engine, docs, live, noteLive, phone, touched, notesChanged, captions);
  }

  /// What says a note was saved here, and that the notes changed: what the shares follow.
  final Listenable? _saved;
  final Listenable? _changed;

  final AccountServices services;
  final SyncEngine engine;
  final TeamDocs _docs;

  /// Live sync, and the door a note's desk opens a note through.
  final LiveServices live;
  final NoteLive noteLive;

  /// The phone's own notifications for what the feed brings.
  final PhoneNotices phone;
  bool _started = false;

  /// What this device kept of an account, read without asking the service anything; then the sync for the life of
  /// the app. Once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await services.account.restore();
    } catch (failure) {
      debugPrint('[ghost] the account kept on this device would not read: $failure');
    }
    // Before the first pass, so the rows it brings are heard.
    phone.start();
    engine.start();
    // What this device shares follows its edits (src/main.tsx `followShares()`): a few seconds after a save here, or
    // after notes changed by sync, every share that changed is written again; and once at launch.
    final saved = _saved ?? _changed;
    if (saved != null) services.shares?.follow(saved: saved, changed: identical(saved, _changed) ? null : _changed);
    // The organizations' rooms, held from here on for as long as the account is in them; and the connection itself
    // while signed in, so the service's word that a meeting's recording or a mail came is a fetch now, not at the
    // next pass five minutes on (lib/live/poke.dart).
    live.start(
      NudgeHooks(keys: engine.syncNotificationsNow, notes: engine.syncTeamsNow),
      PokeHooks(sync: engine.syncNow, meetings: services.meetIn?.readNow),
    );
    // And on that connection, a meeting's captions while Ghost is in it.
    final heard = captions;
    if (heard != null) _stopCaptions = live.hub.listenCaptions((frame) => unawaited(heard.heard(frame)));
  }

  /// The app came back to the front.
  void resumed() {
    live.resumed();
    engine.resumed();
    // What a meeting's captions said while the app was behind, from the frames the service kept.
    unawaited(captions?.catchUpAll());
  }

  /// The app left the front: the relay's socket is let go until it is back.
  void paused() => live.paused();

  void dispose() {
    // The shares stop following, and their wait is let go.
    services.shares?.dispose();
    services.sites?.dispose();
    services.mailIn?.dispose();
    services.meetIn?.dispose();
    _stopCaptions?.call();
    live.dispose();
    phone.dispose();
    engine.dispose();
    engine.sealedKeys?.dispose();
    unawaited(Future<void>.sync(_docs.forget).catchError((Object _) {}));
  }
}
