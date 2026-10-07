/// A note drawn small on its card: the first lines of it after its title, at a fraction of the note's size, clipped
/// to about six lines with the last one fading out where there is more.
///
/// Stands in for `src/app/notes/NotePeek.tsx`. On the web a card's preview is the note's own editor (CodeMirror,
/// read-only, in its formatted view and `peek` mode) given `peekMarkdown(body)`, so whatever a note draws its card
/// draws. The editor is stage 4 of this port; until it is here this draws the same lines by hand, to the rules the
/// editor's stylesheet sets (`editor/markdown.module.css`, `editor/fieldChips.ts`, `editor/headingProgress.ts`,
/// `notes/NotePeek.module.css`), measured on the page:
///
/// - the note's face (Maple Mono) at `--app-body` times the peek's scale, 1.6 to the line, in the third ink;
/// - a heading at its step of the peek's scale, with how many of its to-dos are done after it ("0 of 1");
/// - a list item hung on its marker: the marker quiet, a to-do's box in the mono face, the words in the first ink;
/// - a quote behind its bar, a block of code a step smaller and set in from the edge, a rule;
/// - in a line: bold, italic, struck, code, a link's words, a `#tag` and an `@person` as the chips the editor draws.
///
/// What differs, until the editor replaces it ([NotePeek] is the one seam: nothing else on the home page knows how a
/// preview is drawn):
/// - a table is its rows as typed, a picture its line, a diagram and a query their fences: the editor draws each;
/// - Ghost.md's own marks (`==highlight==`, `||spoiler||`, `??unsure??`, the five effects) and a counter `[3/8]` keep
///   their signs;
/// - code is in the page's ink, not the code theme's colours;
/// - nothing is kept between draws: a card is cheap here, where an editor each was not.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';
import 'home_parts.dart';

/// The preview of a note's [body] on its card. Draws nothing for a canvas (its body is JSON) or a note with nothing
/// under its title.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body, this.fill = false});

  final String body;

  /// The card is stretched to its row's height: the preview takes the room there is, up to its six lines
  /// (NoteCard.module.css `.peek { flex: 1 }` under `max-block-size`).
  final bool fill;

  /// Whether [body] has anything to draw small.
  static bool has(String body) => !isCanvasBody(body) && peekMarkdown(body).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (isCanvasBody(body)) return const SizedBox.shrink();
    final markdown = peekMarkdown(body);
    if (markdown.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    // `--peek-scale: calc(0.62 * var(--app-text-scale))`, and `--app-body` at it.
    final scale = 0.62 * t.len('app-text-scale');
    final em = t.fontSize('lg') * scale;
    final look = _Look(t, scale, em);
    final lines = _read(markdown);
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(top: t.space(2)),
        child: _PeekClip(
          // `max-block-size: calc(1.6em * 6.2)`, and the fade over the last `1.8em`.
          maxHeight: 1.6 * em * 6.2,
          fade: 1.8 * em,
          fill: fill,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < lines.length; i += 1) look.draw(lines, i)],
          ),
        ),
      ),
    );
  }
}

// ---- reading the lines --------------------------------------------------------------------------------------------

enum _Kind { blank, text, heading, item, quote, code, rule }

class _Line {
  _Line(this.kind, this.text, {this.level = 0, this.lead = '', this.box});
  final _Kind kind;

  /// The line's words, its opening marks taken off.
  final String text;

  /// A heading's level, 1 to 6.
  final int level;

  /// A list item's indent, marker and the space after it.
  final String lead;

  /// A to-do's box or a choice's, as written: `[x]`, `( )`.
  final String? box;

  /// A heading's to-dos, done and in all.
  ({int done, int total})? count;
}

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+(\S.*)$');
final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
final RegExp _rule = RegExp(r'^(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$');

List<_Line> _read(String markdown) {
  final lines = <_Line>[];
  String? fence;
  // Progress under a heading (editor/headingProgress.ts): the boxes until the next heading of its level or higher.
  final open = <_Line>[];
  for (final raw in markdown.split('\n')) {
    final fenced = _fence.firstMatch(raw);
    if (fence != null) {
      lines.add(_Line(_Kind.code, raw));
      if (fenced != null && raw.trim().startsWith(fence)) fence = null;
      continue;
    }
    if (fenced != null) {
      fence = fenced.group(1);
      lines.add(_Line(_Kind.code, raw));
      continue;
    }
    if (raw.trim().isEmpty) {
      lines.add(_Line(_Kind.blank, ''));
      continue;
    }
    final heading = _heading.firstMatch(raw);
    if (heading != null) {
      final level = heading.group(1)!.length;
      while (open.isNotEmpty && open.last.level >= level) {
        open.removeLast();
      }
      final line = _Line(_Kind.heading, heading.group(2)!.trimRight(), level: level);
      lines.add(line);
      open.add(line);
      continue;
    }
    final lead = listLead(raw);
    if (lead != null) {
      final boxed = lead.boxAt >= 0;
      final words = raw.substring(lead.wordsAt);
      lines.add(_Line(_Kind.item, words, lead: raw.substring(0, boxed ? lead.boxAt : lead.wordsAt), box: boxed ? raw.substring(lead.boxAt, lead.boxAt + 3) : null));
      // A box with no words is not a to-do yet.
      if (lead.done != null && words.trim().isNotEmpty) {
        for (final each in open) {
          final was = each.count ?? (done: 0, total: 0);
          each.count = (done: was.done + (lead.done! ? 1 : 0), total: was.total + 1);
        }
      }
      continue;
    }
    final quote = _quote.firstMatch(raw);
    if (quote != null) {
      lines.add(_Line(_Kind.quote, quote.group(1)!));
      continue;
    }
    lines.add(_Line(_rule.hasMatch(raw.trim()) ? _Kind.rule : _Kind.text, raw));
  }
  return lines;
}

// ---- drawing them -------------------------------------------------------------------------------------------------

/// What runs inside a line: `**bold**`, `_italic_`, `~~struck~~`, `` `code` ``, a link's words, a note link's title,
/// a tag and a person.
final RegExp _inline = RegExp(
  r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1' // 1, 2: strong
  r'|(?<![\w*])([*_])(?=\S)(.+?)(?<=\S)\3(?![\w*])' // 3, 4: em
  r'|~~(?=\S)(.+?)(?<=\S)~~' // 5: strike
  r'|`([^`\n]+)`' // 6: code
  r'|!?\[\[([^\]|\n]+)(?:\|([^\]\n]*))?\]\]' // 7, 8: a note link, and its own words
  r'|(?<!!)\[([^\]\n]+)\]\((?:[^)\s]+)\)' // 9: a link's words
  r'|(?<![\w/#&])#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)' // 10: a tag
  r'|(?<![\w@.])@(\p{L}[\p{L}\p{N}_.-]*)', // 11: a person
  unicode: true,
);

/// `white-space: break-spaces`, which is how the editor wraps: a space at the end of a line takes its room, and the
/// line breaks before the word that would push it out, where a paragraph of Flutter's hangs the space past the edge
/// (so "sign-in" stayed up where the page had sent "in" down). A no-break space is a space with its width and no
/// hanging, and the zero-width space after it is where the line may break.
String _breakSpaces(String text) => text.replaceAll(' ', '\u00A0\u200B');

/// Maple Mono's ascent, descent and x-height, as shares of its size (hhea 1020 and 300, OS/2 550, of 1000): what the
/// page's line boxes are made of, where a line holds more than one size.
const double _monoAscent = 1.02, _monoDescent = 0.3, _monoX = 0.55;

class _Look {
  _Look(this.t, this.scale, this.em)
      : base = t.textAt(em, mono: true, color: t.color('app-ink-3'), height: 1.6),
        strut = StrutStyle(fontFamily: t.families('glacier-font-mono').firstOrNull, fontSize: em, height: 1.6, leadingDistribution: TextLeadingDistribution.even);

  final Tokens t;
  final double scale;

  /// The words' own size: `--app-body` at the peek's scale.
  final double em;
  final TextStyle base;
  final StrutStyle strut;

  Widget draw(List<_Line> lines, int at) {
    final line = lines[at];
    switch (line.kind) {
      case _Kind.blank:
        return SizedBox(height: 1.6 * em);
      case _Kind.text:
        return _text(TextSpan(children: _spans(line.text, base)));
      case _Kind.rule:
        return _text(TextSpan(text: line.text, style: base.copyWith(color: t.color('glacier-text-subtle'))));
      case _Kind.heading:
        return _headingLine(line, first: at == 0);
      case _Kind.item:
        return _item(line);
      case _Kind.quote:
        final first = at == 0 || lines[at - 1].kind != _Kind.quote;
        final last = at == lines.length - 1 || lines[at + 1].kind != _Kind.quote;
        return _quoteLine(line, first: first, last: last);
      case _Kind.code:
        final first = at == 0 || lines[at - 1].kind != _Kind.code;
        final last = at == lines.length - 1 || lines[at + 1].kind != _Kind.code;
        return _codeLine(line, first: first, last: last);
    }
  }

  /// A block of the words' own size: each line 1.6 of it, to the fraction.
  Widget _text(InlineSpan span, {TextStyle? style}) => CssLines(lineHeight: 1.6 * em, child: _plain(span, style: style));

  Widget _plain(InlineSpan span, {TextStyle? style}) =>
      Text.rich(span, style: style ?? base, strutStyle: strut, textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even));

  /// How far above and below its baseline a run of the mono face at [size] on a line [leading] tall reaches.
  static ({double above, double below}) _reach(double size, double leading) {
    final half = (leading - (_monoAscent + _monoDescent) * size) / 2;
    return (above: _monoAscent * size + half, below: _monoDescent * size + half);
  }

  /// `.h1` to `.h6` (markdown.module.css), at the peek's own sizes (NotePeek.module.css `--app-h1` to `--app-h6`).
  Widget _headingLine(_Line line, {required bool first}) {
    const steps = ['3xl', '2xl', 'xl', 'lg', 'lg', 'md'];
    const leadings = [1.08, 1.12, 1.2, 1.3, 1.6, 1.6];
    const trackings = [-0.035, -0.03, -0.02, -0.01, 0.0, 0.0];
    final level = line.level - 1;
    final size = t.fontSize(steps[level]) * scale;
    final color = switch (line.level) {
      1 => t.colorOf('color-mix(in srgb, var(--glacier-text) 88%, transparent)'),
      6 => t.color('glacier-text-subtle'),
      _ => base.color,
    };
    final style = t.textAt(size, mono: true, weight: line.level <= 2 ? 'bold' : 'semibold', color: color, height: leadings[level], tracking: trackings[level] * size);
    final count = line.count;
    final small = t.fontSize('sm');
    final counted = count != null && count.total > 0;
    // The line's box, as the page's rules stack it: the words' own line, the heading's, and the count's, which is
    // centred on the words' x-height (`vertical-align: middle`) and so hangs a little under the heading's baseline.
    final own = _reach(em, 1.6 * em), big = _reach(size, leadings[level] * size), little = _reach(small, 1.6 * small);
    final drop = (_monoAscent - _monoDescent) / 2 * small - _monoX / 2 * em;
    var above = own.above > big.above ? own.above : big.above, below = own.below > big.below ? own.below : big.below;
    if (counted) {
      if (little.above - drop > above) above = little.above - drop;
      if (little.below + drop > below) below = little.below + drop;
    }
    final words = TextSpan(
      children: [
        ..._spans(line.text, style),
        if (counted)
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              // `.cm-headingCount { margin-inline-start: 0.6em }`.
              padding: EdgeInsetsDirectional.only(start: 0.6 * small),
              child: Transform.translate(
                offset: Offset(0, drop),
                child: Text(
                  count.done == count.total ? 'All ${count.total} done' : '${count.done} of ${count.total}',
                  softWrap: false,
                  style: tabularMono(t.textAt(small, mono: true, weight: 'medium', color: t.color('app-ink-3'), height: 1, tracking: 0.02 * small)),
                ),
              ),
            ),
          ),
      ],
    );
    // Space above a heading, never below, and none over the first line.
    final space = first ? 0.0 : (line.level <= 2 ? t.space(8) : (line.level <= 4 ? t.space(6) : 0.0));
    return Padding(
      padding: EdgeInsets.only(top: space),
      child: CssLines(lineHeight: above + below, above: above, child: Text.rich(words, style: style, textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even))),
    );
  }

  static TextStyle tabularMono(TextStyle style) => style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// `.lineItem`: the words hang off the marker, so a wrapped line starts under the first letter and not the dash.
  Widget _item(_Line line) {
    final ink = base.copyWith(color: t.color('glacier-text'));
    final quiet = base.copyWith(color: t.color('glacier-text-subtle'));
    final box = line.box;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          TextSpan(
            children: [
              TextSpan(text: line.lead.trimRight(), style: quiet),
              TextSpan(text: '\u00A0', style: ink),
              if (box != null) ...[
                TextSpan(text: box.replaceAll(' ', '\u00A0'), style: t.textAt(em, mono: true, weight: 'medium', color: t.color('glacier-accent-text'), height: 1.6)),
                TextSpan(text: '\u00A0', style: ink),
              ],
            ],
          ),
        ),
        Expanded(child: _text(TextSpan(children: _spans(line.text, ink)), style: ink)),
      ],
    );
  }

  /// `.lineQuote`: the bar painted down the line's start, the words in from it, and a little room at each end.
  Widget _quoteLine(_Line line, {required bool first, required bool last}) {
    final edge = t.len('glacier-shape-accent-edge');
    final style = base.copyWith(color: t.color('glacier-text-muted'));
    return Padding(
      padding: EdgeInsets.only(top: first ? 0.35 * em : 0, bottom: last ? 0.35 * em : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: t.color('glacier-border-strong'), width: edge))),
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: edge + 0.75 * em, top: first ? 0.2 * em : 0, bottom: last ? 0.2 * em : 0),
          child: _text(TextSpan(children: _spans(line.text, style)), style: style),
        ),
      ),
    );
  }

  /// `.lineCode`, with its ground taken off as the card takes it: a step smaller, set in from the edge, and clear of
  /// the lines above and below.
  Widget _codeLine(_Line line, {required bool first, required bool last}) {
    final size = em * 0.82;
    final style = t.textAt(size, mono: true, color: t.color('glacier-text'), height: 1.6);
    // A fence's backticks are marks, quiet; the language after them is the block's name, in the first ink.
    final fenced = RegExp(r'^(\s*(?:```+|~~~+))(.*)$').firstMatch(line.text);
    final InlineSpan words = fenced == null || !_fence.hasMatch(line.text)
        ? TextSpan(text: line.text.isEmpty ? ' ' : _breakSpaces(line.text))
        : TextSpan(
            children: [
              TextSpan(text: fenced.group(1), style: style.copyWith(color: t.color('glacier-text-subtle'))),
              TextSpan(text: _breakSpaces(fenced.group(2)!), style: style.copyWith(color: t.color('glacier-accent-text'))),
            ],
          );
    return Padding(
      padding: EdgeInsets.only(left: 0.85 * size, right: 0.85 * size, top: first ? 1.05 * size : 0, bottom: last ? 1.05 * size : 0),
      child: CssLines(
        lineHeight: 1.6 * size,
        child: Text.rich(words, style: style, strutStyle: StrutStyle(fontFamily: style.fontFamily, fontSize: size, height: 1.6, leadingDistribution: TextLeadingDistribution.even)),
      ),
    );
  }

  List<InlineSpan> _spans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: _breakSpaces(text.substring(at, m.start)), style: style));
      at = m.end;
      if (m.group(2) != null) {
        spans.add(TextSpan(children: _spans(m.group(2)!, _bold(style))));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(children: _spans(m.group(4)!, style.copyWith(fontStyle: FontStyle.italic))));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(children: _spans(m.group(5)!, style.copyWith(decoration: TextDecoration.lineThrough))));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(text: _breakSpaces(m.group(6)!), style: style.copyWith(color: t.color('glacier-accent-text'))));
      } else if (m.group(7) != null) {
        spans.add(TextSpan(text: _breakSpaces(m.group(8) ?? m.group(7)!), style: _link(style)));
      } else if (m.group(9) != null) {
        spans.add(TextSpan(text: _breakSpaces(m.group(9)!), style: _link(style)));
      } else if (m.group(10) != null) {
        spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _tag('#${m.group(10)}', style)));
      } else {
        spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _person(m.group(11)!, style)));
      }
    }
    if (at < text.length) spans.add(TextSpan(text: _breakSpaces(text.substring(at)), style: style));
    return spans;
  }

  TextStyle _bold(TextStyle style) => style.copyWith(fontWeight: t.weight('bold'), fontVariations: [FontVariation('wght', t.len('glacier-font-weight-bold'))]);

  TextStyle _link(TextStyle style) =>
      style.copyWith(color: t.color('glacier-accent-text'), fontWeight: t.weight('medium'), fontVariations: [FontVariation('wght', t.len('glacier-font-weight-medium'))], decoration: TextDecoration.underline);

  /// `.cm-tag` (editor/tags.ts): the tag on a wash of its own ink, a touch under the words' size.
  Widget _tag(String words, TextStyle around) {
    final size = 0.92 * (around.fontSize ?? em);
    final color = t.color('app-ink-2');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0.3 * size),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(0.35 * size)),
      child: Text(words, softWrap: false, style: t.textAt(size, mono: true, color: color, height: 1.35)),
    );
  }

  /// `.cm-field[data-person]` (editor/fieldChips.ts): a person's initial in a purple ring, then the name, on a pill.
  Widget _person(String name, TextStyle around) {
    final size = 0.92 * (around.fontSize ?? em);
    final color = t.color('app-ink-2');
    final initial = 0.78 * size;
    return Container(
      padding: EdgeInsetsDirectional.only(start: 0.12 * size, end: 0.35 * size),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 1.25 * initial,
            height: 1.25 * initial,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.colorOf('color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)'), shape: BoxShape.circle),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: t.textAt(initial, mono: true, weight: 'bold', color: t.color('glacier-purple-11'), height: 1.25),
              textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even),
            ),
          ),
          SizedBox(width: 0.28 * initial),
          Text(name, softWrap: false, style: t.textAt(size, mono: true, color: color, height: 1.35)),
        ],
      ),
    );
  }
}

// ---- the clip, and the fade where there is more -------------------------------------------------------------------

/// `max-block-size` with `overflow: hidden`, and `.peek[data-clipped]`'s mask: the child is as tall as its lines, this
/// is no taller than [maxHeight], and where the child is cut the last [fade] of it goes to nothing.
class _PeekClip extends SingleChildRenderObjectWidget {
  const _PeekClip({required this.maxHeight, required this.fade, required this.fill, required Widget super.child});

  final double maxHeight;
  final double fade;
  final bool fill;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPeekClip(maxHeight, fade, fill);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderPeekClip)
      ..maxHeight = maxHeight
      ..fade = fade
      ..fill = fill;
  }
}

class _RenderPeekClip extends RenderProxyBox {
  _RenderPeekClip(this._maxHeight, this._fade, this._fill);

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double _fade;
  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    markNeedsPaint();
  }

  bool _fill;
  set fill(bool value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsLayout();
  }

  bool get _clipped => child != null && child!.size.height > size.height + 1;

  double _capped(double height) => height < _maxHeight ? height : _maxHeight;

  @override
  double computeMinIntrinsicHeight(double width) => _capped(child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) => _capped(child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(BoxConstraints(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth)) ?? Size.zero;
    return constraints.constrain(Size(inner.width, _height(inner.height, constraints)));
  }

  double _height(double inner, BoxConstraints constraints) {
    // Stretched in its card, the preview takes the room it is given, up to its six lines; alone, its own lines.
    if (_fill && constraints.hasBoundedHeight) return _capped(constraints.maxHeight);
    return _capped(inner);
  }

  @override
  void performLayout() {
    final inner = child;
    if (inner == null) {
      size = constraints.smallest;
      return;
    }
    inner.layout(BoxConstraints(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth), parentUsesSize: true);
    size = constraints.constrain(Size(inner.size.width, _height(inner.size.height, constraints)));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final inner = child;
    if (inner == null) return;
    final bounds = offset & size;
    if (!_clipped) {
      if (inner.size.height > size.height) {
        context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) => context.paintChild(inner, offset));
      } else {
        context.paintChild(inner, offset);
      }
      return;
    }
    // A mask and never a painted shadow: the words themselves go to nothing over the last lines.
    final canvas = context.canvas;
    canvas.saveLayer(bounds, Paint());
    canvas.clipRect(bounds);
    context.paintChild(inner, offset);
    final from = (size.height - _fade).clamp(0.0, size.height);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, size.height == 0 ? 0 : from / size.height, 1],
        ).createShader(bounds),
    );
    canvas.restore();
  }
}
