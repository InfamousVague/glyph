import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/editor/commands/task_toggle.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/simple/simple_todos.dart';
import 'package:ghost_md/sounds/sound_pack.dart';
import 'package:ghost_md/sounds/sounds.dart';
import 'package:glacier/glacier.dart';

import '../capture_ui/support/harness.dart';
import '../core/make_note.dart';
import '../support/render.dart';
import 'support.dart';

/// Where the app's events call Settings › Sounds (Matt, 2026-10-27: "build ... the sounds settings"): each plays its
/// sound only with its switch on, and nothing but the recorder's own plays while it records.
void main() {
  setUpAll(loadAppFonts);

  late HeardOutput output;

  setUp(() {
    output = HeardOutput();
    useSounds(heardSounds(output), addTearDown);
    preferences.startWithoutStorage();
    preferences.value = const Preferences(theme: 'light');
  });

  Future<void> turns() => Future<void>.delayed(Duration.zero);

  group('a box ticked in a note', () {
    test('ticks, and a box cleared is quiet', () async {
      var state = EditorState.create(doc: '- [ ] milk');
      state = toggleBox(state, boxAt(state, 0)!).state;
      await turns();
      expect(output.events, ['todo-ticked']);
      toggleBox(state, boxAt(state, 0)!);
      await turns();
      expect(output.events, ['todo-ticked']);
    });

    test('is quiet with its switch off, and while a recording runs', () async {
      final state = EditorState.create(doc: '- [ ] milk');
      preferences.update((now) => now.copyWith(soundEvents: {'todo-ticked': false}));
      toggleBox(state, boxAt(state, 0)!);
      preferences.update((now) => now.copyWith(soundEvents: const {}));
      sounds.recording = true;
      toggleBox(state, boxAt(state, 0)!);
      await turns();
      expect(output.played, isEmpty);
    });
  });

  group('the To-dos view', () {
    Future<void> pump(WidgetTester tester, List<Note> notes) async {
      await pumpApp(tester, home: SimpleTodos(notes: ValueNotifier(notes), clock: () => DateTime(2026, 10, 17, 12), onTick: (_, _, _) {}, onOpen: (_, _) {}));
      await tester.pump();
    }

    Future<void> away(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('ticks each, and the last is the ghost’s moment where its switch is on', (tester) async {
      await pump(tester, [makeNote('a', body: '- [ ] One\n- [ ] Two')]);
      // After the app is up, which puts the test's preferences in place.
      preferences.update((now) => now.copyWith(soundEvents: {'all-ticked': true}));
      await tester.tap(find.bySemanticsLabel('Tick One'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Tick Two'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(output.events, ['todo-ticked', 'all-ticked']);
      await away(tester);
    });

    testWidgets('with the flourish off, the last is a tick like the rest', (tester) async {
      await pump(tester, [makeNote('a', body: '- [ ] One')]);
      await tester.tap(find.bySemanticsLabel('Tick One'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(output.events, ['todo-ticked']);
      await away(tester);
    });
  });

  group('the recorder', () {
    testWidgets('starts with its sound, keeps every other quiet while it runs, and stops with its own', (tester) async {
      final capture = Capture(tester);
      await capture.open();
      await capture.settle();
      expect(output.events, ['record-start']);
      expect(output.played.single.whileRecording, isTrue);
      expect(sounds.recording, isTrue);
      // A failure said while recording is not heard over the take.
      preferences.update((now) => now.copyWith(soundEvents: {'failed': true}));
      sounds.play(SoundEvent.failed);
      await capture.say('Milk.', 0);
      await capture.doneAndFinished();
      await capture.close();
      expect(output.events, ['record-start', 'record-stop']);
      expect(sounds.recording, isFalse);
    });

    testWidgets('with its switches off makes no sound at all', (tester) async {
      final capture = Capture(tester)..prefs = Preferences.defaults.copyWith(soundEvents: {'record-start': false, 'record-stop': false});
      await capture.open();
      await capture.settle();
      await capture.discard();
      await capture.close();
      expect(output.played, isEmpty);
    });
  });

  group('a failure', () {
    testWidgets('said by a toast is heard where its switch is on, and only a failure', (tester) async {
      startSounds();
      addTearDown(() => GlacierToastProvider.onShown = null);
      late BuildContext inside;
      await pumpApp(tester, home: Builder(builder: (context) => (inside = context, const SizedBox()).$2));
      preferences.update((now) => now.copyWith(soundEvents: {'failed': true}));
      GlacierToast.of(inside).toast(message: const Text('Saved'));
      await tester.pump();
      GlacierToast.of(inside).toast(tone: GlacierToastTone.danger, message: const Text('Could not save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(output.events, ['failed']);
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 12));
    });
  });
}
