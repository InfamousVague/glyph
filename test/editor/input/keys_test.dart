// A hardware keyboard: CodeMirror's keymaps through the editor's shortcuts, the commands only a layout can answer
// (up and down by visual line with a goal, Home and End on a wrapped line, a page), undo and redo, and Flutter's
// own text-editing intents for the keys no keymap of the editor's takes.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/commands.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/input/keymap.dart';
import 'package:ghost_md/editor/input/motion.dart';

import '../../support/render.dart';
import 'support.dart';

const String wrapped =
    'short\n'
    'A paragraph long enough to wrap twice on a phone: the quick brown fox jumps over the lazy dog and then turns round to do it all again.\n'
    'x\n'
    'another line of ordinary length\n'
    'last';

Future<void> chord(WidgetTester tester, List<LogicalKeyboardKey> held, LogicalKeyboardKey key) async {
  for (final mod in held) {
    await tester.sendKeyDownEvent(mod);
  }
  await tester.sendKeyEvent(key);
  for (final mod in held.reversed) {
    await tester.sendKeyUpEvent(mod);
  }
  await tester.pump();
}

const ctrl = LogicalKeyboardKey.controlLeft;
const shift = LogicalKeyboardKey.shiftLeft;

void main() {
  setUpAll(loadAppFonts);

  test('key names are CodeMirror\'s', () {
    expect(normalizeKeyName('Mod-z', KeyPlatform.linux), 'Ctrl-z');
    expect(normalizeKeyName('Mod-z', KeyPlatform.mac), 'Meta-z');
    expect(normalizeKeyName('Shift-Mod-k', KeyPlatform.linux), 'Shift-Ctrl-k');
    expect(normalizeKeyName('Mod-Shift-z', KeyPlatform.mac), 'Shift-Meta-z');
    expect(normalizeKeyName('Alt-A', KeyPlatform.linux), 'Shift-Alt-a');
    expect(normalizeKeyName('Ctrl--', KeyPlatform.linux), 'Ctrl--');
    expect(normalizeKeyName('Space', KeyPlatform.linux), ' ');
    expect(keyNamed('ArrowLeft'), LogicalKeyboardKey.arrowLeft);
    expect(keyNamed('z'), LogicalKeyboardKey.keyZ);
    expect(keyNamed('/'), LogicalKeyboardKey.slash);
    expect(keyNamed('\\'), LogicalKeyboardKey.backslash);
  });

  test('the keymap of a platform: a Mac\'s keys on a Mac, Linux\'s on Android', () {
    final all = <List<KeyBinding>>[markdownBindings, historyKeymap, defaultKeymap];
    final linux = Keymap.of(all, KeyPlatform.linux), mac = Keymap.of(all, KeyPlatform.mac);
    expect(linux.byKey.keys, containsAll(<String>['Ctrl-z', 'Ctrl-y', 'Shift-Ctrl-z', 'Ctrl-ArrowLeft', 'Shift-ArrowDown', 'Backspace', 'Enter', 'Home', 'Ctrl-a']));
    expect(linux.byKey.containsKey('Meta-z'), isFalse);
    expect(mac.byKey.keys, containsAll(<String>['Meta-z', 'Shift-Meta-z', 'Alt-ArrowLeft', 'Meta-ArrowLeft', 'Ctrl-a', 'Ctrl-e']));
    // lang-markdown's Enter stands before the default one.
    expect(linux.byKey['Enter']!.length, 2);
    expect(identical(linux.byKey['Backspace']!.first.run, markdownBindings.last.run), isTrue);
  });

  testWidgets('arrows move by character and select with Shift', (tester) async {
    final rig = await pumpEditor(tester, 'one two', caret: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rig.head, 4);
    await chord(tester, [shift], LogicalKeyboardKey.arrowRight);
    await chord(tester, [shift], LogicalKeyboardKey.arrowRight);
    expect((rig.anchor, rig.head), (4, 6));
    await chord(tester, [ctrl], LogicalKeyboardKey.arrowLeft);
    expect((rig.anchor, rig.head), (4, 4));
    await chord(tester, [ctrl, shift], LogicalKeyboardKey.arrowRight);
    expect((rig.anchor, rig.head), (4, 7));
    // The keyboard is kept in step with a caret a key moved.
    expect(rig.ime.value.selection, const TextSelection(baseOffset: 4, extentOffset: 7));
    await finish(tester);
  });

  testWidgets('down and up go by visual line and keep their place across', (tester) async {
    final rig = await pumpEditor(tester, wrapped, caret: 0);
    final para = rig.at('A paragraph');
    final line = rig.view.lineAt(para)!;
    expect(line.visualLines.length, greaterThanOrEqualTo(3));
    // From the middle of the paragraph's first visual line.
    await rig.place(para + 20);
    final x = rig.view.coordsAtPos(para + 20)!.left;
    final y0 = rig.view.coordsAtPos(para + 20)!.top;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    var at = rig.view.coordsAtPos(rig.head, rig.view.state.selection.main.assoc)!;
    expect(rig.view.state.doc.lineAt(rig.head).from, para, reason: 'still in the paragraph: its second visual line');
    expect(at.top, greaterThan(y0 + 10));
    expect(at.left, closeTo(x, 8));
    // On down, through the one-letter line, and out the other side at the same place across.
    for (var i = 0; i < line.visualLines.length - 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pump();
    expect(rig.head, rig.at('x\n') + 1, reason: 'a short line takes the caret to its end');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    at = rig.view.coordsAtPos(rig.head)!;
    expect(rig.view.state.doc.lineAt(rig.head).text, 'another line of ordinary length');
    expect(at.left, closeTo(x, 8), reason: 'the goal was kept through the short line');
    // And back up to where it started.
    for (var i = 0; i < line.visualLines.length + 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    expect(rig.head, para + 20);
    // Up from the note's first line goes to its start; down from its last to its end.
    await rig.place(3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(rig.head, 0);
    await rig.place(rig.doc.length - 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rig.head, rig.doc.length);
    await finish(tester);
  });

  testWidgets('Shift with down selects to the same place a line on', (tester) async {
    final rig = await pumpEditor(tester, wrapped, caret: 0);
    await rig.place(rig.at('another') + 3);
    await chord(tester, [shift], LogicalKeyboardKey.arrowDown);
    expect(rig.anchor, rig.at('another') + 3);
    expect(rig.head, rig.at('last') + 3);
    await finish(tester);
  });

  testWidgets('Home and End stop at a wrapped line\'s own ends', (tester) async {
    final rig = await pumpEditor(tester, wrapped, caret: 0);
    final para = rig.at('A paragraph');
    final line = rig.view.lineAt(para)!;
    // Somewhere on the second visual line.
    final second = line.visualLines[1];
    final from = para + line.hitAt(Offset(line.size.width / 2, (second.contentTop + second.contentBottom) / 2))!.pos;
    await rig.place(from);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    final end = rig.head;
    expect(end, greaterThan(from));
    expect(end, lessThan(rig.view.state.doc.lineAt(para).to), reason: 'the visual line\'s end, not the paragraph\'s');
    expect(rig.view.state.selection.main.assoc, -1, reason: 'the caret stays on the line it ended');
    expect(rig.view.coordsAtPos(end, -1)!.top, closeTo(rig.view.coordsAtPos(from)!.top, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    final home = rig.head;
    expect(home, lessThan(from));
    expect(home, greaterThan(para));
    expect(rig.view.coordsAtPos(home, 1)!.top, closeTo(rig.view.coordsAtPos(from)!.top, 1));
    // Shift-End selects to it.
    await chord(tester, [shift], LogicalKeyboardKey.end);
    expect((rig.anchor, rig.head), (home, end));
    // On the last visual line End is the paragraph's end, and on the first Home is its start.
    await rig.place(rig.view.state.doc.lineAt(para).to - 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(rig.head, rig.view.state.doc.lineAt(para).to);
    await rig.place(para + 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(rig.head, para);
    await finish(tester);
  });

  testWidgets('Page Down moves a page and brings the caret into view', (tester) async {
    final doc = <String>[for (var i = 0; i < 200; i++) 'line $i of the note'].join('\n');
    final rig = await pumpEditor(tester, doc, caret: 5);
    final page = EditorMotion.pageHeight(rig.view);
    expect(page, closeTo(844 - 5, 1));
    final before = rig.view.coordsAtPos(5)!;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.pump();
    final line = rig.view.state.doc.lineAt(rig.head).number;
    final height = rig.view.heights.lineHeight;
    expect(line, closeTo(1 + page / height, 2));
    expect(rig.head - rig.view.state.doc.lineAt(rig.head).from, 5, reason: 'the same place across');
    expect(rig.scroll.offset, greaterThan(0));
    final after = rig.view.coordsAtPos(rig.head)!;
    expect(after.bottom, lessThanOrEqualTo(844));
    expect(after.left, closeTo(before.left, 1));
    // Twice more lands in a part of the note that was never laid out, and back again.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.pump();
    expect(rig.view.state.doc.lineAt(rig.head).number, closeTo(1 + 3 * page / height, 4));
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      await tester.pump();
    }
    expect(rig.view.state.doc.lineAt(rig.head).number, lessThanOrEqualTo(3));
    await finish(tester);
  });

  testWidgets('Enter and Backspace from a hardware keyboard are the markdown commands', (tester) async {
    final rig = await pumpEditor(tester, '- milk', caret: 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(rig.doc, '- milk\n- ');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(rig.doc, '- milk\n  ');
    expect(rig.ime.text, rig.doc);
    await finish(tester);
  });

  testWidgets('undo and redo', (tester) async {
    final rig = await pumpEditor(tester, 'one', caret: 3);
    await rig.ime.type(' two');
    await chord(tester, [ctrl], LogicalKeyboardKey.keyZ);
    expect(rig.doc, 'one');
    await chord(tester, [ctrl], LogicalKeyboardKey.keyY);
    expect(rig.doc, 'one two');
    await chord(tester, [ctrl], LogicalKeyboardKey.keyZ);
    expect(rig.doc, 'one');
    // What Android is to CodeMirror: Ctrl-Shift-z redoes too.
    await chord(tester, [ctrl, shift], LogicalKeyboardKey.keyZ);
    expect(rig.doc, 'one two');
    expect(rig.ime.text, 'one two');
    await finish(tester);
  });

  testWidgets('select all, and the clipboard keys through Flutter\'s own intents', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final rig = await pumpEditor(tester, 'one two', caret: 3);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyA);
    expect((rig.anchor, rig.head), (0, 7));
    await chord(tester, [ctrl], LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(clipboard, 'one two');
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(rig.doc, '');
    await chord(tester, [ctrl], LogicalKeyboardKey.keyV);
    await tester.pump();
    await chord(tester, [ctrl], LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(rig.doc, 'one twoone two');
    expect(rig.events.where((e) => e == 'input.paste').length, 2);
    await finish(tester);
  });

  // docs/PARITY.md, Differs 31. The page has this from CodeMirror (@codemirror/view input.ts `copiedRange`, the
  // `copy`/`cut` handler, `doPaste`): with nothing selected a copy takes the caret's line.
  testWidgets('Ctrl-C and Ctrl-X with nothing selected take the caret\'s line, and Ctrl-V puts it back as a line', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboard};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final rig = await pumpEditor(tester, 'one\ntwo words\nthree', caret: 7);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(clipboard, 'two words', reason: 'the line\'s words, without its break');
    expect(rig.doc, 'one\ntwo words\nthree');
    expect(rig.head, 7);
    // Pasted with nothing selected, a line copied whole goes in above the caret's line, and the caret keeps its
    // place in its own.
    await chord(tester, [ctrl], LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(rig.doc, 'one\ntwo words\ntwo words\nthree');
    expect(rig.head, 17);
    expect(rig.events.last, 'input.paste');
    // The cut takes the line and its break.
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboard, 'two words');
    expect(rig.doc, 'one\ntwo words\nthree');
    expect(rig.events.last, 'delete.cut');
    expect(rig.head, 14);
    // The last line has no break after it to take.
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboard, 'three');
    expect(rig.doc, 'one\ntwo words\n');
    // An empty last line is still a line: the clipboard is given its nothing, and there is no break to take.
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboard, '');
    expect(rig.doc, 'one\ntwo words\n');
    await rig.place(0);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboard, 'one');
    expect(rig.doc, 'two words\n');
    // A selection copied is not a line: pasted, it goes in at the caret.
    await rig.place(0, 3);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(clipboard, 'two');
    await rig.place(9);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(rig.doc, 'two wordstwo\n');
    await finish(tester);
  });

  testWidgets('a note that cannot be changed gives its line to Ctrl-C and keeps it from Ctrl-X', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final rig = await pumpEditor(tester, 'one\ntwo', caret: 5, readOnly: true);
    await chord(tester, [ctrl], LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboard, 'two');
    expect(rig.doc, 'one\ntwo');
    await finish(tester);
  });

  testWidgets('a plugin\'s key handler is asked first, and a keymap of higher precedence before the defaults', (tester) async {
    final keys = <LogicalKeyboardKey>[];
    var swallow = false;
    final rig = await pumpEditor(
      tester,
      '- milk',
      caret: 6,
      more: [
        EditorViewLike.eventHandlers(EditorEventHandlers(keyDown: (event, view) {
          keys.add(event.logicalKey);
          return swallow;
        })),
        Prec.highest(editorKeymap.of([
          KeyBinding(key: 'Enter', run: (target) {
            target.dispatch(target.state.update(target.state.replaceSelection('!')));
            return true;
          }),
        ])),
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(rig.doc, '- milk!');
    swallow = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(rig.doc, '- milk!');
    expect(keys, [LogicalKeyboardKey.enter, LogicalKeyboardKey.enter]);
    await finish(tester);
  });

  testWidgets('deleteLine leaves the caret a line down at its own place across (verticalMotion by layout)', (tester) async {
    final rig = await pumpEditor(tester, 'one\ntwo words\nthree words', caret: 0);
    await rig.place(rig.at('two') + 5);
    await chord(tester, [ctrl, shift], LogicalKeyboardKey.keyK);
    expect(rig.doc, 'one\nthree words');
    expect(rig.head, rig.at('three') + 5);
    await finish(tester);
  });

  testWidgets('a key no binding takes is left for the keyboard to type', (tester) async {
    final rig = await pumpEditor(tester, 'one', caret: 3);
    expect(runKey(rig.view, 'a'), isFalse);
    expect(runKey(rig.view, 'Shift-a'), isFalse);
    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(handled, isFalse);
    await finish(tester);
  });
}
