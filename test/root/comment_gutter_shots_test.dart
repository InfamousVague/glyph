import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/comments/comment_gutter.dart' show commentGlyphTipWait;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Pictures of the comment glyph in a line's gutter (Matt, 2026-10-30: "When hovering a line show the comment icon in
/// the gutter"): a note with a thread on one line, its filled glyph and count beside it, and a pointer resting on
/// another line, its glyph and "Comment on this line" over it. The Mac's window, light and dark, and the Fold opened
/// out with a mouse. Written only by `flutter test --update-goldens test/root/comment_gutter_shots_test.dart`, into
/// build/feature-shots/comment-gutter/*.png (not committed), to be looked at, not held as goldens.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const body = '# Barn dance\n\nThe ==venue==[^c1] is booked for the last Saturday of the month, from seven until late.\n\n'
      'The band still has to be confirmed. Sam spoke to two of them last week and is waiting to hear back.\n\n'
      'Food is a potluck, with a sign-up sheet by the door.\n\n'
      '```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n  matt 2026-10-04T19:05:40Z\n  The hall.\n  sam 2026-10-04T19:06:02Z\n  Good, it has the heating.\n```\n';

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
    File('build/feature-shots/comment-gutter/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (size, ratio, where, mac, theme) in [
    (const Size(1280, 800), 2.0, 'mac-light', true, 'light'),
    (const Size(1280, 800), 2.0, 'mac-dark', true, 'dark'),
    (const Size(704, 933), 2.625, 'fold-mouse', false, 'light'),
  ]) {
    testWidgets('the comment glyph in the gutter, $where', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final library = SampleLibrary.seeded();
      await pumpApp(
        tester,
        size: size,
        ratio: ratio,
        prefs: Preferences(theme: theme),
        home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
      );
      if (mac) {
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
      }
      await tester.pump(const Duration(milliseconds: 300));
      final note = library.create(body);
      await settle(tester, 2);
      tester.state<AppShellState>(find.byType(AppShell)).openNote(note.id);
      await settle(tester);
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(view.coordsAtPos(view.state.doc.line(5).from + 4)!.center);
      await settle(tester, 3);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey<String>('comment-gutter-add'))));
      await tester.pump(commentGlyphTipWait);
      await settle(tester, 4);
      await snap(tester, where);
      await mouse.removePointer();
      tester.state<AppShellState>(find.byType(AppShell)).backToList();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
