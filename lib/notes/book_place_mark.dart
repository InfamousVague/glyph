import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../sheet/css.dart';

/// A page of a book says which (docs/BOOKS.md): the book's mark and its name, on the note's card and on its row in
/// the sidebar (note_tree.dart), one quiet line, the name cut short rather than wrapped. A port of
/// `src/app/notes/BookPlaceMark.tsx` and `BookPlaceMark.module.css`.
///
/// One mark for both, so the two places a note is listed cannot come to say it differently (lib/home/marks.dart
/// hands this one on; the home page drew a second until 2026-10-09).
///
/// What differs: the page said which page it is "to whoever points at it" (a `title`); a finger cannot point, so
/// here it is what a screen reader hears of the mark ([said]) and nothing is shown on a hover.
class BookPlaceMark extends StatelessWidget {
  const BookPlaceMark({super.key, required this.place});
  final BookPlace place;

  /// The page in full: `An entry in <journal>`, or `Page <n> of <book>`.
  String get said => place.journal ? 'An entry in ${place.title}' : 'Page ${place.at + 1} of ${place.title}';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `font-size: var(--glacier-font-size-xs); color: var(--glacier-text-muted)`
    final size = t.fontSize('xs');
    final color = t.color('glacier-text-muted');
    return Semantics(
      label: said,
      excludeSemantics: true,
      // `display: inline-flex; align-items: center; gap: 0.3em; min-inline-size: 0`
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 0.3 * size,
        children: [
          lucide(Lucide.book, size: 12, color: color),
          // `.name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`
          Flexible(child: Text(place.title, style: pageText(t, size, color: color), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// A note listed under a workspace that is filed in a folder inside it says which, as a page says its book: the
/// folder's glyph and its name, one quiet line (Matt, 2026-10-20: "it says them moved with the undo but the UI
/// doesn't update"). A workspace's cards are the notes of its folders too, so a note carried onto a folder's chip
/// stays on the page; this is what changes on it. The port's own.
class FolderPlaceMark extends StatelessWidget {
  const FolderPlaceMark({super.key, required this.name});

  /// The folder's name.
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    final color = t.color('glacier-text-muted');
    return Semantics(
      label: 'In $name',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('folder-place'),
        mainAxisSize: MainAxisSize.min,
        spacing: 0.3 * size,
        children: [
          lucide(Lucide.folder, size: 12, color: color),
          Flexible(child: Text(name, style: pageText(t, size, color: color), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
