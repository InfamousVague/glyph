import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart' show AiChange;
import 'package:ghost_md/ai/marks.dart' show forgetMarks, saveMarks;
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/format/gist.dart' show gistWorking;
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/home/home_parts.dart';
import 'package:ghost_md/home/home_rows.dart';
import 'package:ghost_md/home/marks.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/home/note_peek.dart';
import 'package:ghost_md/notes/workspace_swatch.dart';
import 'package:ghost_md/tapes/tape_art.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/render.dart';
import '../support/editor_text.dart';
import 'package:ghost_md/note/byline.dart' show WholeMarks;

import 'support.dart';

/// The home page's pieces, each alone: a note drawn small, a card, a pinned line giving way, a ticket's mark, the
/// workspace swatch and the cassette. Where a number is the web page's, it was measured there (430 wide, dark).
void main() {
  setUpAll(loadAppFonts);

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// One piece on the page's paper, [width] wide, from the top left of a phone with no notch.
  Future<void> show(WidgetTester tester, Widget piece, {double width = 347.06, String theme = 'dark'}) async {
    await pumpHome(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: piece)), theme: theme, ratio: 2);
    await settle(tester);
  }

  Finder words(String part) => find.textContaining(part, findRichText: true);

  group('a note drawn small', () {
    testWidgets('is the note after its title, a line 1.6 of the words’ size each, hung on its list marks', (tester) async {
      final prd11 = seedLibrary().firstWhere((n) => n.id == 'prd11');
      await show(tester, NotePeek(body: prd11.body));
      // The card's preview on the web page: 104.34 tall under its 8.98 of air. Two lines, a blank, three to-dos.
      expect(tester.getSize(find.byType(NotePeek)).height, closeTo(104.34 + 8.98, 0.5));
      // `white-space: break-spaces`: "sign-in" would fit, but not the space after it, so the line breaks at the hyphen.
      expect(visualLinesOf(tester, 'Signing').first, 'Signing in on the phone sends you back to the sign-');
      // A to-do: its dash quiet, its box in the first ink, its words hung 39.17 in (six letters of the mono face).
      expect(editorTextRect(tester, 'Find').left, closeTo(39.17, 0.3));
      // A person, as the editor's chip: the initial in its ring, then the name.
      expect(find.text('S'), findsOneWidget);
      expect(find.text('sam'), findsOneWidget);
      expect(editorText('@sam'), findsNothing);
      await away(tester);
    });

    testWidgets('stops at six lines and a little, and is not cut where it is shorter', (tester) async {
      final standup = seedLibrary().firstWhere((n) => n.id == 'standup');
      await show(tester, NotePeek(body: standup.body));
      final em = tester.element(find.byType(NotePeek)).tokens.fontSize('lg') * 0.62 * 0.9;
      expect(em, closeTo(10.88, 0.01));
      // `max-block-size: calc(1.6em * 6.2)`: 107.92 on the web page.
      expect(tester.getSize(find.byType(NotePeek)).height, closeTo(107.92 + 8.98, 0.3));
      // A heading counts the to-dos under it, as the editor does, and its line is as tall as the page's: 21.70
      // (measured on the web page at 430 x 932 with tool/editor_reference.mjs's method, 2026-10-07; the hand-drawn
      // preview this replaced had it 22.22).
      expect(find.text('0 of 1'), findsOneWidget);
      final heading = tester.getRect(editorText('Summary').first);
      expect(heading.height, closeTo(21.70, 0.3));
      expect(tester.getRect(editorText('Who').first).top - heading.top, closeTo(21.70, 0.3));
      await away(tester);
    });

    testWidgets('says every to-do done, leaves a board’s fence out, and draws a block of code a step smaller', (tester) async {
      await show(tester, const NotePeek(body: '# Plan\n\n## Done\n- [x] One\n- [x] Two\n\n```board\nNow: a\n```\n\n```js\nconst a = 1;\n```'));
      expect(find.text('All 2 done'), findsOneWidget);
      expect(editorText('Now:'), findsNothing);
      expect(editorLine(tester, 'const').spec.look.base.fontSize, closeTo(10.88 * 0.82, 0.01));
      // Set in from the card's edge by 0.85 of its own size (7.58 on the web page).
      expect(editorTextRect(tester, 'const').left, closeTo(7.58, 0.2));
      await away(tester);
    });

    testWidgets('draws nothing for a canvas, or a note with only its title', (tester) async {
      expect(NotePeek.has('---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}'), isFalse);
      expect(NotePeek.has('# Only a title'), isFalse);
      expect(NotePeek.has('# A title\nand words'), isTrue);
      await show(tester, const NotePeek(body: '# Only a title'));
      expect(tester.getSize(find.byType(NotePeek)).height, 0);
      await away(tester);
    });

    testWidgets('takes the room it is given in a card stretched to its row, up to its six lines', (tester) async {
      await show(tester, const SizedBox(height: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Flexible(child: NotePeek(body: '# T\none line', fill: true)), Text('after')])));
      expect(tester.getSize(find.byType(NotePeek)).height, closeTo(107.92 + 8.98, 0.3));
      expect(tester.getRect(find.text('after')).top, closeTo(107.92 + 8.98, 0.3), reason: 'what follows stands under the preview, not at the card’s foot');
      await away(tester);
    });
  });

  group('text at a stylesheet’s line height', () {
    testWidgets('is as tall as its lines at their true height, where Flutter rounds each to a pixel', (tester) async {
      await show(
        tester,
        Builder(
          builder: (context) => CssLines(
            lineHeight: 17.408,
            child: Text('one\ntwo\nthree', style: context.tokens.textAt(10.88, mono: true, height: 1.6)),
          ),
        ),
      );
      expect(tester.getSize(find.byType(Text)).height, 51, reason: 'three lines of 17');
      expect(tester.getSize(find.byType(CssLines)).height, closeTo(3 * 17.408, 0.001));
      await away(tester);
    });
  });

  group('a row that gives way', () {
    Widget row(double width) => SizedBox(
          width: width,
          child: const ShrinkRow(
            gap: 10,
            minHeight: 30,
            children: [
              SizedBox(key: ValueKey('mark'), width: 16, height: 16),
              Shrink(shrink: 1, child: SizedBox(key: ValueKey('title'), width: 120, height: 20)),
              Shrink(shrink: 100, child: SizedBox(key: ValueKey('book'), width: 80, height: 16)),
              Shrink(shrink: 50, minWidth: 40, child: SizedBox(key: ValueKey('place'), width: 60, height: 18)),
              Shrink(toEnd: true, child: SizedBox(key: ValueKey('when'), width: 50, height: 14)),
            ],
          ),
        );
    double w(WidgetTester tester, String name) => tester.getSize(find.byKey(ValueKey(name))).width;

    testWidgets('lays its children at their own widths while they fit, the last kept to the end', (tester) async {
      await show(tester, row(420), width: 420);
      expect([w(tester, 'mark'), w(tester, 'title'), w(tester, 'book'), w(tester, 'place'), w(tester, 'when')], [16, 120, 80, 60, 50]);
      expect(tester.getRect(find.byKey(const ValueKey('when'))).right, 420);
      expect(tester.getSize(find.byType(ShrinkRow)).height, 30);
      // Centred on the row's height.
      expect(tester.getRect(find.byKey(const ValueKey('mark'))).top, 7);
      await away(tester);
    });

    testWidgets('takes what does not fit from the least precious first, by `flex-shrink` times its width', (tester) async {
      // 366 of content and gaps in 330: 36 too many, shared 120 : 8000 : 3000.
      await show(tester, row(330), width: 330);
      expect(w(tester, 'title'), closeTo(120 - 36 * 120 / 11120, 0.05));
      expect(w(tester, 'book'), closeTo(80 - 36 * 8000 / 11120, 0.05));
      expect(w(tester, 'place'), closeTo(60 - 36 * 3000 / 11120, 0.05));
      expect([w(tester, 'mark'), w(tester, 'when')], [16, 50]);
      await away(tester);
    });

    testWidgets('holds a child at its least, and asks the rest for what it could not give', (tester) async {
      // 136 too many: the notebook goes to nothing and the pill to its 40, and the name gives the rest.
      await show(tester, row(230), width: 230);
      expect(w(tester, 'book'), closeTo(0, 0.02));
      expect(w(tester, 'place'), closeTo(40, 0.05));
      expect(w(tester, 'title'), closeTo(230 - 16 - 0 - 40 - 50 - 40, 0.1));
      await away(tester);
    });
  });

  group('a pinned line', () {
    testWidgets('never runs past the page: its name, its notebook and its workspace’s pill each give way', (tester) async {
      final store = WorkspaceStore();
      final org = store.ensureOrgWorkspace(const OrgLike(id: 'ht', name: 'HelloTrade', hue: 'moss'));
      final note = makeNote('n', body: '# HelloTrade Bug History Review', starred: true, updatedAt: seedNow - 3600000);
      await show(tester, HomeLine(note: note, index: 0, onOpen: (_) {}, now: seedNow, bookName: 'Engineering handbook', space: org), width: 330);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(HomeLine)).width, 330);
      expect(tester.getRect(find.text('1 hr ago')).right, closeTo(330 - 4.5, 0.75));
      // The pill keeps its mark and a few letters of its name; the notebook went first.
      expect(tester.getSize(find.text('Engineering handbook')).width, lessThan(20));
      expect(tester.getSize(find.text('HelloTrade')).width, greaterThan(20));
      expect(find.byType(OrgMark), findsOneWidget);
      await away(tester);
    });
  });

  group('who wrote a note', () {
    const body = '---\nauthors: matt, Claude, ana\n---\n# Plan';
    const long = '---\nauthors: matt, Claude, ana\n---\n# A plan with a name far too long for any line or row to hold whole';

    testWidgets('is their marks on a line and a row where the name leaves room, a whole mark at a time, and none where it leaves none', (tester) async {
      await show(tester, HomeLine(note: makeNote('n', body: body, updatedAt: seedNow - 3600000), index: 0, onOpen: (_) {}, now: seedNow), width: 330);
      final three = tester.getSize(find.byType(WholeMarks)).width;
      expect(three, greaterThan(40));
      expect(tester.getRect(find.byType(WholeMarks)).right, lessThan(tester.getRect(find.text('1 hr ago')).left));
      // At the line's end, beside when it was last touched, not after the name.
      expect(tester.getRect(find.text('1 hr ago')).left - tester.getRect(find.byType(WholeMarks)).right, lessThan(24));
      expect(find.bySemanticsLabel('Plan, by matt, Claude and ana, 1 hr ago'), findsOneWidget);
      await away(tester);

      await show(tester, HomeLine(note: makeNote('n', body: long, updatedAt: seedNow - 3600000), index: 0, onOpen: (_) {}, now: seedNow), width: 330);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(WholeMarks)).width, 0);
      await away(tester);

      await show(tester, HomeRow(note: makeNote('n', body: body, updatedAt: seedNow - 3600000), index: 0, onOpen: (_) {}, now: seedNow), width: 330);
      expect(tester.getSize(find.byType(WholeMarks)).width, three);
      expect(tester.getRect(find.byType(WholeMarks)).left, greaterThan(tester.getRect(find.text('Plan')).right));
      expect(tester.getRect(find.text('1 hr ago')).left - tester.getRect(find.byType(WholeMarks)).right, lessThan(24));
      await away(tester);

      await show(tester, HomeRow(note: makeNote('n', body: long, updatedAt: seedNow - 3600000), index: 0, onOpen: (_) {}, now: seedNow), width: 330);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(WholeMarks)).width, 0);
      await away(tester);

      // A note of the person's own names nobody, and draws no marks.
      await show(tester, HomeLine(note: makeNote('n', body: '# Plan', updatedAt: seedNow - 3600000), index: 0, onOpen: (_) {}, now: seedNow), width: 330);
      expect(find.byType(WholeMarks), findsNothing);
      await away(tester);
    });
  });

  group('a ticket’s mark', () {
    testWidgets('is its key and its status, the status in its category’s colour', (tester) async {
      const body = '---\ntype: ticket\nid: PRD-11\nstatus: In progress\n---\n# Fix';
      await show(tester, const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [TicketMark(body: body), TicketMark(body: '---\ntype: ticket\nid: PRD-2\nstatus: Shipped\n---\n'), TicketMark(body: '# A note')]));
      final t = tester.element(find.byType(Column).first).tokens;
      expect(tester.widget<Text>(find.text('In progress')).style!.color, t.color('glacier-blue-11'));
      expect(tester.widget<Text>(find.text('Shipped')).style!.color, t.color('glacier-green-11'));
      expect(tester.widget<Text>(find.text('PRD-11')).style!.fontFamily, 'Maple Mono');
      expect(find.bySemanticsLabel('PRD-11 · In progress'), findsOneWidget);
      expect(TicketMark.has('# A note'), isFalse);
      expect(TicketMark.has('---\ntype: ticket\nstatus: To do\n---\n', keyOnly: true), isFalse);
      // A status its notebook's workflow alone knows is placed by where it stands in it.
      expect(TicketMark.has(body, notebook: '---\nbook: true\nstatuses: [Ideas, Building, Live]\n---\n'), isTrue);
      await away(tester);
    });
  });

  group('a card', () {
    // Unwired 17 (docs/PARITY.md): the corner was handed in and nobody handed it, so no card ever wore the ring or
    // the dot (notes/NoteCard.tsx: `activeGist() === note.id`, else `hasMarks(note.id)`). The card reads both
    // itself, and hears the runner at the card.
    testWidgets('wears the AI in its corner by itself: the ring while its own line is written, the dot while changes are marked in it', (tester) async {
      addTearDown(() {
        gistWorking.value = null;
        forgetMarks('b');
      });
      Widget cards() => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteCard(key: const ValueKey('a'), note: makeNote('a', body: '# First\n\nWords.', updatedAt: seedNow), index: 0, onOpen: (_) {}, now: seedNow),
              NoteCard(key: const ValueKey('b'), note: makeNote('b', body: '# Second\n\nWords.', updatedAt: seedNow), index: 1, onOpen: (_) {}, now: seedNow),
            ],
          );
      Finder said(String label, String card) => find.descendant(of: find.byKey(ValueKey(card)), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label));
      const ring = "The AI is writing this note's line", dot = 'Changes from the AI are marked in this note';
      await show(tester, cards());
      expect(said(ring, 'a'), findsNothing);
      expect(said(ring, 'b'), findsNothing);
      expect(said(dot, 'a'), findsNothing);
      expect(said(dot, 'b'), findsNothing);

      // The runner starts on the first note's line: its card says so, and the other is left alone.
      gistWorking.value = 'a';
      await tester.pump();
      expect(said(ring, 'a'), findsOneWidget);
      expect(said(ring, 'b'), findsNothing);
      gistWorking.value = 'b';
      await tester.pump();
      expect(said(ring, 'a'), findsNothing);
      expect(said(ring, 'b'), findsOneWidget);
      gistWorking.value = null;
      await tester.pump();
      expect(said(ring, 'a'), findsNothing);
      expect(said(ring, 'b'), findsNothing);

      // Changes the AI made are still marked in the second: the dot, the next time its card is drawn.
      saveMarks('b', '# Second\n\nWords.', const [AiChange(id: 'c1', runId: 'r1', from: 2, to: 8, removed: '', block: false)]);
      await show(tester, cards());
      expect(said(dot, 'a'), findsNothing);
      expect(said(dot, 'b'), findsOneWidget);
      // And the ring over the dot, never both.
      gistWorking.value = 'b';
      await tester.pump();
      expect(said(ring, 'b'), findsOneWidget);
      expect(said(dot, 'b'), findsNothing);
      await away(tester);
    });

    // docs/AB_FINDINGS.json home-1, measured in Ghost.md's page on a phone at 2.625 (2026-10-11): `.when` is 35 device
    // pixels (13.33px) and a section's `.heading` 43 (16.38px), each a line of `line-height: normal` rounded in the
    // phone's own pixels. The engine's whole logical pixels were 14 and 16: every card stood 1.75 device pixels
    // tall and every section's first card one high.
    testWidgets('keeps the page’s lines on a phone: the time under a card 35 device pixels, a section’s heading 43', (tester) async {
      await pumpApp(
        tester,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HomeHeading(words: 'Recent', count: 3),
                NoteCard(note: makeNote('a', body: '# First\n\nWords.', updatedAt: seedNow), index: 0, onOpen: (_) {}, now: seedNow),
              ],
            ),
          ),
        ),
        size: const Size(476, 752),
        prefs: const AppPreferences(theme: 'dark', textSize: 'large'),
        ratio: 2.625,
        measuredAt: 2.625,
      );
      await settle(tester);
      expect(tester.getSize(find.byType(HomeHeading)).height * 2.625, closeTo(43, 0.01));
      final when = find.ancestor(of: find.textContaining('Just now', findRichText: true), matching: find.byType(ExactLines)).first;
      expect(tester.getSize(when).height * 2.625, closeTo(35, 0.01));
      await away(tester);
    });

    // The organizations, two small tiles across (Matt, 2026-10-16): each its mark, its name on one line and its
    // counts under it, the tiles one height and side by side, a third on the next row.
    testWidgets('of organizations are small tiles two across, each a name and its notes and members', (tester) async {
      await pumpApp(
        tester,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: HomeOrganizations(
              orgs: const [HomeOrg(id: 'hello', name: 'HelloTeam', members: 3), HomeOrg(id: 'ghost', name: 'Ghost.md', hue: 'moss', members: 5), HomeOrg(id: 'a-third', name: 'A third organization with a long name', members: 1)],
              notes: const [],
              filed: const {},
              onOpen: (_) {},
            ),
          ),
        ),
        size: const Size(430, 932),
        prefs: const AppPreferences(theme: 'dark'),
        ratio: 3,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      Rect tile(String name) => tester.getRect(find.ancestor(of: find.text(name), matching: find.byType(OrgTile)).first);
      expect(tile('HelloTeam').top, tile('Ghost.md').top);
      expect(tile('HelloTeam').height, tile('Ghost.md').height);
      expect(tile('Ghost.md').left, greaterThan(tile('HelloTeam').right));
      expect(tile('A third organization with a long name').top, greaterThan(tile('HelloTeam').bottom));
      expect(tile('A third organization with a long name').width, closeTo(tile('HelloTeam').width, 0.01));
      expect(tile('HelloTeam').height, lessThan(64));
      expect(find.text('0 notes · 3 members'), findsOneWidget);
      expect(find.text('0 notes · 1 member'), findsOneWidget);
      expect(find.textContaining('here now'), findsNothing);
      await away(tester);
    });

    testWidgets('of a journal says its entries by when each was written; of a recording, how long it runs', (tester) async {
      final journal = exampleJournal(DateTime.fromMillisecondsSinceEpoch(seedNow));
      final notes = [makeNote('j', body: journal.journal, updatedAt: seedNow), makeNote('e', body: journal.entry, createdAt: seedNow, updatedAt: seedNow)];
      await show(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoteCard(note: notes[0], index: 0, onOpen: (_) {}, now: seedNow, entries: journalCards(notes)['j']),
            NoteCard(note: makeNote('t', body: '# Said\n\nWords.', source: NoteSource.capture, recordingMs: 760000, updatedAt: seedNow - 86400000 * 3), index: 1, onOpen: (_) {}, now: seedNow, gist: 'What was said, in a line.'),
            NoteCard(note: makeNote('u', body: '---\ntitle: ""\nbook: true\n---\n', updatedAt: seedNow), index: 2, onOpen: (_) {}, now: seedNow),
            NoteCard(note: makeNote('d', body: '# Dense', starred: true, archivedAt: 5, updatedAt: seedNow), index: 3, onOpen: (_) {}, now: seedNow, dense: true, working: true),
          ],
        ),
      );
      expect(find.text('1 entry'), findsOneWidget);
      expect(find.text('Mon, Sep 28, 10:00'), findsOneWidget);
      expect(words('12:40 · Friday'), findsOneWidget);
      expect(find.text('What was said, in a line.'), findsOneWidget);
      expect(find.text('Untitled notebook'), findsOneWidget);
      expect(find.text('No pages yet'), findsOneWidget);
      // Dense, the card says its pin and its archive itself, and the AI at work in its corner.
      expect(find.bySemanticsLabel('Pinned'), findsOneWidget);
      expect(find.bySemanticsLabel('Archived'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == "The AI is writing this note's line"), findsOneWidget);
      await away(tester);
    });
  });

  group('the workspace swatch', () {
    testWidgets('is the seven hues as a radio group, the chosen one ticked, walked with the arrow keys', (tester) async {
      var hue = 'moss';
      await show(tester, StatefulBuilder(builder: (context, setState) => WorkspaceSwatch(hue: hue, onHue: (next) => setState(() => hue = next))), width: 390);
      for (final name in workspaceHueNames.values) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      expect(workspaceHueNames.keys, workspaceHues);
      Semantics dot(String name) => tester.widget<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == name && w.properties.checked != null));
      expect(dot('Moss').properties.checked, isTrue);
      expect(dot('Sea').properties.checked, isFalse);
      // Each dot a thumb's worth across, in its own colour at this paper's lightness.
      final moss = find.descendant(of: find.bySemanticsLabel('Moss'), matching: find.byType(AnimatedContainer));
      expect(tester.getSize(moss), const Size(32, 32));
      final decoration = tester.widget<AnimatedContainer>(moss).decoration! as BoxDecoration;
      final t = tester.element(find.byType(WorkspaceSwatch)).tokens;
      expect(decoration.color, t.child(attrs: {'hue': 'moss'}).color('app-space'));
      expect(decoration.boxShadow!.length, 2, reason: 'a ring of the paper, then its own colour again');

      await tester.tap(find.bySemanticsLabel('Rose'));
      await settle(tester);
      expect(hue, 'rose');
      // Round the end, back to ink.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(hue, 'ink');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(hue, 'rose');
      await away(tester);
    });
  });

  group('the cassette', () {
    testWidgets('is drawn in the page’s two inks, its label’s words in ink on paper', (tester) async {
      await show(
        tester,
        const RepaintBoundary(
          key: ValueKey('tapes'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TapeArt(positionMs: 100000, title: 'Planning call', side: '25 SEP', counter: '1:40'),
              SizedBox(height: 12),
              TapeArt(positionMs: 290000, bare: true),
            ],
          ),
        ),
        width: 240,
        theme: 'light',
      );
      expect(tester.getSize(find.byType(TapeArt).first), const Size(240, 153));
      await expectLater(find.byKey(const ValueKey('tapes')), matchesGoldenFile('shots/tape-art-light.png'));
      await away(tester);
    });

    testWidgets('turns its reels while it plays, and holds them still when the phone is set to reduce motion', (tester) async {
      await show(tester, const TapeArt(positionMs: 100000, playing: true), width: 240);
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'a ticker is running');
      await away(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await show(tester, const TapeArt(positionMs: 100000, playing: true), width: 240);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await away(tester);
    });
  });

  group('a book’s place', () {
    testWidgets('is said on its page’s card: the notebook’s name, and which page of it', (tester) async {
      final notes = seedLibrary();
      final place = placeOf(bookIndex(notes), notes.firstWhere((n) => n.id == 'lisbon'))!;
      await show(tester, Align(alignment: Alignment.topLeft, child: BookPlaceMark(place: place)));
      expect(find.text('Portugal'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2 of Portugal'), findsOneWidget);
      await away(tester);
    });
  });
}
