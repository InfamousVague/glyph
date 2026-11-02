// An index's card (lib/ai/indexes/index_card.dart; docs/AI_INDEXES.md §6; Matt, 2026-11-02: "for any folder or org,
// the AI keeps an index note"): the switch builds it, the line says where it stands, simple mode keeps the options
// behind More, another device's index offers Take over. With pictures, on a phone and a desktop, light and dark, into
// build/feature-shots/ai-indexes/ under --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:ghost_md/ai/indexes/index_ai.dart';
import 'package:ghost_md/ai/indexes/index_build.dart';
import 'package:ghost_md/ai/indexes/index_card.dart';
import 'package:ghost_md/ai/indexes/index_keeper.dart';
import 'package:ghost_md/ai/indexes/index_scope.dart';
import 'package:ghost_md/ai/indexes/index_section.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/page_tree.dart' show Space;
import 'package:ghost_md/orgs/ui/teamspace_home.dart';

import '../../sidebar/support.dart' show away, pumpPage;
import '../../support/feature_shot.dart';
import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  late ValueNotifier<List<Note>> library;
  late ScriptedAi ai;
  final now = t0.add(const Duration(hours: 2));

  IndexKeeper keeper(String id) => IndexKeeper(
        notes: library,
        get: (id) async => library.value.where((n) => n.id == id).firstOrNull,
        write: (id, change) async {
          library.value = [for (final n in library.value) n.id == id ? n.copyWith(body: change(n.body)) : n];
        },
        makePage: (folder, title) async {
          final page = note('page', '$folder/index.md', '# $title\n', at: ms(t0));
          library.value = [...library.value, page];
          return page;
        },
        pick: () => IndexAiPick(ai),
        deviceId: id,
        deviceName: id == 'mac' ? 'Mac' : 'phone',
        clock: () => t0,
        record: Activity(clock: () => t0),
      );

  setUp(() {
    ai = ScriptedAi();
    library = ValueNotifier(launchNotes());
  });

  Widget page(Widget child) => Builder(
        builder: (context) {
          final t = context.tokens;
          return Container(
            color: t.color('app-paper'),
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 60, 20, 40), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child))),
          );
        },
      );

  Future<void> show(WidgetTester tester, IndexKeeper k, {bool simple = false, Size size = const Size(390, 844), String theme = 'light'}) async {
    await pumpPage(tester, page(IndexCard(keeper: k, folder: 'workspaces/Launch', title: 'Launch', simple: simple, now: () => now)), size: size, theme: theme);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the switch turns it on and builds it; the line says when it was updated', (tester) async {
    final mac = keeper('mac');
    await show(tester, mac);
    expect(find.textContaining('kept up to date by the AI'), findsOneWidget);
    await tester.tap(find.byKey(IndexCard.switchKey));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    final written = library.value.firstWhere((n) => n.id == 'page').body;
    expect(IndexSettings.of(written).on, isTrue);
    expect(readSection(written).span, isNotNull);
    expect(ai.sent, hasLength(3));
    expect(find.text('Updated 2 hr ago · Claude'), findsOneWidget);
    expect(find.byKey(IndexCard.refreshKey), findsOneWidget);
    expect(find.byKey(IndexCard.everyKey(IndexEvery.nightly)), findsOneWidget);
    mac.dispose();
    await away(tester);
  });

  testWidgets('simple mode: the switch and its line, How often and Rebuild behind More', (tester) async {
    final mac = keeper('mac');
    await mac.turnOn('workspaces/Launch', title: 'Launch');
    await show(tester, mac, simple: true);
    expect(find.byKey(IndexCard.everyKey(IndexEvery.hourly)), findsNothing);
    expect(find.byKey(IndexCard.rebuildKey), findsNothing);
    await tester.tap(find.byKey(IndexCard.moreKey));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(IndexCard.everyKey(IndexEvery.hourly)), findsOneWidget);
    expect(find.byKey(IndexCard.rebuildKey), findsOneWidget);
    mac.dispose();
    await away(tester);
  });

  testWidgets('another device’s index: kept by it, no Refresh here, Take over behind More', (tester) async {
    final mac = keeper('mac'), phone = keeper('phone');
    await mac.turnOn('workspaces/Launch', title: 'Launch');
    await show(tester, phone, simple: true);
    expect(find.textContaining('Kept by the Mac'), findsOneWidget);
    expect(find.byKey(IndexCard.refreshKey), findsNothing);
    await tester.tap(find.byKey(IndexCard.moreKey));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(IndexCard.takeOverKey));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(IndexSettings.of(library.value.firstWhere((n) => n.id == 'page').body).by, 'phone');
    expect(find.byKey(IndexCard.refreshKey), findsOneWidget);
    mac.dispose();
    phone.dispose();
    await away(tester);
  });

  // The pictures: a teamspace's home with its index written into Home.md and the card under it, and the card alone
  // on a phone in simple mode, on another device.
  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 900), 'desktop')]) {
      testWidgets('a teamspace’s home with its index, $where, $theme', (tester) async {
        library.value = [
          for (final n in launchNotes()) n.copyWith(path: () => n.path!.replaceFirst('workspaces/Launch', 'orgs/Acme')),
          note('n4', 'orgs/Acme/Hiring plan.md', '---\nowner: sam\n---\n# Hiring plan\nTwo engineers in Q1.', at: ms(t0) - 2000),
          note('home', 'orgs/Acme/Home.md', '---\ntype: teamspace\n---\n# Acme\n\nWelcome to the team. Start with the index below.\n', at: ms(t0) - 9000),
        ];
        final mac = keeper('mac');
        await mac.turnOn('orgs/Acme', title: 'Acme');
        await tester.runAsync(() => mac.refresh('orgs/Acme', title: 'Acme'));
        final home = library.value.firstWhere((n) => n.id == 'home');
        final notes = notesIn('orgs/Acme', library.value, pageId: home.id);
        expect(indexDirty(home.body, notes), isFalse);
        await pumpPage(
          tester,
          page(TeamspaceHome(
            space: const Space.organization(orgId: 'acme', name: 'Acme', folder: 'orgs/Acme'),
            home: home,
            notes: library.value,
            members: const [],
            seen: const [],
            me: 'alice',
            onOpenNote: (_) {},
            index: IndexCard(keeper: mac, folder: 'orgs/Acme', title: 'Acme', now: () => now),
          )),
          size: size,
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Updated 2 hr ago · Claude'), findsOneWidget);
        await featureShot(tester, 'ai-indexes', 'teamspace-home-$where-$theme');
        mac.dispose();
        await away(tester);
      });
    }

    testWidgets('the card on another device, simple mode, More open, phone, $theme', (tester) async {
      final mac = keeper('mac'), phone = keeper('phone');
      await mac.turnOn('workspaces/Launch', title: 'Launch');
      await tester.runAsync(() => mac.refresh('workspaces/Launch', title: 'Launch'));
      await show(tester, phone, simple: true, theme: theme);
      await featureShot(tester, 'ai-indexes', 'card-simple-other-device-$theme');
      await tester.tap(find.byKey(IndexCard.moreKey));
      await tester.pump(const Duration(milliseconds: 300));
      await featureShot(tester, 'ai-indexes', 'card-simple-more-$theme');
      mac.dispose();
      phone.dispose();
      await away(tester);
    });
  }
}
