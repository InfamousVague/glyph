import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../support/render.dart';
import 'support.dart';

/// What the + makes (lib/notes/new_sheet.dart), after the web's `notes/NewSheet.test.tsx`, and where its rows stand,
/// held to the page (Chromium, 390x844, dark: the sheet the home dock's + opens over the seeded library).
void main() {
  setUpAll(loadAppFonts);

  final at = DateTime(2026, 9, 28, 14, 5);
  final usual = entryPresets[0].text;

  Future<({List<String> said, BackStack back, void Function(bool open) set})> host(
    WidgetTester tester, {
    bool canvas = true,
    bool book = true,
    NewSheetEntry Function(List<String> said)? entry,
    bool meeting = false,
    bool? sound,
    Future<void> Function(String link)? fromLink,
    String theme = 'dark',
  }) async {
    final said = <String>[];
    final back = BackStack();
    var open = true, soundOn = sound ?? false;
    late StateSetter redraw;
    await pumpApp(
      tester,
      prefs: AppPreferences(theme: theme),
      home: BackScope(
        stack: back,
        child: StatefulBuilder(
          builder: (context, setState) {
            redraw = setState;
            return Stack(
              children: [
                const Positioned.fill(child: SizedBox.expand()),
                NewSheet(
                  open: open,
                  clock: () => at,
                  onClose: () {
                    said.add('close');
                    setState(() => open = false);
                  },
                  onNote: () => said.add('note'),
                  onCanvas: canvas ? () => said.add('canvas') : null,
                  onBook: book ? () => said.add('book') : null,
                  entry: entry?.call(said),
                  onMeeting: meeting ? () => said.add('meeting') : null,
                  sound: sound == null
                      ? null
                      : NewSheetSound(
                          label: 'Include sound from other apps',
                          hint: 'Android lets Ghost.md hear media and games, never calls.',
                          on: soundOn,
                          onToggle: () => setState(() => soundOn = !soundOn),
                        ),
                  onFromLink: fromLink,
                ),
              ],
            );
          },
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await settle(tester);
    return (said: said, back: back, set: (bool next) => redraw(() => open = next));
  }

  List<String> rows(WidgetTester tester) => [for (final row in tester.widgetList<SheetRow>(find.byType(SheetRow))) (row.key! as ValueKey<String>).value];
  NewSheetEntry diary(List<String> said, {String? template, String hint = 'Starts with the date and the time.'}) =>
      NewSheetEntry(journal: 'Diary', hint: hint, usual: template ?? usual, onPress: (text) => said.add('entry ${text == null ? 'usual' : text.split('\n').first}'));

  testWidgets('draws nothing while it is shut', (tester) async {
    final it = await host(tester);
    it.set(false);
    await settle(tester);
    expect(find.byType(Sheet), findsNothing);
    await away(tester);
  });

  testWidgets('closes as it makes what was chosen', (tester) async {
    final it = await host(tester);
    await tester.tap(find.text('Cards on a page with lines between them.'));
    await settle(tester);
    expect(it.said, ['close', 'canvas']);
    await away(tester);
  });

  testWidgets('offers a notebook by that name, and a copy from a link only where one can be saved', (tester) async {
    final it = await host(tester);
    expect(rows(tester), ['new-note', 'new-canvas', 'new-book']);
    expect(find.text('Notes in an order with an index, or a journal of dated entries.'), findsOneWidget);
    expect(find.text('Journal'), findsNothing);
    await tester.tap(find.text('Notebook'));
    await settle(tester);
    expect(it.said, ['close', 'book']);
    await away(tester);
  });

  testWidgets('leaves out what the port cannot make yet: no Canvas or Notebook row without their callbacks', (tester) async {
    final it = await host(tester, canvas: false, book: false);
    expect(rows(tester), ['new-note']);
    await tester.tap(find.text('Note'));
    await settle(tester);
    expect(it.said, ['close', 'note']);
    await away(tester);
  });

  testWidgets('offers a new entry right after Note, and asks which template it starts with before making it', (tester) async {
    final it = await host(tester, entry: diary);
    expect(rows(tester), ['new-note', 'new-entry', 'new-canvas', 'new-book']);
    expect(find.text('Entry in Diary'), findsOneWidget);
    expect(find.text('Starts with the date and the time.'), findsOneWidget);
    await tester.tap(find.text('Entry in Diary'));
    await settle(tester);
    // Nothing made yet: the sheet shows the templates, the journal's usual one first.
    expect(it.said, isEmpty);
    expect(find.text('Start the entry with'), findsOneWidget);
    expect(rows(tester), ['start-usual', 'start-time', 'start-morning', 'start-todos', 'start-empty']);
    expect(find.text('The date and the time · usual'), findsOneWidget);
    // Each told on one line as it would start this minute.
    expect(find.text('Monday 28 September · 14:05'), findsOneWidget);
    expect(find.text('Nothing, a blank page'), findsOneWidget);
    await tester.tap(find.text('A morning page'));
    await settle(tester);
    expect(it.said, ['close', 'entry # {{date}}']);
    await away(tester);
  });

  testWidgets('sends no template for the usual one, so the entry is made from the journal as it is now', (tester) async {
    final it = await host(tester, entry: diary);
    await tester.tap(find.text('Entry in Diary'));
    await settle(tester);
    await tester.tap(find.text('The date and the time · usual'));
    await settle(tester);
    expect(it.said, ['close', 'entry usual']);
    await away(tester);
  });

  testWidgets('keeps a long line of your own template to its row', (tester) async {
    const own = '# {{date}}\n\nWeather: https://www.example.com/forecast/some/really/long/path/without/any/spaces/at/all?q=London\n\nGratitude';
    await host(tester, entry: (said) => diary(said, template: own, hint: ''));
    await tester.tap(find.text('Entry in Diary'));
    await settle(tester);
    expect(find.text('My own · usual'), findsOneWidget);
    final hint = clipHint(startLine(own, 'Diary', at));
    expect(hint.length, lessThan(120));
    expect(hint.endsWith('…'), isTrue);
    expect(find.text(hint), findsOneWidget);
    await away(tester);
  });

  testWidgets('goes back from the templates to the choices, by its arrow at the top or the back gesture, without closing', (tester) async {
    final it = await host(tester, entry: diary);
    await tester.tap(find.text('Entry in Diary'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('new-sheet-back')));
    await settle(tester);
    expect(find.text('Entry in Diary'), findsOneWidget);
    await tester.tap(find.text('Entry in Diary'));
    await settle(tester);
    // The back gesture steps back too.
    expect(it.back.goBack(), isTrue);
    await settle(tester);
    expect(find.text('Entry in Diary'), findsOneWidget);
    expect(it.said, isEmpty);
    await away(tester);
  });

  testWidgets('saves a copy from a pasted link, saying what went wrong in the row, and closes once it is saved', (tester) async {
    final asked = <String>[];
    final it = await host(tester, fromLink: (link) async {
      asked.add(link);
      if (!link.contains('#')) throw Exception('This link is missing its key.');
    });
    expect(find.text('A copy of a note or notebook someone shared with you.'), findsOneWidget);
    await tester.tap(find.text('From a shared link'));
    await settle(tester);
    expect(find.text('Yours to change; the shared one stays as it is.'), findsOneWidget);
    // Nothing pasted: nothing asked for.
    await tester.tap(find.text('Save a copy'));
    await settle(tester);
    expect(asked, isEmpty);
    await tester.enterText(find.byType(EditableText), '  https://attack.fm/glyph/read.html  ');
    await tester.tap(find.text('Save a copy'));
    await settle(tester);
    expect(asked.last, 'https://attack.fm/glyph/read.html');
    expect(find.text('This link is missing its key.'), findsOneWidget);
    expect(it.said, isEmpty);
    await tester.enterText(find.byType(EditableText), 'https://attack.fm/glyph/read.html#abc.def');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(asked.last, 'https://attack.fm/glyph/read.html#abc.def');
    expect(it.said, ['close']);
    await away(tester);
  });

  testWidgets('opens on its choices again however it was closed, not on the link and the words left in it', (tester) async {
    final it = await host(tester, fromLink: (link) async {});
    await tester.tap(find.text('From a shared link'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'half a li');
    // Closed by the back gesture.
    expect(it.back.goBack(), isTrue);
    await settle(tester);
    expect(it.said, ['close']);
    it.set(true);
    await settle(tester);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('From a shared link'), findsOneWidget);
    await away(tester);
  });

  group('a meeting', () {
    testWidgets('is offered only where one can be recorded, and starts one as the sheet closes', (tester) async {
      await host(tester);
      expect(find.text('Meeting'), findsNothing);
      await away(tester);
      final it = await host(tester, meeting: true);
      expect(rows(tester), ['new-note', 'new-canvas', 'new-book', 'new-meeting']);
      await tester.tap(find.text('Record a meeting. The screen can go off. It is written up afterwards.'));
      await settle(tester);
      expect(it.said, ['close', 'meeting']);
      await away(tester);
    });

    testWidgets('carries the switch for the device’s own sound under it where the device can, which does not close the sheet', (tester) async {
      // Not without a meeting to put the sound in.
      await host(tester, sound: false);
      expect(find.text('Include sound from other apps'), findsNothing);
      await away(tester);
      final it = await host(tester, meeting: true, sound: false);
      SheetRow row() => tester.widget<SheetRow>(find.byKey(const ValueKey('new-sound')));
      expect(row().chosen, isFalse);
      await tester.tap(find.text('Include sound from other apps'));
      await settle(tester);
      expect(row().chosen, isTrue);
      expect(it.said, isEmpty);
      await away(tester);
    });
  });

  group('the journal’s starts (book/entryStarts.ts)', () {
    test('are the usual one first, then the presets it is not, then an empty page', () {
      expect([for (final start in entryStarts(usual)) start.id], ['usual', 'time', 'morning', 'todos', 'empty']);
      expect(entryStarts(usual).first.name, 'The date and the time');
      expect([for (final start in entryStarts('Mine')) (start.id, start.name)].take(2), [('usual', 'My own'), ('stamped', 'The date and the time')]);
      // An empty usual is the empty page already.
      expect([for (final start in entryStarts('')) start.id], ['usual', 'stamped', 'time', 'morning', 'todos']);
    });

    test('tell a template on one line, filled for now, its marks taken off', () {
      expect(startLine(entryPresets[0].text, 'Diary', at), 'Monday 28 September · 14:05');
      expect(startLine(entryPresets[3].text, 'Diary', at), 'Monday 28 September · To do');
      expect(startLine('# {{title}} in {{journal}}', '  ', at), '2026-09-28 14.05 in Journal');
      expect(startLine('', 'Diary', at), 'Nothing, a blank page');
      expect(entryTitle(at), '2026-09-28 14.05');
    });
  });

  group('where its rows stand (Chromium, 390x844)', () {
    void at(Rect rect, double left, double top, double width, double height, String reason) {
      expect(rect.left, closeTo(left, 0.5), reason: '$reason left');
      expect(rect.top, closeTo(top, 0.5), reason: '$reason top');
      expect(rect.width, closeTo(width, 0.5), reason: '$reason width');
      expect(rect.height, closeTo(height, 0.5), reason: '$reason height');
    }

    testWidgets('Note, Canvas, Notebook and From a shared link, as the home dock’s + shows them', (tester) async {
      await host(tester, fromLink: (link) async {});
      Rect row(String key) => tester.getRect(find.byKey(ValueKey(key)));
      at(tester.getRect(find.text('New').first), 22.31, 472.33, 345.38, 24, 'the title');
      at(row('new-note'), 22.31, 514.17, 345.38, 64.78, 'Note');
      at(row('new-canvas'), 22.31, 578.95, 345.38, 65.78, 'Canvas, a hairline taller');
      at(row('new-book'), 22.31, 644.73, 345.38, 81.78, 'Notebook, its hint on two lines');
      at(row('new-link'), 22.31, 726.52, 345.38, 81.78, 'From a shared link');
      at(tester.getRect(find.descendant(of: find.byKey(const ValueKey('new-note')), matching: find.byType(SheetIcon))), 40.16, 531.56, 30, 30, 'the icon’s ring');
      await shot(tester, 'new-sheet-dark');
    });

    testWidgets('in the light, with every row there is', (tester) async {
      await host(tester, theme: 'light', entry: diary, meeting: true, sound: true, fromLink: (link) async {});
      await shot(tester, 'new-sheet-all-light');
    });

    testWidgets('the templates an entry can start with', (tester) async {
      await host(tester, entry: diary);
      await tester.tap(find.text('Entry in Diary'));
      await settle(tester);
      await shot(tester, 'new-sheet-starts-dark');
    });
  });
}
