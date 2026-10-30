// "Linked from" at the foot of a note (lib/links/backlinks_foot.dart; Matt, 2026-10-30, "add all 12"): every note
// that links here, by title, alias, heading, named line and embed, each with where it is kept and the line round its
// link, a press opening it there; a team note while the account is in its organization and not after; many folded to
// their count with Show all; "Mentioned in" with Link it; and nothing at all for a note nobody links to. A phone's
// width and a desktop's.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_index.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/links/backlinks_foot.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

Note note(String id, String body, {String? path}) => Note(id: id, body: body, createdAt: 0, updatedAt: 0, path: path);

final List<Note> library = [
  note('lisbon', '---\naliases: [LX]\n---\n# Lisbon\n\n## Trams\n\nThe 28 up the hill. ^tram\n'),
  note('trip', '# Trip\n\nTen days, the first four in [[Lisbon]].\n'),
  note('city', '# Cities\n\nThe best of them is [[Lisbon|the white city]], by the river.\n', path: 'Inbox/Cities.md'),
  note('trams', '# Getting about\n\nSee [[Lisbon#Trams]] and [[LX#^tram]] for the trams.\n'),
  note('board', '# Board\n\n![[Lisbon#Trams]]\n'),
  note('team', '# Offsite\n\nThe team meets in [[Lisbon]] in May.\n'),
  note('gone', '# Old team plan\n\nWe once went to [[Lisbon]].\n'),
  note('diary', '# Diary\n\nWe flew to Lisbon on a Tuesday.\n'),
  note('alone', '# Alone\n\nNobody links here.\n'),
];

/// Where each is kept: Offsite is a team note of an organization the account is in, the old plan one it left.
String? placeOf(String id) => switch (id) {
      'team' => 'Ghost.md › Plans',
      'gone' => 'Old Co',
      'city' => 'Inbox',
      _ => null,
    };

bool readable(String id) => id != 'gone';

void main() {
  setUpAll(loadAppFonts);

  Future<List<(String, int)>> show(WidgetTester tester, String noteId, {Size size = const Size(390, 844), List<Note>? notes, int most = 6, List<String>? linked}) async {
    final opened = <(String, int)>[];
    final indexer = LinkIndexer(notes: () => notes ?? library);
    addTearDown(indexer.dispose);
    await pumpPage(
      tester,
      size: size,
      Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('app-paper'),
          child: SingleChildScrollView(
            child: BacklinksFoot(
              indexer: indexer,
              noteId: noteId,
              onOpen: (id, line) => opened.add((id, line)),
              onLink: linked == null
                  ? null
                  : (mention, place) async {
                      linked.add('${mention.id}:${place.from}');
                      return true;
                    },
              placeOf: placeOf,
              readable: readable,
              most: most,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  for (final (where, size) in const [('phone', Size(390, 844)), ('desktop', Size(1280, 800))]) {
    testWidgets('every note that links here, by title, words, heading, alias and embed, a press opening it at the link, on a $where', (tester) async {
      final opened = await show(tester, 'lisbon', size: size);
      expect(find.text('LINKED FROM 5 NOTES'), findsOneWidget);
      for (final title in ['Trip', 'Cities', 'Getting about', 'Board', 'Offsite']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      // The old plan is in an organization the account left.
      expect(find.text('Old team plan'), findsNothing);
      // Where each is kept, beside its title.
      expect(find.text('Ghost.md › Plans'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      // The line round the link, the link in it.
      expect(find.textContaining('the first four in [[Lisbon]]', findRichText: true), findsOneWidget);
      expect(find.textContaining('[[Lisbon|the white city]]', findRichText: true), findsOneWidget);
      // Two links in one note: its first, and how many more.
      expect(find.text('  +1'), findsOneWidget);
      // An embed says so.
      expect(find.textContaining('![[Lisbon#Trams]]', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Getting about'));
      await tester.pump();
      expect(opened, [('trams', 2)], reason: 'at the line of its first link, from 0');
      await away(tester);
    });
  }

  testWidgets('Mentioned in: a note that says the name without linking it, with Link it', (tester) async {
    final linked = <String>[];
    await show(tester, 'lisbon', linked: linked);
    expect(find.text('MENTIONED IN 1 NOTE'), findsOneWidget);
    expect(find.text('Diary'), findsOneWidget);
    await tester.tap(find.text('Link it'));
    await tester.pump();
    expect(linked, ['diary:${library.firstWhere((n) => n.id == 'diary').body.indexOf('Lisbon')}']);
    await away(tester);
  });

  testWidgets('many are folded to their count, with Show all and Show fewer', (tester) async {
    final many = [
      note('target', '# Target\n\nWords.\n'),
      for (var i = 0; i < 8; i += 1) note('n$i', '# Note $i\n\nSee [[Target]].\n'),
    ];
    await show(tester, 'target', notes: many);
    expect(find.text('LINKED FROM 8 NOTES'), findsOneWidget);
    expect(find.text('Note 0'), findsNothing, reason: 'folded to its count');
    await tester.tap(find.text('Show all'));
    await tester.pump();
    expect(find.text('Note 0'), findsOneWidget);
    expect(find.text('Note 7'), findsOneWidget);
    await tester.tap(find.text('Show fewer'));
    await tester.pump();
    expect(find.text('Note 0'), findsNothing);
    await away(tester);
  });

  testWidgets('nothing for a note no other note links to, whoever names it', (tester) async {
    await show(tester, 'alone');
    expect(find.byKey(const ValueKey<String>('backlinks-foot')), findsNothing);
    expect(find.textContaining('LINKED FROM'), findsNothing);
    await away(tester);
  });

  testWidgets('drawn again as a link to the note is written elsewhere', (tester) async {
    final notes = [...library];
    final changes = ValueNotifier<int>(0);
    final indexer = LinkIndexer(notes: () => notes, changes: changes);
    addTearDown(indexer.dispose);
    await pumpPage(tester, SingleChildScrollView(child: BacklinksFoot(indexer: indexer, noteId: 'alone', onOpen: (_, _) {})));
    expect(find.textContaining('LINKED FROM'), findsNothing);
    notes.add(note('late', '# Late\n\nNow [[Alone]] has one.\n'));
    changes.value += 1;
    await tester.pump();
    await tester.pump();
    expect(find.text('LINKED FROM 1 NOTE'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    await away(tester);
  });

  test('what the foot reads: embeds count, the unreadable are left out, and no mentions without a backlink', () {
    final index = LinkIndex.build([for (final n in library) (id: n.id, body: n.body, path: n.path, updatedAt: 0)]);
    String? bodyOf(String id) => library.firstWhere((n) => n.id == id).body;
    final read = footLinks(index, 'lisbon', bodyOf, readable: readable);
    expect(read.backlinks.map((b) => b.id), unorderedEquals(['trip', 'city', 'trams', 'board', 'team']));
    expect(read.backlinks.firstWhere((b) => b.id == 'board').links.single.embed, isTrue);
    expect(read.mentions.map((m) => m.id), ['diary']);
    expect(footLinks(index, 'alone', bodyOf).backlinks, isEmpty);
    expect(footLinks(index, 'alone', bodyOf).mentions, isEmpty);
  });
}
