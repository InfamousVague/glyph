/// The row under a search field that says what a search can ask, and what it understood (lib/core/search_query.dart).
///
/// With the field empty and taking the keyboard, the operators, a small chip each (`tag:`, `in:`, `is:pinned` …),
/// in one line that scrolls across: a tap puts one into the field, the keyboard still up. With something typed, a
/// chip for each operator the query holds, said in plain words ("Tagged #work", "Not pinned", "Changed in the last
/// 7 days"), its cross taking that operator out of the field; the plain words are the search's own and get none. And
/// at the end, where the search can be kept, Save as a smart notebook (lib/core/smart_notebooks.dart).
///
/// Used by the home page's search (lib/home/home_filters.dart) and All notes' (lib/notes/all_notes_screen.dart). Its
/// taps count as the field's own (`TextFieldTapRegion`), so pressing one does not take the keyboard away.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/search_query.dart';
import 'home_text.dart';

/// The hint row, or the chips of what was understood, under a search field.
class SearchHints extends StatelessWidget {
  const SearchHints({super.key, required this.query, required this.focused, required this.onQuery, this.onSave});

  /// What is in the field.
  final String query;

  /// Whether the field has the keyboard: the operators are offered only then.
  final bool focused;

  /// The field's words changed from here: an operator put in, or one taken out.
  final ValueChanged<String> onQuery;

  /// Keeps the search as a smart notebook; left out, there is no Save.
  final VoidCallback? onSave;

  /// [query] with [hint] put on its end, a space between where it needs one.
  static String withHint(String query, String hint) {
    if (query.isEmpty) return hint;
    return query.endsWith(' ') ? '$query$hint' : '$query $hint';
  }

  /// [query] without what [part] took, the spaces either side of it made one.
  static String without(String query, SearchPart part) {
    final before = query.substring(0, part.start).trimRight();
    final after = query.substring(part.end).trimLeft();
    return [before, after].where((side) => side.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final blank = query.trim().isEmpty;
    if (blank) {
      if (!focused) return const SizedBox.shrink();
      return TextFieldTapRegion(
        child: Semantics(
          container: true,
          label: 'Ways to search',
          explicitChildNodes: true,
          child: SingleChildScrollView(
            key: const ValueKey('search-hints'),
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: t.space(2),
              children: [
                for (final (said, finds) in searchHints)
                  _Hint(
                    key: ValueKey('hint-$said'),
                    said: said,
                    finds: finds,
                    onPressed: () => onQuery(withHint(query, said)),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final parts = parseSearch(query).parts;
    if (parts.isEmpty && onSave == null) return const SizedBox.shrink();
    return TextFieldTapRegion(
      child: Semantics(
        container: true,
        label: 'Searching for',
        explicitChildNodes: true,
        child: Wrap(
          key: const ValueKey('search-understood'),
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [
            for (final part in parts)
              _Understood(
                key: ValueKey('understood-${part.start}'),
                part: part,
                onPressed: () => onQuery(without(query, part)),
              ),
            if (onSave != null) _Save(onPressed: onSave!),
          ],
        ),
      ),
    );
  }
}

/// One operator offered: what is typed, in the code face, and what it finds, for a screen reader.
class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.said, required this.finds, required this.onPressed});

  final String said;
  final String finds;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'Add $said, $finds',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(7)),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          decoration: BoxDecoration(
            color: t.colorOf(state.hovered ? 'color-mix(in oklch, var(--app-ink) 8%, transparent)' : 'color-mix(in oklch, var(--app-ink) 4%, transparent)'),
            border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: ExcludeSemantics(
            child: Text(said, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2'))),
          ),
        ),
      ),
    );
  }
}

/// One operator understood: what it asks, in words, and a cross that takes it out of the field.
class _Understood extends StatelessWidget {
  const _Understood({super.key, required this.part, required this.onPressed});

  final SearchPart part;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final icon = switch (part.kind) {
      SearchPartKind.tag => Lucide.hash,
      SearchPartKind.place => Lucide.folder,
      SearchPartKind.made || SearchPartKind.changed => Lucide.calendarDays,
      SearchPartKind.phrase => Lucide.textQuote,
      SearchPartKind.without => Lucide.minus,
      SearchPartKind.isFlag || SearchPartKind.has => Lucide.listFilter,
    };
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: '${part.label}: take it out of the search',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(7)),
          padding: EdgeInsetsDirectional.only(start: t.space(2), end: t.space(2)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)'),
            border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 0.4 * sm,
              children: [
                AppIcon(icon, size: 13, strokeWidth: 2.2, color: t.color('app-ink-2')),
                Flexible(child: Text(part.label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')))),
                AppIcon(Lucide.x, size: 13, strokeWidth: 2.4, color: t.color('app-ink-2')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep this search as a smart notebook.
class _Save extends StatelessWidget {
  const _Save({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      key: const ValueKey('search-save'),
      onPressed: onPressed,
      semanticLabel: 'Save this search as a smart notebook',
      builder: (context, state) {
        final ink = t.color(state.hovered ? 'app-ink' : 'app-ink-2');
        return GlacierFocusRing(
          visible: state.focused,
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(7)),
            padding: EdgeInsets.symmetric(horizontal: t.space(2)),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 0.4 * sm,
                children: [
                  AppIcon(Lucide.bookmark, size: 14, strokeWidth: 2.2, color: ink),
                  Text('Save as a smart notebook', maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: ink)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
