/// A note's words changed on two sides since they last agreed, put together line by line, as git merges a file
/// (Matt, 2026-10-29: "make it so the transcripts and meeting summaries are shown in one file"). The port's own.
///
/// What it was for: a meeting Ghost was in is filed on one of the person's devices, its summary written on that one
/// or another, and its transcript landed by the device holding its recording; and the summary's device files it in an
/// organization's Meetings folder (lib/ai/meeting_sort.dart). The device that lands the transcript has the words from
/// before the summary, and adds the transcript to those. Read whole, its words said the summary was taken out: the
/// team's channel took them as the note (lib/team/sync.dart, a note this device had of its own before the team did),
/// and the summary went from every device; the account's own sync kept them as a conflict copy, a second note of the
/// one meeting. Merged from the words both last had, the summary under the title and the transcript under the
/// captions are two changes to different lines, and both stand in one note.
///
/// The rule ([mergedWords]): each side's change from [base] is a list of hunks, lines taken out and put in at a place
/// of base's. Hunks of the two sides that touch different lines are each applied once, a hunk that ends where the
/// other side's begins too (a table's two neighbouring rows, one edited on each side, are both kept); the same hunk on
/// both sides once; lines put in where the other side changed the lines after (the summary put in above the first
/// line the transcript's side changed) go first. Two hunks over the same lines, or two different insertions at one
/// place, are a conflict, and the answer is null: the caller does what it did before (a copy, or this device's words
/// with the summary kept: [withSummaryOf]), never a guess.
///
/// THE DIFF IS IN LINEAR SPACE (the Testing session, 2026-10-29). The versions' diff (lib/core/versions_diff.dart
/// `diffLines`) keeps Myers' whole trace, a row of 2(n+m)+2 integers for every edit, so a change that is all edit takes
/// about (n+m)² × 8 bytes: the transcript's side of a meeting drops `## Captions` and puts `## Transcript` in, both
/// thousands of lines (yesterday's standup had 362,000 characters of captions), which is some 72 MB at 3,000 lines and
/// 200 MB at 5,000, inside a sync on the phone. Here it is Myers' middle snake, divide and conquer (E. W. Myers 1986,
/// section 4b, as diff-match-patch's `bisect` writes it): two rows of the diagonals at a time, so memory is O(n+m),
/// the lines compared as numbers. Time is still O((n+m)·D), so the work is counted, and a merge past [mergeWorkMost]
/// steps, or of more than [mergeLinesMost] lines on a side, answers null: the caller's fallback, which keeps the
/// summary. [mergeDiffPeakBytes] says the most a merge's diffs held at once, for the tests to measure.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'summary_text.dart';

/// The most steps along the diagonals one merge's two diffs may take, every snake's step counted: about half a second
/// on the Mac, two or three times what a 4,000-line captions-to-transcript swap takes (test/core/merge_words_test.dart).
/// Past it, the merge answers null.
const int mergeWorkMost = 40000000;

/// The most lines a side of a merge may have; past it, the merge answers null without looking.
const int mergeLinesMost = 100000;

/// The most bytes the last merge's diffs held at once: the two rows of the diagonals, the work list and the matches
/// (the lines themselves, and the table that numbers them, are the note's size and not counted).
@visibleForTesting
int mergeDiffPeakBytes = 0;

/// [mine], with the summary section [theirs] has (lib/core/summary_text.dart) written at its place where [mine] has
/// none; [mine] as it is otherwise.
String withSummaryOf(String mine, String theirs) {
  if (summarySection(mine) != null) return mine;
  final section = summarySection(theirs);
  return section == null ? mine : withSummary(mine, section.text);
}

/// One side's change to a run of base's lines: base's lines [start] to [end] (none, for an insertion) become [lines].
class _Hunk {
  const _Hunk(this.start, this.end, this.lines);
  final int start;
  final int end;
  final List<String> lines;

  bool get insertion => start == end;

  bool same(_Hunk other) {
    if (other.start != start || other.end != end || other.lines.length != lines.length) return false;
    for (var i = 0; i < lines.length; i += 1) {
      if (other.lines[i] != lines[i]) return false;
    }
    return true;
  }
}

/// More work than a merge may do.
class _TooMuch implements Exception {
  const _TooMuch();
}

/// One diff of numbered lines, [a] to [b], in linear space (see the header): the runs both keep, as (a's start, b's
/// start, length), in order.
class _Diff {
  _Diff(this.a, this.b, this.budget);

  final Int32List a;
  final Int32List b;

  /// Steps left of the merge's work.
  int budget;
  int _peak = 0;

  /// The runs kept, three numbers a run.
  final List<int> kept = <int>[];

  void _held(int bytes) {
    if (bytes > _peak) _peak = bytes;
  }

  int get peak => _peak;

  void run() {
    // The work list: a range to diff (0, aLo, aHi, bLo, bHi), or a run kept (1, aStart, bStart, length, 0), taken from
    // the end, so pushed in the reverse of the order they go in.
    final work = <int>[0, 0, a.length, 0, b.length];
    while (work.isNotEmpty) {
      _held(work.length * 8 + kept.length * 8);
      final s = work.removeLast(), r = work.removeLast(), q = work.removeLast(), p = work.removeLast(), kind = work.removeLast();
      if (kind == 1) {
        kept
          ..add(p)
          ..add(q)
          ..add(r);
        continue;
      }
      var aLo = p, aHi = q, bLo = r, bHi = s;
      final from = aLo, fromB = bLo;
      while (aLo < aHi && bLo < bHi && a[aLo] == b[bLo]) {
        aLo += 1;
        bLo += 1;
      }
      final head = aLo - from;
      var foot = 0;
      while (aHi > aLo && bHi > bLo && a[aHi - 1] == b[bHi - 1]) {
        aHi -= 1;
        bHi -= 1;
        foot += 1;
      }
      budget -= head + foot + 1;
      if (foot > 0) work.addAll([1, aHi, bHi, foot, 0]);
      if (aLo < aHi && bLo < bHi) {
        final split = _bisect(aLo, aHi, bLo, bHi);
        if (split != null) {
          final (x, y) = split;
          work.addAll([0, aLo + x, aHi, bLo + y, bHi]);
          work.addAll([0, aLo, aLo + x, bLo, bLo + y]);
        }
      }
      if (head > 0) work.addAll([1, from, fromB, head, 0]);
      if (budget < 0) throw const _TooMuch();
    }
  }

  /// Where the middle snake of a's lines [aLo] to [aHi] and b's [bLo] to [bHi] splits them, as offsets into each; null
  /// where they have no line in common, or the split would not make either half smaller.
  (int, int)? _bisect(int aLo, int aHi, int bLo, int bHi) {
    final n = aHi - aLo, m = bHi - bLo;
    final most = (n + m + 1) ~/ 2;
    final offset = most, length = 2 * most + 2;
    final v1 = Int32List(length)..fillRange(0, length, -1);
    final v2 = Int32List(length)..fillRange(0, length, -1);
    _held(2 * length * 4 + kept.length * 8);
    v1[offset + 1] = 0;
    v2[offset + 1] = 0;
    final delta = n - m;
    final front = delta.isOdd;
    var k1start = 0, k1end = 0, k2start = 0, k2end = 0;
    (int, int)? found;
    for (var d = 0; d < most && found == null; d += 1) {
      for (var k1 = -d + k1start; k1 <= d - k1end && found == null; k1 += 2) {
        final at = offset + k1;
        var x1 = (k1 == -d || (k1 != d && v1[at - 1] < v1[at + 1])) ? v1[at + 1] : v1[at - 1] + 1;
        var y1 = x1 - k1;
        while (x1 < n && y1 < m && a[aLo + x1] == b[bLo + y1]) {
          x1 += 1;
          y1 += 1;
          budget -= 1;
        }
        budget -= 1;
        v1[at] = x1;
        if (x1 > n) {
          k1end += 2;
        } else if (y1 > m) {
          k1start += 2;
        } else if (front) {
          final there = offset + delta - k1;
          if (there >= 0 && there < length && v2[there] != -1 && x1 >= n - v2[there]) found = (x1, y1);
        }
      }
      for (var k2 = -d + k2start; k2 <= d - k2end && found == null; k2 += 2) {
        final at = offset + k2;
        var x2 = (k2 == -d || (k2 != d && v2[at - 1] < v2[at + 1])) ? v2[at + 1] : v2[at - 1] + 1;
        var y2 = x2 - k2;
        while (x2 < n && y2 < m && a[aLo + n - x2 - 1] == b[bLo + m - y2 - 1]) {
          x2 += 1;
          y2 += 1;
          budget -= 1;
        }
        budget -= 1;
        v2[at] = x2;
        if (x2 > n) {
          k2end += 2;
        } else if (y2 > m) {
          k2start += 2;
        } else if (!front) {
          final there = offset + delta - k2;
          if (there >= 0 && there < length && v1[there] != -1) {
            final x1 = v1[there], y1 = offset + x1 - there;
            if (x1 >= n - x2) found = (x1, y1);
          }
        }
      }
      if (budget < 0) throw const _TooMuch();
    }
    if (found == null) return null;
    final (x, y) = found;
    // A split at either end makes nothing smaller: the two ranges are one change.
    if ((x <= 0 && y <= 0) || (x >= n && y >= m)) return null;
    return found;
  }
}

/// The hunks that turn base into [other], from the runs [diff] kept.
List<_Hunk> _hunks(List<String> other, _Diff diff) {
  final out = <_Hunk>[];
  var pa = 0, pb = 0;
  final kept = diff.kept;
  for (var i = 0; i < kept.length; i += 3) {
    final ka = kept[i], kb = kept[i + 1], n = kept[i + 2];
    if (ka > pa || kb > pb) out.add(_Hunk(pa, ka, other.sublist(pb, kb)));
    pa = ka + n;
    pb = kb + n;
  }
  if (pa < diff.a.length || pb < diff.b.length) out.add(_Hunk(pa, diff.a.length, other.sublist(pb, diff.b.length)));
  return out;
}

/// Whether two hunks of different sides touch the same lines: they overlap, or both put lines in at one place, or one
/// puts lines in strictly inside the other's run. Two runs that only meet, one ending where the other begins, do not.
bool _clash(_Hunk a, _Hunk b) {
  if (a.same(b)) return false;
  if (a.insertion && b.insertion) return a.start == b.start;
  if (a.insertion) return b.start < a.start && a.start < b.end;
  if (b.insertion) return a.start < b.start && b.start < a.end;
  return a.start < b.end && b.start < a.end;
}

/// [mine] and [theirs], each changed from [base], as one: every change of both, where none of them touch the same
/// lines (see the header). Null where two do, or where the merge would take more than it may. Where one side did not
/// change, the other's words.
String? mergedWords(String base, String mine, String theirs) {
  mergeDiffPeakBytes = 0;
  if (mine == theirs || theirs == base) return mine;
  if (mine == base) return theirs;
  final was = base.split('\n'), ours = mine.split('\n'), others = theirs.split('\n');
  if (was.length > mergeLinesMost || ours.length > mergeLinesMost || others.length > mergeLinesMost) return null;
  // Each distinct line a number, so the diffs compare integers.
  final numbers = <String, int>{};
  Int32List numbered(List<String> lines) {
    final out = Int32List(lines.length);
    for (var i = 0; i < lines.length; i += 1) {
      out[i] = numbers.putIfAbsent(lines[i], () => numbers.length);
    }
    return out;
  }

  final baseIds = numbered(was);
  final first = _Diff(baseIds, numbered(ours), mergeWorkMost);
  _Diff? second;
  try {
    first.run();
    second = _Diff(baseIds, numbered(others), first.budget)..run();
  } on _TooMuch {
    return null;
  } finally {
    final peak = second?.peak ?? 0;
    mergeDiffPeakBytes = first.peak > peak ? first.peak : peak;
  }
  final mineHunks = _hunks(ours, first), theirHunks = _hunks(others, second);
  // Both lists are in base's order, so each of mine is held against the few of theirs near it: those that end before
  // it starts touch none of mine after it either, and those that start past its end, none before them.
  var from = 0;
  for (final a in mineHunks) {
    while (from < theirHunks.length && theirHunks[from].end < a.start) {
      from += 1;
    }
    for (var j = from; j < theirHunks.length && theirHunks[j].start <= a.end; j += 1) {
      if (_clash(a, theirHunks[j])) return null;
    }
  }
  // Every hunk once, in base's order; at one place, the lines put in before a run the other side changed.
  final mineAt = <int, List<_Hunk>>{};
  for (final a in mineHunks) {
    (mineAt[a.start] ??= <_Hunk>[]).add(a);
  }
  final all = [
    ...mineHunks,
    for (final b in theirHunks)
      if (!(mineAt[b.start]?.any((a) => a.same(b)) ?? false)) b,
  ]..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : (a.insertion == b.insertion ? 0 : (a.insertion ? -1 : 1)));
  final out = <String>[];
  var at = 0;
  for (final hunk in all) {
    if (hunk.start < at) return null;
    out.addAll(was.getRange(at, hunk.start));
    out.addAll(hunk.lines);
    at = hunk.end;
  }
  out.addAll(was.getRange(at, was.length));
  return out.join('\n');
}
