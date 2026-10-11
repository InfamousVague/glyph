/// Keeps a book's spot while its view is open: the index while the index is shown, and the read-through's place as
/// it is scrolled, written as scrolling settles, when the app is hidden and when the view closes. The hook half of
/// `src/app/book/bookSpot.ts` (`useBookSpot`); the rules it keeps to are lib/book/book_spot.dart's.
///
/// A read-through the book was left in is scrolled back to its place once, when [BookSpotWatch.reading] is given a
/// spot to restore: the chapters' words lay out a moment after the view, so the page is scrolled back once the
/// chapter is there and again shortly after, unless the person scrolls first.
///
/// What differs:
/// - **An effect is two calls.** The page ran one effect whenever the book, the mode or the chapters changed, and
///   its cleanup when they changed again; here the view calls [BookSpotWatch.index] or [BookSpotWatch.reading] at
///   each of those moments, and either one puts away what the last one set up, saving as the cleanup did.
/// - **The page is a [ScrollPosition]**, the note's own, and the tops the page read with `getBoundingClientRect`
///   are asked of the view through [ReadingMeasure]: the scroller's top and each chapter's section's, on the screen.
/// - **A frame is the scheduler's**, and the wait for the chapters ([waitFor]) is counted in the frames' own time,
///   where the page asked `performance.now()`.
/// - **The person scrolling first** was a `pointerdown`, `wheel` or `touchstart` on the scroller. The view tells
///   [BookSpotWatch.touched] of a pointer down or a wheel over the read-through, and a scroll the person is making
///   (`userScrollDirection`) counts as one too, for a drag that began above the book.
/// - `visibilitychange` is the app's lifecycle: hidden or paused, the place is written.
library;

import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/stored.dart';
import 'book_spot.dart';

/// What the read-through looks like now, for its place to be read or put back: the scroller's top and each
/// chapter's section's top, in the index's order, in one frame of reference. Null while it is not drawn.
typedef ReadingMeasure = ({double pageTop, List<double> sectionTops})? Function();

/// The watch one open book keeps (`useBookSpot`). Make it with the book note's id; call [index] while the index is
/// shown and [reading] while the chapters are read straight through; [dispose] it with the view.
class BookSpotWatch {
  BookSpotWatch(this.bookId, {Stored? on, this.now}) : _on = on;

  final String bookId;
  final Stored? _on;

  /// The clock a spot is stamped with; this moment where it is left out.
  final int Function()? now;

  VoidCallback? _cleanup;
  VoidCallback? _touched;

  void _write(BookSpot spot) => writeBookSpot(bookId, spot, now: now?.call(), on: _on);

  /// The index is what is shown: it is the spot.
  void index() {
    _put();
    _write(const IndexSpot());
  }

  /// The chapters are being read straight through, in [page], laid out as [measure] says, their [titles] in the
  /// index's order. [restore] is where the book was left, read once as the view opened: the page is scrolled back
  /// there, and nothing is written until it has been, or has been given up on, or the person has scrolled.
  void reading({required ScrollPosition page, required ReadingMeasure measure, required List<String> titles, ReadingSpot? restore}) {
    _put();
    final names = List<String>.of(titles);
    BookSpot? place() {
      final at = measure();
      return at == null ? null : readingPlaceOf(at.pageTop, at.sectionTops, names);
    }

    BookSpot? latest = restore ?? place();
    // Settled: restored, given up on, or scrolled by the person. Only then is the place theirs to write.
    var settled = restore == null;
    int? frame;
    Timer? again;
    Timer? saving;
    Duration? started;
    var done = false;

    bool scrollBack() {
      if (restore == null) return false;
      final at = measure();
      if (at == null || !page.hasPixels || !page.hasContentDimensions) return false;
      final by = readingScroll(at.pageTop, at.sectionTops, names, restore.title, restore.offset);
      if (by == null) return false;
      // `page.scrollTop += …`, which a browser holds to what there is to scroll.
      page.jumpTo((page.pixels + by).clamp(page.minScrollExtent, page.maxScrollExtent));
      return true;
    }

    void wait(Duration stamp) {
      frame = null;
      if (done || settled || restore == null) return;
      started ??= stamp;
      // `scroller.scrollHeight > scroller.clientHeight`: there is somewhere to scroll to.
      final ready = page.hasContentDimensions && page.maxScrollExtent > page.minScrollExtent && scrollBack();
      if (ready) {
        again = Timer(const Duration(milliseconds: 150), () {
          if (done) return;
          scrollBack();
          settled = true;
        });
        return;
      }
      if (stamp - started! > waitFor) {
        settled = true;
      } else {
        frame = SchedulerBinding.instance.scheduleFrameCallback(wait);
      }
    }

    if (restore != null) frame = SchedulerBinding.instance.scheduleFrameCallback(wait);

    void save() {
      final spot = latest;
      if (settled && spot != null) _write(spot);
    }

    void onTouch() {
      if (settled) return;
      final waiting = frame;
      if (waiting != null) SchedulerBinding.instance.cancelFrameCallbackWithId(waiting);
      frame = null;
      again?.cancel();
      settled = true;
    }

    void onScroll() {
      if (!settled && page.userScrollDirection != ScrollDirection.idle) onTouch();
      if (settled) latest = place() ?? latest;
      saving?.cancel();
      saving = Timer(saveAfter, save);
    }

    final life = AppLifecycleListener(onHide: save, onPause: save);
    // The read-through is the spot as soon as it is shown, before any scroll.
    save();
    page.addListener(onScroll);
    _touched = onTouch;
    _cleanup = () {
      done = true;
      final waiting = frame;
      if (waiting != null) SchedulerBinding.instance.cancelFrameCallbackWithId(waiting);
      frame = null;
      again?.cancel();
      saving?.cancel();
      page.removeListener(onScroll);
      life.dispose();
      _touched = null;
      save();
    };
  }

  /// The person pressed or wheeled over the read-through: a scroll back still waiting is theirs to overrule.
  void touched() => _touched?.call();

  void _put() {
    final cleanup = _cleanup;
    _cleanup = null;
    cleanup?.call();
  }

  /// The view closed: what was being watched is put away, and the read-through's place written.
  void dispose() => _put();
}
