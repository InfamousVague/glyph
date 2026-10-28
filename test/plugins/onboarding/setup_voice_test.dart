// The plugins' setup read aloud (Matt, 2026-10-28: "The voiceover with elevenlabs isn't working on the lovart
// onboarding"): every step's words have their clip in assets/plugin-setup, made from those words, and the sheet says
// the step's clip as it shows, and stops when it goes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/guide/narrator.dart';
import 'package:ghost_md/plugins/lovart/lovart_setup.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';

import '../github/support.dart';

class FakeVoice implements NarrationOutput {
  final List<String> calls = [];

  @override
  Future<bool> narrate(String key, Uint8List bytes) async {
    calls.add('narrate ${key.split('/').last}');
    return true;
  }

  @override
  Future<void> hush() async => calls.add('hush');
}

void main() {
  test('every step has its clip, made from its words as they are now', () {
    final made = jsonDecode(File('assets/plugin-setup/narration.json').readAsStringSync()) as Map<String, Object?>;
    final files = (made['files'] as Map).cast<String, Object?>();
    for (final MapEntry(key: name, value: words) in setupVoice.entries) {
      expect(File(setupVoiceAsset(name)).existsSync(), isTrue, reason: '$name has no clip: python3 tool/plugin_setup_voice.py');
      expect(files.containsKey(name), isTrue, reason: name);
      final entry = (files[name] as Map).cast<String, Object?>();
      // tool/onboarding_voice.py writes the first sixteen hex of the words' SHA-256.
      expect(entry['words'], sha256.convert(utf8.encode(words)).toString().substring(0, 16), reason: '$name was said from other words: python3 tool/plugin_setup_voice.py');
    }
  });

  testWidgets('the sheet says the step showing, and stops when it is put away', (tester) async {
    useStored(MemoryStored());
    final out = FakeVoice();
    final voice = VoiceOver(output: out, load: (asset) async => ByteData(8));
    var open = true;
    await pumpPane(
      tester,
      StatefulBuilder(
        builder: (context, set) => open
            ? PluginSetupSheet(setup: lovartSetup(), memory: SetupMemory(MemoryStored()), voice: voice, onClose: () => set(() => open = false))
            : const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(out.calls, contains('narrate lovart-intro.mp3'));
    await tester.tap(find.byKey(const ValueKey('setup-skip')));
    await tester.pump();
    expect(out.calls.last, 'hush');
    await away(tester);
  });
}
