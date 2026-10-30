// What a note's screen draws under its last line (NoteSeams.foot, lib/links/backlinks_foot.dart's "Linked from"):
// under the note's words, and not while the transcript has the page (a meeting's Transcript, a tape playing), nor
// under a canvas, nor a notebook's index.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_screen.dart';

import '../support/render.dart';
import 'support.dart';

const Key foot = ValueKey<String>('the foot');

Note note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadAppFonts);

  Widget drawn(BuildContext context, double? start) => const SizedBox(key: foot, height: 40, child: Text('Linked from'));

  testWidgets('under a note\'s words, after its last line', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, note('n1', '# Plan\n\nShort.\n'), seams: NoteSeams(foot: drawn));
    expect(find.byKey(foot), findsOneWidget);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final last = screen.view!.coordsAtPos(screen.view!.state.doc.length)!;
    expect(tester.getRect(find.byKey(foot)).top, greaterThan(last.bottom));
    await away(tester);
  });

  testWidgets('not while the transcript has the page', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, note('n1', '# Standup\n\nShip it.\n'), seams: NoteSeams(foot: drawn, transcript: (context) => const Text('The transcript')));
    expect(find.text('The transcript'), findsOneWidget);
    expect(find.byKey(foot), findsNothing);
    await away(tester);
  });

  testWidgets('not under a notebook\'s index, nor a canvas', (tester) async {
    final world = NoteWorld();
    await pumpNote(
      tester,
      world,
      note('b1', '---\nbook: true\n---\n# Portugal\n\n- [[Packing]]\n'),
      seams: NoteSeams(foot: drawn, book: (context, body, onChange) => const SliverToBoxAdapter(child: Text('The index'))),
    );
    expect(find.text('The index'), findsOneWidget);
    expect(find.byKey(foot), findsNothing);
    await away(tester);
  });
}
