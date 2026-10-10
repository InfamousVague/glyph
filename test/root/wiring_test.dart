import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/find_bar/find_bar.dart';
import 'package:ghost_md/editor/items/items.dart' show FieldMenuHost;
import 'package:ghost_md/editor/plus/plus.dart' show PlusLayer;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/account_wiring.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/shell/account_gate.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../account_ui/support.dart' show Device;
import '../support/render.dart';

/// The app put together (lib/root): a note opens on the editor that is typed in, with every piece round it, and
/// what is typed is saved to the library; the account is there only where the build was given one.
void main() {
  setUpAll(loadAppFonts);

  Future<SampleLibrary> open(WidgetTester tester, {AccountServices? services, Size size = const Size(390, 844)}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, services: services),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> openNote(WidgetTester tester, String id) async {
    tester.state<AppShellState>(find.byType(AppShell)).openNote(id);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets go of the app, and of the timers a note's screen leaves (its place, its save).
  Future<void> close(WidgetTester tester) async {
    // Home first: a note taken down with the whole shell clears its tools from a bar that is already gone.
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // The binding's own switch for shadows, which `pumpApp` turned on.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('the base a build is given', () {
    test('none is no account', () {
      expect(accountBase(''), isNull);
      expect(accountBase('   '), isNull);
    });

    test('a local server is taken, without its last slash', () {
      expect(accountBase('http://10.0.2.2:4010/api'), 'http://10.0.2.2:4010/api');
      expect(accountBase('http://127.0.0.1:4010/api/'), 'http://127.0.0.1:4010/api');
    });

    test('the real service is refused in a build that is not a release', () {
      for (final base in ['https://ghostmarkdown.com/api', 'https://www.ghostmarkdown.com/api', 'https://attack.fm/glyph/api']) {
        expect(accountBase(base, debug: true), isNull, reason: base);
      }
      expect(accountBase('https://ghostmarkdown.com/api', debug: false), 'https://ghostmarkdown.com/api');
    });

    test('what is not an http address is no account', () {
      expect(accountBase('ghostmarkdown'), isNull);
      expect(accountBase('ftp://10.0.2.2/api'), isNull);
    });

    test('Live typing’s switch is this device’s own flag, so a note of the account’s own can be live', () {
      final kept = MemoryStored();
      Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async => null;
      final wired = WiredAccount.make(
        making: AccountMaking(base: 'http://127.0.0.1:9/api', crypto: CoreCrypto(core), dataDir: '/nowhere', fetcher: (_) async => throw StateError('nothing is asked'), secure: MemorySecureStore()),
        core: core,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        versions: VersionsStore(core, kept: kept),
        touched: null,
        refresh: () {},
        shownNotes: () => const [],
        prefs: PreferencesStore()..startWithoutStorage(),
        kept: kept,
      );
      addTearDown(wired.dispose);
      // Off until set, as the page's.
      expect((wired.services.liveTyping.value, wired.live.enabled.value, kept.readText('glyph-live')), (false, false, null));
      // The switch on Settings › Account › Sync.
      wired.services.liveTyping.value = true;
      expect((wired.live.enabled.value, kept.readText('glyph-live')), (true, '1'));
      wired.services.liveTyping.value = false;
      expect((wired.live.enabled.value, kept.readText('glyph-live')), (false, null));
      // Turned on from elsewhere, the switch is drawn on.
      wired.live.enabled.set(true);
      expect(wired.services.liveTyping.value, isTrue);

      // A device that had it on opens with the switch on.
      final again = WiredAccount.make(
        making: AccountMaking(base: 'http://127.0.0.1:9/api', crypto: CoreCrypto(core), dataDir: '/nowhere', fetcher: (_) async => throw StateError('nothing is asked'), secure: MemorySecureStore()),
        core: core,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        versions: VersionsStore(core, kept: kept),
        touched: null,
        refresh: () {},
        shownNotes: () => const [],
        prefs: PreferencesStore()..startWithoutStorage(),
        kept: kept,
      );
      addTearDown(again.dispose);
      expect(again.services.liveTyping.value, isTrue);
    });

    test('the phone’s own notifications are made for the service the build was given, and handed to Settings', () {
      final kept = MemoryStored();
      Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async => null;
      final wired = WiredAccount.make(
        making: AccountMaking(base: 'http://127.0.0.1:9/api', crypto: CoreCrypto(core), dataDir: '/nowhere', fetcher: (_) async => throw StateError('nothing is asked'), secure: MemorySecureStore()),
        core: core,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        versions: VersionsStore(core, kept: kept),
        touched: null,
        refresh: () {},
        shownNotes: () => const [],
        prefs: PreferencesStore()..startWithoutStorage(),
        kept: kept,
      );
      addTearDown(wired.dispose);
      // The worker is handed this address and no other: there is none built in (lib/sync/phone.dart).
      expect(wired.phone.base, 'http://127.0.0.1:9/api');
      expect(wired.services.phoneNotices, same(wired.phone));
      // A build that is not a release is given no base for the real service, so nothing above is ever made for it.
      expect(accountBase('https://ghostmarkdown.com/api', debug: true), isNull);
      expect(accountBase('https://attack.fm/glyph/api', debug: true), isNull);
    });

    // Unwired 2 (docs/PARITY.md): `Shares.follow` had no caller, so a shared link never followed an edit while
    // Settings said "Your edits follow it." (src/main.tsx `followShares()`, at launch).
    test('the shares follow a save here and notes changed by sync from the account\'s start, and stop with it', () async {
      final kept = MemoryStored();
      Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async => null;
      final saved = _Heard(), changed = _Heard();
      final wired = WiredAccount.make(
        making: AccountMaking(base: 'http://127.0.0.1:9/api', crypto: CoreCrypto(core), dataDir: '/nowhere', fetcher: (_) async => throw StateError('nothing is asked'), secure: MemorySecureStore()),
        core: core,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        versions: VersionsStore(core, kept: kept),
        touched: saved,
        refresh: () {},
        shownNotes: () => const [],
        notesChanged: changed,
        prefs: PreferencesStore()..startWithoutStorage(),
        kept: kept,
      );
      expect(changed.heard, isFalse);
      await wired.start();
      // The engine hears a save too; only the shares hear the notes change by another hand.
      expect((saved.heard, changed.heard), (true, true));
      wired.dispose();
      expect(changed.heard, isFalse);
    });

    test('a way in with no service says so', () async {
      await expectLater(noServiceWayIn(mode: 'in', handle: 'matt', password: 'correct horse'), throwsA(isA<SaidFailure>().having((f) => f.words, 'words', noServiceWords)));
    });
  });

  group('a note', () {
    testWidgets('opens on the editor that is typed in, with the band, the + and a chip\'s menu round its page', (tester) async {
      final library = await open(tester);
      await openNote(tester, library.value.first.id);
      expect(find.byType(NoteDesk), findsOneWidget);
      expect(find.byType(Editor), findsOneWidget);
      // Round the page that scrolls, which keeps its place in the tree.
      for (final layer in [FieldMenuHost, PlusLayer, ContextBand]) {
        expect(find.ancestor(of: find.byType(CustomScrollView), matching: find.byType(layer)), findsOneWidget, reason: '$layer');
      }
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      expect(view.state.readOnly, isFalse);
      await close(tester);
    });

    testWidgets('saves what is typed to the library', (tester) async {
      final library = await open(tester);
      final note = library.value.first;
      await openNote(tester, note.id);
      final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
      final view = screen.view!;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '\n\nTyped in stage four.'), userEvent: 'input.type'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(library.noteOf(note.id)!.body, endsWith('Typed in stage four.'));
      await close(tester);
    });

    testWidgets('keeps its scroll position when the editor\'s view arrives and when a chip\'s menu opens', (tester) async {
      final library = await open(tester);
      await openNote(tester, library.value.first.id);
      final position = tester.state<ScrollableState>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first).position;
      await tester.pump(const Duration(seconds: 1));
      // Disposed, it would throw here: the place keeper holds the one it was made with.
      expect(() => position.pixels, returnsNormally);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('finds from the desk, in a bar at the page\'s foot, and closes', (tester) async {
      final library = await open(tester);
      await openNote(tester, library.value.first.id);
      final desk = tester.state<NoteDeskState>(find.byType(NoteDesk));
      expect(desk.finding, isFalse);
      final context = tester.element(find.byType(NoteScreen));
      final seams = tester.widget<NoteScreen>(find.byType(NoteScreen)).seams;
      expect(context, isNotNull);
      seams.onFind!(tester.state<NoteScreenState>(find.byType(NoteScreen)).view!, 'the');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FindBar), findsOneWidget);
      expect(desk.finding, isTrue);
      await tester.tap(find.byKey(FindBarKeys.done));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FindBar), findsNothing);
      await close(tester);
    });

    testWidgets('has the cheat sheet, the bookmark and find, and its sharing without an account too, where the row says to sign in first', (tester) async {
      final library = await open(tester);
      await openNote(tester, library.value.first.id);
      final seams = tester.widget<NoteScreen>(find.byType(NoteScreen)).seams;
      expect(seams.cheatSheet, isNotNull);
      expect(seams.bookmark, isNotNull);
      expect(seams.onFind, isNotNull);
      // NoteScreen.tsx `actions` and NoteSettings: Share and Sharing are there signed in or out.
      expect(seams.sharingSection, isNotNull);
      expect(seams.onShare, isNotNull);
      await close(tester);
    });
  });

  group('the account', () {
    testWidgets('is nowhere in a build that was given none', (tester) async {
      await open(tester);
      expect(AccountScope.maybeOf(tester.element(find.byType(AppShell))), isNull);
      expect(find.byType(AccountGate), findsNothing);
      await close(tester);
    });

    testWidgets('is over the shell where there is one, with the way in first on an open that is signed out', (tester) async {
      final device = await Device.make(signedIn: false);
      await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      expect(AccountScope.maybeOf(tester.element(find.byType(AppShell))), same(device.services));
      expect(find.byType(AccountGate), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-gate-skip')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AccountGate), findsNothing);
      await close(tester);
    });

    // Unwired 3 (docs/PARITY.md): the shell was never told, so the bell had no dot (App.tsx `unread`).
    testWidgets('puts the dot on the bell while something unread and wanted waits, and takes it off once read', (tester) async {
      final device = await Device.make();
      await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AppShell>(find.byType(AppShell)).unread, isFalse);
      device.service.notifies(kind: 'member-joined', from: 'sam', org: (id: 'o1', name: 'Ghost'), body: {'name': 'Ghost'});
      await tester.runAsync(device.services.syncNotificationsNow);
      await tester.pump();
      expect(device.services.notifications, hasLength(1));
      expect(tester.widget<AppShell>(find.byType(AppShell)).unread, isTrue);
      // Settings › Notifications' Team switch off: unread still, and not wanted.
      preferences.update((now) => now.copyWith(notifications: const NotificationPrefs(team: false)));
      await tester.pump();
      expect(tester.widget<AppShell>(find.byType(AppShell)).unread, isFalse);
      preferences.update((now) => now.copyWith(notifications: const NotificationPrefs()));
      await tester.pump();
      expect(tester.widget<AppShell>(find.byType(AppShell)).unread, isTrue);
      device.feed.markAllRead();
      await tester.pump();
      expect(tester.widget<AppShell>(find.byType(AppShell)).unread, isFalse);
      await close(tester);
    });

    // Unwired 4 (docs/PARITY.md): every version was written by "me", so the history and an organization's audit
    // log said "You" for everyone (core/versions/record.ts `keeper`).
    testWidgets('signs a version kept here with the account\'s handle, and "me" with nobody signed in', (tester) async {
      final device = await Device.make();
      final library = await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      final id = library.value.first.id;
      await openNote(tester, id);
      final versions = tester.widget<NoteScreen>(find.byType(NoteScreen)).versions!;
      await tester.runAsync(() => versions.keepVersion(id, 'As it was.', now: 1000));
      await tester.runAsync(device.account.signOut);
      await tester.runAsync(() => versions.keepVersion(id, 'As it is.', now: 2000));
      final kept = (await tester.runAsync(() => versions.versionsOf(id)))!.versions;
      expect([for (final version in kept) version.by], ['matt', 'me']);
      await close(tester);
    });

    testWidgets('gives a note its sharing and the shell its organizations, signed in', (tester) async {
      final device = await Device.make();
      final library = await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AccountGate), findsNothing);
      await openNote(tester, library.value.first.id);
      expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.sharingSection, isNotNull);
      expect(tester.widget<AppShell>(find.byType(AppShell)).organizationBuilder, isNotNull);
      await close(tester);
    });
  });
}

/// A listenable that says whether anything listens to it.
class _Heard extends ChangeNotifier {
  bool get heard => hasListeners;
}
