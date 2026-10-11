// What the + tests share: an editor with the + in it drawn as the page draws it (390 x 844, two device pixels, the
// editor's box at the screen's corner, as test/editor/plus/fixtures/reference.mjs mounts the web's), the hooks a
// screen would give it, and the keys and letters an input layer would send.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

export '../../support/render.dart' show loadAppFonts, pumpApp, shot;

/// The hooks a test gives the +, and what they heard.
class Hooked {
  final List<PlusOpening> opened = <PlusOpening>[];
  int closed = 0;
  final List<PlusKey> keys = <PlusKey>[];
  bool take = true;
  bool allow = true;

  late final PlusHooks hooks = PlusHooks(
    allowed: () => allow,
    onOpen: opened.add,
    onClose: () => closed += 1,
    onKey: (key) {
      keys.add(key);
      return take;
    },
  );
}

final List<EditorView> _made = <EditorView>[];

/// A widget test that takes its editors down before the binding counts the timers left running (the +'s settle).
void plusTest(String description, Future<void> Function(WidgetTester tester) body, {bool? skip}) {
  testWidgets(description, skip: skip, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final view in _made) {
        view.destroy();
      }
      _made.clear();
      // pumpApp turned real shadows on; the binding checks the switch is back as a test ends.
      debugDisableShadows = true;
    }
  });
}

/// An editor over `doc` with `extension` in it, not drawn.
EditorView editorOf(String doc, Extension extension, {int? caret}) {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      selection: EditorSelection.single(caret ?? doc.length),
      extensions: noteExtensions(more: <Extension>[history(), extension]),
    ),
  );
  _made.add(view);
  return view;
}

/// Draws `view` under a [PlusLayer] as the page draws the editor, focused, and answers once it is laid out.
Future<void> pumpPlus(
  WidgetTester tester,
  EditorView view, {
  PlusController? controller,
  AddConfig config = const AddConfig(),
  String theme = 'light',
  Size size = const Size(390, 844),
  DateTime Function()? clock,
  bool? coarse,
  bool focused = true,
  double inset = 0,
  Rect? Function()? pane,
}) async {
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme),
    ratio: 2,
    home: Builder(
      // One device pixel to the logical one for the editor's own layout, as test/editor/view/support.dart says.
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: PlusLayer(
          view: view,
          controller: controller,
          config: config,
          clock: clock,
          coarse: coarse,
          pane: pane,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: size.width, child: SingleChildScrollView(child: EditorColumn(view: view))),
            ),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding(top: inset * 2);
  tester.view.viewPadding = FakeViewPadding(top: inset * 2);
  await tester.pump();
  if (focused) {
    view.setFocused(true);
    await tester.pump();
  }
}

/// An editor with the + and a test's hooks, drawn and focused.
Future<(EditorView, Hooked)> mountPlus(WidgetTester tester, String doc, {int? caret, String theme = 'light'}) async {
  final hooked = Hooked();
  final view = editorOf(doc, insertPlus(hooked.hooks), caret: caret);
  await pumpPlus(tester, view, theme: theme);
  return (view, hooked);
}

PlusView plusOf(EditorView view) => plusViewOf(view)!;

/// The render object that puts the + beside its row.
RenderPlusFollower followerOf(WidgetTester tester) => tester.renderObject<RenderPlusFollower>(find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_PlusFollower'));

/// Types letters as the keyboard would: a change at the caret, the caret after it.
void type(EditorView view, String text) {
  final at = view.state.selection.main.head;
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: text), selection: EditorSelection.single(at + text.length), userEvent: 'input.type'));
}

/// A hardware key as the input layer hands it to the view's handlers, in their order: whether one took it.
bool sendKey(EditorView view, LogicalKeyboardKey key, {String? character}) {
  final event = KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyA, logicalKey: key, character: character, timeStamp: Duration.zero);
  for (final handlers in view.eventHandlers) {
    if (handlers.keyDown?.call(event, view) ?? false) return true;
  }
  return false;
}

/// The settle, to the millisecond.
const Duration settle = Duration(milliseconds: settleMs);

/// One case test/editor/plus/fixtures/reference.mjs measured on the web page.
Map<String, dynamic> fixture(String name) => jsonDecode(File('test/editor/plus/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

Rect rectOf(Object? r) {
  final m = r! as Map<String, dynamic>;
  return Rect.fromLTRB((m['left'] as num).toDouble(), (m['top'] as num).toDouble(), (m['right'] as num).toDouble(), (m['bottom'] as num).toDouble());
}

/// How far two rectangles are apart: the largest difference of an edge.
double apart(Rect a, Rect b) => <double>[(a.left - b.left).abs(), (a.top - b.top).abs(), (a.right - b.right).abs(), (a.bottom - b.bottom).abs()].reduce((x, y) => x > y ? x : y);
