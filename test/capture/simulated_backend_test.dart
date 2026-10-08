import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/simulated.dart';
import 'package:ghost_md/core/note.dart' show Segment;

/// The scripted voice as the native capture (lib/capture/simulated.dart `SimulatedBackend`): the test backend for
/// what is written over [CaptureBackend] until the Rust core answers it. Not on the web, so these cases are the
/// Flutter port's own: the Whisper engine's whole path over it, from start to the kept recording.
void main() {
  testWidgets('speaks its script through the Whisper engine, between start and stop, and keeps the recording', (tester) async {
    double now() => tester.binding.clock.now().microsecondsSinceEpoch / 1000;
    final backend = SimulatedBackend(search: const {'simulate': 'say', 'say': 'Grocery run.|Oat milk and eggs.'}, now: now);
    final engine = CaptureEngine(backend: backend, hasNativeGeneration: (_) async => true);
    final partials = <String>[];
    final segments = <Segment>[];
    final session = await engine.startCapture(CaptureHandlers(onPartial: partials.add, onSegment: segments.add, onError: (message) => fail(message)));
    expect((session.kind, session.wantsSamples, session.keepsAudio), (EngineKind.whisper, true, true));
    session.push(Float32List(3200));
    await tester.pump(const Duration(milliseconds: 3000));
    expect(partials, ['Grocery', 'Grocery run.', '', 'Oat', 'Oat milk', 'Oat milk and', 'Oat milk and eggs.', '']);
    expect(segments, const [
      Segment(text: 'Grocery run.', startMs: 0, endMs: 710),
      Segment(text: 'Oat milk and eggs.', startMs: 1010, endMs: 2080),
    ]);
    final stopping = session.stop(const StopOptions(recordAs: 'n1'));
    await tester.pump(const Duration(milliseconds: 50));
    final stopped = await stopping;
    expect(stopped.transcript, 'Grocery run. Oat milk and eggs.');
    expect(stopped.recordedMs, greaterThanOrEqualTo(2080));
    expect(backend.pushed, hasLength(1));
    expect(backend.kept['n1'], stopped.recordedMs);
    // Stopped, it says nothing more: no clock is left running.
    await tester.pump(const Duration(milliseconds: 5000));
    expect(segments, hasLength(2));
  });

  testWidgets('says nothing before a start, and nothing after a cancel', (tester) async {
    double now() => tester.binding.clock.now().microsecondsSinceEpoch / 1000;
    final backend = SimulatedBackend(search: const {'simulate': ''}, now: now);
    final heard = <CaptureEvent>[];
    final listening = backend.events.listen(heard.add);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(heard, isEmpty);
    await backend.start();
    await tester.pump(const Duration(milliseconds: 400));
    expect(heard, isNotEmpty);
    await backend.cancel();
    final said = heard.length;
    await tester.pump(const Duration(milliseconds: 5000));
    expect(heard, hasLength(said));
    unawaited(listening.cancel());
  });
}
