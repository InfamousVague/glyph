// The Keyboard modes plugin (lib/plugins/keymaps/keymaps.dart): built in and off until added, within its manifest,
// Vim chosen until another way is, and its page: Off, Vim or Emacs, Vim's two switches only with Vim, and in Simple
// the choice alone with the rest behind More.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/keymaps/keymaps.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:glacier/glacier.dart';

import '../../settings/support.dart';

void main() {
  setUpAll(loadAppFonts);
  late Registry before;
  setUp(() {
    before = plugins;
    useStored(MemoryStored());
  });
  tearDown(() => usePlugins(before));

  test('built in, off until added, asks for nothing past the device', () {
    expect(builtIn, contains(keymapsPlugin));
    final registry = createRegistry(builtIn, store: MemorySwitches());
    expect(registry.isEnabled(keymapsId), isFalse);
    expect(usesNetwork(keymapsManifest), isFalse);
    expect(keymapsManifest.permissions, isEmpty);
    expect(registry.storageKeys(), containsAll([keymapModeKey, vimNormalStartKey, vimJkKey]));
  });

  test('Off while the plugin is; Vim once added, until another way is chosen; Vim\'s switches as they ship', () {
    final registry = createRegistry(builtIn, store: MemorySwitches());
    usePlugins(registry);
    expect(keyboardMode(), KeyboardMode.off);
    registry.setEnabled(keymapsId, true);
    expect(keyboardMode(), KeyboardMode.vim);
    setKeyboardMode(KeyboardMode.emacs);
    expect(keyboardMode(), KeyboardMode.emacs);
    registry.setEnabled(keymapsId, false);
    expect(keyboardMode(), KeyboardMode.off);
    expect(vimStartsNormal(), isTrue);
    expect(vimJk(), isFalse);
    setVimJk(true);
    expect(vimJk(), isTrue);
  });

  testWidgets('its page: the choice, and Vim\'s switches with Vim alone', (tester) async {
    usePlugins(createRegistry(builtIn, store: MemorySwitches({keymapsId: true})));
    await pumpSettings(tester, const SingleChildScrollView(child: KeymapsPane()));
    expect(find.text('Type like'), findsOneWidget);
    expect(find.text('Start notes in Normal mode'), findsOneWidget);
    expect(find.text('jk to leave Insert'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'jk to leave Insert'));
    await tester.pump();
    expect(vimJk(), isTrue);
    setKeyboardMode(KeyboardMode.emacs);
    await tester.pump();
    await settleSettings(tester);
    expect(find.text('Start notes in Normal mode'), findsNothing);
    expect(find.text('Killing and yanking'), findsOneWidget);
    setKeyboardMode(KeyboardMode.off);
    await tester.pump();
    expect(find.text('Killing and yanking'), findsNothing);
    await endSettings(tester);
  });

  testWidgets('in Simple, the choice alone, the rest behind a More that opens in place', (tester) async {
    usePlugins(createRegistry(builtIn, store: MemorySwitches({keymapsId: true})));
    await pumpSettings(tester, const SingleChildScrollView(child: KeymapsPane()), prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true));
    expect(find.text('Type like'), findsOneWidget);
    expect(find.text('Start notes in Normal mode'), findsNothing);
    expect(find.text('More'), findsOneWidget);
    await tester.ensureVisible(find.text('Show'));
    await tester.tap(find.text('Show'));
    await tester.pump();
    await settleSettings(tester);
    expect(find.text('Start notes in Normal mode'), findsOneWidget);
    expect(find.text('More'), findsNothing);
    await endSettings(tester);
  });
}
