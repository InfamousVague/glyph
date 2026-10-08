import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/band/menu_room.dart';

/// `editor/menuRoom.test.ts`, case for case: the room a menu has, from under the status bar to the keyboard's top,
/// 8px in. Then the placing `ContextMenu.tsx` does with it ([placeBand]), by the sums of ContextMenu.test.tsx's
/// "where it sits", which jsdom could only do with sizes it was told: a band 300 by 57, a Style page 100 high.
void main() {
  group('the status bar', () {
    test('reads the inset in px, and nothing where there is none', () {
      expect(statusBar('32px'), 32);
      expect(statusBar(''), 0);
      expect(statusBar(null), 0);
    });

    test('takes an inset it cannot read for none', () {
      expect(statusBar('env(safe-area-inset-top, 0px)'), 0);
    });
  });

  group('the room', () {
    test('starts 8px under the status bar, and 8px under the window’s top with none', () {
      const window = Size(412, 915);
      expect(menuRoom(window: window, statusBar: 32), const MenuRoom(top: 40, bottom: 907, left: 8, right: 404));
      expect(menuRoom(window: window).top, 8);
    });

    test('ends 8px over the keyboard: the visual viewport’s foot', () {
      expect(menuRoom(window: const Size(1024, 768), viewTop: 0, viewHeight: 579).bottom, 571);
    });

    test('starts under a visual viewport panned past the status bar', () {
      final room = menuRoom(window: const Size(1024, 768), statusBar: 40, viewTop: 100, viewHeight: 400);
      expect(room.top, 108);
      expect(room.bottom, 492);
    });
  });

  group('where it sits', () {
    // jsdom's window, a 32px status bar, the caret's box 200 across with its top at `y`.
    MenuRoom room({double? viewHeight}) => menuRoom(window: const Size(1024, 768), statusBar: 32, viewTop: viewHeight == null ? null : 0, viewHeight: viewHeight);
    Held caretAt(double y) => Held(x: 200, y: y, from: 0, to: 4);
    const band = Size(300, 57), styles = Size(300, 100);

    test('over the header, above the caret, when that clears the status bar', () {
      // 130 - 57 - 12: over a header that runs to 98, and clear of the 32px status bar and its 8px.
      expect(placeBand(caretAt(130), band, room()), const Offset(50, 61));
    });

    test('under the caret when above would reach the status bar', () {
      expect(placeBand(caretAt(90), band, room()).dy, 90 + 40);
    });

    test('never past the keyboard’s top', () {
      // The visual viewport is what the keyboard leaves: 150 high here, so the band's foot is held at 142.
      expect(placeBand(caretAt(60), band, room(viewHeight: 150)).dy, 150 - 8 - 57);
    });

    test('places the Style page again, by the same rule', () {
      expect(placeBand(caretAt(130), band, room()).dy, 61);
      // 130 - 100 - 12 would reach the status bar, so the taller page goes under the caret.
      expect(placeBand(caretAt(130), styles, room()).dy, 170);
    });

    // Not the web's cases: the sides, which its tests left to the one `left` above.
    test('keeps inside the room at either side, and to the left where it is wider than the room', () {
      final narrow = menuRoom(window: const Size(390, 844));
      expect(placeBand(const Held(x: 10, y: 400, from: 0, to: 0), band, narrow).dx, 8);
      expect(placeBand(const Held(x: 385, y: 400, from: 0, to: 0), band, narrow).dx, 390 - 8 - 300);
      expect(placeBand(const Held(x: 200, y: 400, from: 0, to: 0), const Size(500, 57), narrow).dx, 8);
    });

    test('takes the band’s size in whole pixels, as the page’s offsetHeight gave it', () {
      expect(offsetSize(const Size(497.516, 56.844)), const Size(498, 57));
    });
  });
}
