// Pictures of what the files bring, to be looked at (not held to anything): a note with files in it, a picture's
// words offered under it, the PDF viewer and its Find, the + menu's new rows, Settings' Files and scans and a search
// row found by the words read in a PDF; dark, at a phone's size (430 x 932 at 3) and the opened Fold's (900 x 1000).
// Written to build/feature-shots/files/, never to the repository:
//
//     flutter test test/files/files_shots_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/search_hits.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/attachments.dart';
import 'package:ghost_md/editor/media/images.dart';
import 'package:ghost_md/editor/media/picture_words.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/files/attachment_store.dart';
import 'package:ghost_md/files/files_kit.dart';
import 'package:ghost_md/files/pdf_view.dart';
import 'package:ghost_md/files/read_text.dart';
import 'package:ghost_md/home/home_rows.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/files_pane.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// Writes each picture to build/feature-shots/files/ and calls it a match: these are for looking at.
class _Written extends GoldenFileComparator {
  _Written(this.dir);
  final Directory dir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    dir.createSync(recursive: true);
    File('${dir.path}/${golden.pathSegments.last}').writeAsBytesSync(imageBytes);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) => compare(imageBytes, golden);
}

const Size phone = Size(430, 932), fold = Size(900, 1000);

Future<void> settleIo(WidgetTester tester, [int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// A picture of a till receipt, drawn for the test: white paper and dark lines.
Future<Uint8List> receipt() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 600, 420), ui.Paint()..color = const ui.Color(0xFFF4F1EA));
  for (var i = 0; i < 7; i++) {
    canvas.drawRect(ui.Rect.fromLTWH(60, 50.0 + i * 46, i.isEven ? 420 : 300, 14), ui.Paint()..color = const ui.Color(0xFF333333));
  }
  final image = await recorder.endRecording().toImage(600, 420);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    goldenFileComparator = _Written(Directory('${Directory.current.path}/build/feature-shots/files'));
  });

  late Directory data;
  late FakeDocuments device;
  late FilesKit kit;

  setUp(() {
    data = Directory.systemTemp.createTempSync('files-shots');
    device = FakeDocuments();
    kit = FilesKit(dataDir: data.path, store: AttachmentStore(dataDir: data.path), texts: ReadTexts(dataDir: data.path), device: device, bodies: () async => const [], kept: MemoryStored(), listenForInput: false)..install();
  });
  tearDown(() {
    FilesKit.uninstall();
    data.deleteSync(recursive: true);
  });

  Future<EditorView> pumpEditor(WidgetTester tester, String doc, {required Size size, List<Extension> more = const <Extension>[], int? caret}) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: more)));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: size,
      ratio: 3,
      prefs: const AppPreferences(theme: 'dark'),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: SafeArea(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: size.width, child: SingleChildScrollView(child: EditorColumn(view: view))))),
        ),
      ),
    );
    if (caret != null) {
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    }
    await settleIo(tester);
    return view;
  }

  Future<String> notesBody(WidgetTester tester) async {
    final lease = await tester.runAsync(() => kit.store.keep(AttachmentBytes(Uint8List.fromList(tinyPdf(pages: 4).codeUnits)), original: 'Lease 2026.pdf'));
    final sheet = await tester.runAsync(() => kit.store.keep(AttachmentBytes(Uint8List(48213)), original: 'Inventory.xlsx'));
    return '# The flat\n\nThe lease, signed on Friday, and the inventory we walked through.\n\n${lease!.markdown}\n\n${sheet!.markdown}\n\n'
        '[Walkthrough.mov](file/0a1b2c3d-0000-4000-8000-00000000000f.mov "84 MB")\n\n[Deposit receipt.pdf](file/0a1b2c3d-0000-4000-8000-00000000000e.pdf "220 KB")\n\nKeys on the hook by the door.\n';
  }

  testWidgets('a note with files in it, on a phone', (tester) async {
    await pumpEditor(tester, await notesBody(tester), size: phone, more: <Extension>[attachmentCards()]);
    await shot(tester, 'note-files-phone-dark');
  });

  testWidgets('a note with files in it, on the opened Fold', (tester) async {
    await pumpEditor(tester, await notesBody(tester), size: fold, more: <Extension>[attachmentCards()]);
    await shot(tester, 'note-files-fold-dark');
  });

  testWidgets('a picture with words read in it, its line under the caret', (tester) async {
    final bytes = await tester.runAsync(receipt);
    const name = 'a1b2c3d4-0000-4000-8000-000000000001.png';
    final store = MemoryPictureStore({name: bytes!});
    await tester.runAsync(() => kit.texts.keep(const ReadThing.picture(name), 'BAKERY 12 MAIN ST\nTOTAL 42.10'));
    const doc = 'Saturday\n\n![](image/$name)\n\nBread and the cake for Sunday.';
    await pumpEditor(tester, doc, size: phone, caret: doc.indexOf('![') + 2, more: <Extension>[inlineImages(store: store), pictureWords()]);
    await settleIo(tester, 12);
    expect(find.byKey(const ValueKey<String>('picture-words')), findsOneWidget);
    await shot(tester, 'picture-words-phone-dark');
  });

  Future<GlobalKey<PdfViewState>> pumpViewer(WidgetTester tester, Size size) async {
    final key = GlobalKey<PdfViewState>();
    final pdf = FakePdf(readPdfPages(tinyPdf(pages: 4)), pageWords: const ['Lease agreement between the parties', 'Rent is due monthly on the first', '', 'Signed']);
    await pumpApp(tester, size: size, ratio: 3, prefs: const AppPreferences(theme: 'dark'), home: PdfView(key: key, pages: pdf, name: 'Lease 2026.pdf', onClose: () {}, onShare: () async {}, onOpenWith: () async {}));
    await settleIo(tester);
    return key;
  }

  testWidgets('the PDF viewer, on a phone', (tester) async {
    await pumpViewer(tester, phone);
    await shot(tester, 'pdf-viewer-phone-dark');
  });

  testWidgets('the PDF viewer, finding words', (tester) async {
    final key = await pumpViewer(tester, phone);
    await tester.tap(find.byKey(const ValueKey<String>('pdf-find-open')));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'monthly');
    await key.currentState!.find('monthly');
    await settleIo(tester);
    await shot(tester, 'pdf-find-phone-dark');
  });

  testWidgets('the PDF viewer, on the opened Fold', (tester) async {
    await pumpViewer(tester, fold);
    await shot(tester, 'pdf-viewer-fold-dark');
  });

  testWidgets('the + menu with A file and Scan a document', (tester) async {
    final plus = PlusController();
    final view = EditorView(
      wholeDocument: true,
      state: EditorState.create(doc: 'The flat\n', selection: EditorSelection.single(9), extensions: noteExtensions(more: <Extension>[history(), plus.extension])),
    );
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: phone,
      ratio: 3,
      prefs: const AppPreferences(theme: 'dark'),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: PlusLayer(
            view: view,
            controller: plus,
            config: AddConfig(onPicture: () {}, onVideo: () {}, onFile: () {}, onScan: () {}, onPlace: () {}, boards: true, databases: true, blanks: true),
            coarse: true,
            child: SafeArea(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: phone.width, child: SingleChildScrollView(child: EditorColumn(view: view))))),
          ),
        ),
      ),
    );
    view.setFocused(true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(PlusButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A file'), findsOneWidget);
    expect(find.text('Scan a document'), findsOneWidget);
    await shot(tester, 'plus-files-phone-dark');
  });

  testWidgets('Settings: Files and scans', (tester) async {
    await tester.runAsync(() => kit.store.keep(AttachmentBytes(Uint8List(2400000)), original: 'Lease.pdf'));
    await pumpApp(
      tester,
      size: phone,
      ratio: 3,
      prefs: const AppPreferences(theme: 'dark'),
      home: Builder(builder: (context) => ColoredBox(color: context.tokens.color('glacier-bg'), child: const SafeArea(child: PaneBody(children: [FilesAndScans()])))),
    );
    await settleIo(tester);
    await shot(tester, 'settings-files-phone-dark');
  });

  testWidgets('a search row found by the words read in a PDF', (tester) async {
    searchExtraForShots(kit);
    const lease = 'b1b2c3d4-0000-4000-8000-000000000002.pdf';
    await tester.runAsync(() => kit.texts.keep(const ReadThing.file(lease), textOfPages(['Lease agreement', 'Rent is due monthly on the first of each month'])));
    final flat = Note(id: 'flat', body: '# The flat\n\n[Lease 2026.pdf](file/$lease "2.4 MB")\n', createdAt: 0, updatedAt: DateTime(2026, 10, 14).millisecondsSinceEpoch);
    final found = findNotes([flat], 'rent monthly');
    expect(found.single.snippet!.text, endsWith('in Lease 2026.pdf, page 2'));
    await pumpApp(
      tester,
      size: phone,
      ratio: 3,
      prefs: const AppPreferences(theme: 'dark'),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: SafeArea(child: Column(children: [HomeLine(note: flat, index: 0, onOpen: (_) {}, found: found.single, now: DateTime(2026, 10, 16).millisecondsSinceEpoch)])),
        ),
      ),
    );
    await settleIo(tester);
    await shot(tester, 'search-ocr-phone-dark');
    debugDisableShadows = true;
  });
}

/// The kit's words are the search's (FilesKit.install sets it; said again here for the reader of the test).
void searchExtraForShots(FilesKit kit) => kit.install();
