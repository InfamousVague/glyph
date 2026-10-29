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
/// of base's (lib/core/versions_diff.dart `diffLines`, Myers' shortest edit script). Hunks of the two sides that touch
/// different lines are each applied once; the same hunk on both sides once; lines put in where the other side changed
/// the lines after (the summary put in above the first line the transcript's side changed) go first. Two hunks over
/// the same lines, or two different insertions at one place, are a conflict, and the answer is null: the caller does
/// what it did before (a copy, or this device's words), never a guess.
///
/// [withSummaryOf] is what a caller falls back to where they clash: its own words, with the app's summary section
/// of the other side's put in where its own have none, so a meeting's summary is never what a clash loses.
library;

import 'summary_text.dart';
import 'versions_diff.dart';

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

/// The hunks that turn [base] into [other].
List<_Hunk> _hunks(List<String> base, List<String> other) {
  final out = <_Hunk>[];
  var at = 0;
  int? start;
  var put = <String>[];
  void close() {
    if (start != null) out.add(_Hunk(start!, at, put));
    start = null;
    put = <String>[];
  }

  for (final step in diffLines(base, other)) {
    switch (step) {
      case Keep(:final count):
        close();
        at += count;
      case Del():
        start ??= at;
        at += 1;
      case Add(:final line):
        start ??= at;
        put.add(line);
    }
  }
  close();
  return out;
}

/// Whether two hunks of different sides touch the same lines: they overlap, or both put lines in at one place, or one
/// puts lines in strictly inside the other's run.
bool _clash(_Hunk a, _Hunk b) {
  if (a.same(b)) return false;
  if (a.insertion && b.insertion) return a.start == b.start;
  if (a.insertion) return b.start < a.start && a.start < b.end;
  if (b.insertion) return a.start < b.start && b.start < a.end;
  return a.start < b.end && b.start < a.end;
}

/// [mine] and [theirs], each changed from [base], as one: every change of both, where none of them touch the same
/// lines (see the header). Null where two do. Where one side did not change, the other's words.
String? mergedWords(String base, String mine, String theirs) {
  if (mine == theirs || theirs == base) return mine;
  if (mine == base) return theirs;
  final was = linesOf(base);
  final ours = _hunks(was, linesOf(mine)), others = _hunks(was, linesOf(theirs));
  for (final a in ours) {
    for (final b in others) {
      if (_clash(a, b)) return null;
    }
  }
  // Every hunk once, in base's order; at one place, the lines put in before a run the other side changed.
  final all = [
    ...ours,
    for (final b in others)
      if (!ours.any((a) => a.same(b))) b,
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
