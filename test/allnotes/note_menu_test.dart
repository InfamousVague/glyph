import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:ghost_md/main.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/render.dart';
import 'support.dart';

/// A note's menu at the pointer (lib/notes/note_menu.dart), after the web's `notes/NoteMenu.test.tsx`: what it
/// offers, what each row does, how it closes, and where it stands, held to the page (Chromium, 1000x800, a mouse's
/// right-click at 306, 270 on the second card of All notes, dark).
void main() {
  setUpAll(loadAppFonts);

  final groceries = makeNote('g', body: '# Groceries\n\n- [ ] Milk\n');

  Future<({NoteMenuController menu, List<String> said, BackStack back})> host(WidgetTester tester, {List<Note>? notes, bool comment = false, bool coarse = false, Size size = const Size(1000, 800), String theme = 'dark'}) async {
    final menu = NoteMenuController();
    final said = <String>[];
    final back = BackStack();
    final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: theme),
      home: RootStamps(
        sheet: sheet!,
        stamps: const {'split': 'on'},
        child: BackScope(
          stack: back,
          child: Stack(
            children: [
              const Positioned.fill(child: SizedBox.expand()),
              NoteMenuHost(
                controller: menu,
                notes: notes ?? [groceries],
                coarse: coarse,
                onOpen: (note) => said.add('open ${note.id}'),
                onComment: comment ? (note) => said.add('comment ${note.id}') : null,
                onPin: (note) => said.add('pin ${note.id}'),
                onArchive: (note, archived) => said.add('${archived ? 'archive' : 'unarchive'} ${note.id}'),
                onDelete: (note) => said.add('delete ${note.id}'),
              ),
            ],
          ),
        ),
      ),
    );
    return (menu: menu, said: said, back: back);
  }

  List<String> rows(WidgetTester tester) => [for (final item in tester.widgetList<GlacierMenuItem>(find.byType(GlacierMenuItem))) ((item.child as Text).data!)];

  Future<void> open(WidgetTester tester, NoteMenuController menu, [String id = 'g', Offset at = const Offset(10, 10)]) async {
    menu.open(id, at);
    await settle(tester);
  }

  testWidgets('offers Open, Pin, Archive and Delete, Delete in the danger tone', (tester) async {
    final it = await host(tester);
    expect(find.byType(GlacierMenuItem), findsNothing);
    await open(tester, it.menu);
    expect(rows(tester), ['Open', 'Pin', 'Archive', 'Delete']);
    expect(tester.widget<GlacierMenu>(find.byType(GlacierMenu)).ariaLabel, 'Groceries, note');
    final delete = tester.widget<GlacierMenuItem>(find.widgetWithText(GlacierMenuItem, 'Delete'));
    expect(delete.danger, isTrue);
    // In the app's one red, the row and its icon, past the kit's own danger text.
    final red = GlacierTheme.of(tester.element(find.byType(GlacierMenu))).color('glacier-red-11');
    expect(delete.style?.color, red);
    expect(delete.style?.iconColor, red);
    await away(tester);
  });

  testWidgets('offers Add a comment second, where the app can start one, for the note it was opened on', (tester) async {
    final it = await host(tester, comment: true);
    await open(tester, it.menu);
    expect(rows(tester), ['Open', 'Add a comment', 'Pin', 'Archive', 'Delete']);
    await tester.tap(find.text('Add a comment'));
    await settle(tester);
    expect(it.said, ['comment g']);
    expect(find.byType(GlacierMenuItem), findsNothing);
    expect(it.menu.value, isNull);
    await away(tester);
  });

  testWidgets('deletes the note it was opened on, and closes', (tester) async {
    final it = await host(tester);
    await open(tester, it.menu);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(it.said, ['delete g']);
    expect(find.byType(GlacierMenuItem), findsNothing);
    expect(it.menu.value, isNull);
    await away(tester);
  });

  testWidgets('each row does its own: open, pin, archive', (tester) async {
    final it = await host(tester);
    for (final row in ['Open', 'Pin', 'Archive']) {
      await open(tester, it.menu);
      await tester.tap(find.text(row));
      await settle(tester);
    }
    expect(it.said, ['open g', 'pin g', 'archive g']);
    await away(tester);
  });

  testWidgets('closes on the back gesture, which it alone takes', (tester) async {
    final it = await host(tester);
    await open(tester, it.menu, 'g', const Offset(120, 80));
    expect(it.menu.value, const NoteMenuAt(id: 'g', x: 120, y: 80));
    expect(it.back.goBack(), isTrue);
    await settle(tester);
    expect(it.menu.value, isNull);
    expect(find.byType(GlacierMenuItem), findsNothing);
    await away(tester);
  });

  testWidgets('closes on a press anywhere else, and a right-click there opens the next', (tester) async {
    final it = await host(tester);
    await open(tester, it.menu);
    // The right-click that follows the press opens the menu again, somewhere else, before the close is heard.
    final press = await tester.startGesture(const Offset(700, 600), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    it.menu.open('g', const Offset(200, 150));
    await press.up();
    await settle(tester);
    expect(it.menu.value, const NoteMenuAt(id: 'g', x: 200, y: 150));
    expect(find.byType(GlacierMenu), findsOneWidget);
    await tester.tapAt(const Offset(700, 600));
    await settle(tester);
    expect(it.menu.value, isNull);
    await away(tester);
  });

  testWidgets('says Unpin and Unarchive for a note pinned and archived', (tester) async {
    final kept = groceries.copyWith(starred: true, archivedAt: () => 5);
    final it = await host(tester, notes: [kept]);
    await open(tester, it.menu);
    expect(rows(tester), ['Open', 'Unpin', 'Unarchive', 'Delete']);
    await tester.tap(find.text('Unarchive'));
    await settle(tester);
    expect(it.said, ['unarchive g']);
    await away(tester);
  });

  testWidgets('draws nothing for a note no longer there', (tester) async {
    final it = await host(tester);
    await open(tester, it.menu, 'gone');
    expect(find.byType(GlacierMenu), findsNothing);
    await away(tester);
  });

  test('takes a mouse where the pointer says so, and a fine pointer that hovers where it does not', () {
    expect(byMouse(PointerDeviceKind.mouse), isTrue);
    expect(byMouse(PointerDeviceKind.touch), isFalse);
    expect(byMouse(null, fine: true), isTrue);
    expect(byMouse(null, fine: false), isFalse);
  });

  testWidgets('stands where the page’s does: its corner 8px under the pointer, 192 wide, its rows 40.94 tall', (tester) async {
    final it = await host(tester, comment: true);
    await open(tester, it.menu, 'g', const Offset(306, 270));
    void at(Rect rect, double left, double top, double width, double height, String reason) {
      expect(rect.left, closeTo(left, 0.5), reason: '$reason left');
      expect(rect.top, closeTo(top, 0.5), reason: '$reason top');
      expect(rect.width, closeTo(width, 0.5), reason: '$reason width');
      expect(rect.height, closeTo(height, 0.5), reason: '$reason height');
    }

    Rect row(String label) => tester.getRect(find.widgetWithText(GlacierMenuItem, label));
    at(row('Open'), 312, 284, 180, 40.94, 'Open');
    at(row('Add a comment'), 312, 325.94, 180, 40.94, 'Add a comment');
    at(row('Pin'), 312, 367.88, 180, 40.94, 'Pin');
    at(row('Archive'), 312, 409.81, 180, 40.94, 'Archive');
    // The kit's menu puts its rule half a pixel lower than the page's (13.55 from Archive to Delete, where the page
    // has 13.03: two spaces, the rule and three gaps of a pixel). The kit's own, and so held a little looser.
    final rule = tester.getRect(find.descendant(of: find.byType(GlacierMenuSeparator), matching: find.byType(ColoredBox)));
    expect([rule.left, rule.width, rule.height], [closeTo(322.02, 0.5), closeTo(159.97, 0.5), closeTo(1, 0.01)]);
    expect(rule.top, closeTo(456.75, 0.75));
    expect(row('Delete').top, closeTo(463.75, 0.75));
    expect(row('Delete').height, closeTo(40.94, 0.5));
    await shot(tester, 'note-menu-dark');
  });

  testWidgets('a finger’s rows are a thumb’s height, on a phone', (tester) async {
    final it = await host(tester, coarse: true, size: const Size(390, 844), theme: 'light');
    await open(tester, it.menu, 'g', const Offset(60, 300));
    expect(tester.getSize(find.widgetWithText(GlacierMenuItem, 'Open')).height, greaterThanOrEqualTo(44));
    await shot(tester, 'note-menu-phone-light');
  });
}
