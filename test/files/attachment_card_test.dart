// A file's card in a note (lib/editor/media/attachments.dart): under a line that is only a link to a kept file, the
// line folded to the file's own name off the caret; its kind, size and pages, or why it is not here; a tap opening
// a PDF in the app's viewer and anything else in another app; and the + menu's A file and Scan a document.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/attachments.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/files/attachment_store.dart';
import 'package:ghost_md/files/files_kit.dart';
import 'package:ghost_md/files/pdf_view.dart';
import 'package:ghost_md/files/read_text.dart';

import '../editor/media/support.dart';
import '../support/render.dart';
import 'support.dart';

const Key card = ValueKey<String>('cm-fileCard');

String? meta(WidgetTester tester) => tester.widgetList<InlineWords>(find.byKey(const ValueKey<String>('file-meta'))).map((w) => w.text).firstOrNull;

/// Lets the files' real reads and writes finish, and the frames that follow them.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump();
  }
}

void main() {
  setUpAll(loadAppFonts);

  late Directory data;
  late FakeDocuments device;
  late FilesKit kit;

  setUp(() async {
    data = Directory.systemTemp.createTempSync('files-card');
    device = FakeDocuments();
    kit = FilesKit(dataDir: data.path, store: AttachmentStore(dataDir: data.path), texts: ReadTexts(dataDir: data.path), device: device, bodies: () async => const [], kept: MemoryStored(), listenForInput: false)..install();
  });
  tearDown(() {
    FilesKit.uninstall();
    data.deleteSync(recursive: true);
  });

  Future<KeptAttachment> keep(WidgetTester tester, String original, Object contents) async => (await tester.runAsync(
        () => kit.store.keep(AttachmentBytes(contents is String ? Uint8List.fromList(contents.codeUnits) : contents as Uint8List), original: original),
      ))!;

  testWidgets('is drawn under a file’s line, in any lead, and not in fenced code or in a sentence', (tester) async {
    final lease = await keep(tester, 'Lease.pdf', tinyPdf(pages: 3));
    final line = lease.markdown;
    await pumpNote(tester, 'Flat\n$line\n- $line\n```\n$line\n```\nsee $line here', more: <Extension>[attachmentCards()]);
    await settleIo(tester);
    expect(find.byKey(card), findsNWidgets(2));
    expect(meta(tester), startsWith('PDF · '));
    expect(meta(tester), endsWith(' · 3 pages'));
    expect(find.byKey(const ValueKey<String>('file-thumb')), findsWidgets, reason: 'a PDF’s first page is its mark');
  });

  testWidgets('says when the file is not on this device, and when it stays on the one it was added on', (tester) async {
    await pumpNote(tester, '[Lease.pdf](file/0a1b2c3d.pdf "2.4 MB")\n\n[Film.mov](file/0a1b2c3e.mov "80 MB")', more: <Extension>[attachmentCards()]);
    await settleIo(tester);
    final said = tester.widgetList<InlineWords>(find.byKey(const ValueKey<String>('file-meta'))).map((w) => w.text).toList();
    expect(said, ['PDF · 2.4 MB · Not on this device yet.', 'Video · 80 MB · It stays on the device it was added on.']);
    expect(find.byKey(const ValueKey<String>('file-elsewhere')), findsNothing);
  });

  testWidgets('a tap opens a PDF in the app’s viewer, and anything else in another app, under its own name', (tester) async {
    final lease = await keep(tester, 'Lease.pdf', tinyPdf(pages: 2));
    final notes = await keep(tester, 'Notes', 'plain words');
    await pumpNote(tester, '${lease.markdown}\n\n${notes.markdown}', more: <Extension>[attachmentCards()]);
    await settleIo(tester);
    await tester.tap(find.byKey(const ValueKey<String>('file-open')).last);
    await settleIo(tester);
    expect(device.handed, ['open Notes.bin'], reason: 'handed over with the extension it was kept with');
    await tester.tap(find.byKey(const ValueKey<String>('file-open')).first);
    await settleIo(tester);
    expect(find.byType(PdfView), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('pdf-close')));
    await settleIo(tester);
    expect(find.byType(PdfView), findsNothing);
  });

  testWidgets('its line reads as the file’s own name away from the caret, and as written on it', (tester) async {
    final view = await pumpNote(tester, 'Flat\n[Lease 2026.pdf](file/0a1b2c3d.pdf "2.4 MB")\nmore', more: <Extension>[attachmentCards()]);
    expect(shownOf(tester, 1), 'Lease 2026.pdf');
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(8)));
    await tester.pump();
    expect(shownOf(tester, 1), '[Lease 2026.pdf](file/0a1b2c3d.pdf "2.4 MB")');
  });

  test('the + offers A file and Scan a document beside the phone’s own, where the screen can do them', () {
    final now = DateTime(2026, 10, 16, 14, 5);
    final rows = topRows(readGates(picture: true, video: true, file: true, scan: true, place: false, note: false, canvas: false), now).map((r) => r.id).toList();
    expect(rows.sublist(0, 4), ['picture', 'video', 'file', 'scan']);
    expect(topRows(readGates(picture: true, video: false, place: false, note: false, canvas: false), now).map((r) => r.id), isNot(contains('file')));
    expect(allRows(readGates(picture: false, video: false, file: true, place: false, note: false, canvas: false), now).map((r) => r.words), contains('A file'));
  });
}
