// The PDF viewer (lib/files/pdf_view.dart) over a small test PDF of three pages (support.dart `tinyPdf`, its pages
// read back from its own objects): pages drawn on asking, Page n of N, Go to page, Find with the device's places or
// the pages' words, Copy text from the page's own words or the words read in it, and Share and Open with.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/files/pdf_view.dart';
import 'package:ghost_md/files/read_text.dart' show textOfPages;

import '../support/render.dart';
import 'support.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadAppFonts);

  late List<String> copied;
  setUp(() {
    copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
  });

  Future<({FakePdf pdf, List<String> handed, GlobalKey<PdfViewState> key})> open(WidgetTester tester, {bool findable = true, String? read}) async {
    final sizes = readPdfPages(tinyPdf(pages: 3, width: 612, height: 792));
    expect(sizes, const [ui.Size(612, 792), ui.Size(612, 792), ui.Size(612, 792)]);
    final pdf = FakePdf(sizes, pageWords: const ['Lease agreement', 'Rent is due monthly', ''], findable: findable);
    final handed = <String>[];
    final key = GlobalKey<PdfViewState>();
    await pumpApp(
      tester,
      size: const Size(430, 932),
      ratio: 1,
      home: PdfView(
        key: key,
        pages: pdf,
        name: 'Lease 2026.pdf',
        readWords: () => read,
        onClose: () => handed.add('closed'),
        onShare: () async => handed.add('shared'),
        onOpenWith: () async => handed.add('opened'),
      ),
    );
    // pumpApp turns real shadows on for a picture; none is taken here.
    debugDisableShadows = true;
    await settle(tester);
    return (pdf: pdf, handed: handed, key: key);
  }

  testWidgets('draws the page in view as it is wanted, and says which of how many it is', (tester) async {
    final it = await open(tester);
    expect(find.text('Lease 2026.pdf'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(it.pdf.drawn, contains(0));
    expect(it.pdf.drawn, isNot(contains(2)), reason: 'a page not near the one in view is not drawn');
    expect(find.byKey(const ValueKey<String>('pdf-drawn')), findsWidgets);
    await tester.drag(find.byKey(const ValueKey<String>('pdf-pages')), const Offset(-400, 0));
    await settle(tester);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(it.pdf.drawn, contains(1));
  });

  testWidgets('goes to a page by its number', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pdf-page')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey<String>('pdf-jump')).last, '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester);
    expect(find.text('Page 3 of 3'), findsOneWidget);
  });

  testWidgets('finds words where the device says they stand, and steps to them', (tester) async {
    final it = await open(tester);
    await it.key.currentState!.find('monthly');
    await settle(tester);
    expect(it.key.currentState!.page, 1);
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('finds words in the words read in a page where the device cannot say where they stand', (tester) async {
    final it = await open(tester, findable: false, read: textOfPages(['', '', 'Signed by both parties']));
    await it.key.currentState!.find('signed');
    await settle(tester);
    expect(it.key.currentState!.page, 2);
    final none = await findInPdf(it.pdf, 'nowhere', read: textOfPages(['', '', 'Signed']));
    expect(none, isEmpty);
  });

  testWidgets('copies the page’s own words, or the words read in it, and says when there are none', (tester) async {
    final it = await open(tester, read: textOfPages(['', '', 'Signed by both parties']));
    await tester.tap(find.byKey(const ValueKey<String>('pdf-copy')));
    await settle(tester);
    expect(copied, ['Lease agreement']);
    it.key.currentState!.goTo(2);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pdf-copy')));
    await settle(tester);
    expect(copied.last, 'Signed by both parties');
  });

  testWidgets('hands the file over to share or open, and closes', (tester) async {
    final it = await open(tester);
    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.tap(find.bySemanticsLabel('Open with another app'));
    await tester.tap(find.byKey(const ValueKey<String>('pdf-close')));
    await settle(tester);
    expect(it.handed, ['shared', 'opened', 'closed']);
  });
}
