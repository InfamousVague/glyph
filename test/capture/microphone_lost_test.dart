import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/audio.dart';
import 'package:ghost_md/capture/capture_session.dart';
import 'package:ghost_md/capture/device_mic.dart';
import 'package:ghost_md/capture/engine.dart';

/// A microphone that closes without being asked to is heard (docs/PARITY.md, Differs 6): the phone's half says so
/// on its channel ([DeviceMic.lost]), the recorder's handle carries it ([Microphone.lost]), and the session tells
/// its screen once, for the take that is still its own and still running. The phone used to close the device
/// whenever the app left the screen and nothing listened, so a recorder came back counting over a microphone that
/// was gone; it no longer closes it there (android/…/DictationMic.kt), and what is left of "closed by itself" is a
/// device that failed or a window that went.

/// The phone's half of `ghost_md/mic`, as a test drives it.
class FakePhoneMic {
  final List<String> asked = [];
  MockStreamHandlerEventSink? sink;

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DeviceMic.channel, (call) async {
      asked.add(call.method);
      return switch (call.method) {
        'permission' => 'granted',
        'open' => {'sampleRate': 16000, 'direct': false},
        'close' => {'samples': 6400, 'pushed': 0, 'refused': 0},
        _ => null,
      };
    });
    messenger.setMockStreamHandler(DeviceMic.eventChannel, MockStreamHandler.inline(onListen: (arguments, events) => sink = events, onCancel: (arguments) => sink = null));
    DeviceMic.debugSupported = true;
  }

  void remove() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DeviceMic.channel, null);
    messenger.setMockStreamHandler(DeviceMic.eventChannel, null);
    DeviceMic.debugSupported = null;
  }

  void chunk(int samples) => sink!.success({'event': 'chunk', 'rms': 0.25, 'samples': samples, 'pcm': Float32List(4).buffer.asUint8List()});
  void closed(String reason) => sink!.success({'event': 'closed', 'reason': reason});
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Whether [future] has settled by now, and with what.
Future<String?> settledWith(Future<String> future) => Future.any<String?>([future, Future<String?>.delayed(const Duration(milliseconds: 20), () => null)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the phone’s microphone', () {
    late FakePhoneMic phone;

    setUp(() => phone = FakePhoneMic()..install());
    tearDown(() => phone.remove());

    test('says why when the phone lets go of it without being asked', () async {
      final mic = await DeviceMic.openWith(const MicrophoneConstraints());
      final heard = <int>[];
      mic.onSamples = (samples) => heard.add(samples.length);
      phone.chunk(3200);
      await settle();
      expect(heard, [4]);
      expect(mic.state, AudioContextState.running);

      phone.closed('error');
      await settle();
      expect(await settledWith(mic.lost), 'error');
      expect(await mic.closed, 'error');
      expect(mic.state, AudioContextState.closed);
      expect(await mic.totals, isNull, reason: 'nobody was asked what it heard in all');
      // And nothing after it is handed on.
      phone.sink?.success({'event': 'chunk', 'rms': 0.25, 'samples': 6400, 'pcm': Float32List(4).buffer.asUint8List()});
      await settle();
      expect(heard, [4]);
    });

    test('says "background" when the window went with a take open', () async {
      final mic = await DeviceMic.openWith(const MicrophoneConstraints());
      phone.closed('background');
      await settle();
      expect(await settledWith(mic.lost), 'background');
    });

    test('is never "lost" when the recorder let go of it', () async {
      final mic = await DeviceMic.openWith(const MicrophoneConstraints());
      mic.close();
      await settle();
      expect(await mic.closed, 'closed');
      expect(phone.asked, contains('close'));
      expect(await mic.totals, (samples: 6400, pushed: 0, refused: 0));
      // A word from the phone that crosses the close on its way changes nothing.
      phone.sink?.success({'event': 'closed', 'reason': 'background'});
      await settle();
      expect(await settledWith(mic.lost), isNull);
    });

    test('is carried by the handle the recorder holds, and not by a device that cannot say', () async {
      final microphone = await openMicrophone(MicrophoneHandlers(onChunk: (_) {}, onLevel: (_) {}), open: DeviceMic.open);
      expect(microphone.lost, isNotNull);
      phone.closed('error');
      await settle();
      expect(await settledWith(microphone.lost!), 'error');

      final plain = await openMicrophone(MicrophoneHandlers(onChunk: (_) {}, onLevel: (_) {}), open: (constraints, {required sampleRate, required chunk}) async => _Plain());
      expect(plain.lost, isNull);
    });
  });

  group('the session', () {
    late List<String> lost;
    late List<String> warned;
    late Completer<String> gone;
    late int stops;
    var finished = false;
    Completer<CaptureSession>? engine;

    CaptureSession running() => CaptureSession(
          kind: EngineKind.whisper,
          wantsSamples: true,
          keepsAudio: true,
          push: (_) {},
          positionMs: () => 0,
          stop: ([options]) async => const Stopped(recordedMs: null, transcript: null),
          cancel: () {},
        );

    CaptureSessionState probe({Future<CaptureSession> Function()? start}) => CaptureSessionState(
          fromAssistant: true,
          isFinished: () => finished,
          events: SessionEvents(onPartial: (_) {}, onSegment: (_) {}, onLevel: (_, _) {}, onMicrophoneLost: lost.add),
          native: true,
          openMicrophone: (handlers) async => Microphone(stop: () => stops += 1, deviceRate: 16000, state: () => AudioContextState.running, lost: gone.future),
          startCapture: (handlers) => start?.call() ?? Future.value(running()),
          warn: warned.add,
        );

    setUp(() {
      lost = [];
      warned = [];
      gone = Completer<String>();
      stops = 0;
      finished = false;
      engine = null;
    });

    test('tells its screen once, with why, while the take is running', () async {
      final session = probe()..start();
      await settle();
      expect(session.phase, Phase.listening);
      gone.complete('error');
      await settle();
      expect(lost, ['error']);
      expect(warned.single, contains('the microphone closed by itself: error'));
      session.close();
    });

    test('tells it while the model is still loading, too: the first words were being held', () async {
      engine = Completer<CaptureSession>();
      final session = probe(start: () => engine!.future)..start();
      await settle();
      expect(session.phase, Phase.starting);
      gone.complete('background');
      await settle();
      expect(lost, ['background']);
      engine!.complete(running());
      await settle();
      session.close();
    });

    test('says nothing once Done or Discard has begun, or the recorder has gone', () async {
      final ending = probe()..start();
      await settle();
      finished = true;
      gone.complete('error');
      await settle();
      expect(lost, isEmpty);
      ending.close();

      finished = false;
      gone = Completer<String>();
      final closed = probe()..start();
      await settle();
      closed.close();
      gone.complete('error');
      await settle();
      expect(lost, isEmpty);
    });

    test('says nothing of a start that was called off', () async {
      final session = probe();
      session.start();
      await settle();
      final first = gone;
      // Started again (the screen's effect run twice): the first start's microphone is nobody's now.
      session.close();
      gone = Completer<String>();
      session.start();
      await settle();
      first.complete('error');
      await settle();
      expect(lost, isEmpty);
      gone.complete('error');
      await settle();
      expect(lost, ['error']);
      session.close();
    });
  });
}

class _Plain implements MicrophoneInput {
  @override
  num get sampleRate => 16000;

  @override
  AudioContextState get state => AudioContextState.running;

  @override
  set onSamples(void Function(Float32List samples)? handler) {}

  @override
  Future<void> resume() async {}

  @override
  void close() {}
}
