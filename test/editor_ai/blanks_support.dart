// What the blanks' tests and the fill panel's share: the hooks a note's screen gives, an editor that is only a state
// and a view (the web's `new EditorView({ parent: document.body })` with nothing laid out), what such a view draws
// read from its decorations (the page's `querySelectorAll('.cm-blank')`), a note drawn with the fill panel stacked
// over it, and a model the test answers for the cases that need the fills' queue to speak.
import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/fills/queue.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/app/preferences.dart' show AppPreferences;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/ai/blanks.dart';
import 'package:ghost_md/editor/ai/fill_panel.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// Hooks as the note screen gives them, on Monday 28 September 2026 in London, with what was pressed and said.
class Given {
  Given({bool canFill = true, Lookups lookups = Lookups.on, String noteId = 'n1'}) {
    hooks = BlankHooks(
      noteId: () => noteId,
      canFill: () => canFill,
      learntUntil: () => 2024,
      lookups: () => lookups,
      fill: pressed.add,
      say: said.add,
      now: () => DateTime.utc(2026, 9, 28, 13, 5),
      zone: () => 'Europe/London',
    );
  }

  late BlankHooks hooks;
  final List<List<FillTarget>> pressed = <List<FillTarget>>[];
  final List<String> said = <String>[];
}

/// A press's targets as the page's test held them: plain objects.
List<Map<String, Object?>> targetsJson(List<FillTarget> targets) => <Map<String, Object?>>[
      for (final t in targets)
        <String, Object?>{
          'key': t.key,
          'question': t.question,
          'order': t.order,
          if (t.again != null) 'again': <String, Object?>{'mark': t.again!.mark, 'words': t.again!.words},
          if (t.anyway) 'anyway': true,
        },
    ];

/// An editor with the squares, nothing laid out. `given` null is the page's `blanks(null)`.
EditorView editor(String doc, {Given? given, bool noHooks = false, bool formatted = false, int? anchor, bool readOnly = false, List<Extension> more = const <Extension>[]}) {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      selection: anchor == null ? null : EditorSelection.single(anchor),
      extensions: noteExtensions(
        formats: marks,
        display: formatted ? NoteView.formatted : NoteView.mixed,
        readOnly: readOnly,
        more: <Extension>[blanks(noHooks ? null : (given ?? Given()).hooks), ...more],
      ),
    ),
  );
  addTearDown(view.destroy);
  return view;
}

/// Every decoration the view draws, in the order of the note.
List<({int from, int to, Decoration value})> drawn(EditorView view) {
  final found = <({int from, int to, Decoration value})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      found.add((from: from, to: to, value: value));
      return null;
    });
  }
  return found..sort((a, b) => a.from != b.from ? a.from - b.from : a.value.startSide - b.value.startSide);
}

/// The marks of one class: `.cm-blank`, `.cm-blankMark`, `.cm-blankQuestion`.
List<({int from, int to, Decoration value})> marked(EditorView view, String name) =>
    drawn(view).where((d) => (d.value.spec.className ?? '').split(' ').contains(name)).toList();

List<({int from, int to, Decoration value})> squares(EditorView view) => marked(view, 'cm-blank');
List<String?> labels(EditorView view) => <String?>[for (final s in squares(view)) s.value.spec.attributes?['aria-label']];

/// The widgets of one kind, in the order of the note.
List<W> widgets<W extends EditorWidget>(EditorView view) => <W>[
      for (final d in drawn(view))
        if (d.value.widget case final W widget) widget,
    ];

List<String> pills(EditorView view) => <String>[for (final pill in widgets<PillWidget>(view)) pill.label];
List<String> after(EditorView view) => <String>[for (final words in widgets<AfterWidget>(view)) words.text];

/// The ranges hidden (`Decoration.replace({})`): the braces in the Formatted view.
List<({int from, int to})> hiddenRanges(EditorView view) => <({int from, int to})>[
      for (final d in drawn(view))
        if (d.to > d.from && d.value.spec.className == null && d.value.widget == null && d.value is PointDecoration) (from: d.from, to: d.to),
    ];

/// A note drawn as the page draws it (test/editor/media/support.dart `pumpNote`), with the marks, the squares, the
/// fill panel and the panel's own layer stacked over the editor, as the note's screen stacks it.
Future<EditorView> pumpBlanks(
  WidgetTester tester,
  String doc, {
  Given? given,
  bool noHooks = false,
  NoteView display = NoteView.mixed,
  String theme = 'light',
  bool readOnly = false,
  bool still = false,
  int? caret,
  double width = 390,
  bool shadows = false,
  List<Extension> more = const <Extension>[],
}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(
        formats: marks,
        display: display,
        readOnly: readOnly,
        more: <Extension>[markExtensions(marks), blanks(noHooks ? null : (given ?? Given()).hooks, still: still), fillPanel(), ...more],
      ),
    ),
  );
  _views.add(view);
  await pumpApp(
    tester,
    size: Size(width, 844),
    prefs: AppPreferences(theme: theme),
    ratio: 2,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 844,
              child: Stack(
                children: <Widget>[
                  SingleChildScrollView(child: EditorColumn(view: view)),
                  Positioned.fill(child: EditorFillPanel(view: view)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  // pumpApp turns real shadows on for a picture, and the binding wants its switch back as a test ends: a test that
  // takes a picture of the panel keeps them (`shot` puts the switch back), the rest have it back now.
  if (!shadows) debugDisableShadows = true;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  return view;
}

final List<EditorView> _views = <EditorView>[];

/// Ends a drawn test: the views go (their timers with them: the pause, the count, the idle fill) before the test's
/// own check that nothing is still waiting.
Future<void> closeBlanks(WidgetTester tester) async {
  for (final view in _views) {
    view.destroy();
  }
  _views.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// A model the test answers: each generation waits until the test finishes it (test/ai/fills/queue_test.dart).
class FakeModel {
  FakeModel(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();

  Run get run => Run(
        done: _done.future,
        cancel: () {
          if (!_done.isCompleted) _done.completeError(StateError('cancelled'));
        },
      );

  void finish(String text) => _done.complete(Output(text: text, promptTokens: 900, outputTokens: 12, ms: 1500, cachedTokens: 800, prefillMs: 100, loadMs: 0, tokensPerSecond: 20, truncated: false));
}

/// The fills' queue with a model the test answers and no network, for a case that needs it to speak.
class FakeFills {
  final List<FakeModel> models = <FakeModel>[];
  final List<FillToast> toasts = <FillToast>[];
  void Function() _stop = () {};

  void start() {
    useStored(MemoryStored());
    preferences.update((p) => p.copyWith(localOnly: false, lookUpBlanks: true));
    simulateRuns((options) {
      final model = FakeModel(options);
      models.add(model);
      return model.run;
    });
    setFillWorld(now: () => DateTime(2026, 9, 28, 12), fetch: (url) async => throw StateError('offline'));
    _stop = startFills(toasts.add, (_) {}, getNote: (id) async => null, updateNote: (id, body, revision) async => Note(id: id, body: body, createdAt: 0, updatedAt: 0), syncNow: () async {});
  }

  void stop() {
    _stop();
    simulateRuns(null);
    forgetAllRuns();
    forgetFills();
  }

  /// Hooks whose press is the queue's own.
  Given given({String noteId = 'n1'}) {
    final given = Given(noteId: noteId);
    given.hooks = BlankHooks(
      noteId: () => noteId,
      canFill: () => true,
      learntUntil: () => 2024,
      lookups: () => Lookups.on,
      fill: (targets) {
        given.pressed.add(targets);
        pressFill(noteId, targets, 'qwen3.5-4b');
      },
      say: given.said.add,
      now: () => DateTime.utc(2026, 9, 28, 13, 5),
      zone: () => 'Europe/London',
    );
    return given;
  }
}
