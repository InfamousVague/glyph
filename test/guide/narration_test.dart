import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/guide/narration.dart';
import 'package:ghost_md/guide/pages.dart';

/// The voice and the captions are the same words: every file in assets/onboarding was made from the words
/// lib/guide/narration.dart has now (tool/onboarding_voice.py writes what it made from into narration.json, as the
/// first sixteen hex of the words' SHA-256). A page's words changed and not spoken again fails here.
void main() {
  final manifest = jsonDecode(File('assets/onboarding/narration.json').readAsStringSync()) as Map<String, dynamic>;
  final files = (manifest['files'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
  String digest(String words) => sha256.convert(utf8.encode(words)).toString().substring(0, 16);

  test('has each file made from the words the page shows now', () {
    for (final MapEntry(key: name, value: made) in files.entries) {
      final page = GuidePage.values.byName(name);
      expect(made['words'], digest(narration[page]!), reason: '$name: its words changed; run python3 tool/onboarding_voice.py');
      expect(File(narrationAsset(page)).existsSync(), isTrue, reason: name);
    }
  });

  test('reads the words the way the tool does', () {
    // The tool's pattern over narration.dart, here: an entry it cannot read would be a page with no voice.
    final source = File('lib/guide/narration.dart').readAsStringSync();
    final read = {for (final m in RegExp(r"GuidePage\.(\w+):\s*'((?:[^'\\]|\\.)*)'").allMatches(source)) m[1]!: m[2]!};
    expect(read.keys.toSet(), {for (final page in GuidePage.values) page.name});
    for (final page in GuidePage.values) {
      expect(read[page.name], narration[page], reason: page.name);
    }
  });

  test('has a voice for every page, small enough to carry', () {
    for (final page in GuidePage.values) {
      expect(files.containsKey(page.name), isTrue, reason: '${page.name} has no voice yet; run python3 tool/onboarding_voice.py');
    }
    final total = files.values.fold<int>(0, (sum, made) => sum + (made['bytes'] as int));
    expect(total, lessThan(3 * 1024 * 1024));
  }, skip: files.isEmpty ? 'No voice has been made yet: ElevenLabs needs ~/.elevenlabs-key, then python3 tool/onboarding_voice.py' : false);
}
