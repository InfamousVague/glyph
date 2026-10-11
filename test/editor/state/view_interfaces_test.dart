// The interfaces extension files are written against (lib/editor/view/plugin.dart, widget.dart): a plugin and its
// decorations, an update, dispatching, and the facets a view reads, exercised with the smallest view that could
// implement them. The real view is piece C's.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

/// A view with no rendering: it keeps the state, runs the plugins the state asks for, and tells them of updates.
class BareView extends EditorViewLike {
  BareView(this.state) {
    for (final plugin in state.facet(viewPlugin)) {
      _instances[plugin] = plugin.create(this);
    }
  }

  @override
  EditorState state;
  final Map<ViewPlugin<PluginValue>, PluginValue> _instances = Map<ViewPlugin<PluginValue>, PluginValue>.identity();
  final List<ViewUpdate> updates = <ViewUpdate>[];
  bool focused = false;
  int measures = 0;

  @override
  void dispatchTransactions(List<Transaction> trs) {
    final update = ViewUpdate.create(this, trs.last.state, trs);
    state = trs.last.state;
    updates.add(update);
    for (final value in _instances.values) {
      value.update(update);
    }
    for (final listener in state.facet(EditorViewLike.updateListener)) {
      listener(update);
    }
  }

  void setFocus(bool to) {
    focused = to;
    final update = ViewUpdate.create(this, state, const <Transaction>[])..flags |= UpdateFlag.focus;
    for (final value in _instances.values) {
      value.update(update);
    }
    final effects = <StateEffect<Object?>>[
      for (final make in state.facet(EditorViewLike.focusChangeEffect)) ?make(state, to),
    ];
    if (effects.isNotEmpty) dispatch(TransactionSpec(effects: effects));
  }

  List<DecorationSet> get decorations => <DecorationSet>[
    for (final source in state.facet(EditorViewLike.decorations)) EditorViewLike.resolveDecorations(source, this),
  ];

  @override
  DocRange get viewport => DocRange(0, state.doc.length);
  @override
  List<DocRange> get visibleRanges => <DocRange>[viewport];
  @override
  Rect? coordsAtPos(int pos, [int side = 1]) => null;
  @override
  int? posAtCoords(Offset global, {bool precise = true}) => null;
  @override
  void requestMeasure<T>([MeasureRequest<T>? request]) {
    measures++;
    request?.run(this);
  }

  @override
  bool get hasFocus => focused;
  @override
  bool composing = false;
  @override
  bool get compositionStarted => composing;
  @override
  V? plugin<V extends PluginValue>(ViewPlugin<V> plugin) => _instances[plugin] as V?;
  @override
  void focus() => setFocus(true);
}

/// The shape of the Tauri app's tags.ts: a chip on every `#word` in view, redrawn when the document changes.
class TagChips extends PluginValue {
  TagChips(EditorViewLike view) : decorations = decorate(view);

  DecorationSet decorations;
  int redraws = 0;

  static final Decoration chip = Decoration.mark(className: 'cm-tag');

  static DecorationSet decorate(EditorViewLike view) {
    final builder = RangeSetBuilder<Decoration>();
    final doc = view.state.doc;
    for (final range in view.visibleRanges) {
      for (var line = doc.lineAt(range.from); ; line = doc.line(line.number + 1)) {
        for (final match in RegExp(r'#\w+').allMatches(line.text)) {
          builder.add(line.from + match.start, line.from + match.end, chip);
        }
        if (line.to >= range.to || line.number >= doc.lines) break;
      }
    }
    return builder.finish();
  }

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged) {
      decorations = decorate(update.view);
      redraws++;
    }
  }
}

class Chip extends EditorWidget {
  const Chip(this.label);
  final String label;

  @override
  bool eq(Chip other) => other.label == label;

  @override
  Widget build(BuildContext context) => Text('$label in a note of ${EditorViewScope.of(context).state.doc.length}', textDirection: TextDirection.ltr);
}

class Other extends EditorWidget {
  const Other();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

List<List<int>> spans(DecorationSet set) {
  final out = <List<int>>[];
  for (final c = set.iter(); c.value != null; c.next()) {
    out.add(<int>[c.from, c.to]);
  }
  return out;
}

void main() {
  group('ViewPlugin', () {
    final tags = ViewPlugin.fromClass<TagChips>(TagChips.new, decorations: (v) => v.decorations);

    test('lives in the view, sees its updates, and its decorations reach the facet the view reads', () {
      final view = BareView(EditorState.create(doc: 'a #one\nand #two', extensions: tags));
      expect(view.plugin(tags), isA<TagChips>());
      expect(spans(view.decorations.single), <List<int>>[<int>[2, 6], <int>[11, 15]]);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '#zero '), userEvent: 'input.type'));
      expect(spans(view.decorations.single), <List<int>>[<int>[0, 5], <int>[8, 12], <int>[17, 21]]);
      expect(view.plugin(tags)!.redraws, 1);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(3)));
      expect(view.plugin(tags)!.redraws, 1);
    });

    test('is in a state once, however often it is given, and absent from a view without it', () {
      final state = EditorState.create(extensions: Extension.list(<Extension>[tags, Prec.high(tags), tags.extension]));
      expect(state.facet(viewPlugin), hasLength(1));
      expect(state.facet(EditorViewLike.decorations), hasLength(1));
      final other = ViewPlugin.define<TagChips>(TagChips.new);
      expect(BareView(state).plugin(other), isNull);
      expect(BareView(EditorState.create()).decorations, isEmpty);
    });

    test('brings what it provides, and carries its handlers', () {
      final flag = Facet.define<String, List<String>>();
      var taps = 0;
      final handlers = EditorEventHandlers(
        tap: (tap, view) {
          taps++;
          return tap.pos != null;
        },
      );
      final plugin = ViewPlugin.define<TagChips>(TagChips.new, provide: (p) => flag.of('provided'), eventHandlers: handlers);
      final state = EditorState.create(extensions: Extension.list(<Extension>[plugin, EditorViewLike.eventHandlers(EditorEventHandlers(blur: (_) => true))]));
      expect(state.facet(flag), <String>['provided']);
      final found = state.facet(viewPlugin);
      expect(found, hasLength(2));
      expect(found[0].eventHandlers, same(handlers));
      expect(found[1].eventHandlers!.blur, isNotNull);
      final view = BareView(state);
      const tap = EditorTap(global: Offset(1, 2), local: Offset(1, 2), kind: PointerDeviceKind.touch, pos: 4);
      expect(found[0].eventHandlers!.tap!(tap, view), isTrue);
      expect(taps, 1);
      expect(EditorState.create(extensions: EditorViewLike.eventObservers(handlers)).facet(viewPlugin).single.eventObservers, same(handlers));
    });
  });

  group('ViewUpdate', () {
    test('says what changed: the document, the selection, the transactions', () {
      final view = BareView(EditorState.create(doc: 'one two'));
      final first = view.state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '> ')));
      final second = first.state.update(TransactionSpec(changes: const ChangeSpec(from: 5, to: 9), selection: EditorSelection.single(1)));
      view.dispatchTransactions(<Transaction>[first, second]);
      final update = view.updates.single;
      expect(update.docChanged, isTrue);
      expect(update.selectionSet, isTrue);
      expect(update.transactions, hasLength(2));
      expect(update.startState.doc.toString(), 'one two');
      expect(update.state.doc.toString(), '> one');
      expect(update.changes.apply(update.startState.doc).toString(), '> one');
      expect(<List<int>>[for (final r in update.changedRanges) <int>[r.fromA, r.toA, r.fromB, r.toB]], <List<int>>[<int>[0, 0, 0, 2], <int>[3, 7, 5, 5]]);
      expect(update.geometryChanged, isTrue);
      expect(update.viewportChanged, isFalse);
      expect(update.focusChanged, isFalse);
      expect(update.empty, isFalse);
      expect(update.view, same(view));
    });

    test('carries the view\'s flags, and composing', () {
      final view = BareView(EditorState.create(doc: 'x'));
      final update = ViewUpdate.create(view, view.state, const <Transaction>[]);
      expect(update.empty, isTrue);
      expect(update.docChanged, isFalse);
      expect(update.selectionSet, isFalse);
      expect(update.geometryChanged, isFalse);
      update.flags |= UpdateFlag.viewport | UpdateFlag.viewportMoved;
      expect(update.viewportChanged, isTrue);
      expect(update.viewportMoved, isTrue);
      expect(update.empty, isFalse);
      update.flags = UpdateFlag.height;
      expect(update.heightChanged, isTrue);
      expect(update.geometryChanged, isTrue);
      update.flags = UpdateFlag.geometry;
      expect(update.geometryChanged, isTrue);
      update.flags = UpdateFlag.focus;
      expect(update.focusChanged, isTrue);
      expect(update.composing, isFalse);
      view.composing = true;
      expect(update.composing, isTrue);
    });
  });

  group('EditorViewLike', () {
    test('dispatch takes a transaction, a spec, or several specs', () {
      final view = BareView(EditorState.create(doc: 'abc'));
      view.dispatch(view.state.update(const TransactionSpec(changes: ChangeSpec(from: 3, insert: 'd'))));
      expect(view.state.doc.toString(), 'abcd');
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '>')));
      expect(view.state.doc.toString(), '>abcd');
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '1')), const <TransactionSpec>[TransactionSpec(changes: ChangeSpec(from: 5, insert: '2'))]);
      expect(view.state.doc.toString(), '1>abcd2');
      view.dispatch(view.state.changeByRange((range) => RangeChange(changes: ChangeSpec(from: range.from, insert: '^'), range: EditorSelection.cursor(range.from + 1))));
      expect(view.state.doc.toString(), '^1>abcd2');
      expect(view.updates, hasLength(4));
    });

    test('is what a command runs on', () {
      final view = BareView(EditorState.create(doc: 'one', extensions: undoSlot.of(localUndo())));
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, insert: ' two'), userEvent: 'input.type'));
      expect(undo(view), isTrue);
      expect(view.state.doc.toString(), 'one');
      expect(view.updates.last.transactions.single.isUserEvent('undo'), isTrue);
      expect(redo(view), isTrue);
      expect(view.state.doc.toString(), 'one two');
    });

    test('update listeners hear every update', () {
      final heard = <String>[];
      final view = BareView(EditorState.create(doc: 'a', extensions: EditorViewLike.updateListener.of((update) {
        if (update.docChanged) heard.add(update.state.doc.toString());
      })));
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 1, insert: 'b')));
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      expect(heard, <String>['ab']);
    });

    test('editable is on unless told, and the highest precedence wins', () {
      expect(EditorState.create().facet(EditorViewLike.editable), isTrue);
      expect(EditorState.create(extensions: EditorViewLike.editable.of(false)).facet(EditorViewLike.editable), isFalse);
      final state = EditorState.create(extensions: Extension.list(<Extension>[EditorViewLike.editable.of(false), Prec.highest(EditorViewLike.editable.of(true))]));
      expect(state.facet(EditorViewLike.editable), isTrue);
      // The read-only pair the web editor swaps in one compartment.
      final slot = Compartment();
      var both = EditorState.create(extensions: slot.of(const Extension.list(<Extension>[])));
      both = both.update(TransactionSpec(effects: slot.reconfigure(Extension.list(<Extension>[EditorState.readOnlyFacet.of(true), EditorViewLike.editable.of(false)])))).state;
      expect(both.readOnly, isTrue);
      expect(both.facet(EditorViewLike.editable), isFalse);
    });

    test('the keyboard\'s settings merge by precedence, setting by setting', () {
      expect(EditorState.create().facet(EditorViewLike.contentAttributes), const EditorInputAttributes());
      final state = EditorState.create(
        extensions: Extension.list(<Extension>[
          EditorViewLike.contentAttributes.of(EditorInputAttributes.plain),
          Prec.high(EditorViewLike.contentAttributes.of(const EditorInputAttributes(autocorrect: true))),
        ]),
      );
      final merged = state.facet(EditorViewLike.contentAttributes);
      expect(merged.autocorrect, isTrue);
      expect(merged.autocapitalize, TextCapitalization.none);
      expect(merged.spellcheck, isFalse);
      expect(merged.enterKeyHint, TextInputAction.newline);
      // Swapping prose for plain, as the web editor's `assist` does, is a change; swapping like for like is not.
      final slot = Compartment();
      final prose = EditorState.create(extensions: slot.of(EditorViewLike.contentAttributes.of(EditorInputAttributes.prose)));
      final still = prose.update(TransactionSpec(effects: slot.reconfigure(EditorViewLike.contentAttributes.of(EditorInputAttributes.prose)))).state;
      expect(still.facet(EditorViewLike.contentAttributes), same(prose.facet(EditorViewLike.contentAttributes)));
      final plain = prose.update(TransactionSpec(effects: slot.reconfigure(EditorViewLike.contentAttributes.of(EditorInputAttributes.plain)))).state;
      expect(plain.facet(EditorViewLike.contentAttributes).autocorrect, isFalse);
    });

    test('editor attributes: classes join, the rest is won by precedence', () {
      final state = EditorState.create(
        extensions: Extension.list(<Extension>[
          EditorViewLike.editorAttributes.of(const <String, String>{'class': 'peek', 'data-look': 'reading'}),
          EditorViewLike.editorAttributes.of(const <String, String>{'class': 'dark', 'data-look': 'plain', 'data-x': '1'}),
        ]),
      );
      expect(state.facet(EditorViewLike.editorAttributes), <String, String>{'class': 'dark peek', 'data-look': 'reading', 'data-x': '1'});
    });

    test('a scroll target moves with the changes made beside it, and stays in the document', () {
      final state = EditorState.create(doc: 'one two three');
      final tr = state.updateAll(<TransactionSpec>[
        TransactionSpec(effects: EditorViewLike.scrollIntoView(8, y: ScrollStrategy.center, yMargin: 40)),
        const TransactionSpec(changes: ChangeSpec(from: 0, insert: '>> ')),
      ]);
      final target = EditorViewLike.scrollIntoViewEffect.cast(tr.effects.single)!.value;
      expect(target.range.head, 11);
      expect(target.y, ScrollStrategy.center);
      expect(target.yMargin, 40);
      expect(target.x, ScrollStrategy.nearest);
      expect(target.clip(EditorState.create(doc: 'short')).range.head, 5);
      final range = EditorViewLike.scrollIntoView(0, range: EditorSelection.range(2, 6)).value.range;
      expect(<int>[range.from, range.to], <int>[2, 6]);
    });

    test('focus effects are dispatched when focus changes', () {
      final focusEffect = StateEffect.define<bool>();
      final field = StateField.define<bool>(
        create: (_) => false,
        update: (v, tr) {
          for (final e in tr.effects) {
            final found = focusEffect.cast(e);
            if (found != null) v = found.value;
          }
          return v;
        },
      );
      final view = BareView(
        EditorState.create(extensions: Extension.list(<Extension>[field, EditorViewLike.focusChangeEffect.of((state, focusing) => focusEffect.of(focusing))])),
      );
      view.focus();
      expect(view.hasFocus, isTrue);
      expect(view.state.field(field), isTrue);
      view.setFocus(false);
      expect(view.state.field(field), isFalse);
    });

    test('decorations may be a set, a function of the view, or come from a field', () {
      final mark = Decoration.mark(className: 'find');
      final field = StateField.define<DecorationSet>(
        create: (_) => Decoration.set(<Range<Decoration>>[mark.range(0, 1)]),
        update: (set, tr) => set.map(tr.changes),
        provide: (f) => EditorViewLike.decorations.from(f),
      );
      DecorationSet whole(EditorViewLike view) => Decoration.set(<Range<Decoration>>[mark.range(view.viewport.from, view.viewport.to)]);
      final view = BareView(
        EditorState.create(
          doc: 'hello',
          extensions: Extension.list(<Extension>[
            field,
            EditorViewLike.decorations.of(Decoration.set(<Range<Decoration>>[mark.range(2, 4)])),
            EditorViewLike.decorations.of(whole),
          ]),
        ),
      );
      expect(<List<List<int>>>[for (final set in view.decorations) spans(set)], <List<List<int>>>[
        <List<int>>[<int>[0, 1]],
        <List<int>>[<int>[2, 4]],
        <List<int>>[<int>[0, 5]],
      ]);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'oh ')));
      expect(spans(view.decorations[0]), <List<int>>[<int>[3, 4]]);
      expect(spans(view.decorations[2]), <List<int>>[<int>[0, 8]]);
      expect(() => EditorViewLike.resolveDecorations('no', view), throwsArgumentError);
    });

    test('atomic ranges and scroll margins are functions of the view', () {
      final atom = Decoration.replace();
      final view = BareView(
        EditorState.create(
          doc: 'a [[b]] c',
          extensions: Extension.list(<Extension>[
            EditorViewLike.atomicRanges.of((view) => Decoration.set(<Range<Decoration>>[atom.range(2, 7)])),
            EditorViewLike.scrollMargins.of((view) => const EdgeInsets.only(bottom: 80)),
          ]),
        ),
      );
      expect(view.state.facet(EditorViewLike.atomicRanges).single(view).size, 1);
      expect(view.state.facet(EditorViewLike.scrollMargins).single(view)!.bottom, 80);
    });

    test('a measure request reads, then writes what it read', () {
      final view = BareView(EditorState.create(doc: 'four'));
      int? written;
      view.requestMeasure(MeasureRequest<int>(read: (v) => v.state.doc.length, write: (m, _) => written = m, key: 'k'));
      expect(written, 4);
      view.requestMeasure<void>();
      expect(view.measures, 2);
    });
  });

  group('EditorWidget', () {
    test('is compared by class and then by its own eq', () {
      expect(const Chip('a').compare(const Chip('a')), isTrue);
      expect(const Chip('a').compare(const Chip('b')), isFalse);
      expect(const Chip('a').compare(const Other()), isFalse);
      // Without an eq a widget is only ever itself.
      const other = Other();
      expect(other.compare(other), isTrue);
      expect(const Other().compare(Other()), isFalse); // ignore: prefer_const_constructors
      expect(other.estimatedHeight, -1);
      expect(other.lineBreaks, 0);
      expect(other.takesPointer(const PointerDownEvent()), isTrue);
      expect(other.isHidden, isFalse);
      expect(other.editable, isFalse);
    });

    testWidgets('finds the view it is drawn in', (tester) async {
      final view = BareView(EditorState.create(doc: 'twelve chars'));
      await tester.pumpWidget(EditorViewScope(view: view, child: Builder(builder: (context) => const Chip('tag').build(context))));
      expect(find.text('tag in a note of 12'), findsOneWidget);
      await tester.pumpWidget(Builder(builder: (context) => Text('${EditorViewScope.maybeOf(context)}', textDirection: TextDirection.ltr)));
      expect(find.text('null'), findsOneWidget);
    });
  });
}
