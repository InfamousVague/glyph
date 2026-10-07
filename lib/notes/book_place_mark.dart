import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../sheet/css.dart';

/// A page of a book says which (docs/BOOKS.md): the book's mark and its name, on the note's card and on its row in
/// the sidebar (note_tree.dart), one quiet line, the name cut short rather than wrapped. A port of
/// `src/app/notes/BookPlaceMark.tsx` and `BookPlaceMark.module.css`.
///
/// One mark for both, so the two places a note is listed cannot come to say it differently.
///
/// What differs: the page said which page it is "to whoever points at it" (a `title`); a finger cannot point, so
/// here it is the mark's tooltip for a screen reader ([said]) and nothing is shown on a hover.
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
      tooltip: said,
      // `display: inline-flex; align-items: center; gap: 0.3em; min-inline-size: 0`
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 0.3 * size,
        children: [
          ExcludeSemantics(child: lucide(Lucide.book, size: 12, color: color)),
          // `.name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`
          Flexible(child: Text(place.title, style: pageText(t, size, color: color), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
