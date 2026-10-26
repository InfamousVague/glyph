// The keys the web build's app answers (lib/app/ghost_app.dart `pageShortcuts`): never the page's scroll by the
// space bar or the arrows, which the note's editor, being no EditableText, would not get back (docs/WEB.md).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart' show pageShortcuts;

void main() {
  test('the space bar, the arrows and the page keys are left to what has the focus', () {
    expect(pageShortcuts.values.whereType<ScrollIntent>(), isEmpty);
    expect(pageShortcuts.values.whereType<PrioritizedIntents>(), isEmpty);
    final keys = [for (final activator in pageShortcuts.keys) (activator as SingleActivator).trigger];
    for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.pageUp, LogicalKeyboardKey.pageDown]) {
      expect(keys, isNot(contains(key)), reason: key.keyLabel);
    }
    expect(pageShortcuts[const SingleActivator(LogicalKeyboardKey.space)], isA<ActivateIntent>());
    expect(pageShortcuts[const SingleActivator(LogicalKeyboardKey.escape)], isA<DismissIntent>());
  });
}
