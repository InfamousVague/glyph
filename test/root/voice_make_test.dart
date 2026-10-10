// Voice as the app makes it (lib/root/voice_wiring.dart `Voice.make`), over the Mac's core
// (native/target/debug/libghost_core.dylib, tool/build-native.sh host) and no phone. Skipped where the core is not
// built.
//
// Unwired 11 (docs/PARITY.md): the voice model and the better words' queue were never given `onVisible`, so a
// download that failed was tried again only by Try again or a relaunch, and the queue did not look again as the app
// came back (capture/useVoiceModel.ts:58-62, capture/refine.ts:226-229). Unwired 10: what `Voice.make` is given as
// `record` is the summary queue's row in the feed ("A meeting was written up").
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/root/voice_wiring.dart';

import '../capture_native/support.dart';

void main() {
  test('the voice model, the better words\' queue and the summaries hear the app come back to the screen, and the queue\'s row in the feed is the one it was given', () async {
    final missing = await TestCore.missing();
    if (missing != null) return markTestSkipped(missing);
    preferences.startWithoutStorage();
    final it = await TestCore.open('voice-make');
    addTearDown(it.close);
    addTearDown(() => useAiBackend(const NoAiBackend()));
    // No mirror: nothing is asked of anywhere.
    final making = await VoiceMaking.attach(it.core, dataDir: it.dataDir, mirrors: const []);
    final recorded = <(String, Object?)>[];
    final voice = await Voice.make(making, library: SampleLibrary.seeded(), kept: MemoryStored(), record: (kind, details) async => recorded.add((kind, details['noteId'])));
    addTearDown(voice.dispose);

    final model = voice.recorder.voiceModel, refining = voice.recorder.refining!;
    expect(model.onVisible, isNotNull, reason: 'a failed download is tried again each time the app comes back');
    expect(refining.onVisible, isNotNull, reason: 'the better words\' queue looks again as the app comes back');
    // One teller for all three: what the root feeds the app's lifecycle.
    var told = 0;
    final stops = [model.onVisible!(() => told += 1), refining.onVisible!(() => told += 1), voice.summaries!.onVisible(() => told += 1)];
    voice.recorder.lifecycle(AppLifecycleState.paused);
    expect(told, 0);
    voice.recorder.lifecycle(AppLifecycleState.resumed);
    expect(told, 3);
    for (final stop in stops) {
      stop();
    }
    voice.recorder.lifecycle(AppLifecycleState.resumed);
    expect(told, 3);

    await voice.summaries!.record('summary-written', {'noteId': 'n1', 'title': 'Standup'});
    expect(recorded, [('summary-written', 'n1')]);
  });
}
