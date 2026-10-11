import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;

/// The two engines for a desk rather than a phone (lib/capture/engine.dart, lib/capture/simulated.dart): the
/// platform's own recogniser, and the scripted voice `simulate` asks for. Case for case with the web's
/// `capture/devEngines.test.ts`. There is no native capture here, so `startCapture` takes one of these.

class Heard {
  final List<String> partials = [];
  final List<Segment> segments = [];
  final List<String> errors = [];

  CaptureHandlers get handlers => CaptureHandlers(onPartial: partials.add, onSegment: segments.add, onError: errors.add);
}

/// A stand-in for Chrome's webkitSpeechRecognition that the test drives.
class FakeRecognition implements SpeechRecognition {
  FakeRecognition() {
    last = this;
  }

  static FakeRecognition? last;

  @override
  bool continuous = false;
  @override
  bool interimResults = false;
  @override
  String lang = '';
  @override
  void Function(int resultIndex, List<SpeechResult> results)? onresult;
  @override
  void Function(String error) onerror = (_) {};
  @override
  void Function()? onend;
  int starts = 0;
  int stops = 0;

  @override
  void start() => starts += 1;

  @override
  void stop() {
    stops += 1;
    // Chrome ends the session after a stop, as it does after a silence.
    onend?.call();
  }

  /// Chrome's results, from [resultIndex] on: the final ones committed, the rest a guess.
  void say(List<SpeechResult> results, [int resultIndex = 0]) => onresult?.call(resultIndex, results);
}

void main() {
  group('the browser’s own recogniser', () {
    var clock = 0.0;
    SpeechRecognition Function()? recognition;
    CaptureEngine engine() => CaptureEngine(backend: null, hasNativeGeneration: (_) async => false, now: () => clock, recognition: recognition);

    setUp(() {
      clock = 1000;
      recognition = FakeRecognition.new;
    });

    test('commits each final result as a phrase timed from the last, and guesses the rest', () async {
      final on = Heard();
      final session = await engine().startCapture(on.handlers);
      final recognition = FakeRecognition.last!;
      expect((recognition.continuous, recognition.interimResults, recognition.lang, recognition.starts), (true, true, 'en-US', 1));
      clock = 2200;
      recognition.say(const [SpeechResult(transcript: ' Oat milk ', isFinal: true), SpeechResult(transcript: 'and eg', isFinal: false)]);
      clock = 3500;
      recognition.say(const [SpeechResult(transcript: 'Oat milk', isFinal: true), SpeechResult(transcript: ' and eggs', isFinal: true)], 1);
      expect(on.segments, const [Segment(text: 'Oat milk', startMs: 0, endMs: 1200), Segment(text: 'and eggs', startMs: 1200, endMs: 2500)]);
      expect(on.partials, ['and eg', '']);
      expect(session.positionMs(), 2500);
      expect((session.kind, session.wantsSamples, session.keepsAudio), (EngineKind.browser, false, false));
    });

    test('starts again when Chrome ends the session on a silence, until the person stops, and keeps nothing', () async {
      final session = await engine().startCapture(Heard().handlers);
      final recognition = FakeRecognition.last!;
      recognition.onend?.call();
      expect(recognition.starts, 2);
      expect(await session.stop(), const Stopped(recordedMs: null, transcript: null));
      expect(recognition.starts, 2);
      expect(recognition.stops, 1);
    });

    test('hands on an error, and stops for good on cancel', () async {
      final on = Heard();
      final session = await engine().startCapture(on.handlers);
      final recognition = FakeRecognition.last!;
      recognition.onerror('not-allowed');
      expect(on.errors, ['not-allowed']);
      await session.cancel();
      expect(recognition.starts, 1);
    });

    test('says what is needed in a browser without one', () async {
      recognition = null;
      await expectLater(
        engine().startCapture(Heard().handlers),
        throwsA(predicate((Object error) => '$error'.contains('Voice notes need the Ghost.md app; this browser has no speech recognition.'))),
      );
    });
  });

  // The web fakes its timers and its clock; here the widget tester's fake time is both, so "three seconds later" is
  // a thing a test can say.
  group('the scripted voice', () {
    CaptureEngine engine(WidgetTester tester, Map<String, String> search) => CaptureEngine(
          backend: null,
          hasNativeGeneration: (_) async => false,
          search: () => search,
          now: () => tester.binding.clock.now().microsecondsSinceEpoch / 1000,
        );

    testWidgets('speaks the phrases given, each a growing guess and then a phrase, and stops with the length it spoke', (tester) async {
      final on = Heard();
      final session = await engine(tester, {'simulate': 'say', 'say': 'Grocery run.|Oat milk and eggs.'}).startCapture(on.handlers);
      expect((session.kind, session.wantsSamples, session.keepsAudio), (EngineKind.simulated, false, true));
      await tester.pump(const Duration(milliseconds: 3000));
      expect(on.partials, ['Grocery', 'Grocery run.', '', 'Oat', 'Oat milk', 'Oat milk and', 'Oat milk and eggs.', '']);
      expect(on.segments, const [
        Segment(text: 'Grocery run.', startMs: 0, endMs: 710),
        Segment(text: 'Oat milk and eggs.', startMs: 1010, endMs: 2080),
      ]);
      final stopped = session.stop();
      await tester.pump(Duration.zero);
      expect(await stopped, Stopped(recordedMs: session.positionMs().round(), transcript: null));
      expect(session.positionMs(), greaterThanOrEqualTo(2080));
      // The stop's own fifty-millisecond wait, which the web's fake timers drop with the test.
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('pauses long after the fourth phrase of its note, so a paragraph break can be seen', (tester) async {
      final on = Heard();
      final session = await engine(tester, {'simulate': ''}).startCapture(on.handlers);
      await tester.pump(const Duration(milliseconds: 20000));
      final segments = on.segments;
      expect(segments.map((segment) => segment.text).first, 'Weekend trip.');
      expect(segments, hasLength(5));
      expect(segments[4].startMs - segments[3].endMs, 2600);
      expect(segments[1].startMs - segments[0].endMs, 300);
      // The script's clock, which the web's fake timers drop with the test.
      await session.cancel();
    });
  });
}
