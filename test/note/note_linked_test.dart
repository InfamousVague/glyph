// The More sheet's "Linked to" (lib/note/note_settings.dart [NotePlugins]): what editor/NoteSettings.tsx does with
// `plugins.noteLinks()` and `plugins.noteActions()`. A link's row opens its page inside the sheet; an action runs on
// the note with the sheet closed first, or opens its places as a page where it has more than one. The plugins here
// are this file's own.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/plugins/types.dart';

import '../support/render.dart';
import 'support.dart';

class _Editing implements NoteEditing {
  _Editing(this.noteId, this._body);

  @override
  final String noteId;
  final String Function() _body;
  final List<String> said = <String>[];

  @override
  String body() => _body();

  @override
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next) => false;

  @override
  void say(String message) => said.add(message);
}

Widget _icon(BuildContext context, double size) => SizedBox.square(dimension: size);

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'linked${made += 1}', body)))!;

  Future<void> more(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> press(WidgetTester tester, String row) async {
    await tester.ensureVisible(find.text(row));
    await tester.pump();
    await tester.tap(find.text(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  late List<String> ran;
  NoteSeams seams({List<ActionChoice> places = const <ActionChoice>[], String? unavailable}) => NoteSeams(
        plugins: (view) => NotePlugins(
          editing: _Editing('n', () => view.state.doc.toString()),
          links: [
            NoteLink(
              id: 'board',
              label: 'Notion board',
              icon: _icon,
              hint: (id) => 'Not linked. Its to-dos can be sent to a board.',
              unavailable: unavailable == null ? null : () async => unavailable,
              picker: (context, id, onDone) => GestureDetector(onTap: onDone, child: const Text('Pick a board', textDirection: TextDirection.ltr)),
            ),
          ],
          actions: [
            NoteAction(
              id: 'post',
              label: 'Post to Slack',
              icon: _icon,
              visible: (id, body) => body.contains('Day'),
              hint: (id, body) => 'Sends this note to a channel.',
              enabled: (id, body) => true,
              choices: (id) => places,
              run: (editing, [choice]) async => ran.add('post ${choice ?? '-'} "${editing.body().trim()}"'),
            ),
            NoteAction(id: 'never', label: 'Never shown', icon: _icon, visible: (id, body) => false, hint: (id, body) => '', enabled: (id, body) => true, run: (editing, [choice]) async {}),
          ],
        ),
      );

  setUp(() => ran = <String>[]);

  testWidgets('a link’s row opens its page inside the sheet, and its page’s Done comes back to the note’s rows', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n'), seams: seams());
    await more(tester);
    expect(find.text('LINKED TO'), findsOneWidget);
    expect(find.text('Not linked. Its to-dos can be sent to a board.'), findsOneWidget);
    expect(find.text('Never shown'), findsNothing);
    await press(tester, 'Notion board');
    expect(find.text('Pick a board'), findsOneWidget);
    expect(find.text('Post to Slack'), findsNothing);
    await tester.tap(find.text('Pick a board'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Post to Slack'), findsOneWidget);
    await closeNote(tester);
  });

  testWidgets('an action with nowhere to choose runs on the note, the sheet closed first', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n'), seams: seams());
    await more(tester);
    await press(tester, 'Post to Slack');
    expect(ran, ['post - "# Day"']);
    expect(find.text('LINKED TO'), findsNothing);
    await closeNote(tester);
  });

  testWidgets('with one place it goes there at once, and with several they are a page of the sheet', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n'), seams: seams(places: const [ActionChoice(id: 'c1', label: '#general')]));
    await more(tester);
    await press(tester, 'Post to Slack');
    expect(ran, ['post c1 "# Day"']);
    await closeNote(tester);

    await pumpNote(tester, world, await seeded(tester, world, '# Day\n'), seams: seams(places: const [ActionChoice(id: 'c1', label: '#general'), ActionChoice(id: 'c2', label: '#launch', hint: 'Private')]));
    await more(tester);
    await press(tester, 'Post to Slack');
    expect(ran, hasLength(1), reason: 'nothing runs until a place is pressed');
    expect(find.text('Sends this note to a channel.'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    await press(tester, '#launch');
    expect(ran.last, 'post c2 "# Day"');
    await closeNote(tester);
  });

  testWidgets('a link that cannot be used on this build says why and opens nothing, and an action is not shown for a note it is not for', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Elsewhere\n'), seams: seams(unavailable: 'Works in the Ghost.md app on your phone.'));
    await more(tester);
    await tester.pump();
    expect(find.text('Works in the Ghost.md app on your phone.'), findsOneWidget);
    expect(find.text('Post to Slack'), findsNothing);
    await press(tester, 'Notion board');
    expect(find.text('Pick a board'), findsNothing);
    await closeNote(tester);
  });
}
