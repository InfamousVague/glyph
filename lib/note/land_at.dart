/// Landing on an item: a note opened by a link that pointed inside it (`[[Launch week#^ask-sam]]`) puts the caret on
/// that item and scrolls the page to it, rather than going back to where the note was left last time. A port of
/// `src/app/editor/useLandAt.ts`.
///
/// Two stages. The caret goes to the end of the item's words, before its mark and its anchor. The page scrolls so
/// the line sits [landRoom] under the header, which floats over the page: first from the editor's own idea of where
/// the line is, which is a guess for lines it has not drawn, then, once the line is really on screen, from its
/// measured top, a few times at growing intervals. The item is looked for again every 100 ms, up to [landTries]
/// times, since the note's words can arrive a moment after its editor.
///
/// What differs: the hook is [LandAt], made once the editor has a view and the page a scroll position, and disposed
/// of with the screen; the header's foot is asked for as a global y.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;

import '../core/block_ids.dart' show blockIdOf, blockLine, headingNamed;
import '../core/boards/items.dart' show itemAt;
import '../core/item_syntax.dart' show wordsEnd;
import '../editor/editor.dart';
import '../editor/view/editor_view.dart';
import 'note_place.dart';

/// Where a note is opened at its tape (a cassette on the home page's shelf): no item, but the top of the page, where
/// the tape is, and the tape playing (lib/root/note_desk.dart). Not a name a line could have.
const String atTape = '@tape';

/// How far below the header a note opened at an item sits (`LAND_ROOM`).
const double landRoom = 12;

/// How many more looks for an item that is not in the note yet, 100 ms apart (`TRIES`).
const int landTries = 24;

/// How many times the landing is measured and made, the first included (`LANDINGS`).
const int landings = 4;

final RegExp _numbered = RegExp(r'^line:(\d+)$');

/// The line [at] names in [view]'s note, counting from 1, or null while it is not there: an item by its anchor
/// (`^anchor` or `anchor`), or a line by its number, `line:12`; and, as `[[Note#^name]]` and `[[Note#Heading]]`
/// point (lib/core/block_ids.dart), any line by the name at its end, or a heading by its words.
int? landingLine(EditorView view, String at) {
  final anchor = at.replaceFirst(RegExp(r'^\^'), '');
  if (anchor.isEmpty) return null;
  final doc = view.state.doc;
  final numbered = _numbered.firstMatch(anchor);
  if (numbered != null) {
    final n = int.tryParse(numbered.group(1)!) ?? 0;
    // A line by its number is there once the note has that many lines: its words may still be arriving.
    return n >= 1 && n <= doc.lines && doc.length > 0 ? n : null;
  }
  final body = doc.toString();
  return itemAt(body, anchor)?.line ?? blockLine(body, anchor) ?? (at.startsWith('^') ? null : headingNamed(body, at)?.line);
}

class LandAt {
  LandAt({required this.at, required this.view, required this.page, required this.headerBottom}) {
    _timers.add(Timer(Duration.zero, _land));
  }

  final String at;
  final EditorView view;
  final ScrollPosition page;

  /// The header's foot on the screen, which the line lands under.
  final double Function() headerBottom;

  final List<Timer> _timers = [];
  int _tries = 0;
  int _landed = 0;

  /// How many times the landing has been made.
  int get landed => _landed;

  void _land() {
    final found = landingLine(view, at);
    if (found != null && page.hasPixels) {
      final doc = view.state.doc;
      final line = doc.line(found < doc.lines ? found : doc.lines);
      // Before a named line's name, as before an item's: typed there, a letter would go into the name.
      final named = blockIdOf(line.text);
      final caret = named != null && named.from > 0 && wordsEnd(line.text) > named.from ? named.from - 1 : wordsEnd(line.text);
      if (_landed == 0) view.dispatch(TransactionSpec(selection: EditorSelection.single(line.from + caret)));
      final seen = view.coordsAtPos(line.from);
      final room = headerBottom() + landRoom;
      if (seen != null) {
        final to = page.pixels + seen.top - room;
        page.jumpTo(to.clamp(page.minScrollExtent, page.maxScrollExtent < page.minScrollExtent ? page.minScrollExtent : page.maxScrollExtent));
      } else {
        scrollToPlace(view, page, Place(line.from, 0));
      }
      _landed += 1;
      if (_landed < landings) _timers.add(Timer(Duration(milliseconds: _landed * 150), _land));
      return;
    }
    if (_tries < landTries) {
      _tries += 1;
      _timers.add(Timer(const Duration(milliseconds: 100), _land));
    }
  }

  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
  }
}
