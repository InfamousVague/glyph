import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/iphone_page.dart';

import '../support/render.dart';

/// An iPhone's page (lib/app/iphone_page.dart): the phone's text size left alone, and the keyboard's bar with its
/// Done, which the page is laid out above. Nothing of it anywhere else.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the phone’s text size and bold are left alone, and the keyboard’s inset grows by the bar', () {
    const phone = MediaQueryData(size: Size(402, 874), textScaler: TextScaler.linear(1.35), boldText: true, viewInsets: EdgeInsets.only(bottom: 335));
    final page = iPhoneMedia(phone);
    expect(page.textScaler, TextScaler.noScaling);
    expect(page.boldText, isFalse);
    expect(page.viewInsets.bottom, 335 + iPhoneKeyboardBarHeight);
    // With the keyboard down there is no bar, and nothing is kept clear for one.
    expect(iPhoneMedia(phone.copyWith(viewInsets: EdgeInsets.zero)).viewInsets.bottom, 0);
  });

  Future<double> pumpPhone(WidgetTester tester, {required double keyboard}) async {
    late double inset;
    late TextScaler scaler;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester,
      size: const Size(402, 874),
      ratio: 3,
      home: Builder(builder: (context) {
        inset = MediaQuery.viewInsetsOf(context).bottom;
        scaler = MediaQuery.textScalerOf(context);
        return const SizedBox.expand();
      }),
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    await tester.pump();
    if (defaultTargetPlatform == TargetPlatform.iOS) expect(scaler, TextScaler.noScaling);
    return inset;
  }

  testWidgets('an iPhone’s keyboard has a bar with Done, and the page is above both', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await pumpPhone(tester, keyboard: 335), 335 + iPhoneKeyboardBarHeight);
    final done = find.byKey(IPhoneKeyboardBar.doneKey);
    expect(done, findsOneWidget);
    // The bar rests on the keyboard, across the screen.
    final bar = tester.getRect(find.byType(IPhoneKeyboardBar));
    expect(bar, const Rect.fromLTWH(0, 874 - 335 - iPhoneKeyboardBarHeight, 402, iPhoneKeyboardBarHeight));
    expect(find.text('Done'), findsOneWidget);

    // Done tells the phone the keyboard is not wanted.
    final asked = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      asked.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));
    await tester.tap(done);
    await tester.pump();
    expect(asked, contains('TextInput.hide'));

    // The keyboard down: no bar.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(find.byType(IPhoneKeyboardBar), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    // pumpApp draws real shadows; the binding checks its own switch is back as a test ends.
    debugDisableShadows = true;
  });

  testWidgets('no other phone has the bar, or its room', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await pumpPhone(tester, keyboard: 300), 300);
    expect(find.byType(IPhoneKeyboardBar), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  });
}
