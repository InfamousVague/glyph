import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/media/images.dart';
import 'package:ghost_md/home/note_card.dart' show CardRow;

/// A picture's box says its height when asked, so a row that asks its cards their heights (two cards across on an
/// opened Fold) lays out a card with a picture in it at its full height, with nothing thrown.
void main() {
  testWidgets('a card row asks a picture its height and lays it out whole', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 410,
            child: CardRow(
              columns: 2,
              gap: 10,
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [FitPictureBox(natural: Size(800, 400), child: ColoredBox(color: Color(0xFF000000)))]),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // A cell is 200 wide: the 800x400 picture is drawn 200x100, and the row is as tall as it.
    expect(tester.getSize(find.byType(FitPictureBox)), const Size(200, 100));
    expect(tester.getSize(find.byType(CardRow)).height, 100);
  });

  testWidgets('a picture keeps its own size where there is room, and its most height', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: FitPictureBox(natural: Size(120, 600), maxHeight: 300, child: SizedBox.expand())),
      ),
    );
    expect(tester.getSize(find.byType(FitPictureBox)), const Size(60, 300));
  });
}
