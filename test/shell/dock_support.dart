// What the dock's tests share (lib/shell/page_dock.dart): Claude's ring as a test has it, a page of notes' dock as
// the root makes it, and the dock's order and place read back.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart' show Lucide;
import 'package:ghost_md/home/home_icons.dart';
import 'package:ghost_md/shell/page_dock.dart';
import 'package:glacier/glacier.dart';

/// Claude's ring as a test has it: a button of the ring's size that writes down what it was asked about, as
/// `claude` or `claude <subject>`.
DockClaudeBuilder fakeClaude(List<String> asked) => (subject) => GlacierPressable(
      key: const ValueKey('dock-claude'),
      semanticLabel: 'Ask Claude',
      onPressed: () => asked.add('claude ${subject?.call() ?? ''}'.trim()),
      builder: (context, state) => SizedBox.square(dimension: context.tokens.len('app-ring')),
    );

/// A page of notes' dock as the root makes it (lib/root/root_parts.dart `_notesDock`), writing down each press.
PageDockSeam notesDock(List<String> asked) => PageDockSeam(
      claude: fakeClaude(asked),
      actions: [
        DockAction(id: 'search', label: 'Search and commands', glyph: HomeGlyph.magnifier, motion: DockMotion.lean, onPressed: () => asked.add('search')),
        DockAction(id: 'add', label: 'Write a note', glyph: HomeGlyph.plus, motion: DockMotion.turn, onPressed: () => asked.add('new')),
        DockAction(id: 'speak', label: 'Speak a voice note', glyph: HomeGlyph.mic, ink: true, onPressed: () => asked.add('speak')),
      ],
      foot: DockAction(id: 'settings', label: 'Settings', icon: Lucide.settings, onPressed: () => asked.add('settings')),
    );

final RegExp _ring = RegExp(r'^dock-[a-z-]+$');

/// The dock's rings, head to foot, by their ids (`dock-<id>`, less `dock-`): the one [within] where given.
List<String> dockOrder(WidgetTester tester, {Finder? within}) => [
      for (final ring in find
          .descendant(
            of: within == null ? find.byType(PageDock) : find.descendant(of: within, matching: find.byType(PageDock)),
            matching: find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && _ring.hasMatch((widget.key! as ValueKey<String>).value) && !(widget.key! as ValueKey<String>).value.endsWith('-badge')),
          )
          .evaluate())
        (ring.widget.key! as ValueKey<String>).value.substring('dock-'.length),
    ];

/// Each ring pressed, head to foot.
Future<void> pressAll(WidgetTester tester) async {
  for (final id in dockOrder(tester)) {
    await tester.tap(find.byKey(ValueKey('dock-$id')));
    await tester.pump();
  }
}

/// Whether the dock shows now: not stepped aside.
bool dockShown(WidgetTester tester) => tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('page-dock'))).opacity == 1;

/// The dock stands in the window's bottom end corner, in by the safe areas and `--glacier-space-4`, as the home
/// page's does.
void expectInCorner(WidgetTester tester, {Size window = const Size(390, 844)}) {
  final dock = find.byType(PageDock);
  final t = GlacierTheme.of(tester.element(dock));
  final rect = tester.getRect(dock);
  expect(rect.right, closeTo(window.width - t.len('app-safe-right') - t.space(4), 0.01));
  expect(rect.bottom, closeTo(window.height - t.len('app-safe-bottom') - t.space(4), 0.01));
}

/// Ends a test that drew with real shadows (`pumpApp` turns them on, and the binding checks the switch as it ends).
Future<void> done(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
