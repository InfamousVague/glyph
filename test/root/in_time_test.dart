// What the app's start waits for and no longer (lib/root/voice_wiring.dart `inTime`).
//
// Differs 7 (docs/PARITY.md): the phone's half of voice was given three seconds to attach, and a phone slower than
// that had no recorder and no AI in any note for the whole run (lib/main.dart). The app still opens after three
// seconds, and now takes voice when it comes.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/root/voice_wiring.dart';

void main() {
  testWidgets('what comes in time is had at once, and nothing is waited for after', (tester) async {
    final making = Completer<String>();
    ({String? now, Future<String?>? later})? answered;
    unawaited(inTime(making.future).then((it) => answered = it));
    await tester.pump(const Duration(seconds: 1));
    expect(answered, isNull);
    making.complete('voice');
    await tester.pump();
    expect(answered!.now, 'voice');
    expect(answered!.later, isNull);
  });

  testWidgets('what is slower than three seconds is not waited for, and is had when it comes', (tester) async {
    final making = Completer<String>();
    ({String? now, Future<String?>? later})? answered;
    unawaited(inTime(making.future).then((it) => answered = it));
    await tester.pump(const Duration(milliseconds: 2900));
    expect(answered, isNull, reason: 'three seconds are given');
    await tester.pump(const Duration(milliseconds: 200));
    expect(answered, isNotNull, reason: 'and no more');
    expect(answered!.now, isNull);
    String? came;
    unawaited(answered!.later!.then((it) => came = it));
    await tester.pump(const Duration(seconds: 20));
    expect(came, isNull);
    making.complete('voice');
    await tester.pump();
    expect(came, 'voice');
  });

  testWidgets('what fails is said and is nothing, in time or after it, and never an error nobody catches', (tester) async {
    final said = <Object>[];
    final quick = Completer<String>();
    ({String? now, Future<String?>? later})? answered;
    unawaited(inTime(quick.future, failed: said.add).then((it) => answered = it));
    quick.completeError(StateError('no service'));
    await tester.pump();
    expect((answered!.now, answered!.later), (null, null));
    expect(said, hasLength(1));

    final slow = Completer<String>();
    answered = null;
    unawaited(inTime(slow.future, failed: said.add).then((it) => answered = it));
    await tester.pump(const Duration(seconds: 4));
    var came = false;
    String? what = 'unset';
    unawaited(answered!.later!.then((it) {
      came = true;
      what = it;
    }));
    slow.completeError(StateError('gone'));
    await tester.pump();
    expect((came, what), (true, null));
    expect(said, hasLength(2));
  });
}
