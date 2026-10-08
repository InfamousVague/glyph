import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/audio.dart';
import 'package:ghost_md/capture/capture_session.dart';
import 'package:ghost_md/capture/engine.dart';

/// The recorder's microphone and transcriber as they open (lib/capture/capture_session.dart), on a phone: the
/// microphone first, and what it hears while the model loads held and handed over once the engine is up, because
/// the first words of a voice note are usually its subject. And a start called off halfway lets go of what it
/// opened, rather than leaving a second microphone feeding the next start's session. Case for case with the web's
/// `capture/useCaptureSession.test.tsx`: where that renders the hook in a probe, this drives the plain class the
/// same way - `start` for the mount, `close` for the unmount.

typedef Opening = ({MicrophoneHandlers handlers, Completer<Microphone> opened});

/// Every microphone asked for, in order; the newest is the last.
List<Opening> microphones = [];
({CaptureHandlers handlers, Completer<CaptureSession> started})? engine;
int startCaptures = 0;
bool finished = false;

class FakeMic {
  int stops = 0;
  late final Microphone microphone = Microphone(stop: () => stops += 1, deviceRate: 48000, state: () => AudioContextState.running);
}

class FakeSession {
  FakeSession([this.wantsSamples = true]);

  final bool wantsSamples;
  final List<Float32List> pushed = [];
  int cancels = 0;

  late final CaptureSession session = CaptureSession(
    kind: EngineKind.whisper,
    wantsSamples: wantsSamples,
    keepsAudio: true,
    push: pushed.add,
    positionMs: () => 0,
    stop: ([options]) async => const Stopped(recordedMs: null, transcript: null),
    cancel: () {
      cancels += 1;
    },
  );
}

/// The probe: the session as a screen would hold it.
CaptureSessionState probe() => CaptureSessionState(
      fromAssistant: true,
      isFinished: () => finished,
      events: SessionEvents(onPartial: (_) {}, onSegment: (_) {}, onLevel: (_, _) {}),
      native: true,
      openMicrophone: (handlers) {
        final opening = (handlers: handlers, opened: Completer<Microphone>());
        microphones.add(opening);
        return opening.opened.future;
      },
      startCapture: (handlers) {
        startCaptures += 1;
        final started = Completer<CaptureSession>();
        engine = (handlers: handlers, started: started);
        return started.future;
      },
    );

Float32List chunk(double value) => Float32List.fromList([value, value]);
void hear(Float32List samples) => microphones.last.handlers.onChunk(samples);

/// Lets everything already settled have its turn.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() {
    microphones = [];
    engine = null;
    startCaptures = 0;
    finished = false;
  });

  group('opening the recorder on a phone', () {
    test('hands the engine everything the microphone heard while it started, in order, then each chunk as it comes', () async {
      final latest = probe()..start();
      await settle();
      expect(microphones, isNotEmpty);
      final mic = FakeMic();
      // Heard while the microphone was still being opened, and then while the model loaded.
      hear(chunk(1));
      microphones.last.opened.complete(mic.microphone);
      await settle();
      expect(engine, isNotNull);
      hear(chunk(2));
      hear(chunk(3));
      final started = FakeSession();
      engine!.started.complete(started.session);
      await settle();
      expect(latest.phase, Phase.listening);

      expect(started.pushed.map((samples) => samples[0]), [1, 2, 3]);
      hear(chunk(4));
      expect(started.pushed.map((samples) => samples[0]), [1, 2, 3, 4]);
      expect(latest.counts.heardSamples, 8);
      expect(latest.counts.deviceRate, 48000);
      expect(latest.engine, EngineKind.whisper);
      expect(mic.stops, 0);
    });

    test('lets the microphone go when the engine wants none of its samples', () async {
      final latest = probe()..start();
      await settle();
      final mic = FakeMic();
      microphones.last.opened.complete(mic.microphone);
      await settle();
      engine!.started.complete(FakeSession(false).session);
      await settle();
      expect(latest.phase, Phase.listening);
      expect(mic.stops, 1);
    });

    test('stops a microphone that opens after the screen has gone, and never starts an engine to feed it', () async {
      final latest = probe()..start();
      await settle();
      latest.close();
      final mic = FakeMic();
      microphones.last.opened.complete(mic.microphone);
      await settle();
      expect(mic.stops, 1);
      expect(startCaptures, 0);
    });

    // React's StrictMode mounts, unmounts and mounts again on the same hook: start, close, start on the same object.
    test('feeds the take from one microphone when React starts it twice, the first start called off before it opened', () async {
      final latest = probe()
        ..start()
        ..close()
        ..start();
      await settle();
      expect(microphones, hasLength(2));
      final first = microphones[0];
      final second = microphones[1];
      final live = FakeMic();
      second.opened.complete(live.microphone);
      await settle();
      expect(engine, isNotNull);
      final started = FakeSession();
      engine!.started.complete(started.session);
      await settle();
      expect(latest.phase, Phase.listening);

      // The called-off start's microphone opens late: it is stopped, and nothing it hears reaches the take.
      final orphan = FakeMic();
      first.opened.complete(orphan.microphone);
      await settle();
      expect(orphan.stops, 1);
      first.handlers.onChunk(chunk(9));
      second.handlers.onChunk(chunk(1));
      expect(started.pushed.map((samples) => samples[0]), [1]);
      expect(live.stops, 0);
    });

    test('cancels an engine that starts after the screen has gone, and stops its microphone', () async {
      final latest = probe()..start();
      await settle();
      final mic = FakeMic();
      microphones.last.opened.complete(mic.microphone);
      await settle();
      expect(engine, isNotNull);
      latest.close();
      final started = FakeSession();
      engine!.started.complete(started.session);
      await settle();
      expect(started.cancels, 1);
      expect(mic.stops, greaterThan(0));
      expect(started.pushed, isEmpty);
    });

    test('says why when the engine could not start, and lets the microphone go', () async {
      final latest = probe()..start();
      await settle();
      final mic = FakeMic();
      microphones.last.opened.complete(mic.microphone);
      await settle();
      engine!.started.completeError(Exception('The voice model is still downloading.'));
      await settle();
      expect(latest.phase, Phase.failed);
      expect(latest.error, 'The voice model is still downloading.');
      expect(mic.stops, 1);
    });
  });

  group('closing the recorder', () {
    Future<({CaptureSessionState latest, FakeMic mic, FakeSession started})> listening() async {
      final latest = probe()..start();
      await settle();
      final mic = FakeMic();
      microphones.last.opened.complete(mic.microphone);
      await settle();
      final started = FakeSession();
      engine!.started.complete(started.session);
      await settle();
      expect(latest.phase, Phase.listening);
      return (latest: latest, mic: mic, started: started);
    }

    test('cancels the take and the microphone when the screen goes without Done or Discard', () async {
      final (:latest, :mic, :started) = await listening();
      latest.close();
      expect(started.cancels, 1);
      expect(mic.stops, 1);
    });

    test('leaves them to Done or Discard once either has begun', () async {
      final (:latest, :mic, :started) = await listening();
      finished = true;
      latest.close();
      expect(started.cancels, 0);
      expect(mic.stops, 0);
    });
  });
}
