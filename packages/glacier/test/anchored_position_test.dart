import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/src/components/anchored_position.dart';

/// The positioning maths against internal/useAnchoredPosition.ts and internal/ArrowGlass.tsx. The numbers are worked
/// out by hand from the TypeScript; the first group is the kit's own react/test/anchored-position.test.tsx, whose
/// window is jsdom's 1024 x 768.
void main() {
  const window = Size(1024, 768);
  const panel = Size(120, 80);

  // trigger: left 100, top 10, 100x20 (so right 200, bottom 30) unless overridden
  Rect trigger({double left = 100, double top = 10, double width = 100, double height = 20}) => Rect.fromLTWH(left, top, width, height);

  AnchoredPosition at(
    Placement placement, {
    Rect? from,
    Size floating = panel,
    Size viewport = window,
    TextDirection direction = TextDirection.ltr,
    double offset = 8,
    double padding = 8,
  }) =>
      computeAnchoredPosition(
        trigger: from ?? trigger(),
        floating: floating,
        viewport: viewport,
        placement: placement,
        direction: direction,
        offset: offset,
        padding: padding,
      );

  group('the kit\'s own tests (anchored-position.test.tsx)', () {
    test('bottom-start aligns to the trigger left edge in LTR', () {
      final p = at(Placement.bottomStart);
      expect(p.left, 100);
      expect(p.top, 38); // trigger bottom 30 + offset 8
    });

    test('bottom-start aligns to the trigger RIGHT edge in RTL (start = inline start)', () {
      final p = at(Placement.bottomStart, direction: TextDirection.rtl);
      expect(p.left, 80); // trigger right 200 - width 120
      expect(p.top, 38);
    });

    test('bottom-end mirrors to the trigger left edge in RTL', () {
      expect(at(Placement.bottomEnd, direction: TextDirection.rtl).left, 100);
    });

    test('center alignment is direction-neutral', () {
      expect(at(Placement.bottom, direction: TextDirection.rtl).left, 90); // 100 + 50 - 60
      expect(at(Placement.bottom).left, 90);
    });

    test('inline-end resolves to the right side in LTR', () {
      final p = at(Placement.inlineEndStart, from: trigger(left: 400));
      expect(p.left, 508); // trigger right 500 + offset 8
      expect(p.top, 10); // start on a horizontal side stays block-axis
      expect(p.placement, Placement.rightStart); // reports resolved physical side
    });

    test('inline-end resolves to the left side in RTL', () {
      final p = at(Placement.inlineEndStart, from: trigger(left: 400), direction: TextDirection.rtl);
      expect(p.left, 272); // trigger left 400 - offset 8 - width 120
      expect(p.placement, Placement.leftStart);
    });

    test('inline-end flips back to the physical right at the RTL viewport edge', () {
      // 100 - 8 - 120 would poke past the padding
      final p = at(Placement.inlineEndStart, direction: TextDirection.rtl);
      expect(p.left, 208); // trigger right 200 + offset 8
      expect(p.placement, Placement.rightStart);
    });

    test('inline-start resolves to the right side in RTL', () {
      expect(at(Placement.inlineStart, from: trigger(left: 400), direction: TextDirection.rtl).left, 508);
    });

    test('physical left/right placements ignore direction', () {
      expect(at(Placement.rightStart, from: trigger(left: 400), direction: TextDirection.rtl).left, 508);
    });

    test('a context menu hangs from a point of no size, 2px under it', () {
      // menu.test.tsx: contextmenu at 120, 80 puts the panel at left 120, top 82
      final p = at(Placement.bottomStart, from: const Offset(120, 80) & Size.zero, offset: 2);
      expect(p.offset, const Offset(120, 82));
      // and toward inline-start under RTL: right edge at the pointer, 300 - width 120
      expect(at(Placement.bottomStart, from: const Offset(300, 100) & Size.zero, offset: 2, direction: TextDirection.rtl).offset, const Offset(180, 102));
    });

    test('a flyout hangs 2px off its row, start-aligned to the row top', () {
      // menu.test.tsx, RTL: row left 300, top 50, 200x20
      final row = trigger(left: 300, top: 50, width: 200);
      expect(at(Placement.inlineEndStart, from: row, offset: 2, direction: TextDirection.rtl).offset, const Offset(178, 50));
      // no room on the left: back to the physical right, row right 250 + offset 2
      expect(at(Placement.inlineEndStart, from: trigger(left: 50, top: 50, width: 200), offset: 2, direction: TextDirection.rtl).left, 252);
    });

    test('a popover stands 12px off its trigger', () {
      // popover.test.tsx, RTL: left 80, top 42
      expect(at(Placement.bottomStart, offset: 12, direction: TextDirection.rtl).offset, const Offset(80, 42));
    });
  });

  group('every placement, with room on all sides', () {
    // trigger 400..500 across and 300..320 down: centre 450, 310
    final from = trigger(left: 400, top: 300);

    // placement: [left, top, resolved, arrow]
    final ltr = <Placement, List<Object>>{
      Placement.top: [390.0, 212.0, Placement.top, 60.0],
      Placement.topStart: [400.0, 212.0, Placement.topStart, 50.0],
      Placement.topCenter: [390.0, 212.0, Placement.top, 60.0],
      Placement.topEnd: [380.0, 212.0, Placement.topEnd, 70.0],
      Placement.bottom: [390.0, 328.0, Placement.bottom, 60.0],
      Placement.bottomStart: [400.0, 328.0, Placement.bottomStart, 50.0],
      Placement.bottomCenter: [390.0, 328.0, Placement.bottom, 60.0],
      Placement.bottomEnd: [380.0, 328.0, Placement.bottomEnd, 70.0],
      Placement.left: [272.0, 270.0, Placement.left, 40.0],
      Placement.leftStart: [272.0, 300.0, Placement.leftStart, 10.0],
      Placement.leftCenter: [272.0, 270.0, Placement.left, 40.0],
      Placement.leftEnd: [272.0, 240.0, Placement.leftEnd, 70.0],
      Placement.right: [508.0, 270.0, Placement.right, 40.0],
      Placement.rightStart: [508.0, 300.0, Placement.rightStart, 10.0],
      Placement.rightCenter: [508.0, 270.0, Placement.right, 40.0],
      Placement.rightEnd: [508.0, 240.0, Placement.rightEnd, 70.0],
      Placement.inlineStart: [272.0, 270.0, Placement.left, 40.0],
      Placement.inlineStartStart: [272.0, 300.0, Placement.leftStart, 10.0],
      Placement.inlineStartCenter: [272.0, 270.0, Placement.left, 40.0],
      Placement.inlineStartEnd: [272.0, 240.0, Placement.leftEnd, 70.0],
      Placement.inlineEnd: [508.0, 270.0, Placement.right, 40.0],
      Placement.inlineEndStart: [508.0, 300.0, Placement.rightStart, 10.0],
      Placement.inlineEndCenter: [508.0, 270.0, Placement.right, 40.0],
      Placement.inlineEndEnd: [508.0, 240.0, Placement.rightEnd, 70.0],
    };

    test('the table names every placement', () => expect(ltr.keys.toSet(), Placement.values.toSet()));

    for (final entry in ltr.entries) {
      test('${entry.key.css} in LTR', () {
        final p = at(entry.key, from: from);
        expect([p.left, p.top, p.placement, p.arrowOffset], entry.value);
      });
    }

    // Under RTL the logical sides swap, and so do start and end along the top and bottom; the block axis does not.
    final rtl = <Placement, List<Object>>{
      Placement.topStart: [380.0, 212.0, Placement.topStart, 70.0],
      Placement.topEnd: [400.0, 212.0, Placement.topEnd, 50.0],
      Placement.bottomStart: [380.0, 328.0, Placement.bottomStart, 70.0],
      Placement.bottomEnd: [400.0, 328.0, Placement.bottomEnd, 50.0],
      Placement.leftStart: [272.0, 300.0, Placement.leftStart, 10.0],
      Placement.rightEnd: [508.0, 240.0, Placement.rightEnd, 70.0],
      Placement.inlineStart: [508.0, 270.0, Placement.right, 40.0],
      Placement.inlineStartStart: [508.0, 300.0, Placement.rightStart, 10.0],
      Placement.inlineStartEnd: [508.0, 240.0, Placement.rightEnd, 70.0],
      Placement.inlineEnd: [272.0, 270.0, Placement.left, 40.0],
      Placement.inlineEndStart: [272.0, 300.0, Placement.leftStart, 10.0],
      Placement.inlineEndEnd: [272.0, 240.0, Placement.leftEnd, 70.0],
    };
    for (final entry in rtl.entries) {
      test('${entry.key.css} in RTL', () {
        final p = at(entry.key, from: from, direction: TextDirection.rtl);
        expect([p.left, p.top, p.placement, p.arrowOffset], entry.value);
      });
    }

    test('the panel grows out of the edge that faces its anchor', () {
      expect(at(Placement.bottomStart, from: from).transformOrigin, Alignment.topCenter);
      expect(at(Placement.topEnd, from: from).transformOrigin, Alignment.bottomCenter);
      expect(at(Placement.right, from: from).transformOrigin, Alignment.centerLeft);
      expect(at(Placement.leftStart, from: from).transformOrigin, Alignment.centerRight);
    });
  });

  group('flipping at each edge of the window', () {
    test('bottom turns to top at the foot, when the top has room', () {
      // bottom 720 + 8 + 80 = 808 > 760; top 700 - 8 - 80 = 612 > 8
      final p = at(Placement.bottomStart, from: trigger(top: 700));
      expect(p.placement, Placement.topStart);
      expect(p.top, 612);
      expect(p.transformOrigin, Alignment.bottomCenter);
    });

    test('bottom stays where neither side has room', () {
      // window 120 tall: 70 + 88 = 158 > 112, and 50 - 88 = -38 is not past the padding
      final p = at(Placement.bottom, from: trigger(top: 50), viewport: const Size(1024, 120));
      expect(p.placement, Placement.bottom);
      expect(p.top, 78);
    });

    test('bottom that fits exactly does not turn', () {
      // 672 + 8 + 80 = 760, which is not more than 768 - 8
      expect(at(Placement.bottom, from: trigger(top: 652)).placement, Placement.bottom);
      expect(at(Placement.bottom, from: trigger(top: 653)).placement, Placement.top);
    });

    test('top turns to bottom at the head, when the bottom has room', () {
      // 50 - 8 - 80 = -38 < 8; 70 + 8 + 80 = 158 < 760
      final p = at(Placement.topEnd, from: trigger(top: 50));
      expect(p.placement, Placement.bottomEnd);
      expect(p.top, 78);
    });

    test('top stays where the bottom has no room either', () {
      final p = at(Placement.top, from: trigger(top: 50), viewport: const Size(1024, 120));
      expect(p.placement, Placement.top);
      expect(p.top, -38);
    });

    test('top that fits exactly does not turn', () {
      // 96 - 8 - 80 = 8, which is not less than the padding
      expect(at(Placement.top, from: trigger(top: 96)).placement, Placement.top);
      expect(at(Placement.top, from: trigger(top: 95)).placement, Placement.bottom);
    });

    test('right turns to left at the right edge, when the left has room', () {
      // 1000 + 8 + 120 = 1128 > 1016; 900 - 8 - 120 = 772 > 8
      final p = at(Placement.rightStart, from: trigger(left: 900));
      expect(p.placement, Placement.leftStart);
      expect(p.left, 772);
      expect(p.transformOrigin, Alignment.centerRight);
    });

    test('right stays where neither side has room', () {
      final p = at(Placement.right, from: trigger(left: 100), viewport: const Size(300, 768));
      expect(p.placement, Placement.right);
      expect(p.left, 208);
    });

    test('left turns to right at the left edge, when the right has room', () {
      // 100 - 8 - 120 = -28 < 8; 200 + 8 + 120 = 328 < 1016
      final p = at(Placement.leftEnd);
      expect(p.placement, Placement.rightEnd);
      expect(p.left, 208);
    });

    test('left stays where the right has no room either', () {
      final p = at(Placement.left, viewport: const Size(300, 768));
      expect(p.placement, Placement.left);
      expect(p.left, -28);
    });

    test('the offset and the padding both count toward the room', () {
      // offset 12: 660 + 12 + 80 = 752, fits; padding 20 leaves 748, and it turns
      expect(at(Placement.bottom, from: trigger(top: 640), offset: 12).placement, Placement.bottom);
      expect(at(Placement.bottom, from: trigger(top: 640), offset: 12, padding: 20).placement, Placement.top);
    });
  });

  group('shifting along the edge', () {
    test('a panel hanging past the right edge is pushed back in', () {
      // 1024 - 120 - 8 = 896
      final p = at(Placement.bottomStart, from: trigger(left: 1000));
      expect(p.left, 896);
      expect(p.placement, Placement.bottomStart);
      expect(p.arrowOffset, 154); // trigger centre 1050 - 896: the tip stays on the trigger
    });

    test('a panel hanging past the left edge is pushed back in', () {
      // end-aligned to a trigger at -50..50: 50 - 120 = -70, held at the padding
      final p = at(Placement.bottomEnd, from: trigger(left: -50));
      expect(p.left, 8);
      expect(p.arrowOffset, -8); // trigger centre 0 - 8
    });

    test('a side panel is held inside the top and the foot', () {
      // foot: 768 - 80 - 8 = 680
      final low = at(Placement.rightStart, from: trigger(left: 400, top: 750));
      expect(low.top, 680);
      expect(low.arrowOffset, 80); // trigger centre 760 - 680
      // head: end-aligned to a trigger at 0..20 would start at -60
      final high = at(Placement.leftEnd, from: trigger(left: 400, top: 0));
      expect(high.top, 8);
      expect(high.arrowOffset, 2);
    });

    test('a panel wider than the window starts at the padding', () {
      expect(at(Placement.bottom, floating: const Size(2000, 80)).left, 8);
      expect(at(Placement.right, from: trigger(left: 400), floating: const Size(120, 2000)).top, 8);
    });

    test('the padding is the caller\'s', () {
      expect(at(Placement.bottomStart, from: trigger(left: 1000), padding: 24).left, 880);
    });

    test('the main axis is never clamped: a tall panel runs off the foot', () {
      expect(at(Placement.bottom, from: trigger(top: 50), floating: const Size(120, 2000)).top, 78);
    });
  });

  group('whole pixels', () {
    test('Math.round sends halves up', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect(jsRound(-0.5), 0);
      expect(jsRound(2.4), 2);
      expect(jsRound(-2.6), -3);
    });

    test('top and left are rounded, the arrow as compute() has it is not', () {
      final p = at(Placement.bottomStart, from: trigger(left: 100.5, top: 10.25));
      expect(p.left, 101);
      expect(p.top, 38); // 30.25 + 8 = 38.25
      expect(p.arrowOffset, 50); // 150.5 - 100.5, against the place before rounding
    });

    test('the arrow the hook publishes is against where the panel was put, in whole pixels', () {
      final from = trigger(left: 100.5, top: 10.25);
      final p = at(Placement.bottomStart, from: from);
      expect(projectArrowOffset(from, p), 50); // round(150.5 - 101)
      // a page that pinned the panel 16px in: the tip follows the trigger, not the place asked for
      expect(projectArrowOffset(from, p, used: const Offset(16, 38)), 135); // round(150.5 - 16)
      final side = at(Placement.rightStart, from: trigger(left: 400, top: 300.4));
      expect(projectArrowOffset(trigger(left: 400, top: 300.4), side), 10); // round(310.4 - 300)
    });
  });

  group('Placement', () {
    test('is the spec\'s list, in its order', () {
      expect(Placement.values.map((p) => p.css).toList(), [
        'top',
        'top-start',
        'top-center',
        'top-end',
        'bottom',
        'bottom-start',
        'bottom-center',
        'bottom-end',
        'left',
        'left-start',
        'left-center',
        'left-end',
        'right',
        'right-start',
        'right-center',
        'right-end',
        'inline-start',
        'inline-start-start',
        'inline-start-center',
        'inline-start-end',
        'inline-end',
        'inline-end-start',
        'inline-end-center',
        'inline-end-end',
      ]);
    });

    test('parses its own names, and reads an unknown one as bottom-start', () {
      for (final p in Placement.values) {
        expect(Placement.parse(p.css), p);
      }
      expect(Placement.parse('sideways'), Placement.bottomStart);
    });

    test('a bare side is centred, and inline-start is not side inline with align start', () {
      expect(Placement.inlineStart.side, AnchorSide.inlineStart);
      expect(Placement.inlineStart.align, AnchorAlignment.center);
      expect(Placement.inlineEndStart.side, AnchorSide.inlineEnd);
      expect(Placement.inlineEndStart.align, AnchorAlignment.start);
      expect(Placement.left.align, AnchorAlignment.center);
    });
  });

  group('the arrow glass outline (ArrowGlass.tsx buildPath)', () {
    ArrowGlassShape shape(Placement placement, {double w = 200, double h = 100, double r = 16, double? tipAt}) =>
        buildArrowGlassShape(width: w, height: h, radius: r, placement: placement, tipAt: tipAt);

    test('bottom-start: the tip is on the top edge, 14 in from the corner', () {
      final s = shape(Placement.bottomStart);
      expect(s.box, const Rect.fromLTWH(0, -6, 200, 106));
      expect(s.tipCentre, 21); // tipInset 14 + tipHalf 7
      expect(s.d, 'M 16 6 H 14 L 21 0 L 28 6 H 184 A 16 16 0 0 1 200 22 V 90 A 16 16 0 0 1 184 106 H 16 A 16 16 0 0 1 0 90 V 22 A 16 16 0 0 1 16 6 Z');
      expect(s.path.getBounds(), const Rect.fromLTWH(0, 0, 200, 106));
      expect(s.path.contains(const Offset(21, 2)), isTrue); // in the tip
      expect(s.path.contains(const Offset(60, 2)), isFalse); // beside it, above the panel
      expect(s.path.contains(const Offset(100, 56)), isTrue); // the panel
      expect(s.path.contains(const Offset(1, 7)), isFalse); // a rounded corner
    });

    test('top, with the trigger\'s centre given: the tip is on the bottom edge, under the trigger', () {
      final s = shape(Placement.top, tipAt: 150);
      expect(s.box, const Rect.fromLTWH(0, 0, 200, 106));
      expect(s.tipCentre, 150);
      expect(s.d, 'M 16 0 H 184 A 16 16 0 0 1 200 16 V 84 A 16 16 0 0 1 184 100 H 157 L 150 106 L 143 100 H 16 A 16 16 0 0 1 0 84 V 16 A 16 16 0 0 1 16 0 Z');
      expect(s.path.contains(const Offset(150, 104)), isTrue);
    });

    test('left-end: the tip is on the right edge, 14 up from the corner', () {
      final s = shape(Placement.leftEnd);
      expect(s.box, const Rect.fromLTWH(0, 0, 206, 100));
      expect(s.tipCentre, 79); // 100 - 14 - 7
      expect(s.d, 'M 16 0 H 184 A 16 16 0 0 1 200 16 V 72 L 206 79 L 200 86 V 84 A 16 16 0 0 1 184 100 H 16 A 16 16 0 0 1 0 84 V 16 A 16 16 0 0 1 16 0 Z');
      expect(s.path.contains(const Offset(204, 79)), isTrue);
    });

    test('right: the tip is on the left edge, and is kept off the corner', () {
      final s = shape(Placement.right, tipAt: 5);
      expect(s.box, const Rect.fromLTWH(-6, 0, 206, 100));
      expect(s.tipCentre, 23); // radius 16 + tipHalf 7, not 5
      expect(s.d, 'M 22 0 H 190 A 16 16 0 0 1 206 16 V 84 A 16 16 0 0 1 190 100 H 22 A 16 16 0 0 1 6 84 V 30 L 0 23 L 6 16 V 16 A 16 16 0 0 1 22 0 Z');
      expect(s.path.contains(const Offset(2, 23)), isTrue);
    });

    test('the tip is kept off the far corner too', () {
      expect(shape(Placement.bottom, tipAt: 400).tipCentre, 177); // 200 - 16 - 7
      expect(shape(Placement.left, tipAt: 400).tipCentre, 77); // 100 - 16 - 7
    });

    test('without a centre the tip goes by the alignment', () {
      expect(shape(Placement.bottom).tipCentre, 100);
      expect(shape(Placement.bottomEnd).tipCentre, 179); // 200 - 14 - 7
      expect(shape(Placement.rightStart).tipCentre, 21);
      expect(shape(Placement.right).tipCentre, 50);
    });

    test('the radius stops a pixel short of half the panel', () {
      final s = shape(Placement.bottom, w: 40, h: 21);
      expect(s.radius, 9.5); // min(16, 21 / 2 - 1)
      expect(s.d, 'M 9.5 6 H 13 L 20 0 L 27 6 H 30.5 A 9.5 9.5 0 0 1 40 15.5 V 17.5 A 9.5 9.5 0 0 1 30.5 27 H 9.5 A 9.5 9.5 0 0 1 0 17.5 V 15.5 A 9.5 9.5 0 0 1 9.5 6 Z');
      expect(shape(Placement.bottom, w: 40, h: 1).radius, 0); // never below nothing
    });

    test('the tip\'s size is the caller\'s', () {
      final s = buildArrowGlassShape(width: 200, height: 100, radius: 0, placement: Placement.top, tip: 10, tipHalf: 4, tipInset: 20);
      expect(s.box, const Rect.fromLTWH(0, 0, 200, 110));
      expect(s.tipCentre, 100);
      expect(s.d, 'M 0 0 H 200 A 0 0 0 0 1 200 0 V 100 A 0 0 0 0 1 200 100 H 104 L 100 110 L 96 100 H 0 A 0 0 0 0 1 0 100 V 0 A 0 0 0 0 1 0 0 Z');
    });
  });
}
