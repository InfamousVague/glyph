// A picture chosen on the phone (lib/core/phone_pictures.dart): `pickNative` of core/images.ts, with the phone's
// chooser a channel this file answers and the core a function that keeps what it was sent.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/native/files.dart';
import 'package:ghost_md/core/phone_pictures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <({String command, Map<String, Object?> args})>[];
  Object? Function(MethodCall call)? phone;

  Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
    sent.add((command: command, args: args));
    if (args['path'] == '/cache/picked/not-a-picture.jpg') throw StateError('That is not a picture Glyph can add.');
    return null;
  }

  setUp(() {
    sent.clear();
    phone = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, (call) async => phone!(call));
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, null));

  PicturePicker picker() => phonePicturePicker(corePictureAdopter(CoreFiles(core), name: () => '0f8fad5b-d9cb-469f-a165-70867728950e'));

  test('a picture chosen is moved among the library\'s pictures under a fresh name, which is answered', () async {
    phone = (call) => call.method == 'pick' ? <String, Object?>{'path': '/cache/picked/a.jpg'} : null;
    expect(await picker()(), '0f8fad5b-d9cb-469f-a165-70867728950e.jpg');
    expect(sent.single.command, 'sync_put_file_path');
    expect(sent.single.args, {'kind': 'image', 'name': '0f8fad5b-d9cb-469f-a165-70867728950e.jpg', 'path': '/cache/picked/a.jpg'});
  });

  test('none chosen is null, and nothing is kept', () async {
    phone = (_) => <String, Object?>{'cancelled': true};
    expect(await picker()(), isNull);
    expect(sent, isEmpty);
  });

  test('what goes wrong is a sentence for the note', () async {
    phone = (_) => throw PlatformException(code: 'unread', message: 'That picture could not be read.');
    await expectLater(picker()(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'That picture could not be read.')));
    phone = (_) => throw PlatformException(code: 'none', message: 'This phone has no picture picker.');
    await expectLater(picker()(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'This phone has no picture picker.')));
    phone = (_) => <String, Object?>{'path': '/cache/picked/not-a-picture.jpg'};
    await expectLater(picker()(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'That is not a picture Glyph can add.')));
  });

  test('a run with no phone half says the build cannot add pictures', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, null);
    await expectLater(picker()(), throwsA(isA<StateError>().having((e) => e.message, 'message', cannotAddPictures)));
  });

  test('a fresh name is a version 4 UUID and .jpg, as the core names a picture it keeps', () async {
    final name = await corePictureAdopter(CoreFiles(core))('/cache/picked/b.jpg');
    expect(name, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$')));
  });
}
