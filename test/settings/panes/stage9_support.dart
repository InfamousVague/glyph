import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';

import 'support.dart';

export 'support.dart';

/// The core as a page test stands in for it (`vi.mock('../core/tauri.ts')` in the web's tests): every command asked
/// is kept, and answered from [answers], where an answer may be a value, a [CoreError] to throw, or a function of the
/// arguments.
class FakeCore {
  final List<({String command, Map<String, Object?> args})> calls = [];
  final Map<String, Object?> answers = {};

  List<String> get commands => [for (final call in calls) call.command];

  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) async {
    calls.add((command: command, args: args));
    final answer = answers[command];
    if (answer is CoreError) throw answer;
    if (answer is Function) return await Function.apply(answer, [args]);
    return answer;
  }
}

/// One page of Settings alone, open, under the real screen: a page that the table of sections does not list yet is
/// drawn as it will be when it does.
Future<void> showPane(WidgetTester tester, String label, WidgetBuilder pane, {SettingsGlyph glyph = SettingsGlyph.folder, Size size = phone}) async {
  await pumpSettings(
    tester,
    SettingsScreen(
      open: true,
      onClose: () {},
      search: false,
      sections: [SettingsSection(id: 'page', label: label, icon: SettingsIcon(glyph, size: 16), content: pane, group: 1)],
      goTo: const SettingsTarget('page', nonce: 1),
    ),
    size: size,
  );
}

/// Everything the page says, each text once, in the order it is drawn.
String pageText(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text, skipOffstage: false))) text.data ?? text.textSpan?.toPlainText() ?? '',
    ].join('\n');

/// The word a row carries as its action ([RowAction]), by what it says.
Finder actionSaying(String word) => find.descendant(of: find.byType(RowAction, skipOffstage: false), matching: find.text(word, skipOffstage: false), skipOffstage: false);

/// Lets futures a page started run to their end, then draws.
Future<void> letRun(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await settleSettings(tester);
}
