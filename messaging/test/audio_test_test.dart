import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaDeviceInfo;
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/settings.dart';
import 'package:ghost_messaging/ui/voice_pane.dart';
import 'package:ghost_messaging/voice/rtc.dart';
import 'package:ghost_messaging/voice/voice_settings.dart';

import 'support/list_harness.dart';

/// GMFB-2 (@kevin, Windows 0.11.3: "When testing voice calls it is difficult to diagnose issues without an in app audio
/// device test"): Settings › Voice and video tests the microphone chosen, as a call opens it, with how loud it hears
/// you, and plays you back through the speaker chosen when asked.
class _TestMedia extends RtcMedia {
  _TestMedia(VoiceSettings s) : super(settings: s);
  bool started = false, stopped = false;
  @override
  Future<void> start() async {
    started = true;
    levels.value = const {'me': 0.5};
  }

  @override
  Future<void> stop() async => stopped = true;
}

Future<void> _fonts() async {
  final loader = FontLoader('Inter Variable')..addFont(File('assets/fonts/InterVariable-latin.ttf').readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  testWidgets('the microphone test shows how loud it hears you, plays you back when asked, and lets go when stopped', (tester) async {
    ListPhone(const []).install();
    _TestMedia? made;
    AudioTest.make = (s) => made = _TestMedia(s);
    RtcMedia.enumerate = () async => [MediaDeviceInfo(kind: 'audioinput', label: 'USB mic', deviceId: 'mic-1')];
    addTearDown(() {
      AudioTest.make = null;
      RtcMedia.enumerate = null;
    });
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const SettingsSectionScreen('voice'), AppState()..set('voice_input', 'mic-1'));
    await settle(tester);
    final start = find.byKey(const ValueKey('audio-test'));
    await tester.scrollUntilVisible(start, 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Test your microphone'), findsOneWidget);
    await tester.tap(find.text('Test your microphone'));
    await settle(tester);
    expect(made?.started, isTrue);
    expect(made!.settings.input, 'mic-1', reason: 'the microphone chosen is the one tested');
    final bar = tester.getSize(find.byKey(const ValueKey('audio-test-level'))).width;
    final track = tester.getSize(find.ancestor(of: find.byKey(const ValueKey('audio-test-level')), matching: find.byType(Stack)).first).width;
    expect(bar / track, closeTo(0.5, 0.05), reason: 'the bar is as loud as the microphone hears');

    expect(made!.hearMyself, isFalse, reason: 'nobody hears themselves unless they ask');
    await tester.tap(find.bySemanticsLabel('Hear yourself').last);
    await settle(tester);
    expect(made!.hearMyself, isTrue);

    await tester.tap(find.text('Stop the test'));
    await settle(tester);
    expect(made!.stopped, isTrue, reason: 'the microphone is let go of');
    expect(find.text('Test your microphone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
