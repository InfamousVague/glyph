// Lovart's header images for the recent notes as the app's own job, the app put together (lib/root,
// lib/plugins/lovart/banner_run.dart; Matt, 2026-10-26: "Make the header generation async and a background task that
// runs while the app is generating the images"): the line on home with Stop while it runs, the toast as it ends, and a
// note open in its editor given its banner without losing what is being typed.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/banner.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../plugins/github/support.dart' show useGround;
import '../plugins/lovart/banners_test.dart' show GatedClient;
import '../support/render.dart';

const String _words = 'We drove down on Friday, stayed in the old house by the river, walked the market on Saturday morning, '
    'ate far too much at the corner place, and came home on Sunday with a bag of oranges and a plan to go back in spring.';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late SampleLibrary library;
  late GatedClient gated;

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    useGround();
    await lovart.host.secrets.write(lovart.accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(lovart.secretKeySecret, 'sk-1');
    lovartPictureStore = MemoryPictureStore();
    gated = GatedClient();
    lovartClient = () => gated;
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
    lovartBannerRun.value = null;
    library = SampleLibrary.seeded();
    // The seeded notes count as given one, so the run is the notes a test makes.
    lovart.host.storage.set(lovart.bannersDoneKey, [for (final note in library.value) note.id]);
  });

  tearDown(() {
    gated.openAll();
    lovartPictureStore = null;
    lovartClient = () => LovartClient.kept();
    usePlugins(createRegistry(const []));
  });

  Future<void> pumpRoot(WidgetTester tester) async {
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> leave(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the run is the root\'s: its line on home with Stop while it runs, the ring in the header, and nothing said of a run the person stopped', (tester) async {
    for (var i = 0; i < 6; i += 1) {
      library.create('# Trip $i\n\n$_words');
    }
    await pumpRoot(tester);
    expect(lovartBannerJob, isNotNull);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing);
    final running = lovartBannerJob!.start();
    await settle(tester, 2);
    expect(find.textContaining('Making header images · 0 of 6', findRichText: true), findsOneWidget);
    gated.openOne();
    await settle(tester, 2);
    expect(find.textContaining('Making header images · 1 of 6', findRichText: true), findsOneWidget);
    // On the app's record of running work: the ring in the header (docs/ACTIVITY.md).
    expect(find.byKey(const ValueKey('header:activity')), findsOneWidget);
    // Its Stop, on the line.
    await tester.tap(find.byKey(const ValueKey('job-notice-action')));
    gated.openAll();
    await running;
    await settle(tester, 3);
    expect(lovartBannerRun.value!.asked, isTrue);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing, reason: 'a run the person stopped leaves no line');
    // It was a toast; a Stop the person pressed is said by nothing now, and its chip is not drawn.
    expect(find.text('Header images stopped · 4 made · about 24 credits'), findsNothing);
    await leave(tester);
  });

  testWidgets('a run that ends says so by its chip, once for the whole run (docs/ACTIVITY.md, Results)', (tester) async {
    for (var i = 0; i < 3; i += 1) {
      library.create('# Trip $i\n\n$_words');
    }
    await pumpRoot(tester);
    gated.open = true;
    await lovartBannerJob!.start();
    await settle(tester, 3);
    expect(find.text('Header images made for 3 notes · about 18 credits'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-chips')), findsOneWidget);
    await leave(tester);
  });

  testWidgets('stopped for credits, the line says why until Hide', (tester) async {
    library.create('# Trip\n\n$_words');
    await pumpRoot(tester);
    gated
      ..open = true
      ..fails = const LovartFailure('Your Lovart credits have run out.');
    await lovartBannerJob!.start();
    await settle(tester, 3);
    expect(find.text('Header images stopped at 0 of 1: Your Lovart credits have run out.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('job-notice-action')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing);
    await leave(tester);
  });

  testWidgets('a note open in its editor gets its banner as an edit there, and keeps what is typed before and while it is made', (tester) async {
    final note = library.create('# Trip\n\n$_words');
    await pumpRoot(tester);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote(note.id);
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    void type(String words) {
      final end = view.state.doc.length;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: words), userEvent: 'input.type'));
    }

    type('\n\nTyped before.');
    final running = lovartBannerJob!.start();
    await tester.pump();
    // Lovart at work; the person types on, and the save's debounce passes.
    type(' Typed while it was made.');
    await settle(tester, 6);
    expect(bannerOf(library.noteOf(note.id)!.body), isNull);
    gated.openAll();
    await running;
    await tester.pump();
    final body = screen.body;
    expect(bannerOf(body), isNotNull, reason: 'the banner landed in the open editor');
    expect(body, endsWith('$_words\n\nTyped before. Typed while it was made.'));
    expect(lovartBannerRun.value!.made, 1);
    // Typing goes on after it, and every word is saved: the editor's saving was never refused.
    type(' And after.');
    await settle(tester, 10);
    final kept = library.noteOf(note.id)!.body;
    expect(bannerOf(kept), bannerOf(body));
    expect(kept, endsWith('Typed before. Typed while it was made. And after.'));
    shell.backToList();
    await settle(tester, 10);
    expect(library.noteOf(note.id)!.body, kept);
    await leave(tester);
  });
}
