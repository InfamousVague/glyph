// The Keyboard modes plugin in the editor (lib/plugins/keymaps/editor_keys.dart, mode_badge.dart): a hardware
// keyboard's keys taken by Vim or Emacs ahead of the editor's own, Insert typing as it always has with the app's
// Control shortcuts, the block caret in Normal, the badge at the foot, a phone's screen keyboard left alone until a
// hardware key is seen, and with the plugin off every key the editor's as before.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart' show EditorSelectionPainter;
import 'package:ghost_md/plugins/keymaps/keymaps.dart';
import 'package:ghost_md/plugins/keymaps/mode_badge.dart' show KeymapBadgeKeys;
import 'package:ghost_md/plugins/keymaps/vim.dart';

import '../../editor/input/support.dart';
import '../../support/render.dart';

const LogicalKeyboardKey ctrl = LogicalKeyboardKey.controlLeft;

/// The editor with the extension, the badge over its foot, and [mode] chosen.
Future<(Rig, ValueNotifier<KeyboardMode>, List<String>)> pumpKeys(WidgetTester tester, String doc, {KeyboardMode mode = KeyboardMode.vim, int caret = 0, bool startNormal = true}) async {
  final chosen = ValueNotifier<KeyboardMode>(mode);
  final asked = <String>[];
  final view = EditorView(
    state: EditorState.create(
      doc: doc,
      selection: EditorSelection.single(caret),
      extensions: noteExtensions(more: <Extension>[
        editorInput(),
        keyboardModes(KeymapHooks(mode: () => chosen.value, startNormal: () => startNormal, save: () => asked.add('save'), close: () => asked.add('close'))),
      ]),
    ),
  );
  final scroll = ScrollController();
  final controller = EditorController();
  addTearDown(view.destroy);
  addTearDown(scroll.dispose);
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    home: Stack(children: [
      Page(view, scroll, controller: controller),
      Positioned(left: 0, right: 0, bottom: 0, child: KeymapBadge(view: view)),
    ]),
  );
  final rig = Rig(tester, view, scroll, controller);
  await rig.focus();
  return (rig, chosen, asked);
}

Future<void> keys(WidgetTester tester, List<LogicalKeyboardKey> pressed) async {
  for (final key in pressed) {
    await tester.sendKeyEvent(key);
  }
  await tester.pump();
}

Future<void> chord(WidgetTester tester, LogicalKeyboardKey held, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(held);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(held);
  await tester.pump();
}

String? badge(WidgetTester tester) {
  final found = find.byKey(KeymapBadgeKeys.words);
  if (found.evaluate().isEmpty) return null;
  return tester.widget<Text>(found).textSpan!.toPlainText();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => hardwareKeyboardSeen.value = true);
  tearDown(() => hardwareKeyboardSeen.value = false);

  testWidgets('Vim: Normal takes the letters, Insert types as ever, Esc and u come back', (tester) async {
    final (rig, _, _) = await pumpKeys(tester, 'one two three');
    expect(keymapSessionOf(rig.view)!.vim!.mode, VimMode.normal);
    expect(badge(tester), 'NORMAL');
    // A block over the character under the caret.
    expect(rig.view.selectionPainter.runtimeType, isNot(EditorSelectionPainter));
    await keys(tester, [LogicalKeyboardKey.keyW]);
    expect(rig.head, 4);
    await keys(tester, [LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyW]);
    expect(rig.doc, 'one three');
    await keys(tester, [LogicalKeyboardKey.keyI]);
    expect(badge(tester), 'INSERT');
    expect(rig.view.selectionPainter.runtimeType, EditorSelectionPainter);
    // Insert is the keyboard's own typing: a letter's key is not Vim's.
    await keys(tester, [LogicalKeyboardKey.keyX]);
    expect(rig.doc, 'one three');
    await rig.ime.type('new ');
    expect(rig.doc, 'one new three');
    await keys(tester, [LogicalKeyboardKey.escape]);
    expect(badge(tester), 'NORMAL');
    expect(rig.head, 7);
    await keys(tester, [LogicalKeyboardKey.keyU]);
    expect(rig.doc, 'one three');
    await keys(tester, [LogicalKeyboardKey.keyU]);
    expect(rig.doc, 'one two three');
    await finish(tester);
  });

  testWidgets('Vim: the app\'s Control shortcuts still work in Insert, and :w and :q go to the note', (tester) async {
    final (rig, _, asked) = await pumpKeys(tester, 'words', caret: 5, startNormal: false);
    expect(badge(tester), 'INSERT');
    await rig.ime.type('!');
    expect(rig.doc, 'words!');
    // The editor's own undo (Ctrl-z, as Android's keymap has it in a test).
    await chord(tester, ctrl, LogicalKeyboardKey.keyZ);
    expect(rig.doc, 'words');
    // Ctrl-[ is Esc.
    await chord(tester, ctrl, LogicalKeyboardKey.bracketLeft);
    expect(badge(tester), 'NORMAL');
    await tester.sendKeyEvent(LogicalKeyboardKey.semicolon, character: ':');
    await tester.pump();
    expect(badge(tester), ':');
    await keys(tester, [LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyQ, LogicalKeyboardKey.enter]);
    await tester.pump();
    expect(asked, ['save', 'close']);
    await finish(tester);
  });

  testWidgets('Vim on a phone: the screen keyboard\'s Backspace is the editor\'s until a hardware key is pressed', (tester) async {
    hardwareKeyboardSeen.value = false;
    final (rig, _, _) = await pumpKeys(tester, 'abc', caret: 3);
    expect(badge(tester), isNull);
    expect(rig.view.selectionPainter.runtimeType, EditorSelectionPainter);
    await rig.ime.backspace();
    expect(rig.doc, 'ab');
    // A letter's key comes only from a hardware keyboard: Vim wakes, and it is Vim's.
    await keys(tester, [LogicalKeyboardKey.digit0]);
    expect(hardwareKeyboardSeen.value, isTrue);
    expect(rig.head, 0);
    expect(badge(tester), 'NORMAL');
    await finish(tester);
  });

  testWidgets('Off: every key is the editor\'s as before, and nothing is drawn', (tester) async {
    final (rig, chosen, _) = await pumpKeys(tester, 'one two', mode: KeyboardMode.off, caret: 3);
    expect(badge(tester), isNull);
    await keys(tester, [LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyW]);
    expect((rig.doc, rig.head), ('one two', 3));
    await rig.ime.type('!');
    expect(rig.doc, 'one! two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(rig.head, 3);
    // Chosen while the note is open: the note has it at once.
    chosen.value = KeyboardMode.vim;
    await keys(tester, [LogicalKeyboardKey.keyX]);
    expect(rig.doc, 'one two');
    await finish(tester);
  });

  testWidgets('Emacs: C-k and C-y, the mark selecting with C-f, its badge, and C-g', (tester) async {
    final (rig, _, asked) = await pumpKeys(tester, 'first line\nsecond', mode: KeyboardMode.emacs);
    expect(badge(tester), isNull);
    await chord(tester, ctrl, LogicalKeyboardKey.keyK);
    expect(rig.doc, '\nsecond');
    await chord(tester, ctrl, LogicalKeyboardKey.keyE);
    await chord(tester, ctrl, LogicalKeyboardKey.keyY);
    expect(rig.doc, 'first line\nsecond');
    await chord(tester, ctrl, LogicalKeyboardKey.keyA);
    expect(rig.head, 0);
    await chord(tester, ctrl, LogicalKeyboardKey.space);
    expect(badge(tester), 'MARK');
    await chord(tester, ctrl, LogicalKeyboardKey.keyF);
    await chord(tester, ctrl, LogicalKeyboardKey.keyF);
    expect((rig.anchor, rig.head), (0, 2));
    await chord(tester, ctrl, LogicalKeyboardKey.keyG);
    expect(badge(tester), isNull);
    expect(rig.anchor, rig.head);
    // A letter typed is the keyboard's; C-x C-s saves.
    await rig.ime.type('z');
    expect(rig.doc.startsWith('fiz'), isTrue);
    await chord(tester, ctrl, LogicalKeyboardKey.keyX);
    expect(badge(tester), 'C-x-');
    await chord(tester, ctrl, LogicalKeyboardKey.keyS);
    expect(asked, ['save']);
    await finish(tester);
  });
}
