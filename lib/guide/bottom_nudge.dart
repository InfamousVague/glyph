/// Next waits at the bottom of a guide page: it only shows once the page has been scrolled to its end. Until then,
/// after a moment, a nudge fades in where it will be, and a tap on the nudge takes the reader down (guide.dart). A
/// page that fits the screen is already at its bottom. A port of `src/app/guide/useBottomNudge.ts`.
///
/// What differs: the hook watched an element (its scroll, a `ResizeObserver`, a `MutationObserver`); this is a
/// notifier the guide tells what its scroller measures ([BottomNudge.measured]) and when a page opens
/// ([BottomNudge.opened]), which is every time the scroller reports a scroll or new metrics.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What the nudge says, one picked each time a page opens (Matt: "a 'Down Here' button … put 6 different sassy
/// phrases it could use") (`NUDGES`).
const List<String> nudges = <String>['Down here.', 'Keep scrolling, hon.', 'It’s not up there.', 'Scroll. I’ll wait.', 'The good bit’s lower.', 'Thumb down. Literally.'];

/// How long a page is read before the nudge fades in (`NUDGE_AFTER_MS`).
const Duration nudgeAfter = Duration(milliseconds: 2400);

/// How close to the end counts as the bottom (`BOTTOM_SLACK_PX`).
const double bottomSlack = 24;

/// `BottomNudge`, and the hook that kept it.
class BottomNudge extends ChangeNotifier {
  BottomNudge({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  Timer? _timer;
  bool _atBottom = true;
  bool _due = false;
  String _words = nudges.first;

  /// The page has been read to its end, or fits the screen: Next shows.
  bool get atBottom => _atBottom;

  /// The page has been open long enough for the nudge, if it is still wanted.
  bool get due => _due;

  /// What the nudge says on this page.
  String get words => _words;

  /// A page has opened: the wait starts afresh, with new words.
  void opened() {
    _timer?.cancel();
    _due = false;
    _words = nudges[_random.nextInt(nudges.length)];
    _timer = Timer(nudgeAfter, () {
      _due = true;
      notifyListeners();
    });
    notifyListeners();
  }

  /// What the scroller measures now: how far there is to scroll, and how far it has (`check`).
  void measured({required double max, required double pixels}) {
    final at = max - pixels <= bottomSlack;
    if (at == _atBottom) return;
    _atBottom = at;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
