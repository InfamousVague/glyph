// A note the web clipper (clipper/) saved, opened in the app put together: its front matter folded, its title the
// note's, its headings, lists, quote, table, code and links drawn as the editor draws Markdown, and its pictures
// drawn from the files sync keeps beside the library. The fixtures are what the clipper's end-to-end run saved and
// read back through the connector (clipper/e2e/run.mjs, e2e/out/notes), the local addresses of that run put back to
// the fixture sites' own; the pictures are the JPEGs it stored, opened.
//
// The pictures of each are written to build/feature-shots/clipper/ for looking at (git-ignored, never compared).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/media/images.dart' show KeptPicture;
import 'package:ghost_md/editor/tables/table_box.dart' show DrawnTable;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

final _fixtures = Directory('test/clipper/fixtures').absolute.path;

String _body(String name) => File('$_fixtures/$name').readAsStringSync();

/// The core's one answer these notes need: where a picture's file is, from the fixtures' image folder.
Future<Object?> _core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
  if (command != 'file_path' || args['kind'] != 'image') return null;
  final file = File('$_fixtures/image/${args['name']}');
  return file.existsSync() ? {'path': file.path, 'bytes': file.lengthSync()} : null;
}

Future<void> _open(WidgetTester tester, Note note, {Size size = const Size(430, 932)}) async {
  await pumpApp(
    tester,
    size: size,
    ratio: 3,
    prefs: const Preferences(theme: 'dark'),
    home: GhostRoot(
      launch: false,
      core: _core,
      library: SampleLibrary([note], clock: () => seedNow),
      stored: MemoryStored(),
      workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
      clock: () => seedNow,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  tester.state<AppShellState>(find.byType(AppShell)).openNote(note.id);
  // The pictures' files are found and decoded off the test's clock.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2));
}

/// The screen as drawn, to `build/feature-shots/clipper/<name>.png`.
Future<void> _picture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.descendant(of: find.byType(GhostApp), matching: find.byType(RepaintBoundary)).first);
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('build/feature-shots/clipper/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// How many pictures are drawn on the screen with their image.
int _drawn() => find.descendant(of: find.byType(KeptPicture), matching: find.byType(RawImage)).evaluate().length;

/// The note scrolled down by [by], and what came into view given time to find its pictures.
Future<void> _scroll(WidgetTester tester, double by) async {
  final scrolling = tester.state<ScrollableState>(find.ancestor(of: find.byType(Editor), matching: find.byType(Scrollable)).first);
  scrolling.position.jumpTo((scrolling.position.pixels + by).clamp(0, scrolling.position.maxScrollExtent));
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _close(WidgetTester tester) async {
  tester.state<AppShellState>(find.byType(AppShell)).backToList();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 8));
}

void main() {
  setUpAll(loadAppFonts);

  final article = Note(id: 'clip-article', body: _body('clipped_article.md'), createdAt: seedNow, updatedAt: seedNow);
  final reference = Note(id: 'clip-reference', body: _body('clipped_reference.md'), createdAt: seedNow, updatedAt: seedNow);

  test('a clip is named by its first heading, under its front matter', () {
    expect(noteTitle(article.body), 'The Quiet Garden');
    expect(noteTitle(reference.body), 'Sorting in place');
  });

  testWidgets('a clipped article opens with its words, its lists and both its pictures drawn', (tester) async {
    await _open(tester, article);
    final doc = tester.widget<Editor>(find.byType(Editor)).view.state.doc.toString();
    expect(doc, article.body);
    // Where it came from, under its title (lib/editor/media/source_line.dart).
    expect(find.text('From field.example/art…tml', findRichText: true), findsOneWidget);
    // The first picture is on the first screen, its file found and drawn: a picture with no file is a quiet box with
    // no image in it.
    expect(_drawn(), 1);
    await _picture(tester, 'clipped-article-dark');
    // The second is further down, drawn when it is scrolled to.
    await _scroll(tester, 900);
    expect(_drawn(), greaterThanOrEqualTo(1));
    await _picture(tester, 'clipped-article-dark-2');
    await _close(tester);
  });

  testWidgets('a clipped page of tables and code draws its tables as tables', (tester) async {
    await _open(tester, reference);
    expect(find.byType(DrawnTable), findsAtLeastNWidgets(2));
    expect(find.text('From docs.example/tab…tml', findRichText: true), findsOneWidget);
    await _picture(tester, 'clipped-reference-dark');
    await _scroll(tester, 900);
    await _picture(tester, 'clipped-reference-dark-2');
    await _close(tester);
  });

  // The wide screen with the page of tables, which has no pictures: on a home of two cards across, a card whose
  // picture is drawn fails its row's layout (lib/home/note_card.dart CardRow asks a LayoutBuilder for its intrinsic
  // height), with any note that has a picture, clipped or not. That is the home's, said in docs/FEATURES_2_1.md.
  testWidgets('a clipped page of tables and code on the Fold’s inner screen', (tester) async {
    await _open(tester, reference, size: const Size(900, 1000));
    expect(find.byType(DrawnTable), findsAtLeastNWidgets(2));
    await _picture(tester, 'clipped-reference-fold-dark');
    await _close(tester);
  });
}
