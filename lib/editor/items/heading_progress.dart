/// Progress under a heading: a heading with to-dos under it says how many are done, after its words. Ports
/// `src/app/editor/headingProgress.ts`.
///
///     ## Packing            3 of 7
///     - [x] Tent
///     - [ ] Stove
///
/// Nothing is typed and nothing is written: the count is read from the boxes until the next heading of the same
/// level or higher, so a `##` counts its `###` sections too. When every box is ticked it says so. A heading with
/// no to-dos under it says nothing. A box with no words is not a to-do yet, nor is one with only a due day or a
/// person after it: fields are not words.
///
/// What differs: `vertical-align: middle` is worked out here as Blink works it out (the count's own line box set
/// with its middle half an x-height over the heading's baseline), since a paragraph of Flutter's has no such
/// alignment; the x-height is the face's, measured.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/item_syntax.dart';
import '../../core/task_fields.dart';
import '../editor.dart';
import '../looks/look.dart' show FaceMetrics, layoutUnit, lineBoxHeight;
import '../view/line.dart' show EditorRunScope;
import '../view/lines.dart';
import 'inline_box.dart';

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+\S');

class HeadingCount {
  const HeadingCount({required this.line, required this.done, required this.total});

  /// The heading's line number.
  final int line;
  final int done;
  final int total;

  @override
  bool operator ==(Object other) => other is HeadingCount && other.line == line && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(line, done, total);

  @override
  String toString() => 'HeadingCount(line $line, $done of $total)';
}

class _Open {
  _Open(this.line, this.level);
  final int line;
  final int level;
  int done = 0;
  int total = 0;
}

/// What a line is to the counts: a heading, by its level from 1 to 6, or a to-do with words, open (7) or done (8).
/// Kept for every line of a document (`LineFact`), so a letter typed reads the lines it changed, not the note.
final LineFact<int> _counted = LineFact<int>((text) {
  // A heading has its sign and a to-do its box: a line with neither is neither.
  if (!text.contains('#') && !text.contains('[')) return null;
  final heading = _heading.firstMatch(text);
  if (heading != null) return heading.group(1)!.length;
  final lead = listLead(text);
  // A box with only fields after it, `- [ ] 📅 2026-10-03`, has nothing to do yet either.
  if (lead != null && lead.done != null && withoutFields(text.substring(lead.wordsAt)).isNotEmpty) return lead.done! ? 8 : 7;
  return null;
});

final DocMemo<List<HeadingCount>> _counts = DocMemo<List<HeadingCount>>((doc) {
  final open = <_Open>[];
  final counts = <HeadingCount>[];
  void close(int level) {
    while (open.isNotEmpty && open.last.level >= level) {
      final heading = open.removeLast();
      if (heading.total > 0) counts.add(HeadingCount(line: heading.line, done: heading.done, total: heading.total));
    }
  }

  final lines = _counted.of(doc);
  if (lines.isEmpty) return counts;
  // A heading or a box in fenced code is code.
  final fences = DocFences.of(doc);
  for (final line in lines) {
    if (fences.covers(line.number)) continue;
    if (line.fact <= 6) {
      close(line.fact);
      open.add(_Open(line.number, line.fact));
      continue;
    }
    for (final h in open) {
      h.total += 1;
      if (line.fact == 8) h.done += 1;
    }
  }
  close(0);
  return counts..sort((a, b) => a.line - b.line);
});

/// Every heading with to-dos under it, and their count. Worked out once for each document, from the lines the
/// tree keeps; not to be changed.
List<HeadingCount> headingCounts(Doc doc) => _counts.of(doc);

/// The x-height of the faces the app ships, as a share of the size: what `vertical-align: middle` is measured
/// from. Maple Mono's as the page measures it; Inter's from its tables.
double _xHeight(String? family) => (family ?? '').contains('Maple') ? 0.563 : 0.546;

class CountWidget extends EditorWidget {
  const CountWidget(this.done, this.total);

  final int done;
  final int total;

  @override
  bool eq(CountWidget other) => other.done == done && other.total == total;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final base = scope?.line.base;
    // '.cm-headingCount': { marginInlineStart: '0.6em', verticalAlign: 'middle',
    //   fontSize: 'var(--glacier-font-size-sm, 0.8rem)', fontWeight: '500', letterSpacing: '0.02em',
    //   color: 'var(--app-ink-3, currentColor)', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }
    final small = t.fontSize('sm');
    final coding = base?.props.mono ?? true;
    final style = (base?.style ?? t.textAt(small)).copyWith(
      fontSize: small,
      fontWeight: FontWeight.w500,
      fontVariations: <FontVariation>[const FontVariation('wght', 500), if (base?.props.optical ?? false) FontVariation('opsz', small)],
      // `letter-spacing: 0 !important` in a coding face (typefaces.css).
      letterSpacing: coding ? 0 : 0.02 * small,
      color: t.color('app-ink-3'),
      fontFeatures: <FontFeature>[...?base?.style.fontFeatures, const FontFeature.tabularFigures()],
      height: 1,
      decoration: TextDecoration.none,
    );
    // The count's own inline box, as the page makes it: the face's ascent and descent to whole pixels, the line's
    // leading (1.6, inherited as a number) with the upper half floored.
    final face = FaceMetrics.of(style);
    final ascent = (face.ascent * small).roundToDouble(), descent = (face.descent * small).roundToDouble();
    final leading = lineBoxHeight(base?.props.lineHeight ?? 1.6, small);
    final above = ascent + ((leading - ascent - descent) / 2).floorToDouble(), below = leading - above;
    // `vertical-align: middle`: the box's middle on the line's baseline plus half the parent's x-height.
    final em = base?.fontSize ?? t.len('app-body');
    final drop = (above - below) / 2 - layoutUnit(_xHeight(style.fontFamily) * em / 2);
    final text = done == total ? 'All $total done' : '$done of $total';
    return Semantics(
      label: '$done of $total done',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 0.6 * small),
          child: InlineBox(
            above: above - drop,
            below: below + drop,
            // The words on the box's own baseline: under its top by its ascent and the upper half of its leading.
            child: Dropped(
              top: above - face.ascent * small,
              child: Text(text, softWrap: false, textScaler: TextScaler.noScaling, style: style.copyWith(height: face.ascent + face.descent)),
            ),
          ),
        ),
      ),
    );
  }
}

DecorationSet _decorate(Doc doc) {
  final builder = RangeSetBuilder<Decoration>();
  for (final count in headingCounts(doc)) {
    final line = doc.line(count.line);
    builder.add(line.to, line.to, Decoration.widget(widget: CountWidget(count.done, count.total), side: 1));
  }
  return builder.finish();
}

class _Progress extends PluginValue {
  _Progress(EditorViewLike view) : decorations = _decorate(view.state.doc);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged) decorations = _decorate(update.state.doc);
  }
}

final Extension _progress = ViewPlugin.define<_Progress>(_Progress.new, decorations: (value) => value.decorations);

/// "3 of 7" after a heading with to-dos under it.
Extension headingProgress() => _progress;
