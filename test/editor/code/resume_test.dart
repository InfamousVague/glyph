// A block that changed is read on from where it changed, not from its first line (`CodeLanguage.resume`: a Lezer
// parse from the last checkpoint before the change, an older mode from the changed line's kept state). What that
// must never do is colour a block otherwise than reading it whole would: here each language's sample, written
// out several times over so that it has checkpoints in it, is changed two hundred times by chance (a letter
// typed, a stretch deleted, a quote or a bracket or a comment opened where one should not be), and after every
// change the runs of the block taken up again are held to the runs of the same text read from nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/languages.dart';
import 'package:ghost_md/editor/code/stream/js_mode.dart';
import 'package:ghost_md/editor/code/stream/stream_language.dart';
import 'package:ghost_md/editor/code/work.dart';

List<Object> runs(CodeWork work, int from, int to) {
  final out = <Object>[];
  work.spans(from, to, (a, b, cls) {
    out
      ..add(a)
      ..add(b)
      ..add(cls);
  });
  return out;
}

void main() {
  final tokens = (jsonDecode(File('test/editor/code/fixtures/tokens.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  const pieces = <String>['x', ' ', '\n', '"', "'", '/*', '*/', '{', '}', '(', ')', '<', '>', '#', '//', '`', 'if ', 'def f():\n', '  ', '\$', ';', '= 1', '<b>', '-->', '"""'];

  for (final sample in tokens) {
    final name = sample['language'] as String;
    final language = languageNamed(name);
    if (language == null || (sample['file'] as String).startsWith('broken')) continue;
    // The message-chart modes keep whether they are in an attribute list on the mode itself, not in a state:
    // what one of them makes of a block depends on every block it has read, on the web as here, and one
    // reading is not held to another.
    if (const <String>{'MscGen', 'Xù', 'MsGenny'}.contains(name)) continue;
    test('${sample['file']}: $name taken up again is $name read whole', () {
      final random = Random(name.hashCode & 0xffff);
      final code = sample['code'] as String;
      // A mode run from its JavaScript is taken up again by the same few lines of Dart whichever mode it is
      // (`StreamWork`), and what is its own, its state copied at each line, shows in a shorter run: a third
      // of the text and two fifths of the changes, for the hundred of them.
      final interpreted = language is StreamLanguage && language.mode is JsMode;
      var text = List<String>.filled(interpreted ? max(3, (2000 / code.length).ceil()) : max(6, (6000 / code.length).ceil()), code).join('\n');
      var work = language.start(text)..work(text.length, Budget.none());
      CodeStats.reset();
      for (var step = 0; step < (interpreted ? 80 : 200); step++) {
        final at = random.nextInt(text.length + 1);
        final kind = random.nextInt(10);
        if (kind < 6) {
          text = text.substring(0, at) + pieces[random.nextInt(pieces.length)] + text.substring(at);
        } else if (kind < 9) {
          final end = min(text.length, at + random.nextInt(12));
          text = text.substring(0, at) + text.substring(end);
        } else {
          // Half of it read only, as a block being read in slices is when a letter lands in it.
          final cut = language.start(text)..work(text.length ~/ 2, Budget.none());
          work = cut;
          continue;
        }
        work = language.resume(work, text)..work(text.length, Budget.none());
        final fresh = language.start(text)..work(text.length, Budget.none());
        expect(work.done, isTrue);
        final a = runs(work, 0, text.length), b = runs(fresh, 0, text.length);
        if (a.length != b.length || a.toString() != b.toString()) {
          var i = 0;
          while (i < a.length && i < b.length && a[i] == b[i]) {
            i++;
          }
          i -= i % 3;
          fail('step $step: the runs part at ${i ~/ 3}: taken up ${a.skip(i).take(9).toList()}, read whole ${b.skip(i).take(9).toList()}\naround ${jsonEncode(text.substring(max(0, (a.length > i ? a[i] as int : text.length) - 30), min(text.length, (a.length > i ? a[i] as int : text.length) + 30)))}');
        }
        // And a stretch of it asked for by itself is the same stretch of the whole.
        final from = random.nextInt(text.length + 1), to = min(text.length, from + random.nextInt(400));
        expect(runs(work, from, to).toString(), runs(fresh, from, to).toString(), reason: 'step $step, $from to $to');
      }
      // Where a sample written out again and again is still good code, some change was past a checkpoint.
      if (const <String>{'JavaScript', 'TypeScript', 'Python', 'Rust', 'Go', 'Java', 'C++', 'CSS', 'Kotlin', 'Swift', 'Ruby', 'Shell', 'Lua'}.contains(name)) {
        expect(CodeStats.resumed, greaterThan(0), reason: 'never taken up from a checkpoint');
      }
    });
  }
}
