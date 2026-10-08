import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:ghost_md/editor/input/ime.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// A scripted keyboard: what Android's does to a Flutter text client, without Android.
///
/// It holds a value, as a real keyboard holds its copy of the text. A value the editor pushes
/// (`TextInput.setEditingState`) replaces it; everything it does is a delta against it, sent the way the engine
/// sends them (`TextInputClient.updateEditingStateWithDeltas`, the JSON the engine writes). So a test says what a
/// person did on the keyboard and reads what the editor made of it, and what it told the keyboard back.
class FakeIme {
  FakeIme(this.tester);

  final WidgetTester tester;
  int _seen = 0;
  TextEditingValue _value = TextEditingValue.empty;

  List<MethodCall> get log => tester.testTextInput.log;

  /// The calls the editor has made since this was last asked, by method name.
  List<String> takeCalls() {
    final calls = <String>[for (final call in log.skip(_taken)) call.method];
    _taken = log.length;
    return calls;
  }

  int _taken = 0;

  /// How many values the editor has pushed.
  int get pushes => log.where((call) => call.method == 'TextInput.setEditingState').length;

  /// How many times the editor attached.
  int get attaches => log.where((call) => call.method == 'TextInput.setClient').length;

  int get client => (log.lastWhere((call) => call.method == 'TextInput.setClient').arguments as List<dynamic>)[0] as int;

  /// The configuration the editor last attached or updated with.
  Map<String, dynamic> get config {
    for (final call in log.reversed) {
      if (call.method == 'TextInput.setClient') return ((call.arguments as List<dynamic>)[1] as Map).cast<String, dynamic>();
      if (call.method == 'TextInput.updateConfig') return (call.arguments as Map).cast<String, dynamic>();
    }
    throw StateError('The editor never attached');
  }

  /// What the keyboard holds now: the last value pushed, with everything typed since.
  TextEditingValue get value {
    for (; _seen < log.length; _seen++) {
      if (log[_seen].method == 'TextInput.setEditingState') _value = TextEditingValue.fromJSON((log[_seen].arguments as Map).cast<String, dynamic>());
    }
    return _value;
  }

  String get text => value.text;
  int get caret => value.selection.extentOffset;

  Map<String, dynamic> _delta(String oldText, String deltaText, int start, int end, TextSelection selection, TextRange composing) => <String, dynamic>{
    'oldText': oldText,
    'deltaText': deltaText,
    'deltaStart': start,
    'deltaEnd': end,
    'selectionBase': selection.baseOffset,
    'selectionExtent': selection.extentOffset,
    'selectionAffinity': 'TextAffinity.downstream',
    'selectionIsDirectional': false,
    'composingBase': composing.start,
    'composingExtent': composing.end,
  };

  /// One edit of the keyboard's value, as the delta the engine would send; the value follows.
  Map<String, dynamic> edit(int start, int end, String replacement, {int? caret, TextSelection? selection, TextRange composing = TextRange.empty}) {
    final before = value;
    final text = before.text.replaceRange(start, end, replacement);
    final after = selection ?? TextSelection.collapsed(offset: caret ?? start + replacement.length);
    _value = TextEditingValue(text: text, selection: after, composing: composing);
    return _delta(before.text, replacement, start, end, after, composing);
  }

  /// A change of the selection or the composing range alone.
  Map<String, dynamic> move(TextSelection selection, {TextRange composing = TextRange.empty}) {
    final before = value;
    _value = TextEditingValue(text: before.text, selection: selection, composing: composing);
    return _delta(before.text, '', -1, -1, selection, composing);
  }

  /// Sends deltas as one batch.
  Future<void> send(List<Map<String, dynamic>> deltas) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
          client,
          <String, dynamic>{'deltas': deltas},
        ]),
      ),
      (_) {},
    );
    await tester.pump();
  }

  /// Types `text` at the keyboard's selection, a key at a time, committed as it goes (no composing).
  Future<void> type(String text) async {
    for (final char in text.characters) {
      final sel = value.selection;
      await send(<Map<String, dynamic>>[edit(sel.start, sel.end, char)]);
    }
  }

  /// The keyboard's Enter key: an inserted line break.
  Future<void> enter() => type('\n');

  /// The keyboard's Backspace key, as Gboard sends it: a key event, and nothing done to its own text.
  Future<void> backspace() async {
    value;
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
  }

  /// Types `text` as a word being composed: each letter replaces the underlined run with a longer one.
  Future<void> compose(String text) async {
    final sel = value.selection;
    var start = value.composing.isValid ? value.composing.start : sel.start;
    var end = value.composing.isValid ? value.composing.end : sel.end;
    var word = value.composing.isValid ? value.composing.textInside(value.text) : '';
    for (final char in text.characters) {
      word += char;
      await send(<Map<String, dynamic>>[edit(start, end, word, composing: TextRange(start: start, end: start + word.length))]);
      end = start + word.length;
    }
  }

  /// Ends a composition where it stands: the underline goes and the text stays.
  Future<void> commit() => send(<Map<String, dynamic>>[move(value.selection)]);

  /// Moves the keyboard's caret (its own cursor control), or selects.
  Future<void> select(int base, [int? extent]) => send(<Map<String, dynamic>>[move(TextSelection(baseOffset: base, extentOffset: extent ?? base))]);
}

class Page extends StatelessWidget {
  const Page(this.view, this.scroll, {super.key, this.controller, this.onHold, this.footClear = 0, this.autofocus = false, this.barHeight = 60});

  final EditorView view;
  final ScrollController scroll;
  final EditorController? controller;
  final void Function(Held held)? onHold;
  final double footClear;
  final bool autofocus;
  final double barHeight;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.color('glacier-bg'),
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CustomScrollView(
        controller: scroll,
        slivers: <Widget>[
          SliverToBoxAdapter(child: SizedBox(height: barHeight, child: const Text("the note's bar"))),
          Editor(view: view, controller: controller, onHold: onHold, footClear: footClear, autofocus: autofocus),
        ],
      ),
    ),
  );
}

/// What a test gets to hold.
class Rig {
  Rig(this.tester, this.view, this.scroll, this.controller) : ime = FakeIme(tester);

  final WidgetTester tester;
  final EditorView view;
  final ScrollController scroll;
  final EditorController controller;
  final FakeIme ime;
  final List<Held> held = <Held>[];

  /// Every transaction's user event, in order ('' for one without).
  final List<String> events = <String>[];

  EditorIme get client => controller.ime!;
  String get doc => view.state.doc.toString();
  int get head => view.state.selection.main.head;
  int get anchor => view.state.selection.main.anchor;

  /// The part of the note the keyboard is shown.
  String get window => view.state.doc.sliceString(client.windowFrom, client.windowTo);

  /// Where `needle` starts in the note (its `nth` occurrence), plus `plus`.
  int at(String needle, [int plus = 0, int nth = 0]) {
    var from = -1;
    for (var i = 0; i <= nth; i++) {
      from = doc.indexOf(needle, from + 1);
      if (from < 0) throw StateError('"$needle" is not in the note');
    }
    return from + plus;
  }

  /// Puts the caret (or a selection) as a pointer would, and waits a frame.
  Future<void> place(int anchor, [int? head]) async {
    view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), userEvent: 'select.pointer'));
    await tester.pump();
  }

  /// Gives the editor the keyboard.
  Future<void> focus() async {
    controller.focus();
    await tester.pump();
    await tester.pump();
  }

  /// The middle of the text at `pos`, on screen.
  Offset point(int pos, [int side = 1]) => view.coordsAtPos(pos, side)!.center;
}

/// The editor on a phone's screen, in a scroll view under a bar, with the input layer in its state.
Future<Rig> pumpEditor(
  WidgetTester tester,
  String doc, {
  List<Extension> more = const <Extension>[],
  bool readOnly = false,
  bool assist = true,
  bool focus = true,
  int? caret,
  double footClear = 0,
}) async {
  late final Rig rig;
  final view = EditorView(
    state: EditorState.create(
      doc: doc,
      selection: caret == null ? null : EditorSelection.single(caret),
      extensions: noteExtensions(
        readOnly: readOnly,
        more: <Extension>[
          editorInput(assist: assist),
          EditorViewLike.updateListener.of((update) {
            for (final tr in update.transactions) {
              rig.events.add(tr.annotation(Transaction.userEvent) ?? '');
            }
          }),
          ...more,
        ],
      ),
    ),
  );
  final scroll = ScrollController();
  final controller = EditorController();
  rig = Rig(tester, view, scroll, controller);
  addTearDown(view.destroy);
  addTearDown(scroll.dispose);
  await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), ratio: 2, home: Page(view, scroll, controller: controller, onHold: rig.held.add, footClear: footClear));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  if (focus) await rig.focus();
  rig.events.clear();
  return rig;
}

/// Ends a test that drew the app: the tree is taken down so its timers stop, and the shadows switch is put back.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  debugDisableShadows = true;
}

List<RenderEditorLine> drawn(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);
