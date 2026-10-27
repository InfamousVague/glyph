// Settings › Lovart's Queue (lib/plugins/lovart/lovart_queue.dart).
import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/lovart_queue.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';

import '../../support/render.dart' show loadAppFonts;
import '../github/support.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    useGround();
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
  });

  tearDown(() {
    lovartMaking.value = const {};
    lovartInspiring.value = const {};
    lovartBannerMaking.value = const {};
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
  });

  group('the queue', () {
    test('is what is being made first, then the run\'s notes waiting, in its order', () {
      const run = BannerQueue(total: 5, left: ['a', 'b', 'c', 'd'], going: ['a', 'b'], again: ['c'], replacing: {'d': 'lovart-old.png'});
      final items = lovartQueue(
        run: run,
        headers: {'b', 'x'},
        cues: {'n1\n{image: a fox in one line}'},
        inspiring: {'m1'},
      );
      expect([for (final item in items) (item.noteId, item.kind, item.making)], [
        ('a', QueueKind.header, true),
        ('b', QueueKind.header, true),
        ('x', QueueKind.header, true),
        ('n1', QueueKind.picture, true),
        ('m1', QueueKind.inspiration, true),
        ('c', QueueKind.headerAgain, false),
        ('d', QueueKind.headerRedo, false),
      ]);
      expect(items[3].what, 'Picture: a fox in one line');
      expect(items[4].what, 'Inspiration, 4 images');
      expect(items[4].images, 4);
      expect(items.last.what, 'Header image, redone in colour');
    });

    test('is empty with nothing made or waiting', () {
      expect(lovartQueue(), isEmpty);
    });
  });

  group('the section', () {
    Future<void> pump(WidgetTester tester, Map<String, String> titles) => pumpPane(tester, LovartQueueSection(titles: () => titles));

    testWidgets('says nothing waits when nothing does', (tester) async {
      await pump(tester, const {});
      expect(find.byKey(const ValueKey('lovart-queue-empty')), findsOneWidget);
      await away(tester);
    });

    testWidgets('lists the notes by title, making first, the rest numbered, with the credits it will cost', (tester) async {
      lovart.host.storage.set(lovart.bannerRunKey, const BannerQueue(total: 3, left: ['t1', 't2', 't3'], going: ['t1']).toJson());
      lovartMaking.value = {'n1\n{image: a lighthouse at dusk}'};
      await pump(tester, const {'t1': 'Cabin weekend', 't2': 'Grocery list', 't3': 'Baby budget', 'n1': 'Ideas'});
      final text = textOf(tester);
      var at = 0;
      for (final words in ['Cabin weekend', 'Header image', 'Making', 'Ideas', 'Picture: a lighthouse at dusk', 'Making', 'Grocery list', '1', 'Baby budget', '2']) {
        final next = text.indexOf(words, at);
        expect(next, greaterThanOrEqualTo(0), reason: '“$words” after what came before it');
        at = next + words.length;
      }
      expect(text, contains('2 making, 2 waiting on this device: about 24 credits for the 4 pictures still to make.'));
      // As the run goes on, the page follows it.
      lovart.host.storage.set(lovart.bannerRunKey, const BannerQueue(total: 3, left: ['t3'], going: ['t3'], made: 2).toJson());
      lovartMaking.value = const {};
      await tester.pump();
      expect(textOf(tester), isNot(contains('Grocery list')));
      expect(textOf(tester), contains('1 making, 0 waiting'));
      await away(tester);
    });

    testWidgets('lists twenty waiting and counts the rest', (tester) async {
      final ids = [for (var i = 0; i < 30; i += 1) 'n$i'];
      lovart.host.storage.set(lovart.bannerRunKey, BannerQueue(total: 30, left: ids).toJson());
      await pump(tester, {for (final id in ids) id: 'Note $id'});
      expect(find.byKey(const ValueKey('lovart-queue-more')), findsOneWidget);
      expect(textOf(tester), contains('And 10 more waiting'));
      expect(find.byKey(const ValueKey('lovart-queue-waiting-n19')), findsOneWidget);
      expect(find.byKey(const ValueKey('lovart-queue-waiting-n20')), findsNothing);
      await away(tester);
    });

    testWidgets('pictured, a run under way', (tester) async {
      lovart.host.storage.set(lovart.bannerRunKey, const BannerQueue(total: 6, left: ['t1', 't2', 't3', 't4', 't5'], going: ['t1', 't2'], again: ['t4'], made: 1).toJson());
      lovartMaking.value = {'n1\n{image: a lighthouse at dusk, in ink}'};
      await pump(tester, const {'t1': 'Cabin weekend', 't2': 'New Orleans Trip: Nov 6–8', 't3': 'Baby budget', 't4': 'Dynamic Waitlist — build notes', 't5': 'House TODOs', 'n1': 'Ideas for the shop'});
      await expectLater(find.byType(LovartQueueSection), matchesGoldenFile('shots/lovart-queue.png'));
      debugDisableShadows = true;
      await away(tester);
    });

    testWidgets('is on the Lovart page', (tester) async {
      await pumpPane(tester, const LovartPane());
      expect(find.byType(LovartQueueSection), findsOneWidget);
      await away(tester);
    });
  });
}
