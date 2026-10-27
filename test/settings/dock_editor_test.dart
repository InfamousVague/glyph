import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/dock_editor.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/shell/page_dock.dart';
import 'package:glacier/glacier.dart';

import '../shell/dock_support.dart';
import '../support/render.dart';
import 'support.dart' show endSettings;

/// The dock editor (lib/settings/dock_editor.dart; Matt, 2026-10-27: "build the dock editor"), beside a page of
/// notes' dock as the root makes it: what is dragged and switched in the editor is what that dock draws, at once.
void main() {
  const window = Size(390, 1600);

  /// The editor over a page whose dock is the root's for a page of notes (Claude, Search, +, Speak, Settings).
  Future<List<String>> show(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light'), Size size = window}) async {
    setHapticsEnabled(false);
    final asked = <String>[];
    final seam = notesDock(asked);
    await pumpApp(
      tester,
      size: size,
      prefs: prefs,
      home: Stack(
        children: [
          const Positioned.fill(child: SingleChildScrollView(child: Padding(padding: EdgeInsets.fromLTRB(16, 60, 16, 16), child: DockEditor()))),
          Positioned(right: 16, bottom: 16, child: KeyedSubtree(key: const ValueKey('the-dock'), child: PageDock(claude: seam.claude!(null), actions: seam.actions, foot: seam.foot))),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return asked;
  }

  List<String> page(WidgetTester tester) => dockOrder(tester, within: find.byKey(const ValueKey('the-dock')));
  List<String> listed(WidgetTester tester) => [
        for (final element in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('dock-edit:')).evaluate())
          (element.widget.key! as ValueKey<String>).value.substring('dock-edit:'.length),
      ];
  GlacierSwitch toggle(WidgetTester tester, String id) => tester.widget(find.byKey(ValueKey('dock-show:$id')));

  testWidgets('lists every button in the dock’s own order, and the page’s dock is as it always was', (tester) async {
    await show(tester);
    expect(listed(tester), ['claude', 'talk', 'search', 'add', 'speak', 'market', 'settings']);
    expect(page(tester), ['claude', 'search', 'add', 'speak', 'settings']);
    // Nothing chosen, nothing to reset.
    final reset = tester.widget<SettingRow>(find.byKey(const ValueKey('dock-reset')));
    expect((reset.control! as RowAction).disabled, isTrue);
    await endSettings(tester);
  });

  testWidgets('a button dragged by its grip moves in the list and on the dock', (tester) async {
    await show(tester);
    final from = tester.getCenter(find.byKey(const ValueKey('dock-grip:add')));
    final to = tester.getCenter(find.byKey(const ValueKey('dock-grip:claude')));
    final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 230));
    await mouse.moveTo(to - const Offset(0, 4));
    await tester.pump();
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(listed(tester), ['add', 'claude', 'talk', 'search', 'speak', 'market', 'settings']);
    expect(preferences.value.dock.phone.resolved.first, 'add');
    expect(page(tester), ['add', 'claude', 'search', 'speak', 'settings']);
    // And back, by Reset.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dock-reset')), matching: find.byType(RowAction)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(page(tester), ['claude', 'search', 'add', 'speak', 'settings']);
    expect(preferences.value.dock, DockPrefs.defaults);
    await endSettings(tester);
  });

  testWidgets('a button switched off leaves the dock, and on again comes back in its place', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('dock-show:search')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toggle(tester, 'search').checked, isFalse);
    expect(page(tester), ['claude', 'add', 'speak', 'settings']);
    expect(preferences.value.dock.phone.hidden, ['search']);
    // Still listed, to be switched back on.
    expect(listed(tester), contains('search'));
    await tester.tap(find.byKey(const ValueKey('dock-show:search')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(page(tester), ['claude', 'search', 'add', 'speak', 'settings']);
    await endSettings(tester);
  });

  testWidgets('Settings cannot be switched off: its switch is held on and says so', (tester) async {
    await show(tester);
    final settings = toggle(tester, 'settings');
    expect(settings.checked, isTrue);
    expect(settings.disabled, isTrue);
    expect(settings.ariaLabel, contains('always on the dock'));
    expect(find.text('Always on the dock: it is the way back here.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dock-show:settings')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(page(tester), contains('settings'));
    expect(preferences.value.dock.phone.hidden, isEmpty);
    // Everything else off: the dock is Settings alone, still a way here.
    for (final id in ['claude', 'talk', 'search', 'add', 'speak', 'market']) {
      await tester.tap(find.byKey(ValueKey('dock-show:$id')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(page(tester), ['settings']);
    await endSettings(tester);
  });

  testWidgets('a wide window has its own dock once it is asked for, and the phone’s is left as it was', (tester) async {
    await show(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dock-wide-own')), matching: find.byType(GlacierSwitch)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(preferences.value.dock.wide, DockLayout.defaults);
    expect(find.byKey(const ValueKey('dock-editing')), findsOneWidget);
    // The wide one is being edited now: Search off there alone.
    await tester.tap(find.byKey(const ValueKey('dock-show:search')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(preferences.value.dock.wide!.hidden, ['search']);
    expect(preferences.value.dock.phone.hidden, isEmpty);
    // This window is a phone's: its dock keeps Search.
    expect(page(tester), contains('search'));
    expect(preferences.value.dock.layoutFor(wide: true).shows('search'), isFalse);
    await endSettings(tester);
  });

  testWidgets('the Fold opened draws the wide dock', (tester) async {
    await show(tester, size: const Size(900, 1600), prefs: Preferences(theme: 'light', dock: DockPrefs(wide: DockLayout.defaults.showing('add', false))));
    expect(page(tester), ['claude', 'search', 'speak', 'settings']);
    await endSettings(tester);
  });

  testWidgets('in Simple, lists Simple’s four buttons and keeps the wide dock behind More, opened in place', (tester) async {
    await show(tester, prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true));
    expect(listed(tester), ['search', 'add', 'speak', 'settings']);
    expect(find.byKey(const ValueKey('dock-wide-own')), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dock-more')), matching: find.byType(RowAction)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('dock-wide-own')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-more')), findsNothing);
    await endSettings(tester);
  });
}
