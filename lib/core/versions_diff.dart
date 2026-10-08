/// The change from one version of a note to the next, line by line, as git takes it: Myers' shortest edit script
/// (E. W. Myers, "An O(ND) Difference Algorithm and Its Variations", 1986). A port of
/// `src/app/core/versions/diff.ts`.
///
/// A version in a versions file is this change written out (versions_file.dart), so a file holds each version's new
/// lines and not the whole note again. The shared lines at the top and the foot are taken off before the search,
/// which is where nearly every edit of a note leaves most of it; the search then runs over what is left.
///
/// What differs: a step is one of three small classes ([Keep], [Del], [Add]) where the page has a union of object
/// shapes; and steps that keep a count below zero, which only a file changed by hand can say, do not fit
/// ([applySteps] answers null) where the page walks off the front of the array and is caught by the hash.
library;

import 'package:flutter/foundation.dart';

/// One step of a change: keep `n` lines, take one out, or put one in (`Step`).
@immutable
sealed class Step {
  const Step();
}

/// Keep [count] lines as they are (`{ keep }`).
class Keep extends Step {
  const Keep(this.count);
  final int count;

  @override
  bool operator ==(Object other) => other is Keep && other.count == count;

  @override
  int get hashCode => Object.hash(Keep, count);

  @override
  String toString() => '=$count';
}

/// Take the line [line] out (`{ del }`).
class Del extends Step {
  const Del(this.line);
  final String line;

  @override
  bool operator ==(Object other) => other is Del && other.line == line;

  @override
  int get hashCode => Object.hash(Del, line);

  @override
  String toString() => '-$line';
}

/// Put the line [line] in (`{ add }`).
class Add extends Step {
  const Add(this.line);
  final String line;

  @override
  bool operator ==(Object other) => other is Add && other.line == line;

  @override
  int get hashCode => Object.hash(Add, line);

  @override
  String toString() => '+$line';
}

/// A note's text as lines, split so that joining them with `\n` gives the text back exactly (`linesOf`).
List<String> linesOf(String text) => text.split('\n');

/// Appends a run of kept lines to [steps], joined to a run already at its end.
void _keep(List<Step> steps, int count) {
  if (count <= 0) return;
  final last = steps.isEmpty ? null : steps.last;
  if (last is Keep) {
    steps[steps.length - 1] = Keep(last.count + count);
  } else {
    steps.add(Keep(count));
  }
}

/// The steps that turn [before] into [after] (`diffLines`). Runs of kept lines are one step.
List<Step> diffLines(List<String> before, List<String> after) {
  var top = 0;
  while (top < before.length && top < after.length && before[top] == after[top]) {
    top += 1;
  }
  var foot = 0;
  while (foot < before.length - top && foot < after.length - top && before[before.length - 1 - foot] == after[after.length - 1 - foot]) {
    foot += 1;
  }
  final a = before.sublist(top, before.length - foot);
  final b = after.sublist(top, after.length - foot);

  final steps = <Step>[];
  _keep(steps, top);
  for (final step in _middle(a, b)) {
    if (step is Keep) {
      _keep(steps, step.count);
    } else {
      steps.add(step);
    }
  }
  _keep(steps, foot);
  return steps;
}

/// The shortest edit script from [a] to [b], by Myers' greedy search over diagonals, then traced back (`middle`).
List<Step> _middle(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0) return [for (final line in b) Add(line)];
  if (m == 0) return [for (final line in a) Del(line)];
  final max = n + m;
  final offset = max;
  final v = Int32List(2 * max + 2);
  final trace = <Int32List>[];
  var found = -1;
  for (var d = 0; d <= max && found < 0; d += 1) {
    trace.add(Int32List.fromList(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) ? v[offset + k + 1] : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x += 1;
        y += 1;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
  }
  // Back from the end along the path the search took, collecting its moves in reverse.
  final reversed = <Step>[];
  var x = n;
  var y = m;
  for (var d = found; d > 0; d -= 1) {
    final was = trace[d];
    final k = x - y;
    final down = k == -d || (k != d && was[offset + k - 1] < was[offset + k + 1]);
    final prevK = down ? k + 1 : k - 1;
    final prevX = was[offset + prevK];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      reversed.add(const Keep(1));
      x -= 1;
      y -= 1;
    }
    reversed.add(down ? Add(b[prevY]) : Del(a[prevX]));
    x = prevX;
    y = prevY;
  }
  while (x > 0 && y > 0) {
    reversed.add(const Keep(1));
    x -= 1;
    y -= 1;
  }
  final steps = <Step>[];
  for (final step in reversed.reversed) {
    if (step is Keep) {
      _keep(steps, step.count);
    } else {
      steps.add(step);
    }
  }
  return steps;
}

/// [before] with [steps] applied; null where the steps do not fit it (a file changed by hand, or a broken one)
/// (`applySteps`).
List<String>? applySteps(List<String> before, List<Step> steps) {
  final out = <String>[];
  var at = 0;
  for (final step in steps) {
    switch (step) {
      case Keep(:final count):
        if (count < 0 || at + count > before.length) return null;
        out.addAll(before.getRange(at, at + count));
        at += count;
      case Del(:final line):
        if (at >= before.length || before[at] != line) return null;
        at += 1;
      case Add(:final line):
        out.add(line);
    }
  }
  // What is left of the version before is kept: a change written without its last keep still reads.
  out.addAll(before.getRange(at, before.length));
  return out;
}

/// How many lines a change puts in and takes out, for a version's "+3 −1" (`countSteps`).
({int added, int removed}) countSteps(List<Step> steps) {
  var added = 0;
  var removed = 0;
  for (final step in steps) {
    if (step is Add) {
      added += 1;
    } else if (step is Del) {
      removed += 1;
    }
  }
  return (added: added, removed: removed);
}

/// A version's lines; none at all before the first version, rather than one empty line (`linesFrom`).
List<String> linesFrom(String? text) => text == null ? const [] : linesOf(text);

/// The first line a version put in or took out, against the version before it - or against nothing, for a note's
/// first - for the version's line on a timeline (`firstChange`). `kind` is `add` or `del`. Null when it changed no
/// line that says anything: a name given, or blank lines alone.
({String kind, String text})? firstChange(String? before, String after) {
  for (final step in diffLines(linesFrom(before), linesOf(after))) {
    if (step is Add && step.line.trim().isNotEmpty) return (kind: 'add', text: step.line.trim());
    if (step is Del && step.line.trim().isNotEmpty) return (kind: 'del', text: step.line.trim());
  }
  return null;
}
