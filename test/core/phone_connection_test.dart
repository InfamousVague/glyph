// The phone's connection as the app reads it (lib/core/phone_connection.dart), against a phone played on its
// channel: what `navigator.onLine` and the window's `online` event were to the page.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/phone_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  /// The phone says [word] on the channel, as Connection.kt does.
  Future<void> phoneSays(String word) => messenger.handlePlatformMessage(connectionChannel.name, codec.encodeMethodCall(MethodCall(word)), (_) {});

  tearDown(() => messenger.setMockMethodCallHandler(connectionChannel, null));

  test('is online until the phone says otherwise, asks once how things stand, and tells of a connection coming back', () async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(connectionChannel, (call) async {
      asked.add(call.method);
      return false;
    });
    final connection = PhoneConnection();
    expect(connection.onLine, isTrue);
    connection.start();
    await Future<void>.delayed(Duration.zero);
    expect(asked, ['online']);
    expect(connection.onLine, isFalse, reason: 'the phone answered that it has none');

    var back = 0;
    final stop = connection.onOnline(() => back += 1);
    await phoneSays('online');
    expect((connection.onLine, back), (true, 1));
    // Said again with a connection already there (one network taking another's place): not a return.
    await phoneSays('online');
    expect(back, 1);
    await phoneSays('offline');
    expect((connection.onLine, back), (false, 1));
    stop();
    await phoneSays('online');
    expect((connection.onLine, back), (true, 1));
  });

  test('with no phone half behind the channel there is always a connection', () async {
    final connection = PhoneConnection().start();
    await Future<void>.delayed(Duration.zero);
    expect(connection.onLine, isTrue);
  });
}
