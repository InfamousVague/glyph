/// What the recorder's chip says for each thing the recorder tells it (lib/capture/ui/route_chip.dart).
/// `src/app/capture/RouteChip.test.tsx`, case for case.
///
/// What differs: the page read the chip's `textContent`; here the chip's words are its items read left to right with
/// a space between, since each is its own box a gap apart, so Undo stands a space after the words where the page ran
/// them together. `data-phase` is the key on the chip's box.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/take_host.dart';
import 'package:ghost_md/capture/ui/route_chip.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<({String text, String phase, Finder undo})> chip(WidgetTester tester, RouteView route, [String itemWords = '', VoidCallback? onUndo]) async {
    await pumpApp(tester, home: Align(key: UniqueKey(), child: RouteChip(route: route, itemWords: itemWords, onUndo: onUndo)));
    final box = find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('route-chip-'));
    expect(box, findsOneWidget);
    final words = tester.widgetList<RichText>(find.descendant(of: find.byType(RouteChip), matching: find.byType(RichText))).map((words) => words.text.toPlainText()).join(' ');
    return (text: words, phase: (tester.widget(box).key! as ValueKey<String>).value.substring('route-chip-'.length), undo: find.descendant(of: find.byType(RouteChip), matching: find.text('Undo')));
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the chip', () {
    testWidgets('says what name it is looking for while the name is said', (tester) async {
      final drawn = await chip(tester, const RouteViewHearing(name: 'wor'));
      expect(drawn.text, 'Looking for “wor”');
      expect(drawn.phase, 'hearing');
      await away(tester);
    });

    testWidgets('asks for what a named note should get, and shows it as it is said', (tester) async {
      expect((await chip(tester, const RouteViewWaiting(title: 'Work'))).text, 'Say the note for Work');
      expect((await chip(tester, const RouteViewWaiting(title: 'Work'), 'call Sam')).text, 'Work: call Sam');
      await away(tester);
    });

    testWidgets('shows a command as it is said after the keyword', (tester) async {
      expect((await chip(tester, const RouteViewCommand(words: ''))).text, 'Hey Ghost, listening for a command');
      expect((await chip(tester, const RouteViewCommand(words: 'add eggs'), 'Hey Ghost, to work')).text, 'Hey Ghost: add eggs to work');
      await away(tester);
    });

    testWidgets('says what landed, where', (tester) async {
      var drawn = await chip(tester, const RouteViewAdded(title: 'Work', body: '', added: ['- Call Sam']));
      expect(drawn.text, 'Added to Work');
      expect(drawn.phase, 'added');
      expect((await chip(tester, const RouteViewAdded(title: 'Work', body: '', added: ['- Call Sam', '- Email Jo']))).text, '2 added to Work');
      drawn = await chip(tester, const RouteViewMoved(title: 'Work'));
      expect(drawn.text, 'Now on Work');
      expect(drawn.phase, 'moved');
      expect((await chip(tester, const RouteViewMoved(title: 'New note'))).text, 'New note');
      drawn = await chip(tester, const RouteViewDone(text: 'Added to the note you named'));
      expect(drawn.text, 'Added to the note you named');
      expect(drawn.phase, 'moved');
      await away(tester);
    });

    testWidgets('says what was taken back, and where it went instead, with Undo only while it can be tapped', (tester) async {
      var drawn = await chip(tester, const RouteViewTookBack(said: 'Call Sam', outcome: TookBackGone(), undo: 3));
      expect(drawn.text, 'Took back “Call Sam”');
      expect(drawn.phase, 'tookBack');
      expect(drawn.undo, findsNothing);
      expect((await chip(tester, const RouteViewTookBack(said: 'Oat milk', outcome: TookBackSent(sent: 'Groceries'), undo: 3))).text, 'Sent “Oat milk” to Groceries');
      expect((await chip(tester, const RouteViewTookBack(said: 'Buy fuses', outcome: TookBackPlaced(placed: 'in its list'), undo: 3))).text, 'Put “Buy fuses” in its list');
      expect((await chip(tester, const RouteViewTookBack(said: 'three', outcome: TookBackChanged(changed: 'four'), undo: 3))).text, 'Changed “three” to “four”');
      expect(
        (await chip(tester, const RouteViewTookBack(said: 'The meeting is at three', outcome: TookBackReplaced(replaced: 'The meeting is at four'), undo: 3))).text,
        'Replaced “The meeting is at three” with “The meeting is at four”',
      );
      var undone = 0;
      drawn = await chip(tester, const RouteViewTookBack(said: 'Call Sam', outcome: TookBackGone(), undo: 3), '', () => undone += 1);
      // The page's `textContent` ran the two together ("…”Undo"); here they are two boxes on the chip's line.
      expect(drawn.text, 'Took back “Call Sam” Undo');
      expect(drawn.undo, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(drawn.undo);
      await tester.pump();
      expect(undone, 1);
      await away(tester);
    });

    testWidgets('says what did not happen', (tester) async {
      var drawn = await chip(tester, const RouteViewMissed(title: 'Oven'));
      expect(drawn.text, 'No note called “Oven”, so it stays here');
      expect(drawn.phase, 'missed');
      drawn = await chip(tester, const RouteViewSaid(text: 'Not done.'));
      expect(drawn.text, 'Not done.');
      expect(drawn.phase, 'missed');
      await away(tester);
    });
  });
}
