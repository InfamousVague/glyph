// A film chosen on the phone and a film played (lib/core/phone_films.dart, lib/core/films.dart): `pickVideo` of
// core/videos.ts, with the phone's picker and its player channels this file answers and the core a function that
// keeps what it was sent.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/films.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/phone_films.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sent = <({String command, Map<String, Object?> args})>[];
  final told = <String>[];
  Future<Object?> Function(MethodCall call)? phone;
  var here = true;

  Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
    sent.add((command: command, args: args));
    if (command == 'save_video' && args['path'] == '/cache/picked/bad.mp4') throw const CoreError('The video couldn’t be kept.');
    if (command == 'save_video') return <String, Object?>{'video': 'kept.mp4', 'poster': 'still.jpg'};
    if (command == 'file_exists') return here;
    return null;
  }

  const picked = <String, Object?>{'path': '/cache/picked/a.mp4', 'poster': '/cache/picked/a.jpg', 'ms': 12400, 'width': 1080, 'height': 1920};

  setUp(() {
    sent.clear();
    told.clear();
    phone = null;
    here = true;
    messenger.setMockMethodCallHandler(filmsChannel, (call) => phone!(call));
    messenger.setMockMethodCallHandler(filmChannel, (call) async {
      told.add('${call.method} ${(call.arguments as Map)['id'] ?? (call.arguments as Map)['name']}');
      if (call.method == 'open') return <String, Object?>{'id': told.where((t) => t.startsWith('open')).length, 'width': 1920, 'height': 1080, 'ms': 12000, 'turn': 0};
      return null;
    });
    messenger.setMockStreamHandler(filmEvents, MockStreamHandler.inline(onListen: (_, _) {}));
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(filmsChannel, null);
    messenger.setMockMethodCallHandler(filmChannel, null);
    messenger.setMockStreamHandler(filmEvents, null);
  });

  Future<void> say(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(filmEvents.name, const StandardMethodCodec().encodeSuccessEnvelope(event), (_) {});
  }

  group('picking', () {
    test('a film chosen is adopted with its poster, and answered by the names the core gave them', () async {
      final kept = <String>[];
      phone = (_) async => picked;
      final film = await phoneFilmPicker(core, kept: kept.add)();
      expect((film!.video, film.poster, film.ms, film.width, film.height), ('kept.mp4', 'still.jpg', 12400, 1080.0, 1920.0));
      expect(sent.single.command, 'save_video');
      expect(sent.single.args, {'path': '/cache/picked/a.mp4', 'poster': '/cache/picked/a.jpg'});
      expect(kept, ['kept.mp4']);
    });

    test('none chosen is null, and nothing is kept', () async {
      phone = (_) async => <String, Object?>{'cancelled': true};
      expect(await phoneFilmPicker(core)(), isNull);
      expect(sent, isEmpty);
    });

    test('a film no longer wanted once it is copied is thrown away with its poster, never kept', () async {
      phone = (_) async => picked;
      expect(await phoneFilmPicker(core)(keep: () => false), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(sent.map((call) => (call.command, call.args['path'])), [('discard_picked', '/cache/picked/a.mp4'), ('discard_picked', '/cache/picked/a.jpg')]);
    });

    test('the phone says when the copy starts, and only the pick that is waiting hears it', () async {
      var copies = 0;
      phone = (_) async {
        await messenger.handlePlatformMessage(filmsChannel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('copying')), (_) {});
        return picked;
      };
      final pick = phoneFilmPicker(core);
      await pick(copying: () => copies += 1);
      expect(copies, 1);
      // Said again with no pick waiting: nobody is told.
      await messenger.handlePlatformMessage(filmsChannel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('copying')), (_) {});
      expect(copies, 1);
    });

    test('a second pick while the first is still being copied is refused', () async {
      phone = (_) => Future<Object?>.delayed(const Duration(milliseconds: 20), () => picked);
      final pick = phoneFilmPicker(core);
      final first = pick();
      await expectLater(pick(), throwsA(isA<StateError>().having((e) => e.message, 'message', stillAdding)));
      expect((await first)!.video, 'kept.mp4');
      // And the next is asked again.
      expect((await pick())!.video, 'kept.mp4');
    });

    test('what goes wrong is a sentence for the note', () async {
      phone = (_) => throw PlatformException(code: 'unkept', message: 'This kind of video can’t be added. MP4, MOV and WebM can.');
      await expectLater(phoneFilmPicker(core)(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'This kind of video can’t be added. MP4, MOV and WebM can.')));
      phone = (_) async => <String, Object?>{'path': '/cache/picked/bad.mp4', 'poster': '/cache/picked/bad.jpg'};
      await expectLater(phoneFilmPicker(core)(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'The video couldn’t be kept.')));
      phone = (_) async => <String, Object?>{'path': 7};
      await expectLater(phoneFilmPicker(core)(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'This video can’t be read.')));
    });

    test('a run with no phone half says so', () async {
      messenger.setMockMethodCallHandler(filmsChannel, null);
      await expectLater(phoneFilmPicker(core)(), throwsA(isA<StateError>().having((e) => e.message, 'message', cannotAddVideos)));
    });
  });

  group('where a film stands', () {
    test('is asked of the core once and kept, a film just kept is here, and one gone is gone until asked afresh', () async {
      final films = Films(device: PhoneFilmDevice(core, plays: true));
      expect(await films.isHere('a.mp4'), isTrue);
      here = false;
      expect(await films.isHere('a.mp4'), isTrue, reason: 'asked once');
      expect(sent.where((call) => call.command == 'file_exists').single.args, {'kind': 'video', 'name': 'a.mp4'});
      expect(await films.isHere('b.mp4'), isFalse);
      films.kept('b.mp4');
      expect(await films.isHere('b.mp4'), isTrue);
      // A film that would not play is asked again before it is said to be gone.
      expect(await films.stillHere('a.mp4'), isFalse);
      expect(await films.isHere('a.mp4'), isFalse);
      here = true;
      expect(await films.stillHere('a.mp4'), isTrue);
    });
  });

  group('playing', () {
    test('a film is opened by its name, hears its own events, and is let go once', () async {
      final device = PhoneFilmDevice(core, plays: true);
      final film = await device.open('a.mp4') as PhoneFilm;
      expect((film.id, film.width, film.height, film.durationMs), (1, 1920, 1080, 12000));
      film.play();
      await say({'event': 'playing', 'id': 1, 'on': true});
      await say({'event': 'position', 'id': 1, 'ms': 3400});
      // Another film's events are not this one's.
      await say({'event': 'position', 'id': 9, 'ms': 9000});
      expect((film.playing.value, film.position.value), (true, 3400));
      await say({'event': 'ended', 'id': 1});
      expect(film.playing.value, isFalse);
      await say({'event': 'failed', 'id': 1});
      expect(film.failed.value, isTrue);
      film.close();
      film.close();
      film.play();
      await Future<void>.delayed(Duration.zero);
      expect(told, ['open a.mp4', 'play 1', 'close 1']);
    });

    test('starting one film pauses the one playing', () async {
      final device = PhoneFilmDevice(core, plays: true);
      final first = await device.open('a.mp4'), second = await device.open('b.mp4');
      first.play();
      second.play();
      second.play();
      await Future<void>.delayed(Duration.zero);
      expect(told.skip(2), ['play 1', 'pause 1', 'play 2', 'play 2']);
    });

    test('a film that will not open is a sentence', () async {
      messenger.setMockMethodCallHandler(filmChannel, (call) => throw PlatformException(code: 'film', message: 'This video isn’t on this phone.'));
      await expectLater(PhoneFilmDevice(core, plays: true).open('a.mp4'), throwsA(isA<StateError>().having((e) => e.message, 'message', 'This video isn’t on this phone.')));
    });
  });
}
