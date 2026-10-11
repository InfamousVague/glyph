import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/detent_feel.dart';
import 'package:ghost_md/core/pull.dart';
import 'package:ghost_md/core/swipe.dart';
import 'package:ghost_md/tapes/tape.dart';

import 'make_note.dart';

/// The pure halves of the page's gestures, case for case with the web's tests: a note's swipes
/// (`notes/swipe.test.ts`), a pull to refresh (`core/pull.test.ts`), a detent felt coming
/// (`core/detentFeel.test.ts`); and the tape's counter and reels (`capture/tape.ts`).
void main() {
  const left = [
    SwipeAction(id: 'archive', label: 'Archive', icon: SwipeIcon.archive, tone: SwipeTone.neutral, detent: 0.22, removes: true),
    SwipeAction(id: 'delete', label: 'Delete', icon: SwipeIcon.delete, tone: SwipeTone.danger, detent: 0.55, removes: true),
  ];

  group('a note’s swipes (docs/DESIGN.md §151)', () {
    test('pins or unpins to the right, archives to the left, and deletes further left', () {
      final plain = noteSwipes(makeNote('a', body: '# Plain'));
      expect([for (final a in plain.start) [a.id, a.label]], [['pin', 'Pin']]);
      expect([for (final a in noteSwipes(makeNote('b', body: '# Pinned', starred: true)).start) [a.id, a.label, a.icon]], [['pin', 'Unpin', SwipeIcon.unpin]]);
      expect([for (final a in plain.end) [a.id, a.detent, a.tone]], [
        ['archive', 0.22, SwipeTone.neutral],
        ['delete', 0.55, SwipeTone.danger],
      ]);
      expect(armedAt(plain.end, 0.3)?.id, 'archive');
      expect(armedAt(plain.end, 0.6)?.id, 'delete');
      expect(['pin', 'archive', 'delete', 'restore'].map(isNoteSwipe), [true, true, true, false]);
      expect(noteSwipeOf('archive'), NoteSwipe.archive);
    });
  });

  group('swipe detents', () {
    test('arms nothing short of the first detent, then the furthest one passed', () {
      expect(armedAt(left, 0.1), isNull);
      expect(armedAt(left, 0.22)?.id, 'archive');
      expect(armedAt(left, 0.5)?.id, 'archive');
      expect(armedAt(left, 0.7)?.id, 'delete');
    });

    test('leaves the screen edges to the back gesture', () {
      expect(startsInGestureEdge(10, 400), isTrue);
      expect(startsInGestureEdge(395, 400), isTrue);
      expect(startsInGestureEdge(200, 400), isFalse);
    });

    test('follows the finger, then resists past the last detent', () {
      expect(followFinger(-100, 0.55, 400), -100);
      final far = followFinger(-400, 0.55, 400);
      expect(far, lessThan(0));
      expect(far.abs(), lessThan(400));
      expect(far.abs(), greaterThan((0.55 + 0.18) * 400));
    });
  });

  group('how far the page follows the finger', () {
    test('follows at half the travel to the detent, then as a rubber band, and never past the most', () {
      expect(pullOffset(-20), 0);
      expect(pullOffset(40), 20);
      expect(pullOffset(pullDetentPx * 2), pullDetentPx);
      final past = pullOffset(pullDetentPx * 2 + 60);
      expect(past, greaterThan(pullDetentPx));
      expect(past, lessThan(pullDetentPx + 30));
      expect(pullOffset(5000), pullMostPx);
    });

    test('refreshes on a let-go at the detent or past it', () {
      expect(pullArmed(pullDetentPx - 1), isFalse);
      expect(pullArmed(pullDetentPx), isTrue);
    });
  });

  group('which touches are a pull', () {
    test('is a quick drag down, more than across, from a page at its top', () {
      expect(pullIntent(0, 4, true, 20), PullIntent.undecided);
      expect(pullIntent(2, 14, true, 60), PullIntent.pull);
    });

    test('leaves the page anything else: scrolled down, going up, going across, or a finger that rested first', () {
      expect(pullIntent(2, 14, false, 60), PullIntent.other);
      expect(pullIntent(2, -14, true, 60), PullIntent.other);
      expect(pullIntent(14, 12, true, 60), PullIntent.other);
      expect(pullIntent(2, 14, true, pullIntentMs + 50), PullIntent.other);
      expect(pullIntent(0, 3, true, pullIntentMs + 50), PullIntent.other);
    });
  });

  group('feeling a detent coming', () {
    /// The times of the ticks felt dragging steadily from rest to [to] over [ms].
    List<int> ticks(List<double> detents, double to, int ms) {
      final state = Approaching();
      final felt = <int>[];
      for (var now = 0; now <= ms; now += 8) {
        if (tickNow(state, detents, (to * now) / ms, now.toDouble())) felt.add(now);
      }
      return felt;
    }

    test('says which detent a drag is heading for and how far along it is', () {
      expect(approach([0.22, 0.55], 0.11), (index: 0, progress: 0.5));
      expect(approach([0.22, 0.55], 0.385)?.index, 1);
      expect(approach([0.22, 0.55], 0.385)?.progress, closeTo(0.5, 1e-9));
      expect(approach([0.22, 0.55], 0.6), isNull);
    });

    test('ticks nowhere in the first third, then faster and faster', () {
      expect(tickGap(0.2), isNull);
      expect(tickGap(0.35), 240);
      expect(tickGap(0.99)!, lessThan(50));
      expect(tickGap(0.7)!, greaterThan(tickGap(0.9)!));
      expect(tickGap(1), isNull);
    });

    test('packs the ticks closer together near the detent', () {
      final felt = ticks([0.3], 0.299, 2000);
      expect(felt.length, greaterThan(4));
      final gaps = [for (var i = 1; i < felt.length; i += 1) felt[i] - felt[i - 1]];
      expect(gaps.last, lessThan(gaps.first));
    });

    test('is quiet backing off', () {
      final state = Approaching(lastDistance: 0.29);
      expect(tickNow(state, [0.3], 0.2, 1000), isFalse);
      expect(tickNow(state, [0.3], 0.15, 2000), isFalse);
    });
  });

  group('a tape (capture/tape.ts)', () {
    test('counts as a tape deck does', () {
      expect([counter(7000), counter(760000), counter(3723000), counter(-5), counter(40999)], ['0:07', '12:40', '1:02:03', '0:00', '0:40']);
    });

    test('moves its tape from the left reel to the right, the area kept', () {
      final empty = packRadii(0), full = packRadii(tapeMs), half = packRadii(tapeMs / 2);
      expect([empty.supply, empty.takeup], [packMaxR, packMinR]);
      expect([full.supply, full.takeup], [packMinR, packMaxR]);
      expect(half.supply, closeTo(half.takeup, 1e-9));
      expect(packRadii(tapeMs * 4).takeup, packMaxR);
      // The nearly empty reel turns faster than the full one.
      final turn = reelTurn(0, 100);
      expect(turn.takeup, greaterThan(turn.supply));
    });
  });
}
