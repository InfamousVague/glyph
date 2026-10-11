import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/keep_keyboard.dart';

/// The keyboard that was up when the app was left is asked for again when it is come back to, as the web app's
/// page has it back (core/keep_keyboard.dart).
void main() {
  Future<List<String>> leaveAndReturn(WidgetTester tester, {required bool keyboardUp, required bool focused}) async {
    final asked = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      asked.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));
    KeepKeyboard.install();
    addTearDown(KeepKeyboard.remove);
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Focus(focusNode: node, child: const SizedBox.expand())));
    if (focused) node.requestFocus();
    await tester.pump();
    if (keyboardUp) {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Android takes the keyboard down as the app leaves.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    asked.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(KeepKeyboard.again + const Duration(milliseconds: 10));
    return asked;
  }

  testWidgets('a keyboard that was up comes back with the app, asked for twice', (tester) async {
    final asked = await leaveAndReturn(tester, keyboardUp: true, focused: true);
    expect(asked.where((m) => m == 'TextInput.show'), hasLength(2));
  });

  testWidgets('none is raised where none was up', (tester) async {
    expect(await leaveAndReturn(tester, keyboardUp: false, focused: true), isNot(contains('TextInput.show')));
  });

  testWidgets('nor where nothing holds the focus any more', (tester) async {
    expect(await leaveAndReturn(tester, keyboardUp: true, focused: false), isNot(contains('TextInput.show')));
  });
}
