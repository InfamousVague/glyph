import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/sheet/flow.dart';

/// Blocks as a page lays them out (flow.dart): one under another, each as wide as what holds them, the margin
/// between two the larger of the two.
void main() {
  Widget box(String name, double height) => SizedBox(key: ValueKey(name), height: height);

  Future<void> show(WidgetTester tester, Widget flow) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 200, child: flow)),
        ),
      );

  Rect at(WidgetTester tester, String name) => tester.getRect(find.byKey(ValueKey(name)));

  testWidgets('puts the larger of two margins between two blocks, not their sum', (tester) async {
    await show(
      tester,
      CssFlow(
        children: [
          CssFlow.block(margin: const EdgeInsets.only(bottom: 13), child: box('group', 40)),
          CssFlow.block(margin: const EdgeInsets.symmetric(vertical: 9), child: box('heading', 14)),
          CssFlow.block(margin: const EdgeInsets.only(bottom: 13), child: box('last', 40)),
        ],
      ),
    );
    expect(at(tester, 'group'), const Rect.fromLTWH(0, 0, 200, 40));
    expect(at(tester, 'heading').top, 40 + 13);
    expect(at(tester, 'last').top, 40 + 13 + 14 + 9);
    // The last block's margin is kept inside a box that does not let it through.
    expect(tester.getSize(find.byType(CssFlow).first).height, 40 + 13 + 14 + 9 + 40 + 13);
  });

  testWidgets('lets a first and a last child’s margins through a box that collapses, into its own', (tester) async {
    await show(
      tester,
      CssFlow(
        children: [
          box('before', 10),
          // A folder: 1px of its own, and a paragraph inside whose 4px below is the larger.
          CssFlow(
            margin: const EdgeInsets.symmetric(vertical: 1),
            collapse: true,
            children: [
              box('row', 25),
              CssFlow.block(margin: const EdgeInsets.fromLTRB(13, 2, 0, 4), child: box('empty', 12)),
            ],
          ),
          CssFlow.block(margin: const EdgeInsets.symmetric(vertical: 1), child: box('after', 20)),
        ],
      ),
    );
    expect(at(tester, 'row').top, 10 + 1);
    expect(at(tester, 'empty'), const Rect.fromLTWH(13, 10 + 1 + 25 + 2, 187, 12));
    // 4, not 1, and not 5.
    expect(at(tester, 'after').top, 10 + 1 + 25 + 2 + 12 + 4);
  });

  testWidgets('keeps a first child’s margin inside a box with padding over it', (tester) async {
    await show(
      tester,
      CssFlow(
        children: [
          CssFlow(
            padding: const EdgeInsets.only(top: 5),
            collapse: true,
            children: [CssFlow.block(margin: const EdgeInsets.only(top: 3), child: box('inside', 10))],
          ),
        ],
      ),
    );
    expect(at(tester, 'inside').top, 5 + 3);
  });

  testWidgets('sets a box in from its margins and its padding, and paints its decoration between them', (tester) async {
    await show(
      tester,
      CssFlow(
        children: [
          CssFlow(
            key: const ValueKey('inside'),
            margin: const EdgeInsets.only(left: 15),
            padding: const EdgeInsets.only(left: 6),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF000000)))),
            collapse: true,
            children: [box('row', 20)],
          ),
        ],
      ),
    );
    expect(at(tester, 'row'), const Rect.fromLTWH(21, 0, 179, 20));
    final flow = tester.renderObject<RenderCssFlow>(find.byKey(const ValueKey('inside')));
    expect(flow.borderBox, const Rect.fromLTWH(15, 0, 185, 20));
  });

  testWidgets('standing in something that is not a flow, keeps its own margins clear', (tester) async {
    await show(tester, Column(children: [CssFlow.block(key: const ValueKey('block'), margin: const EdgeInsets.fromLTRB(0, 4, 0, 6), child: box('alone', 10)), box('next', 5)]));
    expect(at(tester, 'alone').top, 4);
    expect(at(tester, 'next').top, 4 + 10 + 6);
    expect(tester.renderObject<RenderCssFlow>(find.byKey(const ValueKey('block'))).marginBottom, 6);
  });

  testWidgets('moves what follows when a block inside it changes its margin', (tester) async {
    Widget flow(double margin) => CssFlow(
          children: [
            CssFlow(collapse: true, children: [CssFlow.block(margin: EdgeInsets.only(bottom: margin), child: box('row', 10))]),
            box('after', 10),
          ],
        );
    await show(tester, flow(2));
    expect(at(tester, 'after').top, 12);
    await show(tester, flow(8));
    expect(at(tester, 'after').top, 18);
  });
}
