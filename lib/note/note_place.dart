/// Where a note was being read, so it opens there again (Matt: "add bookmarking notes so opening the same note later
/// reopens to the same position"), and the bookmark put in it on purpose, which wins over that. A port of
/// `src/app/editor/notePlace.ts`.
///
/// A place is the line at the top of the page and how far into it the page was scrolled, not a pixel count: a note
/// that grew above that line since still opens on the same words. Kept on the device under one key, for the most
/// recent notes only.
///
/// What differs:
/// - The page measures with the DOM (`view.documentTop`, the page's `scrollTop`); here the editor is a sliver in
///   the page's scroll view, so where its document starts is what comes before the sliver plus the content's own
///   top padding ([documentOffset]), and a line's place is the height map's.
/// - `useNotePlace` is [NotePlaceKeeper], made once the editor has a view and a scroll position, and disposed of
///   with the screen. It is told of the person's own touch by the screen ([NotePlaceKeeper.touched]).
/// - The bookmark written in the note's words (editor/bookmarkLine.ts) belongs to a piece not built: the keeper
///   takes [NotePlaceKeeper.writtenBookmark] for it, and reads only the device's own bookmark without it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/stored.dart';
import '../editor/view/editor_view.dart';

/// A line of the note and how far past its top (`Place`).
@immutable
class Place {
  const Place(this.pos, this.offset);

  /// The document position of the line at the top of the page.
  final int pos;

  /// How far past that line's top, in pixels.
  final double offset;

  @override
  bool operator ==(Object other) => other is Place && other.pos == pos && other.offset == offset;

  @override
  int get hashCode => Object.hash(pos, offset);

  @override
  String toString() => 'Place($pos, $offset)';
}

const String _placesKey = 'glyph-note-places';
const String _marksKey = 'glyph-note-bookmarks';

/// Notes remembered; the least recently read are forgotten first (`KEEP`).
const int placesKept = 200;

/// A page scrolled no further than this is at the top, and nothing is kept for it (`TOP_PX`).
const double placeTopPx = 24;

/// Scrolling settles for this long before the place is written (`SAVE_AFTER_MS`).
const Duration placeSaveAfter = Duration(milliseconds: 400);

/// How long an opening note is waited on for its words to arrive before it is left at the top (`WAIT_MS`).
const Duration placeWait = Duration(milliseconds: 2500);

Place? _placeOf(Object? value) {
  if (value is! Map) return null;
  final pos = value['pos'], offset = value['offset'];
  return pos is num && offset is num && pos.isFinite && offset.isFinite ? Place(pos.toInt(), offset.toDouble()) : null;
}

/// The places and the bookmarks this device keeps (`readPlace`, `writePlace`, `readBookmark`, `writeBookmark`).
class NotePlaces {
  const NotePlaces([this._kept]);

  final Stored? _kept;
  Stored get _device => _kept ?? stored;

  Map<String, Object?> _sheet(String key) => _device.read<Map<String, Object?>>(key, const {}, (raw) => raw is Map ? raw.cast<String, Object?>() : null);

  /// Where [noteId] was left, or null.
  Place? readPlace(String noteId) => _placeOf(_sheet(_placesKey)[noteId]);

  /// Keeps where [noteId] was left; null, and the note opens at the top, as it did.
  void writePlace(String noteId, Place? place, {int? now}) {
    final all = <String, Object?>{
      for (final entry in _sheet(_placesKey).entries)
        if (entry.value is Map) entry.key: entry.value,
    };
    if (place != null) {
      all[noteId] = {'pos': place.pos, 'offset': place.offset, 'at': now ?? DateTime.now().millisecondsSinceEpoch};
    } else {
      all.remove(noteId);
    }
    num at(Object? value) => value is Map && value['at'] is num ? value['at'] as num : 0;
    final kept = all.entries.toList()..sort((a, b) => at(b.value).compareTo(at(a.value)));
    _device.write(_placesKey, {for (final entry in kept.take(placesKept)) entry.key: entry.value});
  }

  /// The bookmark put in [noteId] from its header, or null.
  Place? readBookmark(String noteId) => _placeOf(_sheet(_marksKey)[noteId]);

  /// Puts a bookmark in [noteId], or takes it off with null.
  void writeBookmark(String noteId, Place? place) {
    final all = {..._sheet(_marksKey)};
    if (place != null) {
      all[noteId] = {'pos': place.pos, 'offset': place.offset};
    } else {
      all.remove(noteId);
    }
    _device.write(_marksKey, all);
  }
}

/// The editor's sliver, while the view is drawn in one and has been laid out.
RenderSliver? _sliverOf(EditorView view) {
  final Object? scroller = view.scroller;
  return scroller is RenderSliver && scroller.attached && scroller.geometry != null ? scroller : null;
}

/// Where the note's document starts inside the scrolling page, in the page's own scroll offsets (`documentOffset`):
/// null until the editor has been laid out.
double? documentOffset(EditorView view) {
  final sliver = _sliverOf(view);
  final look = view.look;
  if (sliver == null || look == null) return null;
  return sliver.constraints.precedingScrollExtent + look.env.contentTop;
}

int _entryAt(EditorView view, int pos) => view.blocks.entryOf(view.state.doc.lineAt(math.min(math.max(0, pos), view.state.doc.length)).number);

/// The place the page is scrolled to now: the line at its top, and how far into it. Null at the top (`placeOf`).
Place? placeOf(EditorView view, ScrollPosition page) {
  final start = documentOffset(view);
  if (start == null) return null;
  final y = page.pixels - start;
  if (page.pixels <= placeTopPx || y < 0) return null;
  final heights = view.heights;
  final line = math.min(math.max(1, heights.lineAt(y)), view.state.doc.lines);
  return Place(view.state.doc.line(line).from, math.max(0, y - heights.offsetOf(line)));
}

/// The caret as a place: the line it is on, from that line's top. Null when the caret's line is not on screen, which
/// is the case in a note nobody has touched since it opened (`caretPlace`).
Place? caretPlace(EditorView view, ScrollPosition page) {
  final start = documentOffset(view);
  if (start == null) return null;
  final entry = _entryAt(view, view.state.selection.main.head);
  final top = start + view.heights.offsetOf(entry);
  final seen = top >= page.pixels - 1 && top < page.pixels + page.viewportDimension;
  return seen ? Place(view.state.doc.line(entry).from, 0) : null;
}

/// Scrolls the page back to [place], clamped to the note as it is now (`scrollToPlace`).
void scrollToPlace(EditorView view, ScrollPosition page, Place place) {
  final start = documentOffset(view);
  if (start == null) return;
  final entry = _entryAt(view, place.pos);
  final to = start + view.heights.offsetOf(entry) + math.min(place.offset, view.heights.heightOf(entry));
  page.jumpTo(to.clamp(page.minScrollExtent, math.max(page.minScrollExtent, page.maxScrollExtent)));
}

/// Opens a note where it was left and remembers where it is left (`useNotePlace`).
///
/// The note's words can arrive a moment after its editor, so the page is scrolled back once the document reaches
/// the place and the page can scroll that far, and once more shortly after, when the editor has measured the lines
/// it scrolled to. Nothing is written until then, or until the person scrolls, so a note closed before its words
/// arrived keeps its place. Then it is read at every scroll and written as scrolling settles, when the app is
/// hidden, and when the note closes (from the last scroll: by then the page is gone).
class NotePlaceKeeper {
  NotePlaceKeeper({required this.noteId, required this.view, required this.page, this.places = const NotePlaces(), this.writtenBookmark, bool lifecycle = true}) {
    _place = places.readBookmark(noteId) ?? places.readPlace(noteId);
    _latest = _place;
    _waiting = Timer.periodic(const Duration(milliseconds: 16), (_) => _wait());
    page.addListener(_onScroll);
    if (lifecycle) _hides = AppLifecycleListener(onHide: _onHide, onPause: _onHide);
  }

  final String noteId;
  final EditorView view;
  final ScrollPosition page;
  final NotePlaces places;

  /// The bookmark written in the note's own words, as a place, where that piece is built (editor/bookmarkLine.ts).
  final Place? Function(EditorView view)? writtenBookmark;

  final Stopwatch _since = Stopwatch()..start();
  AppLifecycleListener? _hides;
  Place? _place;
  Place? _latest;
  bool _written = false;

  /// Settled: restored, given up on, or scrolled by the person. Only then is the place theirs to write.
  bool _settled = false;
  bool _restoring = false;
  bool _gone = false;
  Timer? _waiting;
  Timer? _again;
  Timer? _saving;

  bool get settled => _settled;

  void _wait() {
    if (_settled || _gone) return _waiting?.cancel();
    if (!_written) {
      final mark = writtenBookmark?.call(view);
      if (mark != null) {
        _place = mark;
        _written = true;
      }
    }
    final target = _place;
    final late = _since.elapsed > placeWait;
    if (target == null) {
      // Nothing to go back to, unless the note's words bring a bookmark with them.
      if (view.state.doc.length > 0 || late) _settle();
      return;
    }
    final ready = view.state.doc.length >= target.pos && page.hasContentDimensions && page.maxScrollExtent > page.minScrollExtent && documentOffset(view) != null;
    if (ready) {
      _waiting?.cancel();
      _jump(target);
      _again = Timer(const Duration(milliseconds: 150), () {
        if (_gone) return;
        _jump(target);
        _settled = true;
        _latest = placeOf(view, page) ?? target;
      });
      return;
    }
    if (late) _settle();
  }

  void _jump(Place target) {
    _restoring = true;
    scrollToPlace(view, page, target);
    _restoring = false;
  }

  void _settle() {
    _settled = true;
    _waiting?.cancel();
  }

  void _save() {
    if (_settled) places.writePlace(noteId, _latest);
  }

  /// The person's own scrolling ends the restore: a restore scrolls too, and must not be mistaken for it.
  void touched() {
    if (_settled) return;
    _again?.cancel();
    _settle();
  }

  void _onScroll() {
    if (_restoring || _gone) return;
    if (_settled) _latest = placeOf(view, page);
    _saving?.cancel();
    _saving = Timer(placeSaveAfter, _save);
  }

  void _onHide() {
    if (_gone) return;
    if (_settled && page.hasPixels && documentOffset(view) != null) _latest = placeOf(view, page);
    _save();
  }

  /// The note closes: the place as of the last scroll is written.
  void dispose() {
    if (_gone) return;
    _gone = true;
    _waiting?.cancel();
    _again?.cancel();
    _saving?.cancel();
    _hides?.dispose();
    page.removeListener(_onScroll);
    _save();
  }
}
