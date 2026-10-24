// The app's updates and the invitation's card put where they are read (lib/root/update_wiring.dart, ghost_root.dart):
// one Updates as the launch screen, Settings › About and the card above the notes are each handed it, the card
// through an install on the home page, and an invitation from the account's feed with its Accept and Decline.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/updates.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/launch/launch_screen.dart';
import 'package:ghost_md/aside/aside.dart' show writeSidebarShown;
import 'package:ghost_md/simple/simple_home.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/notes/notices.dart' as notices;
import 'package:ghost_md/orgs/types.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/update_wiring.dart';
import 'package:ghost_md/settings/panes/about_pane.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../orgs_ui/support.dart';

const _base = 'https://releases.example/flutter';
const _file = [1, 2, 3, 4, 5, 6];

/// A release address with one release on it, or none.
class _Server implements UpdateTransport {
  Map<String, Object?>? published = {'version': '0.2.0', 'versionCode': 2, 'sha256': 'the-hash', 'bytes': _file.length, 'url': 'ghost-flutter.apk'};
  Object? down;

  @override
  Future<Uint8List> read(String url) async {
    if (down != null) throw down!;
    if (published == null) throw UpdateFailure('$url: the server answered 404');
    return Uint8List.fromList(utf8.encode(url.endsWith('.sig') ? 'signed' : jsonEncode(published)));
  }

  @override
  Future<void> download(String url, File to, {required int limit, required void Function(int received) onProgress}) async {
    to.writeAsBytesSync(_file);
    onProgress(_file.length);
  }
}

class _Phone implements UpdatePhone {
  _Phone(this.dir);
  final String dir;
  String answer = 'started';
  final List<String> handed = [];

  @override
  Future<InstalledApp?> installed() async => InstalledApp(version: '0.1.0', versionCode: 1, updatesDir: dir);

  @override
  Future<String> install(String path) async {
    handed.add(path);
    return answer;
  }
}

/// The Mac's half: the new app put in place at once, and restarts counted.
class _MacPhone implements RestartingUpdatePhone {
  _MacPhone(this.dir, {this.version = '0.1.0', this.code = 1, this.justUpdated = false});
  final String dir;
  final String version;
  final int code;
  final bool justUpdated;
  int restarts = 0;

  @override
  Future<InstalledApp?> installed() async => InstalledApp(version: version, versionCode: code, updatesDir: dir, justUpdated: justUpdated);

  @override
  Future<String> install(String path) async => 'ready';

  @override
  Future<String> restart() async {
    restarts += 1;
    return 'restarting';
  }
}

Future<Object?> _core(String command, [Map<String, Object?> args = const {}]) async =>
    command == 'update_read' ? jsonDecode(utf8.decode(base64.decode(args['body'] as String))) : null;

FeedNotification _invite(String id, String orgId, {String state = 'pending', String kind = 'invite', int at = 0}) =>
    FeedNotification(id: id, kind: kind, at: at, from: 'sam', org: (id: orgId, name: 'Boo'), state: state);

OrgRow _row(String id, String state) => OrgRow(id: id, name: 'Boo', role: 'member', state: state);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late Directory dir;
  late _Server server;
  late _Phone phone;
  var recording = false;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ghost-updates-root');
    server = _Server();
    phone = _Phone('${dir.path}/updates');
    recording = false;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Updates make() => Updates(config: UpdatesConfig.of(source: _base, keys: const ['a-key'], debug: false)!, invoke: _core, phone: phone, transport: server, recording: () => recording);

  group('one Updates, as each screen is handed it', () {
    test('a build that never looks gives the launch screen nothing to say', () {
      expect(launchUpdatesOf(null), same(LaunchUpdates.none));
      expect(launchUpdatesOf(null).looks, isFalse);
    });

    test('the launch screen is told where the sync stands, by the engine\'s own word, and off for any other', () {
      expect(
        [for (final phase in <String?>['syncing', 'idle', 'error', 'off', null, 'paused']) launchSyncOf(phase)],
        [SyncPhase.syncing, SyncPhase.idle, SyncPhase.error, SyncPhase.off, SyncPhase.off, SyncPhase.off],
      );
    });

    test('the launch screen: checking, then what is out or why not', () async {
      final updates = make();
      final looking = updates.check();
      expect(launchUpdatesOf(updates).checking, isTrue);
      await looking;
      final found = launchUpdatesOf(updates);
      expect((found.checking, found.apkVersion, found.lastError, found.readyBuild), (false, '0.2.0', null, null));
      server.down = const UpdateFailure('$_base/apk.json: Connection refused');
      await updates.check();
      expect(launchUpdatesOf(updates).lastError, '$_base/apk.json: Connection refused');
      // Its own check is the updates' own.
      server.down = null;
      launchUpdatesOf(updates).check();
      await pumpEventQueue();
      expect(updates.lastError, isNull);
    });

    test('Settings › About: the ladder of settings/updateLines.ts, and Install for one found or stopped short', () async {
      final updates = make();
      var about = settingsUpdatesOf(updates);
      expect(about.version, ghostVersion, reason: 'until the phone has said which app this is');
      expect(updatesStatus(about), 'Not checked yet.');
      expect(about.sourceHost, 'releases.example');
      expect(buildLine(about), 'Built into the app · unknown build · updates from releases.example');
      expect((about.ready, about.alerts, about.releases.length, about.store), (false, null, 0, null));

      await updates.check();
      about = settingsUpdatesOf(updates);
      expect(about.version, '0.1.0');
      expect(updatesStatus(about), 'Ghost.md 0.2.0 is ready to install.');
      expect(aboutSummary(about), '0.1.0 · 0.2.0 ready to install');
      expect(about.installable, '0.2.0');

      phone.answer = 'permission';
      await updates.installApk();
      about = settingsUpdatesOf(updates);
      expect(about.installable, '0.2.0', reason: 'still offered while Android waits to be allowed');
      recording = true;
      await updates.installApk();
      expect(settingsUpdatesOf(updates).installable, '0.2.0', reason: 'and after one that failed');
      recording = false;
      phone.answer = 'started';
      settingsUpdatesOf(updates).onInstall!();
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      about = settingsUpdatesOf(updates);
      expect((about.installable, about.downloading), (null, null), reason: 'Android has it now');
      expect(phone.handed, hasLength(2));

      server.published = {...server.published!, 'version': '0.1.0', 'versionCode': 1};
      await updates.check();
      expect(updatesStatus(settingsUpdatesOf(updates)), 'Up to date.');
      server.down = const UpdateFailure('offline');
      await updates.check();
      expect(updatesStatus(settingsUpdatesOf(updates)), "Couldn't check for updates: offline");
    });

    test('the card above the notes: every phase of an install, in the card\'s own kinds', () async {
      final updates = make();
      expect(updateCardOf(updates).apk, isA<notices.ApkNone>());
      await updates.check();
      expect((updateCardOf(updates).apk as notices.ApkAvailable).version, '0.2.0');
      final seen = <Type>[];
      updates.addListener(() => seen.add(updateCardOf(updates).apk.runtimeType));
      phone.answer = 'permission';
      await updates.installApk();
      expect(seen.toSet(), {notices.ApkDownloading, notices.ApkNeedsPermission});
      recording = true;
      await updates.installApk();
      final failed = updateCardOf(updates).apk as notices.ApkFailed;
      expect((failed.version, failed.message), ('0.2.0', 'Stop the meeting first.'));
      recording = false;
      phone.answer = 'started';
      updateCardOf(updates).onInstall!();
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((updateCardOf(updates).apk as notices.ApkInstalling).version, '0.2.0');
      expect(updateCardOf(updates).ready, isFalse);
    });
  });

  group('the Mac\'s, as each screen is handed it', () {
    Updates makeMac(_MacPhone mac) => Updates(
          config: UpdatesConfig.of(source: _base, keys: const ['a-key'], debug: false)!,
          invoke: _core,
          phone: mac,
          transport: server,
          recording: () => recording,
          kind: UpdateKind.mac,
          openLink: (_) async {},
        );

    test('the card and About through an update put in place, in the Mac\'s words, and the launch after it', () async {
      final mac = _MacPhone('${dir.path}/updates');
      final updates = makeMac(mac);
      await updates.check();
      expect((updateCardOf(updates).apk as notices.ApkAvailable).version, '0.2.0');
      expect(updatesStatus(settingsUpdatesOf(updates)), 'Ghost.md 0.2.0 is ready to install.');

      await updates.installApk();
      expect((updateCardOf(updates).apk as notices.ApkReady).version, '0.2.0');
      var about = settingsUpdatesOf(updates);
      expect((about.restartable, about.installable), ('0.2.0', null));
      expect(updatesStatus(about), 'Ghost.md 0.2.0 is downloaded. Restart to update.');
      expect(aboutSummary(about), '0.1.0 · 0.2.0 ready, restart to update');
      // A check while it waits says nothing new.
      await updates.check();
      expect(updatesStatus(settingsUpdatesOf(updates)), 'Ghost.md 0.2.0 is downloaded. Restart to update.');

      // Restart to update, from About or from the card: the same.
      settingsUpdatesOf(updates).onRestart!();
      await pumpEventQueue();
      expect((updateCardOf(updates).apk as notices.ApkRestarting).version, '0.2.0');
      about = settingsUpdatesOf(updates);
      expect((about.restarting, updatesStatus(about)), ('0.2.0', 'Restarting into Ghost.md 0.2.0.'));
      expect(mac.restarts, 1);

      // The next launch is the new version, and says so where "Up to date" would be.
      final after = makeMac(_MacPhone('${dir.path}/updates', version: '0.2.0', code: 2, justUpdated: true));
      server.published = {...server.published!, 'version': '0.2.0', 'versionCode': 2};
      await after.check();
      expect(launchUpdatesOf(after).updatedTo, '0.2.0');
      expect(updatesStatus(settingsUpdatesOf(after)), 'Up to date.');
      // And a launch that is not one says nothing of it.
      expect(launchUpdatesOf(updates).updatedTo, isNull);
    });
  });

  group('in the app', () {
    Future<void> open(WidgetTester tester, Updates? updates) async {
      await pumpApp(
        tester,
        prefs: const Preferences(theme: 'light'),
        home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored(), updates: updates),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> close(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('with no updates there is no card, and About has no Updates rows', (tester) async {
      await open(tester, null);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('update-notice')), findsNothing);
      expect(tester.widget<SettingsSheet>(find.byType(SettingsSheet)).updates, isNull);
      await close(tester);
    });

    testWidgets('a newer version found four seconds in is a card above the notes, installed from it, and in About', (tester) async {
      final updates = make();
      await open(tester, updates);
      expect(find.byKey(const ValueKey('update-notice')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ghost.md 0.2.0 is out.'), findsOneWidget);
      final about = tester.widget<SettingsSheet>(find.byType(SettingsSheet)).updates!;
      expect(updatesStatus(about), 'Ghost.md 0.2.0 is ready to install.');

      // Install: the file comes down (real files, so outside the test's clock) and Android is handed it.
      await tester.runAsync(updates.installApk);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ghost.md 0.2.0 is waiting on Android.'), findsOneWidget);
      expect(phone.handed, ['${dir.path}/updates/ghost-2.apk']);

      // The root goes, as at a reset; the updates are the process's and outlive it.
      await close(tester);
      expect(updates.apk, isA<ApkPhaseInstalling>());
      updates.dispose();
    });

    testWidgets('on a Mac the card offers the version, then Restart to update once it is in place', (tester) async {
      final mac = _MacPhone('${dir.path}/updates');
      final updates = Updates(config: UpdatesConfig.of(source: _base, keys: const ['a-key'], debug: false)!, invoke: _core, phone: mac, transport: server, kind: UpdateKind.mac, openLink: (_) async {});
      await open(tester, updates);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ghost.md 0.2.0 is out.'), findsOneWidget);
      await tester.runAsync(updates.installApk);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ghost.md 0.2.0 is ready.'), findsOneWidget);
      await tester.tap(find.text('Restart to update'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(mac.restarts, 1);
      expect(find.textContaining('Restarting into Ghost.md 0.2.0.', findRichText: true), findsOneWidget);
      await close(tester);
      updates.dispose();
    });

    testWidgets('the sidebar carries the card on a window in two panes, whichever style is chosen, and a phone\'s card leaves it to the home page', (tester) async {
      Future<Updates> shown(Size size, String style, {bool docked = false}) async {
        final updates = make();
        final local = MemoryStored();
        if (docked) writeSidebarShown(true, local);
        await pumpApp(
          tester,
          size: size,
          prefs: Preferences(theme: 'light', sidebarStyle: style),
          home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: local, updates: updates),
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 500));
        if (!docked) {
          // The notes' icon in the bar opens them as a card.
          await tester.tap(find.bySemanticsLabel('All your notes'));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        return updates;
      }

      // The Fold opened, the sidebar shown: simple's list beside the note has it over its rows (Matt, 2026-10-24:
      // "make the sidebar on advanced mode the same as simple"), whichever style is chosen.
      for (final style in ['docked', 'popover']) {
        final updates = await shown(const Size(704, 933), style, docked: true);
        expect(tester.widget<SimpleHome>(find.byType(SimpleHome)).notices.single, isA<notices.UpdateNotice>());
        expect(find.descendant(of: find.bySemanticsLabel('Your notes'), matching: find.text('Ghost.md 0.2.0 is out.')), findsOneWidget);
        await close(tester);
        updates.dispose();
      }

      // A phone: its home page says it, and its card of notes does not say it again.
      final updates = await shown(const Size(390, 844), 'popover');
      expect(tester.widget<NotesDrawer>(find.byType(NotesDrawer)).notices, isEmpty);
      expect(find.text('Ghost.md 0.2.0 is out.'), findsOneWidget);
      await close(tester);
      updates.dispose();
    });

    testWidgets('while a meeting records the root says so, and nothing is fetched', (tester) async {
      final updates = make();
      await open(tester, updates);
      await tester.pump(const Duration(seconds: 4));
      // The root gave its own answer for the meeting at its start: no voice here, so never recording.
      updates.recording = () => true;
      await tester.runAsync(updates.installApk);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ghost.md 0.2.0 didn’t install. Stop the meeting first.'), findsOneWidget);
      expect(phone.handed, isEmpty);
      await close(tester);
      updates.dispose();
    });
  });

  group('an invitation', () {
    test('is the newest still pending whose organization the account is still invited to', () {
      final feed = [_invite('n3', 'gone'), _invite('n2', 'boo', state: 'accepted'), _invite('n1', 'boo'), _invite('n0', 'old')];
      final orgs = [_row('boo', 'invited'), _row('old', 'invited'), _row('mine', 'member')];
      expect(waitingInvite(feed, orgs)?.id, 'n1');
      expect(waitingInvite(feed, [_row('boo', 'member')]), isNull, reason: 'answered on another device');
      expect(waitingInvite(feed, const []), isNull, reason: 'deleted under it');
      expect(waitingInvite([_invite('n1', 'boo', kind: 'member-joined')], orgs), isNull);
      expect(waitingInvite(const [], orgs), isNull);
    });

    testWidgets('is a card with who sent it, and Accept joins and opens the organization', (tester) async {
      final device = await Device.make();
      final opened = <String>[];
      await device.pump(tester, InviteWaiting(services: device.services, onOpen: opened.add));
      expect(find.byKey(const ValueKey('invite-notice')), findsNothing, reason: 'nothing to say with none waiting');

      final id = device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      await settle(tester);
      expect(find.byKey(const ValueKey('invite-notice')), findsOneWidget);
      expect(find.text('sam invited you to Boo'), findsOneWidget);
      expect(find.text('Accept to join; its workspace is made for you.'), findsOneWidget);
      await tapKey(tester, 'invite-accept');
      await settle(tester, 14);
      expect(device.service.rowIn(id), (role: 'member', state: 'member'));
      expect(opened, [id]);
      expect(find.byKey(const ValueKey('invite-notice')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('declined, it goes and nothing opens', (tester) async {
      final device = await Device.make();
      final id = device.service.invited('Boo', 'sam');
      await device.services.syncNow();
      final opened = <String>[];
      await device.pump(tester, InviteWaiting(services: device.services, onOpen: opened.add));
      expect(find.text('sam invited you to Boo'), findsOneWidget);
      await tapKey(tester, 'invite-decline');
      await settle(tester, 14);
      expect(device.service.rowIn(id)?.state, isNot('member'));
      expect(opened, isEmpty);
      expect(find.byKey(const ValueKey('invite-notice')), findsNothing);
      await endSettings(tester);
    });
  });
}
