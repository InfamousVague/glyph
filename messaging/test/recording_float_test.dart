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

  test('the meter says each voice now: its peak and its average power, silence once it stops, and a clip that stays', () {
    final dir = Directory.systemTemp.createTempSync('ghost-meter-now');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/me.pcm');
    // A window of a square wave at half scale: its peak and its RMS are both a half.
    final d = ByteData(RecordingMeter.window * 2);
    for (var i = 0; i < RecordingMeter.window; i++) {
      d.setInt16(i * 2, i.isEven ? 16384 : -16384, Endian.little);
    }
    f.writeAsBytesSync(d.buffer.asUint8List());
    final m = RecordingMeter();
    m.read({'me': f.path});
    expect(m.now['me']!.peak, closeTo(0.5, 0.001));
    expect(m.now['me']!.rms, closeTo(0.5, 0.001));
    expect(m.clipped, isEmpty);
    // Nothing more written: the voice has stopped, and its meter falls to nothing.
    m.read({'me': f.path});
    expect(m.now['me'], (peak: 0.0, rms: 0.0));
    // A sample at the top: clipped, and still so after quieter sound, until cleared.
    final loud = ByteData(RecordingMeter.window * 2)..setInt16(100, 32767, Endian.little);
    f.writeAsBytesSync(loud.buffer.asUint8List(), mode: FileMode.append);
    m.read({'me': f.path});
    expect(m.clipped, {'me'});
    f.writeAsBytesSync(Uint8List(RecordingMeter.window * 2), mode: FileMode.append);
    m.read({'me': f.path});
    expect(m.now['me']!.peak, 0);
    expect(m.clipped, {'me'});
    m.clearClip('me');
    expect(m.clipped, isEmpty);
  });

  test('the mixer keeps each change with its moment: a fader, a mute, and a solo that takes the others out', () {
    final mix = RecordingMix();
    expect(mix.gain('a'), 1);
    expect(mix.points('a'), isEmpty);
    mix.setFader('a', 0.5, 48000);
    // Dragged on in the same moment: one point, the last value.
    mix.setFader('a', 0.25, 48000);
    expect(mix.points('a'), [(sample: 48000, gain: 0.25)]);
    mix.setFader('a', 9, 96000);
    expect(mix.fader('a'), RecordingMix.most, reason: 'held to +6 dB');
    mix.setMuted('a', true, 144000);
    expect(mix.gain('a'), 0);
    expect(mix.fader('a'), RecordingMix.most, reason: 'the fader stays where it was under the mute');
    mix.setMuted('a', false, 192000);
    expect(mix.points('a').map((p) => p.gain), [0.25, 2.0, 0.0, 2.0]);
    // A solo moves the others: b and c leave the mix, and come back when it ends.
    mix.setSolo('b', true, 240000, among: ['a', 'b', 'c']);
    expect([mix.gain('a'), mix.gain('b'), mix.gain('c')], [0.0, 1.0, 0.0]);
    expect(mix.points('b'), isEmpty, reason: 'b itself is as it was');
    expect(mix.points('c'), [(sample: 240000, gain: 0.0)]);
    mix.setSolo('b', false, 288000, among: ['a', 'b', 'c']);
    expect(mix.points('c'), [(sample: 240000, gain: 0.0), (sample: 288000, gain: 1.0)]);
    expect(mix.gainAt('c', 250000), 0);
    expect(mix.gainAt('c', 300000), 1);
    expect(mix.gainAt('a', 0), 1, reason: 'as recorded before its first change');
  });

  test('the mix follows the faders as they were moved, with no click at a change; each voice\'s own file is untouched', () {
    final dir = Directory.systemTemp.createTempSync('ghost-mix-gain');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Two voices, three seconds each, steady at 8000 and 4000.
    File steady(String name, int value) {
      final d = ByteData(48000 * 3 * 2);
      for (var i = 0; i < 48000 * 3; i++) {
        d.setInt16(i * 2, value, Endian.little);
      }
      return File('${dir.path}/$name.pcm')..writeAsBytesSync(d.buffer.asUint8List());
    }

    final a = steady('a', 8000), b = steady('b', 4000);
    final before = a.readAsBytesSync();
    // a: halved from the first second, muted from the second (across a block's edge). b: as recorded.
    mixPcm([a.path, b.path], '${dir.path}/mix.pcm', gains: [
      [(sample: 48000, gain: 0.5), (sample: 96000, gain: 0.0)],
      const [],
    ]);
    final d = ByteData.sublistView(File('${dir.path}/mix.pcm').readAsBytesSync());
    int at(int sample) => d.getInt16(sample * 2, Endian.little);
    expect(d.lengthInBytes, 48000 * 3 * 2);
    expect(at(100), 12000, reason: 'both as recorded');
    expect(at(47999), 12000);
    expect(at(48000 + 2000), 8000, reason: 'a at half, b whole');
    expect(at(96000 + 2000), 4000, reason: 'a out of the mix');
    expect(at(48000 * 3 - 1), 4000);
    // Reached over a hundredth of a second, never a step: no two samples differ by more than a few.
    var jump = 0;
    for (var i = 1; i < 48000 * 3; i++) {
      jump = math.max(jump, (at(i) - at(i - 1)).abs());
    }
    expect(jump, lessThan(64));
    expect(a.readAsBytesSync(), before);
    // With no gains it is the plain sum.
    mixPcm([a.path, b.path], '${dir.path}/plain.pcm');
    expect(ByteData.sublistView(File('${dir.path}/plain.pcm').readAsBytesSync()).getInt16(100000 * 2, Endian.little), 12000);
  });

  for (final (size, at) in [('phone', const Size(412, 892)), ('wide', const Size(1100, 760))]) {
    for (final dark in [false, true]) {
      testWidgets('a pill that moves, opening into the tracks as a timeline ($size, ${dark ? 'dark' : 'light'})', (tester) async {
        final rec = CallRecorder.standing(
          names: {'me': 'Matt', 'a1b2c3d4': 'Maya Chen', 'e5f6a7b8': 'Theo', 'c9d0e1f2': 'Sam Ortiz'},
          since: DateTime.now().subtract(const Duration(seconds: 47)),
          left: {'c9d0e1f2'},
          markers: [21.5],
        );
        rec.meter.seed({
          'me': _speech(470, seed: 1),
          'a1b2c3d4': _speech(470, seed: 2, from: 40),
          'e5f6a7b8': _speech(470, seed: 3, quiet: true),
          'c9d0e1f2': _speech(230, seed: 4),
        }, live: {
          'me': (peak: 0.62, rms: 0.31),
          'a1b2c3d4': (peak: 0.34, rms: 0.16),
          'e5f6a7b8': (peak: 0.99, rms: 0.5),
          'c9d0e1f2': (peak: 0, rms: 0),
        }, clipping: {'e5f6a7b8'});
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
        // Every track has its meter; a voice has mute and solo, the mix has neither.
        for (final k in ['*mix', 'me', 'a1b2c3d4']) {
          expect(find.byKey(ValueKey('recording-lane-meter-$k')), findsOneWidget, reason: k);
        }
        expect(find.byKey(const ValueKey('recording-lane-mute-*mix')), findsNothing);
        // Maya muted in the mix: said to the recorder, and her lane's M is lit (the picture).
        await tester.tap(find.byKey(const ValueKey('recording-lane-mute-a1b2c3d4')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.mix.muted('a1b2c3d4'), isTrue);
        expect(rec.mix.gain('a1b2c3d4'), 0);
        expect(rec.mix.points('a1b2c3d4').single.gain, 0);
        // A moment marked: a flag on the ruler, kept by the recorder.
        await tester.tap(find.byKey(const ValueKey('recording-mark')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.markers, hasLength(2));
        expect(rec.markers.last, closeTo(47, 2));
        await _keep(tester, '$size-timeline-${dark ? 'dark' : 'light'}');
        // The mixer: a strip per track, a fader per voice.
        await tester.tap(find.byKey(const ValueKey('recording-view')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('recording-mixer')), findsOneWidget);
        expect(find.byKey(const ValueKey('recording-lanes')), findsNothing);
        expect(find.byKey(const ValueKey('recording-strip-*mix')), findsOneWidget);
        expect(find.byKey(const ValueKey('recording-fader-*mix')), findsNothing, reason: 'the mix is what the faders make');
        final fader = find.byKey(const ValueKey('recording-fader-me'));
        expect(fader, findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const ValueKey('recording-gain-me'))).data, '0.0');
        // Dragged down, Matt is quieter in the mix; up past the notch, louder; pressed twice, as recorded again.
        await tester.drag(fader, const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.mix.fader('me'), lessThan(1));
        expect(rec.mix.points('me'), isNotEmpty);
        final quiet = rec.mix.fader('me');
        await tester.drag(fader, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.mix.fader('me'), greaterThan(quiet));
        expect(tester.widget<Text>(find.byKey(const ValueKey('recording-gain-me'))).data, '+6.0', reason: 'the strip says what the fader is at');
        await tester.tap(find.byKey(const ValueKey('recording-solo-e5f6a7b8')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.mix.gain('me'), 0, reason: 'Theo soloed: the others are out of the mix');
        expect(rec.mix.gain('e5f6a7b8'), 1);
        await _keep(tester, '$size-mixer-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('recording-solo-e5f6a7b8')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(rec.mix.gain('me'), greaterThan(0));
        // Back to the timeline.
        await tester.tap(find.byKey(const ValueKey('recording-view')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('recording-lanes')), findsOneWidget);
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
