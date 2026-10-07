/// The small marks a listed note wears beside its name: a ticket's key and status, the notebook a page is in, and the
/// mark of an organization's workspace. Ports of `src/app/notes/TicketMark.tsx` (and TicketMark.module.css `.mark`),
/// `notes/BookPlaceMark.tsx` and `notes/OrgMark.tsx`, each one widget for every place the mark is drawn, so the places
/// cannot come to say it differently.
///
/// What differs: the web's `TicketStatusButton` (a notebook's own list changes a status from it) comes with the
/// notebook's screen. A mark's `title`, read by a pointer resting on it, is its semantics label here.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/properties.dart';
import 'home_icons.dart';
import 'home_text.dart';

/// A ticket's key and status where it is listed (`TicketMark`): small and quiet, the key in the mono face, the
/// status's dot in its category's colour, and the status's words in that colour once it is under way or done. Nothing
/// for a note that is not a ticket.
///
/// [notebook] is the body of the notebook it is a page of, whose workflow its status is placed in. [after] is a
/// `::after` a list hangs on the mark (a row's `·`), drawn as one more item of the mark's own row.
class TicketMark extends StatelessWidget {
  const TicketMark({super.key, required this.body, this.notebook, this.keyOnly = false, this.after});

  final String body;
  final String? notebook;
  final bool keyOnly;
  final String? after;

  /// Whether a mark is drawn for [body] at all.
  static bool has(String body, {String? notebook, bool keyOnly = false}) {
    final ticket = ticketOf(body, notebook == null ? null : statusesOf(notebook));
    if (ticket == null || (ticket.id == null && ticket.status == null)) return false;
    return !(keyOnly && ticket.id == null);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ticketOf(body, notebook == null ? null : statusesOf(notebook));
    if (ticket == null || (ticket.id == null && ticket.status == null)) return const SizedBox.shrink();
    if (keyOnly && ticket.id == null) return const SizedBox.shrink();
    final t = context.tokens;
    final size = t.fontSize('xs');
    final muted = t.color('glacier-text-muted');
    final (words, dot) = switch (ticket.category) {
      StatusCategory.doing => (t.color('glacier-blue-11'), t.color('glacier-blue-9')),
      StatusCategory.done => (t.color('glacier-green-11'), t.color('glacier-green-9')),
      StatusCategory.todo => (muted, t.color('app-ink-4')),
    };
    final status = ticket.status;
    return Semantics(
      label: [ticket.id, if (!keyOnly) status].whereType<String>().join(' · '),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ticket.id != null) Text(ticket.id!, softWrap: false, style: t.textAt(size, mono: true, color: muted, height: normalLeading(size), tracking: 0.02 * size)),
          if (ticket.id != null && status != null && !keyOnly) SizedBox(width: t.space(2)),
          if (status != null && !keyOnly)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 0.55 * size, height: 0.55 * size, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  SizedBox(width: t.space(1)),
                  Flexible(child: Text(status, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, size, color: words))),
                ],
              ),
            ),
          if (after != null) ...[SizedBox(width: t.space(2)), Text(after!, style: pageText(t, size, color: t.color('app-ink-3')))],
        ],
      ),
    );
  }
}

/// A page of a book says which (`BookPlaceMark`): the book's mark and its name, one quiet line, the name cut short
/// rather than wrapped.
class BookPlaceMark extends StatelessWidget {
  const BookPlaceMark({super.key, required this.place});

  final BookPlace place;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    final color = t.color('glacier-text-muted');
    return Semantics(
      label: place.journal ? 'An entry in ${place.title}' : 'Page ${place.at + 1} of ${place.title}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeIcon(HomeGlyph.book, size: 12, color: color),
          SizedBox(width: 0.3 * size),
          Flexible(child: Text(place.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, size, color: color))),
        ],
      ),
    );
  }
}

/// The small mark an organization's workspace wears before its name (`OrgMark`): the kit's group, a touch under the
/// text's size ([em]), in the words' own [color] at 85%, with its `margin-inline-end: 0.35em` after it.
class OrgMark extends StatelessWidget {
  const OrgMark({super.key, required this.em, required this.color, this.size});

  /// The font size of the words it stands before.
  final double em;
  final Color color;

  /// Its box, where a rule sets one over OrgMark's own 0.9em (`.choiceMark`, 1em).
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Organization',
      image: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: 0.35 * em),
        child: HomeIcon(HomeGlyph.organization, size: size ?? 0.9 * em, color: color.withValues(alpha: color.a * 0.85)),
      ),
    );
  }
}
