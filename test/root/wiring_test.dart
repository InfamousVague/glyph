import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/link_preview.dart' show LinkOpener;
import 'package:ghost_md/core/notifications.dart' show sentenceOf;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_share.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/find_bar/find_bar.dart';
import 'package:ghost_md/editor/items/items.dart' show FieldMenuHost;
import 'package:ghost_md/editor/plus/plus.dart' show PlusLayer, moreRows, readGates;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/live/presence.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';
import 'package:ghost_md/root/account_wiring.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/shell/account_gate.dart';
import 'package:ghost_md/settings/organization_sheet.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/record.dart';

import '../account_ui/support.dart' show Device;
import '../support/render.dart';
import 'part_of.dart';

/// The app put together (lib/root): a note opens on the editor that is typed in, with every piece round it, and
/// what is typed is saved to the library; the account is there only where the build was given one.
void main() {
  setUpAll(loadAppFonts);

  Future<SampleLibrary> open(WidgetTester tester, {AccountServices? services, Size size = const Size(390, 844), LinkOpener? openLink, List<Seen> Function(String orgId)? presence}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      // A memory of its own for each app opened: what one test kept on the device (a note's versions) is not there
      // for the next.
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), stored: MemoryStored(), clock: () => seedNow, services: services, openLink: openLink, presence: presence),
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

    // Unwired 10 (docs/PARITY.md): `Voice.make` was given no `record`, so a meeting written up never reached the
    // bell (ai/summaries.ts:688 `record('summary-written', …)`).
    test('a meeting written up is a row in the account\'s own feed, and nothing in a build with no account', () async {
      final device = await Device.make(engine: false);
      final engine = SyncEngine(
        account: AccountDoor(device.account),
        api: device.api,
        crypto: device.service.crypto,
        keys: device.keys,
        prefs: preferences,
        notes: device.notes,
        files: device.files,
        feed: device.feed,
        orgs: device.orgs,
        orgKeys: device.orgKeys,
        kept: device.kept,
        record: SelfNotifications(feed: device.feed, api: device.api),
      );
      addTearDown(engine.dispose);
      final services = AccountServices(account: device.account, engine: engine, orgs: device.orgs, orgKeys: device.orgKeys, feed: device.feed, listNotes: () async => const [], prefs: preferences, workspaces: device.workspaces, kept: device.kept);
      await feedRecord(() => services)('summary-written', {'noteId': 'n1', 'title': 'Standup'});
      final row = services.notifications.single;
      expect(sentenceOf(row, device.feed.openDetails(row)), 'A meeting was written up: Standup');
      expect(device.service.calls.where((call) => call == 'POST notifications'), hasLength(1));
      // No account in the build: asked, and nothing happens.
      await feedRecord(() => null)('summary-written', {'noteId': 'n1', 'title': 'Standup'});
      expect(device.service.calls.where((call) => call == 'POST notifications'), hasLength(1));
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

    // Unwired 6 (docs/PARITY.md): `AddConfig.blanks` was never set, so More never offered the two rows
    // (editor/addRows.ts: always there, since writing a blank needs no model).
    testWidgets('offers A blank for the AI from its +, and Blanks in the empty cells under a table with one', (tester) async {
      final library = await open(tester);
      await openNote(tester, library.value.first.id);
      final config = tester.widget<PlusLayer>(find.byType(PlusLayer)).config;
      expect(config.blanks, isTrue);
      List<String> more({required bool tableAbove}) => [
            for (final row in moreRows(readGates(picture: false, video: false, place: false, note: true, canvas: false, tableAbove: tableAbove, board: config.boards, database: config.databases, blank: config.blanks, effects: config.effects))) row.words,
          ];
      expect(more(tableAbove: false), contains('A blank for the AI'));
      expect(more(tableAbove: false), isNot(contains('Blanks in the empty cells')));
      expect(more(tableAbove: true), containsAllInOrder(['A blank for the AI', 'Blanks in the empty cells']));
      await close(tester);
    });

    // Unwired 19 (docs/PARITY.md): `leadLine()` had no caller, so a reading note's first paragraph was set as any
    // other (Editor.tsx `lookExtensions`: `look === 'reading' ? leadLine() : []`).
    testWidgets('of the Reading look sets the paragraph under its title as its lead, and no other look does', (tester) async {
      final library = await open(tester);
      final read = library.create('---\nlook: reading\n---\n# The long road\n\nIt went on for a while.\n\nAnd then it stopped.\n');
      await tester.pump();
      await openNote(tester, read.id);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      List<String> leads() {
        final found = <String>[];
        for (final set in view.decorations) {
          set.between(0, view.state.doc.length, (from, to, value) {
            if (value is LineDecoration && (value.spec.className ?? '').split(' ').contains('cm-lead')) found.add(view.state.doc.lineAt(from).text);
            return null;
          });
        }
        return found;
      }

      expect(leads(), ['It went on for a while.']);
      // The look taken off in the note's words: the same editor, and no lead.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: '---\nlook: reading\n---\n'.length, insert: ''), userEvent: 'input.type'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(leads(), isEmpty);
      await close(tester);
    });

    // Unwired 20 (docs/PARITY.md): `NoteSeams.shareVersionsFile` was never given, so the history's row was off. On
    // Android the page copies the file's text and says so (core/versions/share.ts: no share sheet in a WebView).
    testWidgets('hands over its versions file from its history: copied as text on the phone, and said', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final library = await open(tester);
      final note = library.value.first;
      await openNote(tester, note.id);
      final screen = tester.widget<NoteScreen>(find.byType(NoteScreen));
      final share = screen.seams.shareVersionsFile;
      expect(share, isNotNull);
      expect(await tester.runAsync(() => share!(note.id, 'Packing')), 'This note has no versions yet.');
      expect(copied, isEmpty);
      await tester.runAsync(() => screen.versions!.keepVersion(note.id, 'As it was.', now: 1000));
      expect(await tester.runAsync(() => share!(note.id, 'Packing')), 'This device can’t send a file, so the versions file is copied as text.');
      expect(copied.single, contains('As it was.'));
      expect(versionsFileName(' Trip: Lisbon / Porto? '), 'Trip  Lisbon   Porto.versions');
      expect(versionsFileName(''), 'Untitled.versions');
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

    // Unwired 13 (docs/PARITY.md): `onOrganization` was given to none of them, so an organization's workspace
    // opened the plain workspace sheet, whose one row could not be pressed (App.tsx:1281-1282,1591,1666).
    testWidgets('opens an organization from its workspace: the sidebar\'s "…" and All notes\' sheet its settings on their sections, All notes\' pill its page', (tester) async {
      final device = await Device.make();
      final id = (await tester.runAsync(() => device.orgs.createOrg('Ghost')))!.id;
      await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      OrganizationSheet? sheet() => tester.widgetList<OrganizationSheet>(find.byType(OrganizationSheet)).firstOrNull;

      // The sidebar, as the root draws it floating and docked.
      final drawer = partOf<NotesDrawer>(shell.context, tester.widget<AppShell>(find.byType(AppShell)).sidebarBuilder!(shell.context, shell, () {}));
      final docked = partOf<NoteTree>(shell.context, tester.widget<AppShell>(find.byType(AppShell)).dockedSidebarBuilder!(shell.context, shell));
      expect(drawer.onOrganization, isNotNull);
      expect(docked.onOrganization, isNotNull);
      drawer.onOrganization!(id);
      await tester.pump(const Duration(milliseconds: 400));
      expect((sheet()?.orgId, sheet()?.from, sheet()?.landOnMembers), (id, null, false));
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));
      expect(sheet(), isNull);

      // All notes: the pill is the organization's page, the sheet's row its settings.
      shell.showAllNotes();
      await tester.pump(const Duration(milliseconds: 400));
      final all = tester.widget<AllNotesScreen>(find.byType(AllNotesScreen));
      all.onOrganizationSettings!(id);
      await tester.pump(const Duration(milliseconds: 400));
      expect((sheet()?.orgId, sheet()?.from), (id, null));
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));
      all.onOrganization!(id);
      await tester.pump(const Duration(milliseconds: 400));
      expect(shell.screen, isA<ScreenOrganization>().having((screen) => screen.orgId, 'orgId', id));
      await close(tester);
    });

    // Unwired 14 (docs/PARITY.md): the sheet was never given `onOpenLink`, so Report a member or a note was drawn and
    // could not be pressed (settings/OrganizationSheet.tsx `openLink(reportMail(…))`).
    testWidgets('hands an organization\'s report to the phone as an email naming it', (tester) async {
      final device = await Device.make();
      final id = (await tester.runAsync(() => device.orgs.createOrg('Ghost')))!.id;
      final opened = <String>[];
      await open(tester, services: device.services, openLink: (url) async => opened.add(url));
      await tester.pump(const Duration(milliseconds: 200));
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onOrganization!(id);
      await tester.pump(const Duration(milliseconds: 400));
      final sheet = tester.widget<OrganizationSheet>(find.byType(OrganizationSheet));
      expect(sheet.onOpenLink, isNotNull);
      sheet.onOpenLink!(reportMail(orgId: id, name: 'Ghost', handle: device.services.session?.handle));
      expect(opened.single, startsWith('mailto:$reportTo?subject=Ghost.md%20report%3A%20Ghost'));
      expect(Uri.decodeComponent(opened.single), contains('Reported by: matt'));
      await close(tester);
    });

    // Unwired 15 (docs/PARITY.md): Jump to cursor handed on a member's caret and never their pointer, so a canvas
    // opened where it was left and not where they are (notes/OrganizationScreen.tsx `onJump(at.note, at.cursor ??
    // at.pointer)`).
    testWidgets('opens a canvas centred on a member\'s pointer from the organization\'s Jump to cursor', (tester) async {
      final device = await Device.make();
      final id = (await tester.runAsync(() => device.orgs.createOrg('Ghost')))!.id;
      // Named once the library has it: the root asks who is where from its first frame.
      String? canvasId;
      final library = await open(
        tester,
        services: device.services,
        presence: (orgId) => orgId == id && canvasId != null ? [Seen(handle: 'sam', hue: null, client: 9, at: Whereabouts(note: canvasId, title: 'Map', kind: 'canvas', pointer: const Spot(300, 200)))] : const [],
      );
      canvasId = library.create(canvasNoteBody('Map', parseCanvas('{"nodes":[{"id":"a","type":"text","text":"A card","x":0,"y":0,"width":120,"height":60}],"edges":[]}')!)).id;
      await tester.pump(const Duration(milliseconds: 200));
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      shell.openOrganization(id);
      await tester.pump(const Duration(milliseconds: 400));
      tester.widget<OrganizationScreen>(find.byType(OrganizationScreen)).onJumpTo!(canvasId);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<CanvasView>(find.byType(CanvasView)).goTo, (x: 300.0, y: 200.0));
      await close(tester);
    });

    test('a member\'s place in a note is their caret, else their pointer\'s spot, and nobody else\'s', () {
      const caret = {'anchor': 4, 'head': 9};
      Seen at(String note, {Map<String, Object?>? cursor, Spot? pointer}) => Seen(handle: 'sam', hue: null, client: 1, at: Whereabouts(note: note, title: '', cursor: cursor, pointer: pointer));
      expect(jumpPlace([at('n1', cursor: caret)], 'n1'), caret);
      expect(jumpPlace([at('n1', pointer: const Spot(3, 4))], 'n1'), {'x': 3.0, 'y': 4.0});
      expect(jumpPlace([at('n2', cursor: caret)], 'n1'), isNull);
      expect(jumpPlace([at('n1'), const Seen(handle: 'lee', hue: null, client: 2, at: null)], 'n1'), isNull);
    });

    // Differs 24 (docs/PARITY.md): Edit from home's filters opened an organization's settings on Members under
    // "← Organizations", and leaving one from its dashboard's cog left its emptied page on screen (App.tsx
    // `openOrganizationSettings` with no `from`, `closeOrganizationSettings`).
    testWidgets('opens an organization\'s settings on their sections from home\'s filters, and goes home when it was left from its own page', (tester) async {
      final device = await Device.make();
      final id = (await tester.runAsync(() => device.orgs.createOrg('Ghost')))!.id;
      await open(tester, services: device.services);
      await tester.pump(const Duration(milliseconds: 200));
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      OrganizationSheet? sheet() => tester.widgetList<OrganizationSheet>(find.byType(OrganizationSheet)).firstOrNull;
      tester.widget<HomeScreen>(find.byType(HomeScreen)).onOrganizationSettings!(id);
      await tester.pump(const Duration(milliseconds: 400));
      expect((sheet()?.from, sheet()?.landOnMembers), (null, false));
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));
      // From Settings' own list it lands on Members, under "← Organizations".
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onOrganization!(id);
      await tester.pump(const Duration(milliseconds: 400));
      expect((sheet()?.from, sheet()?.landOnMembers), (OrganizationFrom.settings, true));
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));

      // Its page, its cog, and the organization deleted from there: closing finds home, not the emptied page.
      shell.openOrganization(id);
      await tester.pump(const Duration(milliseconds: 400));
      tester.widget<OrganizationScreen>(find.byType(OrganizationScreen)).onSettings();
      await tester.pump(const Duration(milliseconds: 400));
      expect(sheet()?.from, OrganizationFrom.dashboard);
      // Closed with the organization still there: its page again.
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shell.screen, isA<ScreenOrganization>());
      tester.widget<OrganizationScreen>(find.byType(OrganizationScreen)).onSettings();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => device.orgs.deleteOrg(id));
      await tester.pump();
      sheet()!.onClose();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shell.screen, isA<ScreenList>());
      await close(tester);
    });

    testWidgets('offers none of it in a build with no account', (tester) async {
      await open(tester);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      expect((partOf<NotesDrawer>(shell.context, tester.widget<AppShell>(find.byType(AppShell)).sidebarBuilder!(shell.context, shell, () {}))).onOrganization, isNull);
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
