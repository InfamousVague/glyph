// A state kept asleep reads nothing of its note (lib/editor/view/syntax_tree.dart `syntaxAsleep`): the editor a
// note keeps behind its canvas holds the canvas's JSON, which nothing draws, and reading that as Markdown is the
// dearest thing its opening did. Held here, by counting the parser's work (`SyntaxWork`):
//
// - made asleep, handed other words whole, and typed into, a state parses nothing, and answers the empty tree to
//   those who draw;
// - who acts on the words (a command, the AI's blanks) is answered from the whole tree all the same, read once for
//   the words as they are;
// - woken, the state holds the tree a state never asleep holds, and its editor draws the page an editor never
//   asleep draws, to the pixel.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/editor/ai/blanks.dart' show editorBlanks;
import 'package:ghost_md/editor/boards/boards.dart' show drawnBoards;
import 'package:ghost_md/editor/commands/syntax_tree.dart' as commands;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/media/media.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/syntax_tree.dart';

import '../../support/render.dart';
import '../input/support.dart';

/// A canvas as the app writes one: the spec's JSON, two spaces in, under the note's front matter.
String canvasOf(int cards) {
  final out = StringBuffer('---\ntitle: "Cabin weekend, laid out"\n---\n{\n  "nodes": [\n');
  for (var i = 0; i < cards; i++) {
    out.write('    {\n      "id": "card$i",\n      "type": "text",\n      "x": ${i * 320},\n      "y": 0,\n      "width": 260,\n      "height": 110,\n'
        '      "text": "# Book the cabin $i\\n\\nThe deposit is **200**, `{?not this}` and {?how much is left}."\n    }${i + 1 < cards ? ',' : ''}\n');
  }
  out.write('  ],\n  "edges": []\n}\n');
  return out.toString();
}

void main() {
  setUpAll(loadAppFonts);

  EditorState stateOf(String doc, {required bool asleep, Compartment? sleep}) => EditorState.create(
        doc: doc,
        extensions: noteExtensions(more: <Extension>[(sleep ?? Compartment()).of(syntaxAsleep.of(asleep))]),
      );

  test('asleep, a state reads nothing: not as it is made, not handed other words, not typed into', () {
    final canvas = canvasOf(40);
    SyntaxWork.reset();
    var state = stateOf(canvas, asleep: true);
    expect(syntaxTree(state).length, 0, reason: 'those who draw are answered the empty tree');
    expect(syntaxTreeOrNull(state), isNull);
    expect(syntaxText(state), isNull);
    // The canvas's words handed over whole, as the note's screen does when the canvas has been written to.
    state = state.update(TransactionSpec(changes: ChangeSpec(from: 0, to: state.doc.length, insert: canvasOf(41)))).state;
    // And a letter, as a version put back or a rename does.
    state = state.update(TransactionSpec(changes: ChangeSpec(from: 5, insert: 'x'))).state;
    expect(syntaxTree(state).length, 0);
    expect((SyntaxWork.whole, SyntaxWork.again), (0, 0), reason: 'nothing was parsed');

    // The same three steps awake, for what they cost: once whole as it is made, once whole for other words, and the
    // letter's own lines.
    SyntaxWork.reset();
    var awake = stateOf(canvas, asleep: false);
    awake = awake.update(TransactionSpec(changes: ChangeSpec(from: 0, to: awake.doc.length, insert: canvasOf(41)))).state;
    awake = awake.update(TransactionSpec(changes: ChangeSpec(from: 5, insert: 'x'))).state;
    expect(syntaxTree(awake).length, awake.doc.length);
    expect(SyntaxWork.whole + SyntaxWork.again, 3);
  });

  test('who acts on the words is answered from the whole tree, read once for the words as they are', () {
    final canvas = canvasOf(6);
    final awake = stateOf(canvas, asleep: false), asleep = stateOf(canvas, asleep: true);
    SyntaxWork.reset();
    final whole = syntaxTreeWhole(asleep)!;
    expect(whole.toString(), syntaxTree(awake).toString(), reason: 'the whole tree of a sleeping state is the tree of a state awake');
    expect(identical(syntaxTreeWhole(asleep), whole), isTrue);
    expect(identical(commands.syntaxTree(asleep), whole), isTrue, reason: 'a command reads the same one');
    expect(SyntaxWork.whole, 1, reason: 'read once');
    expect(identical(syntaxTreeWhole(awake), syntaxTree(awake)), isTrue, reason: 'awake, the whole tree is the tree the state keeps');

    // A blank in code is not a blank; one in the words is. Six cards, one of each in each.
    final found = editorBlanks(asleep), wanted = editorBlanks(awake);
    expect(wanted, hasLength(6));
    expect(<(int, int, String)>[for (final blank in found) (blank.from, blank.to, blank.question)], <(int, int, String)>[for (final blank in wanted) (blank.from, blank.to, blank.question)]);
    expect(found.every((blank) => blank.question == 'how much is left'), isTrue);
    expect(SyntaxWork.whole, 1, reason: 'the blanks asked for no reading of their own');

    // Other words are read again, once.
    final next = asleep.update(TransactionSpec(changes: ChangeSpec(from: asleep.doc.length, insert: '\n'))).state;
    expect(syntaxTreeWhole(next)!.length, next.doc.length);
    expect(SyntaxWork.whole, 2);
  });

  test('woken, a state holds the tree of a state never asleep, and reads its note once', () {
    final sleep = Compartment();
    final never = syntaxTree(stateOf(sampleNoteBody, asleep: false)).toString();
    final asleep = stateOf(sampleNoteBody, asleep: true, sleep: sleep);
    SyntaxWork.reset();
    final woken = asleep.update(TransactionSpec(effects: <StateEffect<Object?>>[sleep.reconfigure(syntaxAsleep.of(false))])).state;
    expect(SyntaxWork.whole, 1);
    expect(syntaxTree(woken).toString(), never);
    expect(syntaxText(woken), sampleNoteBody);
    // Put back to sleep, it lets the tree go and reads nothing more.
    final again = woken.update(TransactionSpec(effects: <StateEffect<Object?>>[sleep.reconfigure(syntaxAsleep.of(true))])).state;
    expect(syntaxTree(again).length, 0);
    expect(SyntaxWork.whole, 1);

    // A state whose whole tree was asked for while it slept wakes with that reading, not another.
    final other = stateOf(sampleNoteBody, asleep: true, sleep: sleep);
    SyntaxWork.reset();
    final read = syntaxTreeWhole(other);
    final up = other.update(TransactionSpec(effects: <StateEffect<Object?>>[sleep.reconfigure(syntaxAsleep.of(false))])).state;
    expect(identical(syntaxTree(up), read), isTrue);
    expect(SyntaxWork.whole, 1);
  });

  testWidgets('an editor woken draws the page an editor never asleep draws', (tester) async {
    List<Extension> pieces() => <Extension>[
          markExtensions(marks),
          itemExtensions(wiki: WikiOptions(known: (title) => title.length.isEven, open: (title, [anchor]) {}), openHeading: true, doneSyncs: true),
          drawnTables(),
          drawnBoards(),
          mediaExtensions(places: PlaceMode.live),
        ];
    // The page as it stands, pixel for pixel.
    Future<Uint8List> picture() async {
      final element = find.byType(Page).evaluate().single;
      return (await tester.runAsync(() async {
        final image = await captureImage(element);
        final bytes = await image.toByteData();
        image.dispose();
        return bytes!.buffer.asUint8List();
      }))!;
    }

    final sleep = Compartment();
    final rig = await pumpEditor(tester, sampleNoteBody, focus: false, more: <Extension>[...pieces(), sleep.of(syntaxAsleep.of(true))]);
    expect(syntaxTree(rig.view.state).length, 0);
    final slept = await picture();
    rig.view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[sleep.reconfigure(syntaxAsleep.of(false))]));
    await tester.pump();
    await tester.pump();
    final wokenLines = <int>[for (final line in drawn(tester)) line.from];
    final woken = await picture();
    expect(wokenLines.length, greaterThan(10));
    await finish(tester);

    await pumpEditor(tester, sampleNoteBody, focus: false, more: pieces());
    final freshLines = <int>[for (final line in drawn(tester)) line.from];
    final fresh = await picture();
    expect(wokenLines, freshLines, reason: 'the same lines are on the page');
    expect(woken.length, fresh.length);
    var differing = 0;
    for (var i = 0; i < fresh.length; i++) {
      if (woken[i] != fresh[i]) differing += 1;
    }
    expect(differing, 0, reason: 'the page of an editor woken is the page of one never asleep, to the pixel');
    // And the check can fail: asleep, with nothing read, the page was another picture (no heading, no mark).
    var apart = 0;
    for (var i = 0; i < fresh.length && i < slept.length; i++) {
      if (slept[i] != fresh[i]) apart += 1;
    }
    expect(apart, greaterThan(1000), reason: 'the two pictures are of different pages before the waking');
    await finish(tester);
  });
}
