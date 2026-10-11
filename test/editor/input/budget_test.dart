// What a keystroke costs in a note of 380 kB, through the keyboard's client: the delta in, the transaction, the
// frame. The keyboard is shown three lines of it, nothing is pushed back for a letter typed, and one line is laid
// out.
//
// Timed twice, with the motor off and on, and the times are printed, not held: a time measured on a Mac that is
// also running three other things said 33 ms where the same code alone said 3, and a test that fails by the
// machine's load holds nothing. What is held is what the keystroke READ, which is the same number however busy
// the machine is (lib/editor/state/text.dart `DocWork`): the note made a string once (the parser's), and lines
// handed out for the screen, not for the note. The app's own list of extensions is held the same way by
// test/root/typing_budget_test.dart.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/state/text.dart' show DocWork;
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
    final read = <bool, ({int lines, int strings, int chars})>{};
    for (final motor in <bool>[false, true]) {
      setHapticsEnabled(motor);
      final times = <int>[], laidOut = <int>[];
      DocWork.reset();
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
      // Forty letters and their frames: the note a string forty times (once a letter, the parser's), and a screen's
      // worth of lines for each, where the note has ten thousand.
      read[motor] = (lines: DocWork.lines, strings: DocWork.strings, chars: DocWork.stringChars);
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
      '  the same with the motor on (feel.dart reads the tree the state keeps): median ${medians[true]} ms, worst ${worst[true]} ms\n'
      '  Enter: ${enter / 1000} ms; Backspace (a key, the markdown command\'s tree, and a push): ${backspace / 1000} ms',
    );
    // ignore: avoid_print
    print('  read by forty keystrokes: motor off ${read[false]}, motor on ${read[true]}');
    for (final motor in <bool>[false, true]) {
      final counted = read[motor]!;
      expect(counted.chars, lessThanOrEqualTo(40 * (doc.length + 200)), reason: 'the note is made a string once for a letter, not several times (motor ${motor ? 'on' : 'off'})');
      expect(counted.lines, lessThanOrEqualTo(40 * 400), reason: 'a letter hands out lines for the screen, not the note\'s ${rig.view.state.doc.lines} (motor ${motor ? 'on' : 'off'})');
    }
    await finish(tester);
  });
}
