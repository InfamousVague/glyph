// What a keystroke costs in a note of 380 kB, through the keyboard's client: the delta in, the transaction, the
// frame. The keyboard is shown three lines of it, nothing is pushed back for a letter typed, and one line is laid
// out.
//
// Timed twice. With the motor off it is the input layer's own cost, and that is what is held to a frame. With the
// motor on every letter also asks feel.dart what it is worth, which reads the commands' syntax tree
// (lib/editor/commands/syntax_tree.dart): a whole parse of the note for each new document, about 45 ms of this
// test's 60. Enter and Backspace read the same tree. That number is printed, not asserted: it is that file's to
// bring down, by reading the tree the state already keeps (lib/editor/view/syntax_tree.dart `syntaxTreeOrNull`).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:glacier/glacier.dart' show hapticsEnabled, setHapticsEnabled;

import '../../support/render.dart';
import '../view/sliver_test.dart' show bigNote;
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a note of 380 kB: a keystroke, Enter and Backspace through the keyboard', (tester) async {
    final doc = bigNote(380000);
    final rig = await pumpEditor(tester, doc, focus: false);
    // Half way down the note, in the words of a paragraph.
    rig.scroll.jumpTo(rig.scroll.position.maxScrollExtent / 2);
    await tester.pump();
    await tester.pump();
    final line = drawn(tester).firstWhere((l) => l.spec.projection.display.startsWith('The quick') && l.localToGlobal(Offset.zero).dy > 100);
    await rig.place(line.from + 9);
    await rig.focus();
    expect(rig.ime.text.length, lessThan(400), reason: 'the keyboard holds three lines, not 380 kB');
    expect(rig.ime.text, rig.window);

    final clock = Stopwatch();
    final pushes = rig.ime.pushes;
    final was = hapticsEnabled();
    addTearDown(() => setHapticsEnabled(was));
    final medians = <bool, double>{}, worst = <bool, double>{};
    for (final motor in <bool>[false, true]) {
      setHapticsEnabled(motor);
      final times = <int>[], laidOut = <int>[];
      for (var i = 0; i < 40; i++) {
        final sel = rig.ime.value.selection;
        final delta = rig.ime.edit(sel.start, sel.end, 'abcdefghij'[i % 10]);
        final message = SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
            rig.ime.client,
            <String, dynamic>{
              'deltas': [delta],
            },
          ]),
        );
        final before = RenderEditorLine.layouts;
        clock
          ..reset()
          ..start();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(SystemChannels.textInput.name, message, (_) {});
        await tester.pump();
        times.add(clock.elapsedMicroseconds);
        laidOut.add(RenderEditorLine.layouts - before);
        await tester.pump();
      }
      times.sort();
      medians[motor] = times[times.length ~/ 2] / 1000;
      worst[motor] = times.last / 1000;
      // Its own line; and one more the once the paragraph grows a line and pushes another into reach.
      expect(laidOut.every((n) => n <= 2) && laidOut.where((n) => n == 1).length >= 36, isTrue, reason: 'a keystroke lays out its own line: $laidOut');
    }
    setHapticsEnabled(false);
    expect(rig.ime.pushes, pushes, reason: 'typing pushes nothing');
    expect(rig.doc.length, doc.length + 80);

    clock
      ..reset()
      ..start();
    await rig.ime.enter();
    final enter = clock.elapsedMicroseconds;
    clock
      ..reset()
      ..start();
    await rig.ime.backspace();
    final backspace = clock.elapsedMicroseconds;
    // Enter took the space after the caret with it (insertNewlineAndIndent), and Backspace the line break.
    expect(rig.doc.length, doc.length + 79);
    expect(rig.ime.text, rig.window);
    expect(rig.ime.text.length, lessThan(400));

    // ignore: avoid_print
    print(
      '380 kB note through the keyboard: ${rig.view.state.doc.lines} lines, the keyboard holds ${rig.ime.text.length} characters\n'
      '  a keystroke, delta to frame, the motor off: median ${medians[false]} ms, worst ${worst[false]} ms\n'
      '  the same with the motor on (feel.dart over the commands\' whole parse): median ${medians[true]} ms, worst ${worst[true]} ms\n'
      '  Enter: ${enter / 1000} ms; Backspace (a key, the markdown command\'s tree, and a push): ${backspace / 1000} ms',
    );
    // A frame at 60 a second is 16.6 ms; this is a debug build under a test, several times slower than the phone's.
    expect(medians[false], lessThan(16.6), reason: 'a keystroke fits in a frame');
    await finish(tester);
  });
}
