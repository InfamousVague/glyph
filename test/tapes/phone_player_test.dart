// The phone's player of a note's recording over a fake channel (lib/tapes/phone_player.dart): what it asks the phone's
// half for, and where it tells the half to look. The recordings live under the library since 2026-10-31 and are
// still read from beside it (lib/files/attachment_places.dart), and the half, which opens the file itself
// (TapePlayer.kt, TapeChannel.swift), is handed the folders with each load rather than keep the rule twice.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/tapes/phone_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('ghost_md/tape');
  const events = EventChannel('ghost_md/tape/events');
  final asked = <MethodCall>[];

  setUp(() {
    asked.clear();
    AttachmentPlaces.forget();
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call);
      return switch (call.method) { 'load' => 4200, 'onDevice' => true, _ => null };
    });
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, _) {}));
  });
  tearDown(() {
    AttachmentPlaces.forget();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(events, null);
  });

  const places = AttachmentPlaces(image: ['/data/Library/image', '/data/images'], file: ['/data/Library/file', '/data/images/files'], video: ['/data/Library/video', '/data/video'], recording: ['/data/Library/recordings', '/data/recordings']);

  test('the arguments name the file and, with the core’s answer, the folders to look in', () {
    expect(loadArguments('n1'), {'noteId': 'n1'});
    expect(loadArguments('n1', places: places), {'noteId': 'n1', 'dirs': ['/data/Library/recordings', '/data/recordings']});
    expect(loadArguments('file:5f0c2e9a.mp3', places: places), {'file': '5f0c2e9a.mp3', 'dirs': ['/data/Library/file', '/data/images/files']});
    expect(loadArguments('file:../etc/passwd', places: places), {'file': '', 'dirs': ['/data/Library/file', '/data/images/files']}, reason: 'a name that is not one names nothing, wherever the half looks');
    expect(loadArguments('cached:eleven.mp3', places: places), {'cached': 'eleven.mp3'}, reason: 'the cache has one folder of its own');
  });

  test('a load and an onDevice hand the half the folders the core answered last, as paths, with the id', () async {
    final player = PhoneTapePlayer();
    // Nothing has asked the core yet: the half looks where it did before, with no folders said.
    await player.load('n1');
    expect(asked.single.method, 'load');
    expect(asked.single.arguments, {'noteId': 'n1'});
    expect(player.duration.value, 4200);
    // The core has answered (FilesKit.start asks at launch): every load carries the folders.
    AttachmentPlaces.current = places;
    await player.load('n2');
    expect(asked.last.arguments, {'noteId': 'n2', 'dirs': ['/data/Library/recordings', '/data/recordings']});
    expect(await player.onDevice('n2'), isTrue);
    expect(asked.last.method, 'onDevice');
    expect(asked.last.arguments, {'noteId': 'n2', 'dirs': ['/data/Library/recordings', '/data/recordings']});
    // A sound file a note links looks in the files' folders; a cached sound in none.
    await player.load('file:5f0c2e9a.mp3');
    expect(asked.last.arguments, {'file': '5f0c2e9a.mp3', 'dirs': ['/data/Library/file', '/data/images/files']});
    await player.load('cached:eleven.mp3');
    expect(asked.last.arguments, {'cached': 'eleven.mp3'});
    player.dispose();
  });

  test('the folders are asked of the core again at each load, so a library moved since the launch is followed', () async {
    var answers = 0;
    Future<Object?> core(String command, [Map<String, Object?> args = const {}]) async {
      expect(command, 'attachment_places');
      answers += 1;
      final root = answers == 1 ? '/data/Library' : '/Users/matt/Notes';
      return {'image': ['$root/image', '/data/images'], 'file': ['$root/file', '/data/images/files'], 'video': ['$root/video', '/data/video'], 'recording': ['$root/recordings', '/data/recordings']};
    }

    expect((await AttachmentPlaces.ask(core, dataDir: '/data')).recording, ['/data/Library/recordings', '/data/recordings']);
    expect(AttachmentPlaces.current?.recording, ['/data/Library/recordings', '/data/recordings']);
    final player = PhoneTapePlayer();
    await player.load('n1');
    expect(asked.last.arguments, {'noteId': 'n1', 'dirs': ['/Users/matt/Notes/recordings', '/data/recordings']}, reason: 'the library moved to a folder of the person’s between the launch and the Play');
    expect(answers, 2);
    player.dispose();
  });

  test('a core that cannot say leaves the old folders, and the half is told those', () async {
    Future<Object?> core(String command, [Map<String, Object?> args = const {}]) async => throw StateError('no such command');
    expect(await AttachmentPlaces.ask(core, dataDir: '/data'), AttachmentPlaces.legacy('/data'));
    final player = PhoneTapePlayer();
    await player.load('n1');
    expect(asked.last.arguments, {'noteId': 'n1', 'dirs': ['/data/recordings']});
    player.dispose();
  });
}
