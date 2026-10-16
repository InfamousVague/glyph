/// A note's headings, as an outline to go about it by: each heading indented by its level, the one the page is
/// at marked, a tap scrolling the page to it. On the More sheet's Outline page and, on a screen wide enough for
/// two panes, in the side panel's Outline tab (lib/links/note_links.dart), where the mark follows the page as it
/// scrolls.
///
/// The headings are read from the editor's own lines (a `LineFact`, kept with the document's tree), so a letter
/// typed reads the line it changed and never the note again; the lines inside a code block are left out.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/view/editor_view.dart';
import '../note/note_place.dart' show documentOffset;
import '../sheet/css.dart' show snapBorder;

/// One heading of the note: its level from 1, its words, and where its line starts.
typedef OutlineHeading = ({int level, String text, int from, int line});

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

final LineFact<({int level, String text})> _headings = LineFact<({int level, String text})>((text) {
  if (!text.startsWith('#')) return null;
  final found = _heading.firstMatch(text);
  final words = found?.group(2) ?? '';
  return found == null || words.isEmpty ? null : (level: found.group(1)!.length, text: words);
});

final LineFact<bool> _fences = LineFact<bool>((text) => text.contains('```') || text.contains('~~~') ? (_fence.hasMatch(text) ? true : null) : null);

final LineFact<bool> _fronts = LineFact<bool>((text) => text == '---' || text == '+++' ? true : null);

/// The headings of [doc], in order, none inside a code block or the front matter.
List<OutlineHeading> outlineOf(Doc doc) {
  final heads = _headings.of(doc);
  if (heads.isEmpty) return const [];
  final fences = _fences.of(doc);
  // The front matter: from a fence on the first line to the next fence.
  var frontEnd = 0;
  final fronts = _fronts.of(doc);
  if (fronts.isNotEmpty && fronts.first.from == 0 && fronts.length > 1) frontEnd = fronts[1].from;
  final out = <OutlineHeading>[];
  var f = 0;
  var inFence = false;
  for (final head in heads) {
    while (f < fences.length && fences[f].from < head.from) {
      inFence = !inFence;
      f += 1;
    }
    if (inFence || head.from <= frontEnd && frontEnd > 0) continue;
    out.add((level: head.fact.level, text: head.fact.text, from: head.from, line: doc.lineAt(head.from).number));
  }
  return out;
}

/// How far under the page's top a heading lands once scrolled to, and where the page counts as being: the header
/// floats over the page.
const double outlineRoom = 96;

/// Which of [headings] the page is at: the last one whose line is above the top of what can be read. -1 above the
/// first.
int currentHeading(EditorView view, ScrollPosition page, List<OutlineHeading> headings) {
  if (headings.isEmpty) return -1;
  final start = documentOffset(view);
  if (start == null || !page.hasPixels) return -1;
  final y = page.pixels - start + outlineRoom + 8;
  final lines = view.state.doc.lines;
  final line = math.min(math.max(1, view.heights.lineAt(y)), lines);
  final at = view.state.doc.line(line).from;
  var found = -1;
  for (var i = 0; i < headings.length; i += 1) {
    if (headings[i].from <= at) found = i;
  }
  return found;
}

/// The page scrolled so the heading starting at [from] sits under the header.
void scrollToHeading(EditorView view, ScrollPosition page, int from, {bool animate = true}) {
  final start = documentOffset(view);
  if (start == null || !page.hasPixels) return;
  final entry = view.blocks.entryOf(view.state.doc.lineAt(math.min(math.max(0, from), view.state.doc.length)).number);
  final to = (start + view.heights.offsetOf(entry) - outlineRoom).clamp(page.minScrollExtent, math.max(page.minScrollExtent, page.maxScrollExtent)).toDouble();
  if (animate) {
    unawaitedScroll(page.animateTo(to, duration: const Duration(milliseconds: 320), curve: const Cubic(0.2, 0.8, 0.2, 1)));
  } else {
    page.jumpTo(to);
  }
}

void unawaitedScroll(Future<void> scrolled) => scrolled.then<void>((_) {}, onError: (Object _) {});

/// The outline drawn: a row for each heading, indented by its level below the note's highest, [current] marked.
/// [compact] is the side panel's smaller type; without it the rows are the sheet's size.
class OutlineList extends StatelessWidget {
  const OutlineList({super.key, required this.headings, required this.current, required this.onPick, this.compact = false});

  final List<OutlineHeading> headings;
  final int current;
  final ValueChanged<OutlineHeading> onPick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (headings.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
        child: Text('No headings yet. A line that starts with # is one.', style: t.textAt(t.fontSize('sm'), color: t.color('glacier-text-muted'))),
      );
    }
    final top = headings.map((heading) => heading.level).reduce(math.min);
    final em = t.fontSize(compact ? 'sm' : 'md');
    final radius = t.radius('sm');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Outline',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          for (final (i, heading) in headings.indexed)
            GlacierPressable(
              key: ValueKey('outline:${heading.from}'),
              onPressed: () => onPick(heading),
              semanticLabel: heading.text,
              selected: i == current ? true : null,
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: radius,
                offset: -2,
                child: Container(
                  padding: EdgeInsetsDirectional.fromSTEB((0.6 + 1.1 * (heading.level - top)) * em, 0.42 * em, 0.6 * em, 0.42 * em),
                  decoration: BoxDecoration(
                    color: state.hovered || state.pressed ? t.colorOf('color-mix(in srgb, var(--glacier-text) 6%, transparent)') : null,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  // The heading the page is at: a ring, as the side panel marks the open chapter.
                  foregroundDecoration: i == current
                      ? BoxDecoration(
                          border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)'), width: snapBorder(context, t.len('app-line'))),
                          borderRadius: BorderRadius.circular(radius),
                        )
                      : null,
                  child: ExcludeSemantics(
                    child: Text(
                      heading.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textAt(em, weight: heading.level == top ? 'semibold' : 'regular', color: t.color(heading.level - top >= 2 ? 'glacier-text-muted' : 'glacier-text')),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The outline of an open note that follows it: its headings read again as the words change, and the mark moved
/// as the page scrolls, each at most once a frame.
class LiveOutline extends StatefulWidget {
  const LiveOutline({super.key, required this.view, required this.page, this.onPicked, this.compact = false});

  final EditorView view;
  final ScrollPosition page;

  /// Told after a heading was gone to: the sheet closes.
  final VoidCallback? onPicked;
  final bool compact;

  @override
  State<LiveOutline> createState() => _LiveOutlineState();
}

class _LiveOutlineState extends State<LiveOutline> {
  late List<OutlineHeading> _headings = outlineOf(widget.view.state.doc);
  late int _current = currentHeading(widget.view, widget.page, _headings);
  Doc? _read;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _read = widget.view.state.doc;
    widget.page.addListener(_moved);
    widget.view.addListener(_moved);
  }

  @override
  void didUpdateWidget(LiveOutline old) {
    super.didUpdateWidget(old);
    if (!identical(old.page, widget.page)) {
      old.page.removeListener(_moved);
      widget.page.addListener(_moved);
    }
    if (!identical(old.view, widget.view)) {
      old.view.removeListener(_moved);
      widget.view.addListener(_moved);
      _read = null;
      _moved();
    }
  }

  @override
  void dispose() {
    widget.page.removeListener(_moved);
    widget.view.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (_asked || !mounted) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asked = false;
      if (!mounted) return;
      final doc = widget.view.state.doc;
      final headings = identical(doc, _read) ? _headings : outlineOf(doc);
      _read = doc;
      final current = currentHeading(widget.view, widget.page, headings);
      if (!identical(headings, _headings) || current != _current) {
        setState(() {
          _headings = headings;
          _current = current;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => OutlineList(
        headings: _headings,
        current: _current,
        compact: widget.compact,
        onPick: (heading) {
          widget.onPicked?.call();
          scrollToHeading(widget.view, widget.page, heading.from);
        },
      );
}
