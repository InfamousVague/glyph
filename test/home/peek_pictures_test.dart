// A note drawn small draws what the page's `peek` draws (Editor.tsx under `peek`: `inlineImages`, `videoCards` as a
// still): a picture under its line and a film as its still, on a note's card on the home page, in the sidebar's
// rows, and in a card of words on a canvas, from the pictures the app keeps. And the sidebar's preview is the home
// page's own, one widget where there were two.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/card.dart' show CardWords;
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/video_refs.dart' show videoMarkdown;
import 'package:ghost_md/editor/media/images.dart' show ImageWidget;
import 'package:ghost_md/editor/media/videos.dart' show VideoWidget;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/plugin.dart' show EditorViewScope;
import 'package:ghost_md/home/note_peek.dart';
import 'package:ghost_md/notes/note_peek.dart' as sidebar;
import 'package:glacier/glacier.dart';

import '../support/editor_text.dart';
import '../support/render.dart';

/// One white pixel, as a PNG.
final Uint8List pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

final String withPicture = '# Trip\n\nThe cabin, from the road:\n\n![](image/cabin.jpg)\n\nMore after it.';
final String withFilm = '# Trip\n\nThe drive up:\n\n${videoMarkdown('still.jpg', 'drive.mp4', 6000)}\n\nMore after it.';

/// The block widgets a preview's editor draws, by their kind.
Set<Type> drawnIn(WidgetTester tester) {
  final kinds = <Type>{};
  for (final element in find.byType(EditorViewScope).evaluate()) {
    final view = (element.widget as EditorViewScope).view;
    if (view is! EditorView) continue;
    for (final set in view.decorations) {
      set.between(0, view.state.doc.length, (from, to, value) {
        final widget = value.spec.widget;
        if (widget != null) kinds.add(widget.runtimeType);
        return null;
      });
    }
  }
  return kinds;
}

Widget onCard(Widget child, {PictureStore? store}) => Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('app-paper'),
        child: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: 320, child: PeekPictures(store: store, child: child)))),
      ),
    );

void main() {
  setUpAll(loadAppFonts);

  Future<void> done(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a note’s card draws a picture under its line, where the app has its pictures over it', (tester) async {
    final store = MemoryPictureStore({'cabin.jpg': pixel});
    await pumpApp(tester, home: onCard(NotePeek(body: withPicture), store: store));
    await tester.pump();
    expect(drawnIn(tester), contains(ImageWidget));
    expect(editorText('The cabin, from the road:'), findsOneWidget);
    await done(tester);
  });

  testWidgets('with no pictures over it a picture is its line, as it was', (tester) async {
    await pumpApp(tester, home: onCard(NotePeek(body: withPicture)));
    await tester.pump();
    expect(drawnIn(tester), isNot(contains(ImageWidget)));
    expect(editorText('![](image/cabin.jpg)'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a film is its still, and nothing to play', (tester) async {
    final store = MemoryPictureStore({'still.jpg': pixel});
    await pumpApp(tester, home: onCard(NotePeek(body: withFilm), store: store));
    await tester.pump();
    expect(drawnIn(tester), contains(VideoWidget));
    expect(editorText('drive.mp4'), findsNothing);
    await done(tester);
  });

  testWidgets('a card of words on a canvas draws them too', (tester) async {
    final store = MemoryPictureStore({'cabin.jpg': pixel, 'still.jpg': pixel});
    await pumpApp(tester, home: onCard(SizedBox(height: 400, child: CardWords(markdown: '$withPicture\n\n${videoMarkdown('still.jpg', 'drive.mp4', 6000)}', pictures: store))));
    await tester.pump();
    expect(drawnIn(tester), containsAll(<Type>[ImageWidget, VideoWidget]));
    await done(tester);
    await pumpApp(tester, home: onCard(const SizedBox(height: 400, child: CardWords(markdown: '# Trip\n\n![](image/cabin.jpg)'))));
    await tester.pump();
    expect(drawnIn(tester), isNot(contains(ImageWidget)));
    await done(tester);
  });

  testWidgets('the sidebar’s preview is the home page’s own, with no room of its own over it', (tester) async {
    late Widget? row;
    late Widget? none;
    await pumpApp(
      tester,
      home: Builder(builder: (context) {
        row = sidebar.NotePeek.plain(context, '# Trip\n\nPack the #gear and go.');
        none = sidebar.NotePeek.plain(context, '# Only a title');
        return onCard(row!);
      }),
    );
    await tester.pump();
    expect(row, isA<NotePeek>());
    expect((row! as NotePeek).margin, isFalse);
    expect(none, isNull);
    // The drawing alone: the preview's box starts where its first line does.
    expect(tester.getRect(find.byType(NotePeek)).top, 16);
    // And its words are the editor's own lines, a tag drawn as the editor draws one.
    expect(editorText('Pack the'), findsOneWidget);
    final view = (find.byType(EditorViewScope).evaluate().first.widget as EditorViewScope).view as EditorView;
    final classes = <String>{};
    for (final set in view.decorations) {
      set.between(0, view.state.doc.length, (from, to, value) {
        classes.addAll((value.spec.className ?? '').split(' '));
        return null;
      });
    }
    expect(classes, contains('cm-tag'));
    await done(tester);
  });
}
