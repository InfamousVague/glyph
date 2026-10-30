// Another note drawn inside this one (lib/editor/media/note_embeds.dart): which lines are embeds, a note, a section
// and a named line drawn read only with the name over them, a picture, the caret on the line stepping the drawing
// aside, two levels at most and never a circle, and a picture of it (build/feature-shots/links/, with
// --update-goldens).
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/editor/media/canvas_frames.dart';
import 'package:ghost_md/editor/media/images.dart' show KeptPicture, pictureStore;
import 'package:ghost_md/editor/media/note_embeds.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';

/// A note on the screen with its embeds, the notes it can name, and what it opened.
class Embedded {
  final Map<String, String> bodies = <String, String>{
    'Packing': '---\ntags: trip\n---\n# Packing\n\n- [ ] Shoes ^shoes\n  - The old ones\n- [ ] Charger\n\n## For the coast\n\nSun cream and a hat.',
    'Lisbon': '# Lisbon\n\nTrams up the hill.\n\nThe ferry leaves at nine from Cais do Sodré. ^ferry\n\n![[Packing]]',
    'Loop': '# Loop\n\nIt draws the trip.\n\n![[Trip]]',
    'Map': canvasNoteBody('Map', parseCanvas('{"nodes":[],"edges":[]}')!),
  };
  final List<String> opened = <String>[];
  late final EditorView view;

  Future<void> show(WidgetTester tester, String doc, {String theme = 'light', int? caret, PictureStore? pictures, double width = 390, double height = 844}) async {
    final options = EmbedOptions(body: (title) => bodies[title] ?? bodies.entries.where((entry) => entry.key.toLowerCase() == title.toLowerCase()).firstOrNull?.value, open: (title, [anchor]) => opened.add(anchor == null ? title : '$title#$anchor'));
    view = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: doc,
        extensions: noteExtensions(
          more: <Extension>[
            wikiLinks(WikiOptions(known: bodies.containsKey, open: (title, [anchor]) {})),
            noteEmbeds(options),
            if (pictures != null) pictureStore.of(pictures),
          ],
        ),
      ),
    );
    addTearDown(view.destroy);
    view.focusRequest = () => view.setFocused(true);
    await pumpApp(
      tester,
      size: Size(width, height),
      ratio: 3,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => BackScope(
          child: ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: SingleChildScrollView(child: EditorColumn(view: view)))),
          ),
        ),
      ),
    );
    debugDisableShadows = true;
    await tester.pump();
    if (caret != null) {
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
      await tester.pump();
    }
    await tester.pump();
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('which lines are embeds', () {
    test('a note, a heading in one, a named line, a picture and its width', () {
      expect(embedOf('![[Packing]]'), (title: 'Packing', anchor: null, size: null, picture: false));
      expect(embedOf('  ![[Packing#For the coast]] '), (title: 'Packing', anchor: 'For the coast', size: null, picture: false));
      expect(embedOf('![[Lisbon#^ferry|the ferry]]'), (title: 'Lisbon', anchor: '^ferry', size: null, picture: false));
      expect(embedOf('![[photo.JPG|300]]'), (title: 'photo.JPG', anchor: null, size: '300', picture: true));
      expect(embedOf('![[image/img-1.png]]')?.title, 'img-1.png');
    });

    test('not a link without the !, an embed inside a sentence, nor one with no name', () {
      expect(embedOf('[[Packing]]'), isNull);
      expect(embedOf('see ![[Packing]] here'), isNull);
      expect(embedOf('![[#^shoes]]'), isNull);
      expect(embedOf('![[ ]]'), isNull);
    });
  });

  group('the embed', () {
    testWidgets('draws a note as a quoted card with its name, a link\'s mark and Edit in source, its front matter left out, and opens it from a tap', (tester) async {
      final embedded = Embedded();
      await embedded.show(tester, '# Trip\n\n![[Packing]]\n\nAfter.');
      expect(find.byType(DrawnNoteEmbed), findsOneWidget);
      expect(find.bySemanticsLabel('From Packing'), findsOneWidget);
      expect(editorText('![[Packing]]'), findsNothing);
      expect(editorText('Sun cream and a hat.'), findsOneWidget);
      expect(editorText('tags: trip'), findsNothing);
      expect(find.descendant(of: find.byType(DrawnNoteEmbed), matching: find.byWidgetPredicate((w) => w is AppIcon && w.icon == Lucide.link2)), findsOneWidget);
      await tester.tap(find.text('Edit in source'));
      await tester.pump();
      await tester.tap(editorText('Sun cream and a hat.'), warnIfMissed: false);
      await tester.pump();
      expect(embedded.opened, ['Packing', 'Packing']);
    });

    testWidgets('draws a heading and what is under it, and a named line alone', (tester) async {
      final embedded = Embedded();
      await embedded.show(tester, '# Trip\n\n![[Packing#For the coast]]\n\n![[Lisbon#^ferry]]');
      expect(find.byType(DrawnNoteEmbed), findsNWidgets(2));
      expect(editorText('Sun cream and a hat.'), findsOneWidget);
      expect(editorText('Shoes'), findsNothing);
      expect(editorText('The ferry leaves at nine'), findsOneWidget);
      expect(editorText('Trams up the hill'), findsNothing);
      await tester.tap(find.text('Edit in source').last);
      await tester.pump();
      expect(embedded.opened, ['Lisbon#^ferry']);
    });

    testWidgets('says so when the heading, the name or the note is not there, and leaves a canvas to its frame', (tester) async {
      final embedded = Embedded();
      await embedded.show(tester, '![[Packing#Nowhere]]\n\n![[Lisbon#^gone]]\n\n![[Nobody]]\n\n![[Map]]');
      expect(find.text('Packing has no heading “Nowhere”.'), findsOneWidget);
      expect(find.text('Lisbon has no line named ^gone.'), findsOneWidget);
      expect(find.text('No note is called “Nobody” yet.'), findsOneWidget);
      expect(editorText('![[Nobody]]'), findsNothing);
      // Nothing to open: a press puts the caret on its line, to change it.
      expect(find.bySemanticsLabel('Edit in source: Nobody'), findsNothing);
      await tester.tap(find.text('No note is called “Nobody” yet.'));
      await tester.pump();
      await tester.pump();
      expect(editorText('![[Nobody]]'), findsOneWidget);
      expect(editorText('![[Map]]'), findsOneWidget);
      expect(embedded.opened, isEmpty);
    });

    testWidgets('draws two levels at most, and a loop says so rather than drawing round in a circle', (tester) async {
      final embedded = Embedded();
      // Trip draws Loop, which would draw Trip again; and Trip names itself.
      await embedded.show(tester, '# Trip\n\n![[Loop]]\n\n![[Trip]]\n\n![[Lisbon]]');
      // Loop, the loop inside it, Trip's own, Lisbon, and Packing in Lisbon two levels down.
      expect(find.byType(DrawnNoteEmbed), findsNWidgets(5));
      expect(find.text('A note is not drawn inside itself.'), findsOneWidget);
      expect(find.text('“Trip” has this note in it, so it is not drawn again here.'), findsOneWidget);
      expect(find.bySemanticsLabel('From Trip, not drawn again'), findsNWidgets(1), reason: 'the one in Trip itself; the one inside Loop is drawn read only, unread');
      expect(editorText('Sun cream and a hat.'), findsOneWidget);
    });

    testWidgets('a loop two notes round is found from either side', (tester) async {
      final embedded = Embedded()..bodies['Trip'] = '# Trip\n\n![[Loop]]';
      await embedded.show(tester, '# Loop\n\nIt draws the trip.\n\n![[Trip]]');
      expect(find.text('“Loop” has this note in it, so it is not drawn again here.'), findsOneWidget);
    });

    testWidgets('steps aside for its line while the caret is on it, and a press on its name puts the caret there', (tester) async {
      final embedded = Embedded();
      await embedded.show(tester, 'Before\n\n![[Packing]]\n\nAfter');
      await tester.tap(find.descendant(of: find.byType(DrawnNoteEmbed), matching: find.text('Packing')).first);
      await tester.pump();
      await tester.pump();
      expect(embedded.view.state.selection.main.head, 'Before\n\n'.length);
      expect(find.byType(DrawnNoteEmbed), findsNothing);
      expect(editorText('![[Packing]]'), findsOneWidget);
      embedded.view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DrawnNoteEmbed), findsOneWidget);
    });

    testWidgets('is drawn again when the other note changes', (tester) async {
      final embedded = Embedded();
      await embedded.show(tester, '![[Packing#For the coast]]');
      embedded.bodies['Packing'] = '# Packing\n\n## For the coast\n\nA towel.';
      embedded.view.dispatch(TransactionSpec(effects: refreshCanvasFrames.of(null)));
      await tester.pump();
      await tester.pump();
      expect(editorText('A towel.'), findsOneWidget);
    });

    testWidgets('draws a picture the library keeps, and its name where it keeps none', (tester) async {
      final embedded = Embedded();
      final pictures = MemoryPictureStore();
      await embedded.show(tester, '![[photo.png|120]]', pictures: pictures);
      expect(find.byType(KeptPicture), findsOneWidget);
      // Not kept here: its box, with its name in it.
      expect(find.text('photo.png'), findsOneWidget);
      expect(editorText('![[photo.png|120]]'), findsNothing);
    });
  });

  group('pictures', () {
    for (final (name, size) in const [('note-embed-phone', Size(430, 932)), ('note-embed-fold', Size(900, 1000))]) {
      testWidgets('an embed in the editor, $name', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final embedded = Embedded();
        await embedded.show(
          tester,
          '# Trip to Lisbon\n\nTen days in October. What to bring is kept in one place:\n\n![[Packing]]\n\nAnd the one line about the ferry:\n\n![[Lisbon#^ferry]]\n\nAfter that, the coast.',
          theme: 'dark',
          width: size.width,
          height: size.height,
        );
        await tester.pump(const Duration(milliseconds: 400));
        Directory('build/feature-shots/links').createSync(recursive: true);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../../build/feature-shots/links/$name.png'));
      });
    }
  });
}
