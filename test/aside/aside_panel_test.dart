import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/aside/aside.dart';
import 'package:ghost_md/aside/aside_panel.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/notes/floating_card.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/render.dart';

/// The aside (aside/aside_panel.dart): `src/app/aside/Aside.test.tsx`'s cases, where everything sits against the web
/// page at the Fold's unfolded size (fixtures/aside_704.json), and the pictures.
void main() {
  setUpAll(loadAppFonts);
  final web = jsonDecode(File('test/aside/fixtures/aside_704.json').readAsStringSync()) as Map<String, dynamic>;
  List<double> rect(Object? raw) => [for (final n in raw as List) (n as num).toDouble()];

  const project = '---\ntitle: "Example project"\nbook: true\n---\n# Example project\n\n- [[Plan the first release]]\n- [[Fix the sign-in loop]]\n- [[Write the welcome page]]\n';
  final notes = [
    makeNote('book', body: project),
    makeNote('plan', body: '# Plan the first release\n'),
    makeNote('fix', body: '# Fix the sign-in loop\n'),
    makeNote('write', body: '# Write the welcome page\n'),
  ];

  final card = find.byKey(const ValueKey('floating-card'));

  Future<List<String>> show(WidgetTester tester, AsideContent? content, {bool popup = true, AsideHistoryBuilder? history, AsideHistoryBuilder? links, AsideHistoryBuilder? outline, Stored? stored, String theme = 'dark', Size size = const Size(704, 933)}) async {
    final said = <String>[];
    final local = stored ?? MemoryStored();
    await pumpApp(
      tester,
      size: size,
      ratio: 2.625,
      measuredAt: 2.625,
      prefs: AppPreferences(theme: theme),
      home: BackScope(
        child: Builder(
          builder: (context) {
            final t = context.tokens;
            return ColoredBox(
              color: t.color('glacier-bg'),
              child: popup
                  ? Stack(
                      children: [
                        AsideCard(content: content, history: history, links: links, outline: outline, stored: local, onOpen: (id) => said.add('open:$id'), onOpenTitle: (title) => said.add('title:$title'), onClose: () => said.add('close')),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 240,
                        child: AsidePanel(content: content, history: history, links: links, outline: outline, stored: local, onOpen: (id) => said.add('open:$id'), onOpenTitle: (title) => said.add('title:$title')),
                      ),
                    ),
            );
          },
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return said;
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the card is where the page’s is, and everything in it, at the Fold’s unfolded size', (tester) async {
    await show(tester, asideContent(notes, notes[0]));
    final got = tester.getRect(card);
    final want = rect(web['card']);
    // The page's card hangs under its bar; this one has no bar over it, so everything is asked from the card's corner.
    expect(got.left, closeTo(want[0], 0.5));
    expect(got.width, closeTo(want[2], 0.5));
    expect(got.height, closeTo(want[3], 0.5), reason: 'the card’s height');
    void near(Finder finder, Object? raw, String what, {double by = 0.5}) {
      final r = tester.getRect(finder);
      final w = rect(raw);
      expect(r.left - got.left, closeTo(w[0] - want[0], by), reason: '$what: left');
      expect(r.top - got.top, closeTo(w[1] - want[1], by), reason: '$what: top');
      expect(r.width, closeTo(w[2], by), reason: '$what: width');
      expect(r.height, closeTo(w[3], by), reason: '$what: height');
    }

    near(find.bySemanticsLabel('Open the notebook Example project'), web['headButton'], 'the book’s button');
    near(find.text('Example project'), web['headTitle'], 'the book’s name', by: 0.8);
    near(find.bySemanticsLabel('Close'), web['close'], 'the close');
    final titles = ['Plan the first release', 'Fix the sign-in loop', 'Write the welcome page'];
    for (var i = 0; i < 3; i += 1) {
      near(find.bySemanticsLabel(titles[i]), (web['rows'] as List)[i], 'row ${i + 1}');
      near(find.text('${i + 1}'), (web['numbers'] as List)[i], 'number ${i + 1}');
      // A title's box is its words' on the page and the rest of the row here; its left edge and its line are asked.
      final r = tester.getRect(find.text(titles[i]));
      final w = rect((web['titles'] as List)[i]);
      expect(r.left - got.left, closeTo(w[0] - want[0], 0.5), reason: 'title ${i + 1}: left');
      expect(r.top - got.top, closeTo(w[1] - want[1], 0.5), reason: 'title ${i + 1}: top');
      expect(r.height, closeTo(w[3], 0.5), reason: 'title ${i + 1}: height');
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/aside-card-book.png'));
    await away(tester);
  });

  testWidgets('a tap on a chapter opens it by its title and closes the card; the book’s name opens the book', (tester) async {
    final said = await show(tester, asideContent(notes, notes[2]));
    await tester.tap(find.bySemanticsLabel('Write the welcome page'));
    expect(said, ['close', 'title:Write the welcome page']);
    said.clear();
    await tester.tap(find.bySemanticsLabel('Open the notebook Example project'));
    expect(said, ['close', 'open:book']);
    said.clear();
    await tester.tap(find.bySemanticsLabel('Close'));
    expect(said, ['close']);
    await away(tester);
  });

  testWidgets('the open chapter is marked, and no other', (tester) async {
    await show(tester, asideContent(notes, notes[2]));
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.bySemanticsLabel('Fix the sign-in loop')).flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Plan the first release')).flagsCollection.isSelected.toBoolOrNull(), isNot(true));
    handle.dispose();
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/aside-card-page.png'));
    await away(tester);
  });

  testWidgets('a press outside the card closes it, and one on its own icon does not', (tester) async {
    final said = <String>[];
    await pumpApp(
      tester,
      size: const Size(704, 933),
      home: BackScope(
        child: Stack(
          children: [
            const Positioned(top: 0, right: 0, child: FloatingCardToggle(toggle: asideToggle, child: ColoredBox(color: Color(0xFF000000), child: SizedBox(key: ValueKey('icon'), width: 40, height: 40)))),
            AsideCard(content: asideContent(notes, notes[0]), stored: MemoryStored(), onOpen: (_) {}, onOpenTitle: (_) {}, onClose: () => said.add('close')),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('icon'))));
    expect(said, isEmpty);
    await tester.tapAt(const Offset(40, 800));
    expect(said, ['close']);
    await away(tester);
  });

  testWidgets('a journal’s aside is its month: the day, the time and how the entry starts', (tester) async {
    entry(String id, String title, String date, String words) => makeNote(id, body: '---\ntitle: "$title"\ndate: $date\n---\n# Day\n\n**${date.substring(11)}** $words');
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-28 14.05]]\n- [[2026-09-27 21.40]]\n';
    final all = [makeNote('j', body: journal), entry('late', '2026-09-28 14.05', '2026-09-28T14:05', 'Walked along the river until the light went.'), entry('early', '2026-09-27 21.40', '2026-09-27T21:40', 'Dinner.')];
    final said = await show(tester, asideContent(all, all[2]));
    expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.textContaining('14:05 Walked along'), findsOneWidget);
    await tester.tap(find.text('28'));
    expect(said, ['close', 'open:late']);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/aside-card-journal.png'));
    await away(tester);
  });

  testWidgets('an empty book and an empty journal say so', (tester) async {
    final empty = makeNote('e', body: '---\ntitle: "Blank"\nbook: true\n---\n# Blank\n\n');
    await show(tester, asideContent([empty], empty));
    expect(find.text('No pages yet.'), findsOneWidget);
    await away(tester);
    final log = makeNote('l', body: '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n');
    await show(tester, asideContent([log], log));
    expect(find.text('No entries yet.'), findsOneWidget);
    await away(tester);
  });

  testWidgets('with a book and a history there are two tabs, the one chosen kept; with one, that one alone', (tester) async {
    final local = MemoryStored();
    Widget history(BuildContext context) => const Text('the versions');
    await show(tester, asideContent(notes, notes[1]), history: history, stored: local, popup: false);
    expect(find.text('Index'), findsOneWidget);
    expect(find.text('the versions'), findsNothing);
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.text('the versions'), findsOneWidget);
    expect(find.text('Version history'), findsOneWidget);
    expect(readAsideTab(local), AsideTab.history);
    // Asked for from elsewhere: the bar's History button.
    showAsideTab(AsideTab.contents, local);
    await tester.pump();
    expect(find.text('the versions'), findsNothing);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/aside-docked-tabs.png'));
    await away(tester);
    await show(tester, null, history: history, stored: local, popup: false);
    expect(find.text('History'), findsNothing);
    expect(find.text('the versions'), findsOneWidget);
    await away(tester);
  });

  testWidgets('a run of chapters whose book is no note names it without a button', (tester) async {
    chapter(String id, String title) => makeNote(id, body: '# $title\n\n« [[The Book]]\n\nWords.');
    final run = [chapter('c2', '02 · Second'), chapter('c1', '01 · First')];
    final said = await show(tester, asideContent(run, run[0]));
    expect(find.bySemanticsLabel('Open The Book'), findsNothing);
    expect(find.text('The Book'), findsOneWidget);
    expect(tester.getTopLeft(find.text('First')).dy, lessThan(tester.getTopLeft(find.text('Second')).dy));
    await tester.tap(find.text('First'));
    expect(said, ['close', 'open:c1']);
    await away(tester);
  });

  testWidgets('a note\'s links and its outline are tabs of their own beside the index, the one chosen kept', (tester) async {
    final local = MemoryStored();
    Widget links(BuildContext context) => const Text('the links');
    Widget outline(BuildContext context) => const Text('the headings');
    await show(tester, asideContent(notes, notes[1]), links: links, outline: outline, stored: local, popup: false);
    expect(find.text('Index'), findsOneWidget);
    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Outline'), findsOneWidget);
    await tester.tap(find.text('Outline'));
    await tester.pump();
    expect(find.text('the headings'), findsOneWidget);
    expect(readAsideTab(local), AsideTab.outline);
    showAsideTab(AsideTab.links, local);
    await tester.pump();
    expect(find.text('the links'), findsOneWidget);
    await away(tester);
    // A note in no book: the two alone, the one kept still chosen.
    await show(tester, null, links: links, outline: outline, stored: local, popup: false);
    expect(find.text('Index'), findsNothing);
    expect(find.text('the links'), findsOneWidget);
    await away(tester);
  });
}
