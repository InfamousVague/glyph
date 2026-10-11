/// The Mac's own sound in the meeting recorder (lib/capture/ui/computer_sound.dart): the tap opened only once the
/// capture runs and the switch is on, closed when either goes, and the one line when nothing comes through it.
/// `src/app/capture/ComputerSound.test.tsx`, case for case.
///
/// What differs: the page mocked the module's four commands and read the preference from its store; here the tap is
/// a stand-in [SystemSoundBackend] and the preference is a value the test holds, changed by the word's own
/// `onWanted`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/system_sound.dart';
import 'package:ghost_md/capture/ui/computer_sound.dart';

import '../support/render.dart';

class Tap implements SystemSoundBackend {
  SoundSupport support = const SoundSupport(supported: true, reason: null);
  int started = 0;
  int stopped = 0;
  SoundStarted answer = const SoundStarted(capturing: true, reason: null);
  bool heard = false;

  @override
  Future<SoundSupport> available() async => support;

  @override
  Future<SoundStarted> start() async {
    started += 1;
    return answer;
  }

  @override
  Future<void> stop() async {
    stopped += 1;
  }

  @override
  Future<({bool capturing, bool heard})> status() async => (capturing: answer.capturing, heard: heard);
}

void main() {
  setUpAll(loadAppFonts);

  late Tap tap;
  late ValueNotifier<bool> meetingSound;

  setUp(() {
    tap = Tap();
    meetingSound = ValueNotifier<bool>(false);
  });

  SystemSound sound() => SystemSound(backend: tap, isAndroid: false, isMacApp: true, hasNativeGeneration: (_) async => true, meetingSoundOnHost: () => null);

  Future<void> show(WidgetTester tester, {required bool live, void Function(String text)? onSay}) async {
    await pumpApp(
      tester,
      home: Align(
        key: UniqueKey(),
        child: ValueListenableBuilder<bool>(
          valueListenable: meetingSound,
          builder: (context, wanted, _) => ComputerSound(live: live, sound: sound(), wanted: wanted, onWanted: (next) => meetingSound.value = next, onSay: onSay ?? (_) {}),
        ),
      ),
    );
    // The support, then the tap's answer.
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group("the Mac's sound in a meeting", () {
    testWidgets('draws nothing on a Mac that cannot', (tester) async {
      tap.support = const SoundSupport(supported: false, reason: 'Recording the computer’s sound needs macOS 14.2 or later.');
      await show(tester, live: true);
      expect(find.descendant(of: find.byType(ComputerSound), matching: find.byType(Text)), findsNothing);
      await unmount(tester);
    });

    testWidgets('opens the tap only once the capture runs with the switch on, and closes it when the switch goes off', (tester) async {
      await show(tester, live: false);
      expect(find.text("This Mac's sound: off"), findsOneWidget);
      await tester.tap(find.text("This Mac's sound: off"));
      await tester.pump();
      expect(meetingSound.value, isTrue);
      expect(tap.started, 0);
      await unmount(tester);
      await show(tester, live: true);
      expect(find.text("With this Mac's sound"), findsOneWidget);
      expect(tap.started, 1);
      await tester.tap(find.text("With this Mac's sound"));
      await tester.pump();
      expect(meetingSound.value, isFalse);
      await tester.pump();
      expect(tap.stopped, 1);
      await unmount(tester);
    });

    testWidgets('says why when the tap would not open, and where the switch is when nothing comes through', (tester) async {
      meetingSound.value = true;
      tap.answer = const SoundStarted(capturing: false, reason: 'The computer’s sound could not be opened.');
      final said = <String>[];
      await show(tester, live: true, onSay: said.add);
      expect(said, ['The computer’s sound could not be opened.']);
      await unmount(tester);
      tap.answer = const SoundStarted(capturing: true, reason: null);
      final quiet = <String>[];
      await show(tester, live: true, onSay: quiet.add);
      for (var i = 0; i < 8; i += 1) {
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump();
      }
      expect(quiet, [nothingFromTheMac]);
      await unmount(tester);
    });
  });
}
