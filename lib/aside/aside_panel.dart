import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../book/book_view.dart' show numbered;
import '../core/stored.dart';
import '../notes/floating_card.dart';
import '../sheet/css.dart';
import 'aside.dart';

/// The open note's version history, for the aside's second tab (`AsideHistory`): given the close of the card it is
/// in, where it is in one. Left out where the aside has no room for it (a phone), as the page leaves it out.
typedef AsideHistoryBuilder = Widget Function(BuildContext context);

/// The right-hand aside with all it can hold: a book's index while a book or one of its pages is on screen, the open
/// chapter marked and a tap opening another; one month of a journal's entries; with no book, a numbered chapter's
/// run in order; and the open note's version history, in a second tab where there are both. A port of
/// `src/app/aside/Aside.tsx` (`AsidePanel`, `AsideIndex`) and `Aside.module.css`.
///
/// Its shell follows the sidebar's: a column of the split window when the sidebar is docked (app.css `.app-aside`),
/// else the notes drawer's floating card at the right ([AsideCard]). With nothing to hold it is not built at all.
///
/// What differs from the web:
/// - The history is a widget its caller builds ([history]), where the page drew `AsideHistory` itself: the note's
///   live words and its restore are the note's screen's to give.
/// - A tab asked for from elsewhere ([showAsideTab]) is heard through a notifier, not a window event.
/// - A row's `:hover` is a mouse over it.
class AsidePanel extends StatefulWidget {
  const AsidePanel({super.key, required this.content, this.history, this.links, this.outline, required this.onOpen, required this.onOpenTitle, this.onClose, this.popup = false, this.stored});

  /// The open note's book or run of chapters, or null where it has neither.
  final AsideContent? content;
  final AsideHistoryBuilder? history;

  /// The open note's links and its outline (lib/links/note_links.dart), in tabs of their own; left out where the
  /// note has none to show (a canvas, a notebook's index) or the window no room for them.
  final AsideHistoryBuilder? links;
  final AsideHistoryBuilder? outline;
  final void Function(String id) onOpen;
  final void Function(String title) onOpenTitle;

  /// In the floating card: the close in its head.
  final VoidCallback? onClose;

  /// In the floating card, which has no bar over it.
  final bool popup;
  final Stored? stored;

  @override
  State<AsidePanel> createState() => _AsidePanelState();
}

class _AsidePanelState extends State<AsidePanel> {
  late AsideTab _tab = readAsideTab(widget.stored);

  @override
  void initState() {
    super.initState();
    asideTabChosen.addListener(_chosen);
  }

  @override
  void dispose() {
    asideTabChosen.removeListener(_chosen);
    super.dispose();
  }

  void _chosen() {
    final tab = asideTabChosen.value;
    if (tab != null && mounted) setState(() => _tab = tab);
  }

  void _choose(AsideTab next) {
    setState(() => _tab = next);
    writeAsideTab(next, widget.stored);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content = widget.content;
    final history = widget.history;
    final links = widget.links, outline = widget.outline;
    final tabs = [if (content != null) AsideTab.contents, if (history != null) AsideTab.history, if (links != null) AsideTab.links, if (outline != null) AsideTab.outline];
    final both = tabs.length > 1;
    final showing = tabs.contains(_tab) ? _tab : (tabs.isEmpty ? AsideTab.contents : tabs.first);
    // `font-size: var(--glacier-font-size-sm)`, on the page's own line.
    final size = t.fontSize('sm');
    final words = t.textAt(size, color: t.color('glacier-text'));
    return DefaultTextStyle(
      style: words,
      child: SingleChildScrollView(
        // `padding: calc(var(--app-safe-top) + var(--glacier-space-3)) var(--glacier-space-3) var(--glacier-space-6)`,
        // and in the card `padding-block-start: var(--glacier-space-3)`.
        padding: EdgeInsets.fromLTRB(t.space(3), (widget.popup ? 0 : t.len('app-safe-top')) + t.space(3), t.space(3), t.space(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (both)
              _Tabs(
                labels: [
                  if (content != null) (AsideTab.contents, switch (content) { AsideChapters() => 'Chapters', AsideBook(journal: true) => 'Entries', _ => 'Index' }),
                  if (history != null) (AsideTab.history, 'History'),
                  if (links != null) (AsideTab.links, 'Links'),
                  if (outline != null) (AsideTab.outline, 'Outline'),
                ],
                on: showing,
                onChoose: _choose,
              ),
            if (showing == AsideTab.contents && content != null)
              ..._index(context, content, size)
            else if (showing == AsideTab.links && links != null) ...[
              _Head(icon: Lucide.link2, title: 'Links', onClose: widget.onClose, em: size),
              links(context),
            ] else if (showing == AsideTab.outline && outline != null) ...[
              _Head(icon: Lucide.listTree, title: 'Outline', onClose: widget.onClose, em: size),
              outline(context),
            ] else if (history != null) ...[
              _Head(icon: Lucide.history, title: 'Version history', onClose: widget.onClose, em: size),
              history(context),
            ],
          ],
        ),
      ),
    );
  }

  /// `AsideIndex`: what a book's index or a run of chapters puts in the aside.
  List<Widget> _index(BuildContext context, AsideContent content, double em) {
    final t = context.tokens;
    final words = t.textAt(em, color: t.color('glacier-text'));
    switch (content) {
      case AsideBook(journal: true):
        final month = content.month;
        return [
          _Head(icon: Lucide.bookOpen, title: content.place.title, label: 'Open the journal ${content.place.title}', onPressed: () => widget.onOpen(content.place.book.id), onClose: widget.onClose, em: em),
          if (month == null)
            const _Empty('No entries yet.')
          else ...[
            _Month(month.label),
            _List(
              label: 'Entries',
              rows: [
                for (final entry in month.entries)
                  _Row(
                    number: entry.day,
                    label: entry.label,
                    current: entry.id == content.open,
                    onPressed: () => widget.onOpen(entry.id),
                    em: em,
                    // Its time and how it starts, faded at the edge and never cut with an ellipsis.
                    child: _Faded(child: _line(t, '${entry.time}${entry.first.isEmpty ? '' : ' ${entry.first}'}', words, clip: true)),
                  ),
              ],
            ),
          ],
        ];
      case AsideBook():
        final chapters = content.place.chapters;
        final numbers = numbered(chapters);
        return [
          _Head(icon: Lucide.bookOpen, title: content.place.title, label: 'Open the notebook ${content.place.title}', onPressed: () => widget.onOpen(content.place.book.id), onClose: widget.onClose, em: em),
          if (chapters.isEmpty)
            const _Empty('No pages yet.')
          else
            _List(
              label: 'Pages',
              rows: [
                for (var i = 0; i < chapters.length; i += 1)
                  _Row(
                    number: numbers[i],
                    label: chapters[i].title,
                    current: content.place.at == i,
                    // `.list li[data-depth='1'] .row { padding-inline-start: 1.6em }`
                    deep: chapters[i].depth == 1,
                    onPressed: () => widget.onOpenTitle(chapters[i].title),
                    em: em,
                    child: _line(t, chapters[i].title, words),
                  ),
              ],
            ),
        ];
      case AsideChapters():
        final id = content.titleId;
        return [
          _Head(icon: Lucide.bookOpen, title: content.title, label: 'Open ${content.title}', onPressed: id == null ? null : () => widget.onOpen(id), onClose: widget.onClose, em: em),
          _List(
            label: 'Chapters',
            rows: [
              for (final chapter in content.chapters)
                _Row(
                  number: '${chapter.number}',
                  label: chapter.name,
                  current: chapter.id == content.open,
                  onPressed: () => widget.onOpen(chapter.id),
                  em: em,
                  child: _line(t, chapter.name, words),
                ),
            ],
          ),
        ];
    }
  }
}

/// A line of the aside's words, exactly as tall as the page's `line-height: normal` makes it at this device's ratio
/// (the engine would make each a whole pixel, and a list of rows drifts by the difference).
Widget _line(Tokens t, String words, TextStyle style, {bool clip = false, TextAlign? align}) => ExactLines.of(
      Text(words, maxLines: 1, softWrap: clip ? false : null, overflow: clip ? TextOverflow.clip : TextOverflow.ellipsis, textAlign: align, style: style),
      normal: true,
      dpr: t.css.lineDpr,
    );

/// `.head`: the book's name, a way to it, and in the card the close.
class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title, this.label, this.onPressed, this.onClose, required this.em});
  final LucideIcon icon;
  final String title;
  final String? label;

  /// Null for a name that is not a button: a run of chapters whose book isn't a note, the history's heading.
  final VoidCallback? onPressed;
  final VoidCallback? onClose;
  final double em;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('glacier-text');
    final radius = t.radius('sm');
    Widget name(bool hovered) => Container(
          // `padding: 0.3em 0.4em; border-radius: var(--glacier-radius-sm)`;
          // `.headButton:hover { background: color-mix(in srgb, var(--glacier-text) 6%, transparent) }`
          padding: EdgeInsets.symmetric(vertical: 0.3 * em, horizontal: 0.4 * em),
          decoration: BoxDecoration(color: hovered ? t.colorOf('color-mix(in srgb, var(--glacier-text) 6%, transparent)') : null, borderRadius: BorderRadius.circular(radius)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lucide(icon, size: 15, color: ink),
              // `gap: 0.4em`
              SizedBox(width: 0.4 * em),
              // `.headTitle { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: semibold }`
              Flexible(child: _line(t, title, t.textAt(em, weight: 'semibold', color: ink))),
            ],
          ),
        );
    final press = onPressed;
    return Container(
      // `padding: 0 var(--glacier-space-1) var(--glacier-space-2); border-block-end: 1px solid var(--glacier-border-subtle);
      //  margin-block-end: var(--glacier-space-2)`
      margin: EdgeInsets.only(bottom: t.space(2)),
      padding: EdgeInsets.fromLTRB(t.space(1), 0, t.space(1), t.space(2)),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: snapBorder(context, 1)))),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              // `margin-inline-start: -0.4em`: the name's own padding hangs outside the head's.
              child: Transform.translate(
                offset: Offset(-0.4 * em, 0),
                child: press == null
                    ? Semantics(header: true, child: name(false))
                    : GlacierPressable(
                        onPressed: press,
                        semanticLabel: label,
                        builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: radius, child: ExcludeSemantics(child: name(state.hovered))),
                      ),
              ),
            ),
          ),
          if (onClose != null) ...[
            // `gap: var(--glacier-space-2)`
            SizedBox(width: t.space(2)),
            GlacierPressable(
              onPressed: onClose,
              semanticLabel: 'Close',
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                // `.close { inline-size: 2rem; block-size: 2rem; border-radius: 999px; color: var(--glacier-text-muted) }`
                child: SizedBox.square(dimension: t.lenOf('2rem'), child: Center(child: lucide(Lucide.x, size: 16, color: t.color('glacier-text-muted')))),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.list`: the rows, a pixel apart.
class _List extends StatelessWidget {
  const _List({required this.label, required this.rows});
  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        // `display: flex; flex-direction: column; gap: 1px`
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: rows),
      );
}

/// `.row`: a chapter's number in its own column and its name, or an entry's day and how it starts.
class _Row extends StatelessWidget {
  const _Row({required this.number, required this.label, required this.current, required this.onPressed, required this.em, required this.child, this.deep = false});
  final String number;
  final String label;
  final bool current;
  final bool deep;
  final VoidCallback onPressed;
  final double em;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = t.radius('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      // `aria-current="page"`
      selected: current ? true : null,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: radius,
        offset: -2,
        child: Container(
          // `padding: 0.45em 0.6em; border-radius: var(--glacier-radius-sm)`
          padding: EdgeInsetsDirectional.fromSTEB((deep ? 1.6 : 0.6) * em, 0.45 * em, 0.6 * em, 0.45 * em),
          // `.row:hover { background: color-mix(in srgb, var(--glacier-text) 6%, transparent) }`
          decoration: BoxDecoration(color: state.hovered ? t.colorOf('color-mix(in srgb, var(--glacier-text) 6%, transparent)') : null, borderRadius: BorderRadius.circular(radius)),
          // The open chapter: a ring, as the sidebar marks the open note.
          // `box-shadow: inset 0 0 0 var(--app-line) color-mix(in oklch, var(--app-ink) 55%, transparent)`
          foregroundDecoration: current
              ? BoxDecoration(
                  border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)'), width: snapBorder(context, t.len('app-line'))),
                  borderRadius: BorderRadius.circular(radius),
                )
              : null,
          child: ExcludeSemantics(
            child: Row(
              // `align-items: baseline`: one size, one line, so the middle is the baseline.
              children: [
                // `.number { min-inline-size: 1.6em; text-align: end; font-variant-numeric: tabular-nums; color: muted }`
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 1.6 * em),
                  child: _line(t, number, t.textAt(em, color: t.color('glacier-text-muted')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]), align: TextAlign.end),
                ),
                // `gap: 0.5em`
                SizedBox(width: 0.5 * em),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `mask-image: linear-gradient(to right, #000 calc(100% - 32px), transparent)` over one clipped line.
class _Faded extends StatelessWidget {
  const _Faded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: const <Color>[Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: <double>[0, bounds.width <= 32 ? 0 : (bounds.width - 32) / bounds.width, 1],
        ).createShader(bounds),
        child: ClipRect(child: Align(alignment: AlignmentDirectional.centerStart, child: child)),
      );
}

/// `.empty`: a book with no pages, a journal with no entries, a note with no history.
class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `margin: var(--glacier-space-2) var(--glacier-space-1); color: var(--glacier-text-muted)`
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
      child: Text(text, style: t.textAt(t.fontSize('sm'), color: t.color('glacier-text-muted'))),
    );
  }
}

/// `.month`: a journal's month over its entries, the small spaced capitals a sheet's group wears (`app-eyebrow`).
class _Month extends StatelessWidget {
  const _Month(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    // `margin: var(--glacier-space-2) var(--glacier-space-1) var(--glacier-space-1)`
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(1), t.space(2), t.space(1), t.space(1)),
      child: Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Text(text.toUpperCase(), style: t.text('xs', weight: 'bold', color: t.color('app-ink-3')).copyWith(letterSpacing: t.len('app-tracking-caps', em: size))),
        ),
      ),
    );
  }
}

/// `.tabs`: a pair of words in one rounded track, the one shown filled.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.on, required this.onChoose});
  final List<(AsideTab, String)> labels;
  final AsideTab on;
  final ValueChanged<AsideTab> onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final full = BorderRadius.circular(t.radius('full'));
    final em = t.fontSize('sm');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'What the side panel shows',
      child: Container(
        // `gap: 2px; padding: 2px; margin-block-end: var(--glacier-space-3); border-radius: full;
        //  background: color-mix(in srgb, var(--glacier-text) 6%, transparent)`
        margin: EdgeInsets.only(bottom: t.space(3)),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--glacier-text) 6%, transparent)'), borderRadius: full),
        child: Row(
          spacing: 2,
          children: [
            for (final (tab, label) in labels)
              Expanded(
                child: GlacierPressable(
                  onPressed: () => onChoose(tab),
                  semanticLabel: label,
                  selected: on == tab,
                  builder: (context, state) => GlacierFocusRing(
                    // `.tab:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 1px }`
                    visible: state.focused,
                    offset: 1,
                    child: Container(
                      // `min-block-size: 2rem; padding: 0 var(--glacier-space-2)`
                      constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
                      padding: EdgeInsets.symmetric(horizontal: t.space(2)),
                      alignment: Alignment.center,
                      // `.tab[data-on] { background: var(--glacier-bg); color: var(--glacier-text); box-shadow: 0 1px 2px rgb(0 0 0 / 18%) }`
                      decoration: on == tab
                          ? BoxDecoration(color: t.color('glacier-bg'), borderRadius: full, boxShadow: const [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 1), blurRadius: 2)])
                          : null,
                      child: ExcludeSemantics(
                        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(em, weight: 'medium', color: t.color(on == tab ? 'glacier-text' : 'glacier-text-muted'))),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The aside as the notes drawer's card (notes/floating_card.dart), at the right: the same rounded, blurred card hung
/// from the icon that opened it, the page live beside it, closed by a tap outside, Escape, the phone's back gesture,
/// the X, or opening a page. The icon itself is left to close it, as the drawer leaves its own (`AsideCard`).
class AsideCard extends StatelessWidget {
  const AsideCard({super.key, required this.content, this.history, this.links, this.outline, required this.onOpen, required this.onOpenTitle, required this.onClose, this.stored});

  final AsideContent? content;
  final AsideHistoryBuilder? history;
  final AsideHistoryBuilder? links;
  final AsideHistoryBuilder? outline;
  final void Function(String id) onOpen;
  final void Function(String title) onOpenTitle;
  final VoidCallback onClose;
  final Stored? stored;

  @override
  Widget build(BuildContext context) => FloatingCard(
        side: FloatingCardSide.end,
        label: 'Side panel',
        toggle: asideToggle,
        onClose: onClose,
        child: AsidePanel(
          content: content,
          history: history,
          links: links,
          outline: outline,
          popup: true,
          stored: stored,
          onClose: onClose,
          onOpen: (id) {
            onClose();
            onOpen(id);
          },
          onOpenTitle: (title) {
            onClose();
            onOpenTitle(title);
          },
        ),
      );
}
