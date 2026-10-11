/// What the review after a recording is doing before its model runs: listening again, comparing. The `ReviewStage`
/// of `src/app/ai/useNoteReview.ts`, in a file of its own so the AI's strip and the at-work scene (lib/scene) can
/// name it without the review's whole machine (ai/note_review.dart, which says these).
library;

import 'package:flutter/foundation.dart';

/// A stage of the review (`ReviewStage`).
@immutable
class ReviewStage {
  const ReviewStage({required this.what, required this.detail, required this.percent});

  /// "Listening again", "Comparing".
  final String what;
  final String detail;

  /// 0 to 100 while it can be told, else null.
  final int? percent;

  @override
  bool operator ==(Object other) => other is ReviewStage && other.what == what && other.detail == detail && other.percent == percent;

  @override
  int get hashCode => Object.hash(what, detail, percent);

  @override
  String toString() => 'ReviewStage($what, $detail, $percent)';
}
