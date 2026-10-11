import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// Makes `card.png`, the one picture both engines bend in the parity pictures (tool/wisp_reference.mjs draws the web
/// app's filters over it in Chromium, test/art/wisp_parity_test.dart the shaders): a page of words in the app's own
/// face and ink on nothing, 390 by 420 at two device pixels to the logical pixel. Only run when asked, since the
/// Chromium pictures have to be made again from whatever this writes:
/// `flutter test --update-goldens test/art/reference/card_test.dart`.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('the card', (tester) async {
    final key = GlobalKey();
    await pumpApp(
      tester,
      size: const Size(390, 420),
      prefs: const AppPreferences(theme: 'dark'),
      home: Builder(
        builder: (context) {
          final t = context.tokens;
          final ink = t.color('app-ink');
          Widget line(String words, {double size = 16, String weight = 'regular'}) =>
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(words, style: t.textAt(size, weight: weight, color: ink, height: 1.4)));
          return Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 390,
                height: 420,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line('Planning the weekend', size: 26, weight: 'bold'),
                      line('Hold. Talk. Done. The notes that matter are the ones you can find again on a Monday.'),
                      line('Shopping', size: 20, weight: 'semibold'),
                      line('Oat milk, two lemons, the good bread from the place on the corner, candles.'),
                      Container(height: 2, color: ink, margin: const EdgeInsets.only(bottom: 10)),
                      line('Call Sam about the boat before nine, then the long walk if the weather holds.'),
                      line('Ideas', size: 20, weight: 'semibold'),
                      line('A list that sorts itself. A page that reads back what you said, word for word.'),
                      line('The ferry leaves at ten past four and the last one home is at eleven.'),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('test/art/reference/card.png').writeAsBytesSync(bytes!);
    debugDisableShadows = true;
  }, skip: !autoUpdateGoldenFiles);
}
