// @mentions and verified pages in the app itself (Matt, 2026-10-30: "add all 12"): a note opened from the list with a
// verified page's badge at its top, a person's chip, a day to come and a day passed in red; an at sign typed opens
// the picker under the caret, and a day picked is written as the day. On a phone and the Mac's window, light and dark,
// with pictures into build/feature-shots/mentions-verified/ under --update-goldens (not committed), to be looked at.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/days.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/feature_shot.dart';
import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  final today = isoDay(DateTime.now());
  final until = isoDayAfter(today, 40)!, soon = isoDayAfter(today, 6)!, passed = isoDayAfter(today, -3)!;
  String body(String until) => '---\nverified: {by: "@matt", until: $until}\n---\n# Launch plan\n\nAsk @sam to check the copy by @$soon.\n\nThe venue was due @$passed, so @ana is calling them.\n\n';

  Future<EditorView> open(WidgetTester tester, {required Size size, required double ratio, required String theme, required bool mac, String? verifiedUntil}) async {
    useStored(MemoryStored());
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final library = SampleLibrary(<Note>[...seedLibrary(seedNow), Note(id: 'mentions-plan', body: body(verifiedUntil ?? until), createdAt: seedNow, updatedAt: seedNow)], clock: () => seedNow + 60000);
    await pumpApp(
      tester,
      size: size,
      ratio: ratio,
      prefs: Preferences(theme: theme),
      home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    if (mac) {
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
    }
    await tester.pump(const Duration(milliseconds: 200));
    tester.state<AppShellState>(find.byType(AppShell)).openNote('mentions-plan');
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return tester.widget<Editor>(find.byType(Editor)).view;
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }

  void type(EditorView view, String text) {
    final at = view.state.selection.main.head;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, to: at, insert: text), selection: EditorSelection.single(at + text.length), userEvent: 'input.type'));
  }

  List<String> chips(EditorView view) {
    final found = <String>[];
    for (final set in view.decorations) {
      set.between(0, view.state.doc.length, (from, to, value) {
        final classes = (value.spec.className ?? '').split(' ');
        if (classes.contains('cm-mention')) found.add('${view.state.sliceDoc(from, to)}${value.spec.attributes?.containsKey('data-past') == true ? ' passed' : ''}');
        return null;
      });
    }
    return found;
  }

  testWidgets('the note’s badge, its chips, and the picker an at sign opens, which writes a day as the day', (tester) async {
    final view = await open(tester, size: const Size(390, 844), ratio: 3, theme: 'light', mac: false);
    expect(find.byKey(const ValueKey('verified-badge')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Verified by Matt · until ')), findsOneWidget);
    expect(chips(view), containsAll(['@sam', '@$soon', '@$passed passed', '@ana']));
    view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
    type(view, 'Next: @');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('mention-picker')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('mention-day-${isoDayAfter(today, 1)}')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(view.state.doc.toString(), endsWith('Next: @${isoDayAfter(today, 1)} '));
    expect(find.byKey(const ValueKey('mention-picker')), findsNothing);
    await close(tester);
  });

  testWidgets('an expired page says Needs review', (tester) async {
    await open(tester, size: const Size(390, 844), ratio: 3, theme: 'light', mac: false, verifiedUntil: isoDayAfter(today, -1));
    expect(find.bySemanticsLabel('Needs review'), findsOneWidget);
    await close(tester);
  });

  for (final theme in ['light', 'dark']) {
    for (final (size, ratio, where, mac) in [(const Size(390, 844), 3.0, 'phone', false), (const Size(1280, 800), 2.0, 'mac', true)]) {
      testWidgets('pictures: the note, and the picker open, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final view = await open(tester, size: size, ratio: ratio, theme: theme, mac: mac);
        await featureShot(tester, 'mentions-verified', 'note-$where-$theme');
        view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
        type(view, 'Next: @');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await featureShot(tester, 'mentions-verified', 'note-picker-$where-$theme');
        await close(tester);
      });
      testWidgets('pictures: a page soon to run out, and one that has, $where, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await open(tester, size: size, ratio: ratio, theme: theme, mac: mac, verifiedUntil: soon);
        await featureShot(tester, 'mentions-verified', 'note-soon-$where-$theme');
        await close(tester);
        await open(tester, size: size, ratio: ratio, theme: theme, mac: mac, verifiedUntil: passed);
        await featureShot(tester, 'mentions-verified', 'note-expired-$where-$theme');
        await close(tester);
      });
    }
  }
}
