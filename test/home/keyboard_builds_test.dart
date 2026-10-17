// A keyboard coming up over the home page (search opened over it, on a phone) builds the page when what it draws
// by the keyboard changes (whether it is up at all), not at every frame of its rise: the page asked the window for
// the keyboard's height, and its cards for the window's size, whose height the page under the keyboard is told
// anew at each of those frames (lib/home/home_screen.dart `_KeyboardWatch`, `_AboveKeyboard`; lib/home/note_card.dart).
//
// Counted by the framework's own word for an element built again (`debugOnRebuildDirtyWidget`), over twelve frames
// of a keyboard rising and twelve of it going. The page still ends at the keyboard, less the phone's bar, at every
// frame.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/root/ghost_root.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the home page and its cards are not built again at every frame of the keyboard', (tester) async {
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NoteCard), findsWidgets);
    final cards = find.byType(NoteCard).evaluate().length;
    final counted = <Type, int>{NoteCard: 0, SliverNoteCards: 0};
    final ratio = tester.view.devicePixelRatio;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final type = element.widget.runtimeType;
      if (counted.containsKey(type)) counted[type] = counted[type]! + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final scroll = tester.renderObject<RenderBox>(find.descendant(of: find.byType(HomeScreen), matching: find.byType(CustomScrollView)).first);
    double foot() => scroll.localToGlobal(Offset(0, scroll.size.height)).dy;
    final window = foot();
    for (var i = 1; i <= 12; i++) {
      tester.view.viewInsets = FakeViewPadding(bottom: i * 25 * ratio);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // With the keyboard 300 up, the page ends 300 above where it ended, less the phone's bar it always stands clear
    // of: what stood over the bar stands over the keys.
    final bar = (tester.view.viewPadding.bottom / ratio).ceilToDouble();
    expect(foot(), closeTo(window - (300 - bar), 0.5), reason: 'the page ends the bar\'s height into the keyboard');
    for (var i = 11; i >= 0; i--) {
      tester.view.viewInsets = FakeViewPadding(bottom: i * 25 * ratio);
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    tester.view.resetViewInsets();
    // ignore: avoid_print
    print('home through a keyboard up and down, 24 frames, $cards cards on the page: $counted');
    // The page draws nothing by the keyboard now (the room for the phone's bar stays): at most a card that comes
    // near the window's foot as the keyboard leaves it. (Before: 84 for three cards, 24 for their list; then each
    // card twice, as the bar's room went and came back.)
    expect(counted[NoteCard], lessThan(cards * 4), reason: 'a card is built when the keyboard is up or gone, not at each frame between: $counted');
    expect(counted[SliverNoteCards], lessThanOrEqualTo(4), reason: 'the cards’ lists likewise: $counted');
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
