/// The model's output read into answers, by blank (docs/DESIGN.md §145, 5.6). A port of `src/app/ai/fills/read.ts`.
/// Pure.
///
/// An answer line is `[N] words`, a space after the bracket: a note's own numbered lists are `1. ` and `1) `, a
/// reference definition is `[1]: `, and a `[1]` inside a line is not at its start, so a model carrying on a list with
/// `3. Rail pass` never fills blank 3. The same number on several lines is an items blank's items, in order. A number
/// that was not asked is passed over. With one blank asked, a bare answer is read too, so a model that never writes
/// `[1]` (the 2B, Gemma) still fills a single blank.
///
/// What differs: nothing.
library;

import '../../core/item_syntax.dart' show jsTrim;

final RegExp _line = RegExp(r'^\s*\[(\d{1,2})\] +(.*)$');

/// Every asked blank's lines, by its number; a blank with none has none. [asked] is the numbers asked, in order.
Map<int, List<String>> readFill(String text, List<int> asked) {
  final lines = text.replaceAll('\r', '').split('\n');
  final answers = <int, List<String>>{for (final n in asked) n: []};
  var numbered = false;
  for (final line in lines) {
    final found = _line.firstMatch(line);
    if (found == null) continue;
    numbered = true;
    final n = int.parse(found.group(1)!);
    final words = jsTrim(found.group(2)!);
    if (answers.containsKey(n) && words.isNotEmpty) answers[n]!.add(words);
  }
  if (!numbered && asked.length == 1) {
    answers[asked[0]] = lines.map(jsTrim).where((l) => l.isNotEmpty).toList();
  }
  return answers;
}

/// Whether every line with words is an `[N]` line for an asked blank: the bar rung 1 is held to (5.8).
bool allNumbered(String text, List<int> asked) => text.split('\n').where((l) => jsTrim(l).isNotEmpty).every((l) {
  final found = _line.firstMatch(l);
  return found != null && asked.contains(int.parse(found.group(1)!));
});

/// Each ask's answer lines, by the numbers the message wrote it with (ai/fills/message.dart `Built.numbers`): an
/// items blank's slots in order. With no numbered line at all and one ask, the bare answer is that ask's, every line
/// of it.
List<List<String>> readAsks(String text, List<List<int>> numbers) {
  final flat = [for (final mine in numbers) ...mine];
  final read = readFill(text, flat);
  final numbered = text.split('\n').any(_line.hasMatch);
  if (!numbered && numbers.length == 1) {
    return [text.split('\n').map(jsTrim).where((l) => l.isNotEmpty).toList()];
  }
  return [
    for (final mine in numbers) [for (final n in mine) ...?read[n]],
  ];
}
