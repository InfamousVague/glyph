import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/sheet/sheet_drag.dart';

/// `editor/sheetDrag.test.tsx`, case for case: a sheet taken by its handle. Pulled down it follows the finger, and
/// let go far enough down - or flicked - it closes; pulled up it gives a little and never far; let go short, it
/// springs back. Every bottom sheet's grip is this.
void main() {
  late double offset;
  late bool sprung;
  late int closed;
  late double now;
  late SheetDrag drag;

  setUp(() {
    offset = 0;
    sprung = false;
    closed = 0;
    now = 0;
    drag = SheetDrag(
      onMove: (dy, {required animated}) {
        offset = dy;
        sprung = animated;
      },
      onClose: () => closed += 1,
    );
  });

  /// A pointer event on the grip, [ms] after the last one.
  void down(double y, {double ms = 16, bool primary = true}) => drag.down(y, now += ms, primary: primary);
  void move(double y, {double ms = 16}) => drag.move(y, now += ms);
  void up(double y, {double ms = 16}) => drag.end(y, now += ms);

  test('follows the finger down, and closes when let go past 96 px', () {
    down(100);
    move(150, ms: 200);
    expect(offset, 50);
    move(200, ms: 200);
    up(200, ms: 200);
    expect(closed, 1);
    expect(offset, 0);
  });

  test('springs back when let go short of it, slowly', () {
    down(100);
    move(160, ms: 400);
    up(160, ms: 400);
    expect(closed, 0);
    expect(offset, 0);
    expect(sprung, isTrue);
  });

  test('closes on a flick that ends fast, though it covered little ground', () {
    down(100);
    move(110, ms: 300);
    // 30 px in the last 20 ms: 1.5 px/ms, three times what a flick needs.
    up(140, ms: 20);
    expect(closed, 1);
  });

  test('does not close on a quick nudge of under 24 px', () {
    down(100);
    up(120, ms: 5);
    expect(closed, 0);
  });

  test('gives when pulled up, less and less, and never as far as 28 px', () {
    down(300);
    move(280);
    final little = offset;
    move(0);
    final far = offset;
    expect(little, lessThan(0));
    expect(far, lessThan(little));
    expect(far, greaterThan(-28));
  });

  test('ignores a second finger', () {
    down(100, primary: false);
    move(300);
    up(300);
    expect(offset, 0);
    expect(closed, 0);
    expect(drag.held, isFalse);
  });

  test('says its spring as the page writes it', () {
    expect(SheetDrag.springDuration, const Duration(milliseconds: 220));
    expect(SheetDrag.springCurve.transform(0), 0);
    expect(SheetDrag.springCurve.transform(1), 1);
    // cubic-bezier(0.2, 0.9, 0.3, 1): most of the way there in the first third.
    expect(SheetDrag.springCurve.transform(0.33), greaterThan(0.8));
  });
}
