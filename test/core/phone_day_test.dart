// Pick a date over the phone's calendar (lib/core/phone_day.dart): the channel is this file's to answer.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/phone_day.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final asked = <MethodCall>[];
  Object? answer;

  setUp(() {
    asked.clear();
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dayChannel, (call) async {
      asked.add(call);
      return answer;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dayChannel, null));

  test('opens on the day a field has and answers the day chosen', () async {
    answer = '2026-10-12';
    expect(await phoneDayPicker(Offset.zero, '2026-10-09'), '2026-10-12');
    expect(asked.single.method, 'pick');
    expect(asked.single.arguments, {'current': '2026-10-09'});
  });

  test('opens on today for a field with no day, or one that is not a day', () async {
    answer = '2026-10-12';
    await phoneDayPicker(Offset.zero, null);
    await phoneDayPicker(Offset.zero, 'next week');
    expect([for (final call in asked) call.arguments], [<String, Object?>{}, <String, Object?>{}]);
  });

  test('a calendar left without a day, an answer that is not one, and no phone half all pick nothing', () async {
    expect(await phoneDayPicker(Offset.zero, null), isNull);
    answer = 'tomorrow';
    expect(await phoneDayPicker(Offset.zero, null), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(dayChannel, null);
    expect(await phoneDayPicker(Offset.zero, null), isNull);
  });
}
