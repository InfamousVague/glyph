// Sections folded and toggle blocks (lib/editor/view/section_folds.dart; Matt, 2026-10-30, "add all 12"): what folds
// and how far, a fold drawn as nothing and stepped over, a find's match and a landing unfolding it, a person's edit at
// its edge opening it rather than changing it unseen, the keys, what this device keeps, and a toggle written as
// GitHub writes it that comes back byte for byte.
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/commands/find.dart' as finding;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/find_bar/find_marks.dart' show findBarExtensions, searchIn;
import 'package:ghost_md/editor/plus/add_rows.dart' show RowBlock, planFor, toggleSeed, writeRow;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/section_folds.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../sidebar/support.dart' show away, pumpPage;
import '../input/support.dart' show finish, pumpEditor;

const String plan = '# Trip\n\nTen days.\n\n## Packing\n\n- Boots\n- Hat\n\n### For the coast\n\nSun cream.\n\n## Ferry\n\nAt nine.\n\n## Empty\n\n\n## Last\n\nThe end.\n';

const String toggled = '# Notes\n\n<details>\n<summary>Packing list</summary>\n\n- Boots\n- Hat\n\n</details>\n\nAfter.\n';

EditorState stateOf(String doc, {String? noteId}) => EditorState.create(doc: doc, extensions: sectionFolds(SectionFolds(noteId: noteId)));

FoldPoint pointAt(EditorState state, String title) => foldPointsOf(state).firstWhere((point) => point.title == title);

/// A view-less view: the state, and what is dispatched applied to it.
class _Target extends EditorViewLike {
  _Target(this.state, this.told);
  @override
  EditorState state;
  final void Function(EditorState) told;

  @override
  void dispatchTransactions(List<Transaction> trs) {
    for (final tr in trs) {
      state = tr.state;
    }
    told(state);
  }

  @override
  bool get hasFocus => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EditorState fold(EditorState state, String title, [bool shut = true]) {
  final point = pointAt(state, title);
  final target = _Target(state, (_) {});
  setFold(target, point.from, shut);
  return target.state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => useStored(MemoryStored()));

  group('what folds', () {
    test('a heading folds to the next heading as high or higher, its blank lines at the end left out', () {
      final state = stateOf(plan);
      final points = foldPointsOf(state);
      expect(points.map((p) => p.title), ['Trip', 'Packing', 'For the coast', 'Ferry', 'Last'], reason: 'Empty has only blank lines under it');
      final packing = pointAt(state, 'Packing');
      expect(plan.substring(packing.bodyFrom, packing.to), '\n- Boots\n- Hat\n\n### For the coast\n\nSun cream.', reason: 'its ### with it, and not the blank line before Ferry');
      final trip = pointAt(state, 'Trip');
      expect(plan.substring(trip.bodyFrom, trip.to), endsWith('The end.'), reason: 'the title folds the whole note');
      expect(pointAt(state, 'For the coast').level, 3);
    });

    test('not a heading in fenced code or the front matter', () {
      const doc = '---\ntags: trip\n---\n# Real\n\nWords.\n\n```\n# code\nmore\n```\n\n~~~\n## Also code\n~~~\n';
      expect(foldPointsOf(stateOf(doc)).map((p) => p.title), ['Real']);
    });

    test('a toggle, its summary on its own line or on the first, open or not, nested, and a heading in one ending with it', () {
      const doc = '<details><summary>One line</summary>\n\nA.\n\n</details>\n\n<details open>\n<summary>Two lines</summary>\n\n## Inside\n\nB.\n\n<details>\n<summary>Deeper</summary>\n\nC.\n\n</details>\n\n</details>\n\n<details>\n\nNo summary.\n\n</details>\n\n<details>\n<summary>Never closed</summary>\n';
      final state = stateOf(doc);
      final toggles = foldPointsOf(state).where((p) => p.kind == FoldKind.toggle).toList();
      expect(toggles.map((p) => (p.title, p.open)), [('One line', false), ('Two lines', true), ('Deeper', false), ('Details', false)]);
      final inside = pointAt(state, 'Inside');
      expect(doc.substring(inside.bodyFrom, inside.to), '\nB.\n\n<details>\n<summary>Deeper</summary>\n\nC.\n\n</details>', reason: 'the heading ends where its toggle does');
      final two = pointAt(state, 'Two lines');
      expect(doc.substring(two.from, two.headTo), '<details open>\n<summary>Two lines</summary>');
      expect(doc.substring(two.closeFrom!, two.to), '</details>');
    });

    test('a toggle opens as it is written: shut, unless it says open', () {
      final state = stateOf(toggled);
      expect(foldedOf(state), {pointAt(state, 'Packing list').from});
      expect(foldedOf(stateOf(toggled.replaceFirst('<details>', '<details open>'))), isEmpty);
    });
  });

  group('folded', () {
    test('what is under the heading is drawn as nothing and kept as it was', () {
      final state = fold(stateOf(plan), 'Packing');
      final packing = pointAt(state, 'Packing');
      expect(hiddenFolds(state), [(from: packing.bodyFrom, to: packing.to)]);
      expect(state.doc.toString(), plan, reason: 'folding writes nothing');
      expect(gutterFolds(state).map((f) => (f.line, f.folded)), [(1, false), (5, true), (14, false), (21, false)], reason: 'For the coast is inside the fold and has no triangle');
      expect(fold(state, 'Packing', false).doc.toString(), plan);
      expect(hiddenFolds(fold(state, 'Packing', false)), isEmpty);
    });

    test('the folds follow their headings through the app\'s edits, and go with a heading taken out', () {
      var state = fold(fold(stateOf(plan), 'Packing'), 'Ferry');
      // A sync writes a line at the top.
      state = state.update(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'Synced.\n\n'))).state;
      expect(foldedOf(state), {pointAt(state, 'Packing').from, pointAt(state, 'Ferry').from});
      // Ferry is no heading now.
      final ferry = pointAt(state, 'Ferry');
      state = state.update(TransactionSpec(changes: ChangeSpec(from: ferry.from, to: ferry.from + 3))).state;
      expect(foldedOf(state), {pointAt(state, 'Packing').from});
    });

    test('a pointer\'s press inside lands at the end of the heading; a landing there unfolds it', () {
      final state = fold(stateOf(plan), 'Packing');
      final packing = pointAt(state, 'Packing');
      final inside = plan.indexOf('Hat');
      final pressed = state.update(TransactionSpec(selection: EditorSelection.single(inside), userEvent: 'select.pointer')).state;
      expect(pressed.selection.main.head, packing.headTo);
      expect(foldedOf(pressed), contains(packing.from));
      // A search's hit, a [[Note#Heading]]: the app puts the caret there.
      final landed = state.update(TransactionSpec(selection: EditorSelection.single(inside), scrollIntoView: true)).state;
      expect(landed.selection.main.head, inside);
      expect(foldedOf(landed), isEmpty);
    });

    test('a landing inside a fold inside a fold unfolds both', () {
      var state = fold(stateOf(plan), 'For the coast');
      state = fold(state, 'Packing');
      final landed = state.update(TransactionSpec(selection: EditorSelection.single(plan.indexOf('Sun cream')))).state;
      expect(foldedOf(landed), isEmpty);
    });

    test('the find bar\'s match in a fold unfolds it, and the note\'s words are still searched there', () {
      var state = EditorState.create(doc: plan, extensions: Extension.list(<Extension>[sectionFolds(), findBarExtensions]));
      state = fold(state, 'Packing');
      final target = _Target(state, (_) {});
      searchIn(target, 'sun cream');
      expect(finding.currentMatch(target.state)?.from, plan.indexOf('Sun cream'));
      expect(foldedOf(target.state), isEmpty);
    });

    test('a person\'s Backspace or Delete at its edge opens it, and changes nothing; a selection holding it all deletes it', () {
      final state = fold(stateOf(plan), 'Packing');
      final packing = pointAt(state, 'Packing');
      // Backspace at the start of Ferry would join it to the folded words.
      final back = state.update(TransactionSpec(changes: ChangeSpec(from: packing.to, to: packing.to + 1), userEvent: 'delete.backward')).state;
      expect(back.doc.toString(), plan);
      expect(foldedOf(back), isEmpty);
      // Delete at the end of the folded heading.
      final forward = state.update(TransactionSpec(changes: ChangeSpec(from: packing.headTo, to: packing.headTo + 1), userEvent: 'delete.forward')).state;
      expect(forward.doc.toString(), plan);
      expect(foldedOf(forward), isEmpty);
      // Typing at the end of the folded heading is the heading's.
      final typed = state.update(TransactionSpec(changes: ChangeSpec(from: packing.headTo, insert: ' list'), userEvent: 'input.type')).state;
      expect(typed.doc.toString(), contains('## Packing list\n'));
      expect(foldedOf(typed), {packing.from});
      // The heading and all it folds, selected and deleted.
      final gone = state.update(TransactionSpec(changes: ChangeSpec(from: packing.from, to: packing.to + 1), userEvent: 'delete.selection')).state;
      expect(gone.doc.toString(), isNot(contains('Boots')));
      // The app's own write goes through.
      final synced = state.update(TransactionSpec(changes: ChangeSpec(from: plan.indexOf('Hat'), to: plan.indexOf('Hat') + 3, insert: 'Cap'))).state;
      expect(synced.doc.toString(), contains('- Cap'));
      expect(foldedOf(synced), {packing.from});
    });

    test('Cmd-Alt-[ folds the section the caret is in, Cmd-Alt-] unfolds it', () {
      var state = stateOf(plan);
      final target = _Target(state.update(TransactionSpec(selection: EditorSelection.single(plan.indexOf('Hat')))).state, (_) {});
      expect(foldHere(target), isTrue);
      state = target.state;
      final packing = pointAt(state, 'Packing');
      expect(foldedOf(state), {packing.from}, reason: 'the innermost: Packing, not Trip');
      expect(state.selection.main.head, packing.headTo);
      expect(unfoldHere(target), isTrue);
      expect(foldedOf(target.state), isEmpty);
    });
  });

  group('kept on the device', () {
    test('what is folded is kept for the note, and comes back when it is opened again', () {
      final doc = '$plan\n$toggled';
      final view = EditorView(wholeDocument: true, state: stateOf(doc, noteId: 'n1'));
      addTearDown(view.destroy);
      setFold(view, pointAt(view.state, 'Ferry').from, true);
      // The toggle opened: it was shut as written, so that is kept too.
      setFold(view, pointAt(view.state, 'Packing list').from, false);
      expect(keptFolds('n1'), {'h2|Ferry|0': true, 't|Packing list|0': false});
      final again = stateOf(doc, noteId: 'n1');
      expect(foldedOf(again), {pointAt(again, 'Ferry').from});
      // Another note, and this one on another device (nothing kept): as written.
      expect(foldedOf(stateOf(doc, noteId: 'n2')), {pointAt(again, 'Packing list').from});
      // Folded back to how it opens: nothing is kept for it.
      setFold(view, pointAt(view.state, 'Ferry').from, false);
      setFold(view, pointAt(view.state, 'Packing list').from, true);
      expect(keptFolds('n1'), isEmpty);
    });

    test('two headings of the same words are told apart', () {
      expect(foldKeys(foldPointsOf(stateOf('## Day\n\nOne.\n\n## Day\n\nTwo.\n'))), ['h2|Day|0', 'h2|Day|1']);
    });
  });

  group('the toggle round-trips', () {
    test('inserted from the +, written as GitHub writes one, the title selected', () {
      final state = EditorState.create(doc: 'Before\n\n', selection: EditorSelection.single(8), extensions: sectionFolds());
      final row = planFor(state, 'toggle', DateTime(2026, 10, 30));
      expect(row, isA<RowBlock>());
      expect((row! as RowBlock).text, '<details>\n<summary>Title</summary>\n\n\n\n</details>');
      final target = _Target(state, (_) {});
      expect(writeRow(target, 'toggle', DateTime(2026, 10, 30)), isTrue);
      final doc = target.state.doc.toString();
      expect(doc, contains(toggleSeed));
      final main = target.state.selection.main;
      expect(doc.substring(main.from, main.to), 'Title');
      expect(foldedOf(target.state), isEmpty, reason: 'a toggle just made is open, to be written in');
      expect(foldPointsOf(target.state).single.kind, FoldKind.toggle);
    });

    test('opened, shut, and the caret moved through it: the note is the same, byte for byte', () {
      var state = stateOf(toggled);
      final point = pointAt(state, 'Packing list');
      for (final shut in [false, true, false]) {
        state = fold(state, 'Packing list', shut);
        state = state.update(TransactionSpec(selection: EditorSelection.single(point.headTo))).state;
      }
      expect(state.doc.toString(), toggled);
    });
  });

  group('drawn', () {
    Future<EditorView> show(WidgetTester tester, String doc, {double width = 390}) async {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[sectionFolds()])));
      addTearDown(view.destroy);
      view.focusRequest = () => view.setFocused(true);
      await pumpPage(
        tester,
        size: Size(width, 800),
        Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: SingleChildScrollView(child: EditorColumn(view: view)))),
          ),
        ),
      );
      await tester.pump();
      return view;
    }

    for (final (name, width) in const [('phone', 390.0), ('desktop', 1100.0)]) {
      testWidgets('a toggle drawn shut, opened from its triangle, and its summary edited where it is written, $name', (tester) async {
        final view = await show(tester, toggled, width: width);
        expect(find.byType(FoldTriangle), findsOneWidget);
        expect(find.text('Packing list'), findsOneWidget);
        expect(editorText('Boots'), findsNothing, reason: 'shut as it is written');
        expect(editorText('<summary>'), findsNothing);
        final point = pointAt(view.state, 'Packing list');
        await tester.tap(find.byKey(ValueKey<String>('toggle-head-${point.from}')));
        await tester.pump();
        await tester.pump();
        expect(editorText('Boots'), findsOneWidget);
        expect(view.state.doc.toString(), toggled);
        // A press on the summary puts the caret there, and its lines are shown as written.
        await tester.tap(find.text('Packing list'));
        await tester.pump();
        await tester.pump();
        expect(editorText('<summary>Packing list</summary>'), findsOneWidget);
        await away(tester);
      });

      testWidgets('a folded heading wears its ⋯, which unfolds it, $name', (tester) async {
        final view = await show(tester, plan, width: width);
        setFold(view, pointAt(view.state, 'Packing').from, true);
        await tester.pump();
        await tester.pump();
        expect(editorText('Boots'), findsNothing);
        expect(editorText('Ferry'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey<String>('folded-mark-${pointAt(view.state, 'Packing').from}')));
        await tester.pump();
        await tester.pump();
        expect(editorText('Boots'), findsOneWidget);
        await away(tester);
      });
    }

    testWidgets('the keys fold and unfold at the caret: Cmd-Alt on a Mac, Ctrl-Alt elsewhere', (tester) async {
      final rig = await pumpEditor(tester, plan, more: <Extension>[sectionFolds()], caret: plan.indexOf('Boots'));
      final mod = defaultTargetPlatform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      Future<void> chord(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(mod);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(mod);
        await tester.pump();
      }

      await chord(LogicalKeyboardKey.bracketLeft);
      expect(foldedOf(rig.view.state), {pointAt(rig.view.state, 'Packing').from});
      expect(rig.view.state.selection.main.head, pointAt(rig.view.state, 'Packing').headTo);
      expect(editorText('Boots'), findsNothing);
      await chord(LogicalKeyboardKey.bracketRight);
      expect(foldedOf(rig.view.state), isEmpty);
      expect(editorText('Boots'), findsOneWidget);
      await finish(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Ctrl-Alt off a Mac', (tester) async {
      final rig = await pumpEditor(tester, plan, more: <Extension>[sectionFolds()], caret: plan.indexOf('At nine'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(foldedOf(rig.view.state), {pointAt(rig.view.state, 'Ferry').from});
      await finish(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
