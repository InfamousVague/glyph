/// Where the fast speech model and the careful one heard different words. A port of `src/app/review/diff.ts`.
///
/// The live transcript comes from a small model that keeps up with speech; the review listens again with a larger
/// one. The places they disagree are where the fast one most likely slipped, and they are what the reviewing model is
/// shown first. A word-level diff (longest common subsequence over normalised words) grouped into runs, each with a
/// little context either side so a run can be found again in the note.
///
/// What differs: nothing but the home. Kept under lib/ai/support until lib/review has a diff.dart of its own.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One run the two transcripts differ by (`WordChange`).
class WordChange {
  const WordChange({required this.heard, required this.careful, required this.before, required this.after});

  /// What the fast model wrote, as written. Empty when the careful one heard words the fast one missed.
  final String heard;

  /// What the careful model wrote. Empty when the fast one wrote words that were not said.
  final String careful;

  /// A few words before the change, from the fast transcript, to place it.
  final String before;
  final String after;

  @override
  bool operator ==(Object other) => other is WordChange && other.heard == heard && other.careful == careful && other.before == before && other.after == after;

  @override
  int get hashCode => Object.hash(heard, careful, before, after);

  @override
  String toString() => 'WordChange(…$before [$heard → $careful] $after…)';
}

final RegExp _notWord = RegExp(r"[^\p{L}\p{N}']+", unicode: true);
final RegExp _space = RegExp(r'\s+');

String _norm(String word) => word.toLowerCase().replaceAll(_notWord, '');

/// Words and the spaces between them, so a run can be joined back as it was written.
List<String> _wordsOf(String text) => text.split(_space).where((word) => word.isNotEmpty).toList();

/// The runs where [fast] and [careful] differ, ignoring case and punctuation.
List<WordChange> wordChanges(String fast, String careful, [int context = 3]) {
  final a = _wordsOf(fast);
  final b = _wordsOf(careful);
  final na = a.map(_norm).toList();
  final nb = b.map(_norm).toList();
  // LCS table, small: a take is hundreds of words, not thousands.
  final rows = na.length + 1;
  final cols = nb.length + 1;
  final table = Uint16List(rows * cols);
  for (var i = na.length - 1; i >= 0; i -= 1) {
    for (var j = nb.length - 1; j >= 0; j -= 1) {
      table[i * cols + j] = na[i] == nb[j] ? table[(i + 1) * cols + j + 1] + 1 : math.max(table[(i + 1) * cols + j], table[i * cols + j + 1]);
    }
  }
  final changes = <WordChange>[];
  var i = 0;
  var j = 0;
  while (i < na.length || j < nb.length) {
    if (i < na.length && j < nb.length && na[i] == nb[j]) {
      i += 1;
      j += 1;
      continue;
    }
    final startA = i;
    final startB = j;
    while ((i < na.length || j < nb.length) && !(i < na.length && j < nb.length && na[i] == nb[j])) {
      if (j >= nb.length || (i < na.length && table[(i + 1) * cols + j] >= table[i * cols + j + 1])) {
        i += 1;
      } else {
        j += 1;
      }
    }
    final heard = a.sublist(startA, i).join(' ');
    final said = b.sublist(startB, j).join(' ');
    // The same words once case and punctuation go; "hello trade" and "HelloTrade" still differ.
    if (na.sublist(startA, i).join(' ') == nb.sublist(startB, j).join(' ')) continue;
    changes.add(
      WordChange(
        heard: heard,
        careful: said,
        before: a.sublist(math.max(0, startA - context), startA).join(' '),
        after: a.sublist(i, math.min(a.length, i + context)).join(' '),
      ),
    );
  }
  return changes;
}
