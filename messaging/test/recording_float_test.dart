import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/recording_float.dart';
import 'package:ghost_messaging/voice/recorder.dart';

import 'support/list_harness.dart';

/// The recording over the app (lib/ui/recording_float.dart; Matt, 2026-11-20: "show the different audio tracks being
/// recorded and the sound waves from each audio track, collapse it to a button that can be moved around the app when
/// expanded the tracks and stuff should appear similar to adobe premiere"). Pictures in build/themes/recording.
void main() {
  test('the meter reads each voice\'s file a tenth of a second at a time, the loudest sample of each', () {
    final dir = Directory.systemTemp.createTempSync('ghost-meter');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/me.pcm');
    // Two and a half steps: silence, a step peaking at half, and half a step not yet whole.
    final d = ByteData(RecordingMeter.step * 2 * 2 + RecordingMeter.step);
    d.setInt16((RecordingMeter.step + 10) * 2, 16384, Endian.little);
    d.setInt16((RecordingMeter.step + 20) * 2, -8000, Endian.little);
    f.writeAsBytesSync(d.buffer.asUint8List());
    final m = RecordingMeter();
    m.read({'me': f.path});
    expect(m.levels['me'], [0.0, 0.5]);
    // The rest of the third step comes: it is read, and only it.
    f.writeAsBytesSync(Uint8List(RecordingMeter.step), mode: FileMode.append);
    m.read({'me': f.path, 'gone': '${dir.path}/none.pcm'});
    expect(m.levels['me'], [0.0, 0.5, 0.0]);
    expect(m.levels.containsKey('gone'), isFalse);
  });

  for (final (size, at) in [('phone', const Size(412, 892)), ('wide', const Size(1100, 760))]) {
    for (final dark in [false, true]) {
      testWidgets('a pill that moves, opening into the tracks as a timeline ($size, ${dark ? 'dark' : 'light'})', (tester) async {
        final rec = CallRecorder.standing(
          names: {'me': 'Matt', 'a1b2c3d4': 'Maya Chen', 'e5f6a7b8': 'Theo', 'c9d0e1f2': 'Sam Ortiz'},
          since: DateTime.now().subtract(const Duration(seconds: 47)),
          left: {'c9d0e1f2'},
        );
        rec.meter.seed({
          'me': _speech(470, seed: 1),
          'a1b2c3d4': _speech(470, seed: 2, from: 40),
          'e5f6a7b8': _speech(470, seed: 3, quiet: true),
          'c9d0e1f2': _speech(230, seed: 4),
        });
        final sheet = await loadSheet(tester);
        await pumpScreen(tester, sheet, Stack(children: [const SizedBox.expand(), Positioned.fill(child: RecordingFloat(recorder: rec))]), AppState()..set('theme', dark ? 'dark' : 'light'), size: at);
        await tester.pump(const Duration(milliseconds: 200));
        final pill = find.byKey(const ValueKey('recording-float'));
        expect(pill, findsOneWidget);
        await _keep(tester, '$size-pill-${dark ? 'dark' : 'light'}');
        // Dragged, it stays where it is put.
        final before = tester.getTopLeft(pill);
        await tester.drag(pill, const Offset(-120, -200));
        await tester.pump();
        final after = tester.getTopLeft(pill);
        expect(after.dx, lessThan(before.dx));
        expect(after.dy, lessThan(before.dy));
        // Pressed, the timeline: a header per track (the mix first) and the lanes.
        await tester.tap(pill);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('recording-timeline')), findsOneWidget);
        for (final k in ['*mix', 'me', 'a1b2c3d4', 'e5f6a7b8', 'c9d0e1f2']) {
          expect(find.byKey(ValueKey('recording-track-$k')), findsOneWidget, reason: k);
        }
        expect(find.text('Left'), findsOneWidget, reason: 'Sam left: their track keeps what it has');
        expect(find.text('A1'), findsOneWidget);
        await _keep(tester, '$size-timeline-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('recording-collapse')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('recording-timeline')), findsNothing);
        expect(find.byKey(const ValueKey('recording-float')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

/// Speech's loudness by step: phrases and pauses, made up but the same each run.
List<double> _speech(int steps, {required int seed, int from = 0, bool quiet = false}) {
  final r = math.Random(seed);
  final out = <double>[];
  var talking = false;
  var left = 0;
  for (var i = 0; i < steps; i++) {
    if (left-- <= 0) {
      talking = !talking;
      left = talking ? 8 + r.nextInt(30) : 4 + r.nextInt(25);
    }
    final base = i < from ? 0.0 : (talking ? (quiet ? 0.08 : 0.25) + r.nextDouble() * (quiet ? 0.12 : 0.55) : r.nextDouble() * 0.01);
    out.add(base);
  }
  return out;
}

Future<void> _keep(WidgetTester tester, String name) async {
  final element = find.byType(WidgetsApp).evaluate().single;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('build/themes/recording/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}
