// editor/images.test.ts, case for case, and useNotePictures.ts (which has no test of its own on the page). A paste
// reaches the editor through `pasteImages`, which the input layer calls with the clipboard's pictures; "a picture a
// keyboard hands over as an item rather than a file" is that layer's to tell apart, so both are one list here.
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/images.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'support.dart';

/// Keeping a picture is the store's; here it answers a name, or refuses, as the test says.
class Kept extends MemoryPictureStore {
  List<String> names = <String>[];
  String? refuse;
  int asked = 0;

  @override
  Future<String> save(Uint8List bytes, {String type = 'image/jpeg'}) async {
    asked += 1;
    if (refuse != null) throw StateError(refuse!);
    if (names.isEmpty) throw StateError('no name left to give');
    return names.removeAt(0);
  }

  @override
  Future<String> adopt(String path) async => 'adopted-${path.split('/').last}';
}

EditorView view(String doc, int caret, [PictureStore? store]) {
  final made = EditorView(state: EditorState.create(doc: doc, selection: EditorSelection.single(caret), extensions: inlineImages(store: store)));
  addTearDown(made.destroy);
  return made;
}

final PastedPicture picture = (bytes: Uint8List(1), type: 'image/jpeg');

void main() {
  setUpAll(loadAppFonts);

  group('putting a picture into a note', () {
    test('goes under the line the caret is on, never splitting it', () {
      final v = view('Book the cabin by Friday', 8);
      insertImage(v, 'a.jpg');
      expect(v.state.doc.toString(), 'Book the cabin by Friday\n![](image/a.jpg)\n');
    });

    test('takes an empty line', () {
      final v = view('Trip\n\nMore', 5);
      insertImage(v, 'a.jpg');
      expect(v.state.doc.toString(), 'Trip\n![](image/a.jpg)\n\nMore');
    });

    test('lands where the caret was when the paste happened, whatever changed since', () {
      const doc = '![](image/first.jpg)\n\no';
      final v = view(doc, doc.length);
      final spot = reserveImageSpot(v);
      // The caret jumps into the first line, and a word is typed above, while the picture is saved.
      v.dispatch(TransactionSpec(selection: EditorSelection.single(12)));
      v.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Title\n')));
      insertImageAt(v, spot, 'second.jpg');
      expect(v.state.doc.toString(), 'Title\n![](image/first.jpg)\n\no\n![](image/second.jpg)\n');
    });
  });

  group('putting a picture into a note, where the language says what a line is', () {
    testWidgets('takes an empty to-do’s line, with a blank line so it is not the to-do’s words; goes under a quote outside it', (tester) async {
      var v = await pumpNote(tester, '- [ ] milk\n- [ ] ', more: <Extension>[inlineImages()]);
      insertImage(v, 'a.jpg', 17);
      expect(v.state.doc.toString(), '- [ ] milk\n\n![](image/a.jpg)\n');
      v = await pumpNote(tester, '> The deposit comes back.', more: <Extension>[inlineImages()]);
      insertImage(v, 'a.jpg', 4);
      expect(v.state.doc.toString(), '> The deposit comes back.\n\n![](image/a.jpg)\n');
    });
  });

  group('a picture shown in the note', () {
    testWidgets('is drawn under its line, the markdown left as it is, and drawn again when the picture arrives', (tester) async {
      final store = MemoryPictureStore();
      await pumpNote(tester, 'Cabin\n![the porch](image/porch.png)\nafter', more: <Extension>[inlineImages(store: store)]);
      // Not here yet: its place is kept at a small height.
      expect(find.byKey(const ValueKey<String>('figure-waiting')), findsOneWidget);
      expect(shownOf(tester, 1), '![the porch](image/porch.png)');
      store.lend(<String, Uint8List>{'porch.png': Uint8List.fromList(MediaFixture.picture('porch.png'))});
      await settlePictures(tester);
      expect(find.byKey(const ValueKey<String>('figure-waiting')), findsNothing);
      expect(find.byKey(const ValueKey<String>('figure')), findsOneWidget);
      expect(find.bySemanticsLabel('the porch'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey<String>('figure-img'))).height, greaterThan(200));
    });

    testWidgets('steps aside for a film’s line, whose card draws its poster', (tester) async {
      await pumpNote(tester, '[![video 0:12](image/p.jpg)](video/a.mp4)\n![](image/q.jpg)', more: <Extension>[inlineImages(store: MemoryPictureStore())]);
      expect(find.byKey(const ValueKey<String>('figure-waiting')), findsOneWidget);
    });
  });

  group('pasting a picture', () {
    test('keeps each picture and puts them in at the caret, one after another, and nothing else from the paste', () async {
      final kept = Kept()..names = <String>['one.jpg', 'two.jpg'];
      final v = view('Trip notes', 4, kept);
      expect(await pasteImages(v, <PastedPicture>[picture, picture]), isTrue);
      expect(v.state.doc.toString(), 'Trip notes\n![](image/one.jpg)\n![](image/two.jpg)\n');
    });

    test('takes a picture into an empty note', () async {
      final kept = Kept()..names = <String>['kb.jpg'];
      final v = view('', 0, kept);
      await pasteImages(v, <PastedPicture>[picture]);
      expect(v.state.doc.toString(), '![](image/kb.jpg)\n');
    });

    test('leaves a paste with no picture to the editor, and says why a picture could not be kept', () async {
      final said = <String>[];
      final kept = Kept();
      final v = view('Trip', 4, kept);
      expect(await pasteImages(v, <PastedPicture>[(bytes: Uint8List(2), type: 'text/plain')], onError: said.add), isFalse);
      expect(kept.asked, 0);
      kept.refuse = 'The disk is full.';
      await pasteImages(v, <PastedPicture>[picture], onError: said.add);
      expect(said, <String>['The disk is full.']);
      expect(v.state.doc.toString(), 'Trip');
    });
  });

  group('the note’s pictures (useNotePictures)', () {
    test('puts a picked picture where the caret was when the picker opened, and buzzes', () async {
      final v = view('Trip notes\nmore', 4);
      var placed = 0;
      final pictures = NotePictures(view: () => v, pick: () async {
        // The caret moves while the picker is up.
        v.dispatch(TransactionSpec(selection: EditorSelection.single(v.state.doc.length)));
        return 'picked.jpg';
      }, onPlaced: () => placed += 1);
      await pictures.addPhoto();
      // On a line of its own under the caret's line, a fresh line after it for the caret (inserts.dart's rule).
      expect(v.state.doc.toString(), 'Trip notes\n![](image/picked.jpg)\n\nmore');
      expect(placed, 1);
      expect(pictures.problem, isNull);
    });

    test('puts nothing in for a pick that chose nothing, and adopts one the shell copied out of the clipboard', () async {
      final v = view('Trip', 4, Kept());
      final pictures = NotePictures(view: () => v, pick: () async => null, store: v.state.facet(pictureStore));
      await pictures.addPhoto();
      expect(v.state.doc.toString(), 'Trip');
      await pictures.pasteImage('/cache/clip.jpg');
      expect(v.state.doc.toString(), 'Trip\n![](image/adopted-clip.jpg)\n');
    });

    testWidgets('says why a picture did not come in, once, and then gets out of the way', (tester) async {
      final v = view('Trip', 4);
      final pictures = NotePictures(view: () => v, pick: () async => throw StateError('The picker did not open.'));
      addTearDown(pictures.dispose);
      var told = 0;
      pictures.addListener(() => told += 1);
      await pictures.addPhoto();
      expect(pictures.problem, 'The picker did not open.');
      expect(v.state.doc.toString(), 'Trip');
      await tester.pump(saidFor - const Duration(milliseconds: 1));
      expect(pictures.problem, isNotNull);
      await tester.pump(const Duration(milliseconds: 2));
      expect(pictures.problem, isNull);
      expect(told, 2);
      // With no picker at all, the build says it cannot.
      final none = NotePictures(view: () => v);
      addTearDown(none.dispose);
      await none.addPhoto();
      expect(none.problem, cannotAddPictures);
      none.say(null);
    });
  });
}
