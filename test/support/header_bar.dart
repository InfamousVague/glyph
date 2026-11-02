import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/shell/header_toolbar.dart';

/// The controls the header toolbar keeps behind the round button for you (lib/shell/header/header_kit.dart
/// `youEntries`): the bell, the organizations and Settings.
const Set<String> heldByYou = {'bell', 'organizations', 'settings'};

Future<void> _beat(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Presses the bar's control [id] (lib/shell/header_toolbar.dart's `HeaderAct.id`: `more`, `aside`, `links` …)
/// by its [label] where something answers to it, by its key where the line draws it, or its row under the menu that
/// holds it: the button for you's for the bell, the organizations and Settings ([heldByYou]), else the bar's •••
/// where the line puts it away (on a phone).
Future<void> pressInBar(WidgetTester tester, String id, {required String label}) async {
  final ring = find.bySemanticsLabel(label);
  final own = find.byKey(HeaderAct.keyOf(id));
  if (ring.evaluate().isNotEmpty) {
    await tester.tap(ring.first);
  } else if (own.evaluate().isNotEmpty) {
    await tester.tap(own.last);
  } else {
    await openBarMenu(tester, heldByYou.contains(id) ? 'you' : 'overflow');
    await tester.tap(find.byKey(HeaderAct.keyOf(id)).last);
  }
  await _beat(tester);
}

/// Opens the bar's menu under [id]: `you`, the round button for you, or `overflow`, the line's •••.
Future<void> openBarMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(HeaderAct.keyOf(id)).last);
  await _beat(tester);
}
