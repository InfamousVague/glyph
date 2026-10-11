import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/open_link.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/orgs/join_links.dart';
import 'package:ghost_md/orgs/ui/join_sheet.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/share/app_links.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../account_ui/support.dart' show Device;
import '../support/render.dart';

/// The phone's links, as a test says them: [kept] is what the activity holds until asked.
class _Links implements LinkSource {
  final List<String> kept = [];
  final StreamController<void> _arrived = StreamController<void>.broadcast();
  int asked = 0;

  /// Another link while the app runs.
  void arrive(String link) {
    kept.add(link);
    _arrived.add(null);
  }

  @override
  Future<List<String>> take() async {
    asked += 1;
    final all = [...kept];
    kept.clear();
    return all;
  }

  @override
  String? takeActivityLink() => null;

  @override
  Stream<void> get arrived => _arrived.stream;
}

/// Links that open the app, followed by the app put together (lib/root) as `shell/useAppLinks.ts` follows them, and
/// an address in a note handed to the phone.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late _Links links;
  late List<String> opened;

  Future<SampleLibrary> open(WidgetTester tester, {AccountServices? services, List<String> first = const []}) async {
    final library = SampleLibrary.seeded();
    links = _Links()..kept.addAll(first);
    opened = [];
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        services: services,
        links: links,
        openLink: (url) async => opened.add(url),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).closeNotifications();
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  group('a link that opened the app', () {
    testWidgets('is taken once the notes are read: a note link opens that note', (tester) async {
      final id = SampleLibrary.seeded().value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id;
      await open(tester, first: ['ghostmd://note/$id']);
      await settle(tester);
      expect(links.asked, 1);
      expect(shellOf(tester).shown, id);
      await close(tester);
    });

    testWidgets('arriving while the app runs is followed too', (tester) async {
      final library = await open(tester);
      await settle(tester, 2);
      expect(shellOf(tester).shown, isNull);
      final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week');
      links.arrive('ghostmd://note/${note.id}');
      await settle(tester);
      expect(shellOf(tester).shown, note.id);
      await close(tester);
    });

    testWidgets('names a note that is not there: nothing opens', (tester) async {
      await open(tester);
      await settle(tester, 2);
      links.arrive('ghostmd://note/nobody-has-this');
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenList>());
      await close(tester);
    });

    testWidgets('opens the notifications drawer', (tester) async {
      await open(tester);
      await settle(tester, 2);
      expect(shellOf(tester).notificationsOpen, isFalse);
      links.arrive('ghostmd://notifications');
      await settle(tester, 3);
      expect(shellOf(tester).notificationsOpen, isTrue);
      await close(tester);
    });

    testWidgets('opens an organization\'s dashboard, in a build with an account, and nothing in one with none', (tester) async {
      await open(tester);
      await settle(tester, 2);
      links.arrive('ghostmd://org/abcDEF123');
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenList>());
      await close(tester);

      final device = await tester.runAsync(Device.make);
      await open(tester, services: device!.services);
      await settle(tester, 2);
      links.arrive('ghostmd://org/abcDEF123');
      await settle(tester, 3);
      expect(shellOf(tester).screen, const ScreenOrganization('abcDEF123'));
      await close(tester);
    });

    testWidgets('asks before an invitation is joined, and holds its code on this device', (tester) async {
      final device = await tester.runAsync(() => Device.make(signedIn: false));
      await open(tester, services: device!.services);
      await settle(tester, 2);
      // The way in is up at launch: the invitation waits behind it.
      await tester.tap(find.byKey(const ValueKey('account-gate-skip')));
      await settle(tester, 3);
      expect(find.byType(JoinSheet), findsNothing);
      links.arrive('ghostmd://join/AbCdEfGh12345678');
      await settle(tester, 3);
      final sheet = tester.widget<JoinSheet>(find.byType(JoinSheet));
      expect(sheet.code, 'AbCdEfGh12345678');
      expect(heldJoin(kept: device.kept), 'AbCdEfGh12345678');
      expect(device.services.joined, isEmpty, reason: 'nothing is joined until the person says so');
      await close(tester);
    });

    testWidgets('is not pushed as a route: the phone hands Flutter the address too, and there is still one app', (tester) async {
      await open(tester);
      await settle(tester, 2);
      for (final address in ['ghostmd://notifications', 'ghostmd://note/abc', 'ghostmd://fork#id.key']) {
        final call = const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': address}));
        await tester.runAsync(() => tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', call, (_) {}));
        await settle(tester, 2);
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(GhostRoot), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
      await close(tester);
    });

    testWidgets('that is none of the app\'s is left alone', (tester) async {
      await open(tester, first: ['ghostmd://nowhere', 'https://example.com/', 'ghostmd://note/../../etc']);
      await settle(tester, 3);
      expect(shellOf(tester).screen, isA<ScreenList>());
      expect(shellOf(tester).notificationsOpen, isFalse);
      expect(find.byType(JoinSheet), findsNothing);
      expect(opened, isEmpty);
      await close(tester);
    });
  });

  group('a shared link\'s copy', () {
    testWidgets('is offered from the + only where the build has a service to read it from', (tester) async {
      await open(tester);
      expect(tester.widget<NewSheet>(find.byType(NewSheet)).onFromLink, isNull);
      await close(tester);

      final device = await tester.runAsync(Device.make);
      await open(tester, services: device!.services);
      await settle(tester, 2);
      final from = tester.widget<NewSheet>(find.byType(NewSheet)).onFromLink;
      expect(from, isNotNull);
      // An invite pasted where a share was asked for is an invite: asked about, and nothing saved.
      await tester.runAsync(() => from!('ghostmd://join/AbCdEfGh12345678'));
      await settle(tester, 3);
      expect(find.byType(JoinSheet), findsOneWidget);
      await close(tester);
    });
  });

  group('an address', () {
    testWidgets('tapped in a note, on a canvas or in Settings is handed to the phone', (tester) async {
      final library = await open(tester);
      shellOf(tester).openNote(library.value.first.id);
      await settle(tester);
      final world = tester.widget<NoteDesk>(find.byType(NoteDesk)).world;
      await world.openLink!('https://example.com/a');
      tester.widget<SettingsSheet>(find.byType(SettingsSheet)).onOpenLink!('https://example.com/b');
      expect(opened, ['https://example.com/a', 'https://example.com/b']);
      await close(tester);
    });

    test('only the five schemes reach the phone', () {
      for (final url in ['https://example.com', 'http://example.com/x', 'mailto:a@example.com', 'tel:+15550100', 'geo:51.5,-0.12']) {
        expect(canOpenLink(url), isTrue, reason: url);
      }
      for (final url in ['javascript:alert(1)', 'file:///etc/passwd', 'content://x', 'intent://x#Intent;end', 'ghostmd://note/a', 'https://', 'https://exa mple.com', '']) {
        expect(canOpenLink(url), isFalse, reason: url);
      }
    });
  });
}
