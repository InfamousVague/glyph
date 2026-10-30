import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/section_folds.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Pictures of three of the plain-Markdown features (Matt, 2026-10-30, "add all 12"): "Linked from" at a note's foot
/// with a team note and "Mentioned in"; section embeds as quoted cards, a missing note and a loop; a heading folded
/// from the gutter beside the comment glyph, and a toggle shut and open. A phone (430 wide, under a finger) and the
/// Mac's window (with a mouse), light and dark. Written only by `flutter test --update-goldens
/// test/root/notes_native_shots_test.dart`, into build/feature-shots/notes-native-1/*.png (not committed), to be looked
/// at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });
  setUp(() => useStored(MemoryStored()));

  const packing = '# Packing\n\nWhat goes in the bag for Portugal.\n\n## Clothes\n\n- [ ] Shoes for the hills ^shoes\n- [ ] A coat\n- [ ] Two shirts\n\n## Papers\n\nPassports and the ferry tickets.\n\nThe booking for the flat, printed.\n\n## For the coast\n\nSun cream, and a towel each.\n\n<details>\n<summary>If it rains</summary>\n\nThe tram museum, and the long lunch.\n\n</details>\n\n<details open>\n<summary>Who brings what</summary>\n\n- Ana: the guidebook\n- Matt: the adapters\n\n</details>\n';
  const ferry = '# The ferry\n\nNine from Cais do Sodré. See [[Packing#Papers]] for the tickets.\n\nWhat to wear on deck:\n\n![[Packing#Clothes]]\n\nAnd the plan for the far side:\n\n![[Almada day]]\n\n![[The ferry]]\n';
  const offsite = '# Team offsite\n\nEveryone brings what [[Packing|the packing list]] says, and one thing more.\n';
  const diary = '# Diary\n\nPacking took all evening.\n';

  Future<void> snap(WidgetTester tester, String name) async {
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/notes-native-1/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<AppShellState> open(WidgetTester tester, {required Size size, required double ratio, required bool mac, required String theme}) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final library = SampleLibrary.seeded();
    final seeded = seedWorkspaces();
    final sheet = WorkspaceSheet(list: [...seeded.list, Workspace(id: orgWorkspaceId('acme'), name: 'Acme', hue: 'sea')], notes: {...seeded.notes, 'offsite': orgWorkspaceId('acme')});
    await pumpApp(
      tester,
      size: size,
      ratio: ratio,
      prefs: Preferences(theme: theme),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(sheet)), clock: () => seedNow),
    );
    if (mac) {
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
    }
    await tester.pump(const Duration(milliseconds: 300));
    library.value = [
      for (final note in library.value)
        if (note.id == 'packing') note.copyWith(body: packing) else note,
    ];
    await library.createNote(ferry, id: 'ferry');
    await library.createNote(offsite, id: 'offsite');
    await library.createNote(diary, id: 'diary');
    await settle(tester, 2);
    return tester.state<AppShellState>(find.byType(AppShell));
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

  ScrollPosition pageOf(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first).position;

  const looks = [
    (Size(430, 932), 3.0, 'phone-light', false, 'light'),
    (Size(430, 932), 3.0, 'phone-dark', false, 'dark'),
    (Size(1280, 800), 2.0, 'mac-light', true, 'light'),
    (Size(1280, 800), 2.0, 'mac-dark', true, 'dark'),
  ];

  for (final (size, ratio, where, mac, theme) in looks) {
    testWidgets('Linked from at the foot, $where', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final shell = await open(tester, size: size, ratio: ratio, mac: mac, theme: theme);
      shell.openNote('packing');
      await settle(tester);
      final page = pageOf(tester);
      page.jumpTo(page.maxScrollExtent);
      await settle(tester, 4);
      await snap(tester, 'backlinks-$where');
      await close(tester);
    });

    testWidgets('section embeds as quoted cards, a missing note and a loop, $where', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final shell = await open(tester, size: size, ratio: ratio, mac: mac, theme: theme);
      shell.openNote('ferry');
      await settle(tester);
      await snap(tester, 'embeds-$where');
      await close(tester);
    });

    testWidgets('a folded heading and toggles, $where', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final shell = await open(tester, size: size, ratio: ratio, mac: mac, theme: theme);
      shell.openNote('packing');
      await settle(tester);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      setFold(view, foldPointsOf(view.state).firstWhere((p) => p.title == 'Clothes').from, true);
      await settle(tester, 3);
      if (mac) {
        // A pointer on Papers: its triangle and its comment glyph side by side in the gutter.
        final papers = view.state.doc.toString().split('\n').indexOf('## Papers') + 1;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(view.coordsAtPos(view.state.doc.line(papers).from + 4)!.center);
        await settle(tester, 4);
        await snap(tester, 'folds-$where');
        await mouse.removePointer();
      } else {
        await snap(tester, 'folds-$where');
      }
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await close(tester);
    });
  }
}
