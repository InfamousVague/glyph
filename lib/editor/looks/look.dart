/// How a class name becomes paint: the small part of a browser's cascade the editor's stylesheets need, so that
/// `editor/markdown.module.css` and the themes the extension files write with `EditorView.baseTheme` port rule for
/// rule (`markdown_look.dart`, and each extension's own [LookSheet]).
///
/// CodeMirror hands the page class names (`Decoration.line({class})`, `Decoration.mark({class})`) and the page's
/// stylesheets say what they mean. Here a [LookSheet] is a stylesheet: [LookRule]s in source order, each for one
/// class, each a function that sets properties on a [Props] as the rule's declarations do. A [Look] is the
/// stylesheets in force over one editor, with the tokens they read ([LookEnv]); it resolves a line's classes to a
/// [LineLook] and a run's nest of marks to a [RunLook].
///
/// What is kept of CSS, because the editor's rules lean on it:
/// - order: the rule with more classes in its selector wins, then the later sheet, then the later rule (so `.mark`,
///   last in the file, dims a `**` that is also `.strong`);
/// - inheritance: a line's face, size, ink and leading reach its runs, and a mark inside a mark starts from the
///   outer one; `em` sizes multiply down the nest (`.cm-calloutName, .cm-calloutName *` is 0.82em twice over);
/// - `.x *` rules ([LookRule.under]), `:first-child`, `:last-of-type`, `.a + .b` and an empty line, as conditions
///   on a [LineContext];
/// - a line box as Blink makes it: every inline box on the line gives its rounded ascent and descent and its
///   leading, half of it floored above ([RunLook.above], [RunLook.below]), lengths kept to a sixty-fourth of a
///   pixel and a border to a whole device pixel. The numbers are measured on the page (tool/editor_reference.mjs).
///
/// What is not: anything not listed. A property the editor's sheets never set has no field here.
library;

import 'package:flutter/painting.dart';
import 'package:glacier/glacier.dart';

import 'code_themes.dart';

/// A length as Blink lays it out: a whole number of sixty-fourths of a pixel, the nearest. What a line-height is
/// taken to.
double layoutUnit(double value) => (value * 64).roundToDouble() / 64;

/// A padding, a margin or a gutter as Blink takes it: down to the sixty-fourth below (measured: four headings'
/// paddings rounded to the nearest put the fifth a sixteenth of a pixel low).
double layoutUnitFloor(double value) => (value * 64 + 1e-6).floorToDouble() / 64;

/// A width of text as Blink takes it: up to the next sixty-fourth.
double layoutUnitCeil(double value) => (value * 64 - 1e-6).ceilToDouble() / 64;

/// An element a rule may match: a line, or the span of one mark decoration. Its classes and its attributes, as
/// the decoration gave them.
class LookElement {
  LookElement(String? className, [this.attrs = const <String, String>{}]) : classes = _split(className);

  const LookElement.of(this.classes, [this.attrs = const <String, String>{}]);

  static List<String> _split(String? className) {
    if (className == null || className.isEmpty) return const <String>[];
    if (!className.contains(' ')) return <String>[className];
    return className.split(' ').where((c) => c.isNotEmpty).toList();
  }

  final List<String> classes;
  final Map<String, String> attrs;

  bool has(String name) => classes.contains(name);

  /// A custom property from the element's `style` attribute (`--hang: 20.95px`), in pixels; null when it has none.
  double? styleLength(String property) {
    final style = attrs['style'];
    if (style == null) return null;
    final found = RegExp('${RegExp.escape(property)}\\s*:\\s*(-?[\\d.]+)px').firstMatch(style);
    return found == null ? null : double.parse(found.group(1)!);
  }

  String get key => attrs.isEmpty ? classes.join(' ') : '${classes.join(' ')}|${attrs.entries.map((e) => '${e.key}=${e.value}').join(';')}';
}

/// Where a line stands among its siblings: what `:first-child`, `:last-of-type`, `.cm-frontFold + .cm-line` and
/// `:has(> br:only-child)` ask.
class LineContext {
  const LineContext({this.first = false, this.last = false, this.after, this.empty = false});

  /// The first thing in the editor's content.
  final bool first;

  /// The last line of the document.
  final bool last;

  /// The class of the block widget directly before the line, if one is.
  final String? after;

  /// A line with nothing drawn on it.
  final bool empty;

  String get key => '${first ? 'f' : ''}${last ? 'l' : ''}${empty ? 'e' : ''}${after ?? ''}';

  static const LineContext none = LineContext();
}

/// What the rules read that is not the element: the tokens, the sizes the page sets as custom properties
/// (`--app-body`, `--app-h1`... `--app-gutter`, which a card's preview sets again for itself), and what the root
/// says of the note's face.
class LookEnv {
  LookEnv({
    required this.t,
    required this.body,
    required this.headings,
    required this.gutter,
    this.devicePixelRatio = 2,
    this.dark = false,
    this.meHue,
    this.attrs = const <String, String>{},
    this.ink,
    this.tabSize = 4,
    double? contentTop,
    double? contentBottom,
  }) : contentTop = layoutUnitFloor(contentTop ?? t.space(5)),
       contentBottom = layoutUnitFloor(contentBottom ?? roomUnder(t)),
       code = CodeTheme.of(t),
       noteFamilies = _families(t, 'app-note-font', attrs),
       monoFamilies = _families(t, 'glacier-font-mono', const <String, String>{}),
       codingFace = _coding(t, attrs);

  /// The page's own sizes: app.css's `--app-body`, `--app-h1` to `--app-h6` and `--app-gutter` at the root.
  factory LookEnv.page(Tokens t, {double devicePixelRatio = 2, String? meHue, Map<String, String> attrs = const <String, String>{}, int tabSize = 4}) => LookEnv(
    t: t,
    body: t.len('app-body'),
    headings: <double>[for (var level = 1; level <= 6; level++) t.len('app-h$level')],
    gutter: t.len('app-gutter'),
    devicePixelRatio: devicePixelRatio,
    dark: t.isDark,
    meHue: meHue,
    attrs: attrs,
    tabSize: tabSize,
  );

  final Tokens t;

  /// `--app-body`.
  final double body;

  /// `--app-h1` to `--app-h6`.
  final List<double> headings;

  /// `--app-gutter`.
  final double gutter;

  /// Device pixels to the logical one: a border is drawn a whole number of them wide.
  final double devicePixelRatio;

  /// Which side of the page's theme is in force, for the selection (glyphTheme.ts).
  final bool dark;

  /// The hue the person wears (`data-me-hue` round the editor), for the selection.
  final String? meHue;

  /// The editor's own attributes (`EditorView.editorAttributes`): `data-look`.
  final Map<String, String> attrs;

  /// The ink the editor's words start in, where what holds it sets another (`.peek { color }`): null for
  /// `var(--glacier-text)`.
  final Color? ink;

  /// `tab-size` on the content: the state's tab size.
  final int tabSize;

  /// `.cm-content { padding: var(--glacier-space-5) 0 var(--glacier-space-24) }` (glyphTheme.ts): room over the
  /// first line and under the last. A card's preview has none; the split layout a paragraph's worth below.
  final double contentTop;
  final double contentBottom;

  /// The room under the last line on the split layout, and nothing said anywhere else (markdown.module.css):
  ///
  ///     :global(.app-split) .editor :global(.cm-editor) :global(.cm-content) { padding-block-end: var(--glacier-space-8) }
  ///
  /// Four classes, written to beat the theme's two, and so it beats every rule of three that says an editor in a
  /// smaller place has no room at all: a notebook's words over its index (`.preface .cm-editor .cm-content`), a
  /// card's preview (`.peek .cm-editor .cm-content`). On the page each keeps this paragraph's worth under its last
  /// line while the window is in panes, and so does whoever asks here. The panes are the shell's
  /// (`GlacierScope(classes: {'app-split'})`, shell/app_shell.dart).
  static double? splitRoom(Tokens t) => t.classes.contains('app-split') ? t.space(8) : null;

  /// The room under a note's last line: the split layout's, or the phone's tall one.
  static double roomUnder(Tokens t) => splitRoom(t) ?? t.space(24);

  /// The code theme for the page's side (codeThemes.css).
  final CodeTheme code;

  /// `var(--app-note-font, var(--glacier-font-sans))`, the faces the app ships.
  final List<String> noteFamilies;

  /// `var(--glacier-font-mono)`.
  final List<String> monoFamilies;

  /// typefaces.css: a note in a coding face (Maple Mono, Fira Code) and not a page to read has the font's own
  /// features, no optical sizing, and `letter-spacing: 0 !important` on everything in it.
  final bool codingFace;

  static bool _reading(Map<String, String> attrs) => attrs['data-look'] == 'reading';

  static List<String> _families(Tokens t, String name, Map<String, String> attrs) {
    // `.cm-editor[data-look='reading'] { --app-note-font: var(--glacier-font-sans) }`
    if (name == 'app-note-font' && _reading(attrs)) return t.families('glacier-font-sans');
    if (t.raw(name) == null) return t.families('glacier-font-sans');
    return t.families(name);
  }

  static bool _coding(Tokens t, Map<String, String> attrs) {
    if (_reading(attrs)) return false;
    final face = t.attrs['note-font'];
    return face == null || face == 'maple' || face == 'fira';
  }

  double heading(int level) => headings[level - 1];

  /// A border's width as the page draws it: down to a whole device pixel, never under one.
  double border(double width) {
    if (width <= 0) return 0;
    final device = (width * devicePixelRatio).floorToDouble();
    return (device < 1 ? 1 : device) / devicePixelRatio;
  }

  /// What tells one environment from another: the stylesheet and what the root says, not the object that reads
  /// them, which is made again at every build.
  String get key => '${identityHashCode(t.sheet)}|${t.attrs}|${t.classes}|$body|${headings.join(',')}|$gutter|$devicePixelRatio|$dark|$meHue|$attrs|$ink|$tabSize|$contentTop|$contentBottom';
}

/// Something painted behind or over a run by whoever styled it: the hook a plugin's format look (a highlight's
/// wash, a spoiler's cover) draws through. Called once for each visual line the run is on.
abstract class RunPainter {
  const RunPainter();

  /// Paints under the words. `boxes` are the run's rectangles on one visual line, in the canvas's coordinates.
  void paintBehind(Canvas canvas, List<Rect> boxes, RunLook look) {}

  /// Paints over the words.
  void paintOver(Canvas canvas, List<Rect> boxes, RunLook look) {}

  /// Whether the words themselves are drawn.
  bool get drawsWords => true;
}

/// The properties a rule sets: the ones a line's or a span's rules in the editor's stylesheets declare. Text
/// properties are inherited by what is inside; box properties are a line's alone.
class Props {
  Props.root(LookEnv env)
    : fontSize = env.body,
      families = env.noteFamilies,
      // `.cm-scroller { line-height: 1.6 }`
      lineHeight = 1.6,
      color = env.ink ?? env.t.color('glacier-text'),
      weight = 400,
      mono = env.codingFace,
      optical = !env.codingFace,
      pageFeatures = !env.codingFace,
      _parentSize = env.body;

  Props.inherit(Props parent)
    : fontSize = parent.fontSize,
      families = parent.families,
      lineHeight = parent.lineHeight,
      color = parent.color,
      weight = parent.weight,
      italic = parent.italic,
      tracking = parent.tracking,
      mono = parent.mono,
      optical = parent.optical,
      pageFeatures = parent.pageFeatures,
      tabular = parent.tabular,
      tabSize = parent.tabSize,
      underlineAbove = parent.underlineAbove || parent.underline,
      lineThroughAbove = parent.lineThroughAbove || parent.lineThrough,
      _parentSize = parent.fontSize,
      _parentWeight = parent.weight;

  // -- text, inherited ---------------------------------------------------------------------------------------------
  double fontSize;
  List<String> families;

  /// `line-height` as a multiple of the element's own size, which is how a unitless one inherits.
  double lineHeight;
  Color color;
  double weight;
  bool italic = false;

  /// `letter-spacing`, in pixels.
  double tracking = 0;

  /// The face is a coding one: the font's own features, and no spacing.
  bool mono;

  /// `font-optical-sizing: auto`.
  bool optical;

  /// The page's own font features (app.css on `body`: Inter's `cv11`, `ss01`), until a rule sets
  /// `font-feature-settings`.
  bool pageFeatures;

  /// `font-variant-numeric: tabular-nums`.
  bool tabular = false;
  int? tabSize;

  // -- text, the element's own -----------------------------------------------------------------------------------
  bool underline = false;
  bool lineThrough = false;

  /// An ancestor's decoration, which a child cannot switch off.
  bool underlineAbove = false;
  bool lineThroughAbove = false;

  /// `vertical-align: super` (above zero) or `sub`: how far the baseline is raised, in pixels.
  double shift = 0;
  Color? Function(Color current)? background;
  RunPainter? painter;

  // -- a line's box ----------------------------------------------------------------------------------------------
  double marginStart = 0, marginEnd = 0;
  double paddingStart = 0, paddingEnd = 0, paddingTop = 0, paddingBottom = 0;

  /// Transparent borders above and below: the space round a block, which the paint stays inside.
  double borderTop = 0, borderBottom = 0;

  /// A real border down the start edge.
  double borderStart = 0;
  Color? Function(Color current)? borderStartColor;

  /// A bar painted down the start of the padding box (a quote's `background-image`).
  double barWidth = 0;
  Color? barColor;

  /// Corner radii of the border box, as CSS gives them: across and down.
  Radius topStart = Radius.zero, topEnd = Radius.zero, bottomStart = Radius.zero, bottomEnd = Radius.zero;

  /// `text-indent`, in pixels: below zero is a hanging first line.
  double textIndent = 0;

  /// The element the rules are running for, for a rule that reads its attributes (`var(--hang)`).
  LookElement? element;

  final double _parentSize;
  double? _parentWeight;
  double? _trackingEm;

  /// The parent's font size: what `em` means in `font-size`.
  double get parentSize => _parentSize;

  /// `font-size: <n>em`.
  void sizeEm(double em) => fontSize = _parentSize * em;

  /// `letter-spacing: <n>em`, of the element's own size once the cascade is done.
  void trackingEm(double em) => _trackingEm = em;

  void trackingPx(double px) {
    _trackingEm = null;
    tracking = px;
  }

  /// `font-weight: inherit`.
  void weightInherit() => weight = _parentWeight ?? weight;

  /// `em` in a box property: the element's own font size. Only right after every font-size rule has run, which is
  /// why box lengths are given as functions of the finished size ([LookRule.box]).
  double em(double n) => fontSize * n;

  void _finish(LookEnv env) {
    if (_trackingEm != null) tracking = fontSize * _trackingEm!;
    // `.cm-editor:not([data-look='reading']) * { letter-spacing: 0 !important }` (typefaces.css)
    if (env.codingFace) tracking = 0;
  }
}

/// One rule of a stylesheet.
class LookRule {
  /// `.name { ... }`, on the element that has the class. `classes` is how many classes the selector has, which
  /// orders it against other rules (a CSS-module class alone is 1; `.editor .cm-line.lineItem` is 3; a rule from
  /// `EditorView.theme` or `baseTheme` has the theme's own class before it, so `.cm-sup` there is 2).
  const LookRule(this.name, this.apply, {this.classes = 1, this.when, this.box, this.under = false});

  /// `.name * { ... }`: on every element inside one that has the class.
  const LookRule.under(this.name, this.apply, {this.classes = 1, this.when, this.box}) : under = true;

  final String name;
  final bool under;
  final int classes;

  /// A further condition on the element and, for a line, on where it stands.
  final bool Function(LookElement element, LineContext context)? when;

  /// The declarations that do not depend on the element's finished font size.
  final void Function(Props p, LookEnv e)? apply;

  /// The declarations in `em` of the element's own size (padding, borders, radii), run once the size is known.
  final void Function(Props p, LookEnv e)? box;
}

/// A stylesheet: rules in source order.
class LookSheet {
  const LookSheet(this.name, this.rules);

  /// The file it ports.
  final String name;
  final List<LookRule> rules;
}

/// One class's face, measured once: the ascent and descent of a font as shares of its size, which Blink rounds to
/// whole pixels at each size.
class FaceMetrics {
  const FaceMetrics(this.ascent, this.descent);

  final double ascent;
  final double descent;

  static final Map<String, FaceMetrics> _known = <String, FaceMetrics>{};
  static bool _watching = false;

  static FaceMetrics of(TextStyle face) {
    final key = '${face.fontFamily}|${face.fontFamilyFallback?.join(',')}|${face.fontWeight?.value}|${face.fontStyle}';
    return _known.putIfAbsent(key, () {
      if (!_watching) {
        _watching = true;
        // A font that arrives later is a different answer.
        PaintingBinding.instance.systemFonts.addListener(_known.clear);
      }
      const probe = 1000.0;
      final painter = TextPainter(
        text: TextSpan(text: 'x', style: face.copyWith(fontSize: probe, height: kTextHeightNone, letterSpacing: 0)),
        textDirection: TextDirection.ltr,
      )..layout();
      final line = painter.computeLineMetrics().first;
      painter.dispose();
      return FaceMetrics(line.ascent / probe, line.descent / probe);
    });
  }
}

/// A run's resolved look: how its words are set, and what its inline boxes give the line.
class RunLook {
  RunLook({
    required this.style,
    required this.fontSize,
    required this.color,
    required this.ascent,
    required this.descent,
    required this.above,
    required this.below,
    required this.shift,
    required this.backgrounds,
    required this.painter,
    required this.props,
  });

  /// The words' style. Its height is the font's own: the line box is worked out here, not by the paragraph.
  final TextStyle style;
  final double fontSize;
  final Color color;

  /// The innermost box's content area above and below its baseline: the font's ascent and descent, each rounded
  /// to a whole pixel. What `coordsAtPos` answers for a position in the run.
  final double ascent;
  final double descent;

  /// How far above and below the line's baseline the run's inline boxes reach, leading included: the most of every
  /// box in the nest.
  final double above;
  final double below;

  /// How far the words' own baseline is raised above the line's.
  final double shift;

  /// The grounds painted behind the words, outermost first.
  final List<Color> backgrounds;
  final RunPainter? painter;

  /// The properties it was resolved from, for what is nested inside.
  final Props props;
}

/// A line's resolved look: its box, and the look of words no mark covers.
class LineLook {
  LineLook({
    required this.base,
    required this.marginStart,
    required this.marginEnd,
    required this.paddingStart,
    required this.paddingEnd,
    required this.paddingTop,
    required this.paddingBottom,
    required this.borderTop,
    required this.borderBottom,
    required this.borderStart,
    required this.borderStartColor,
    required this.background,
    required this.barWidth,
    required this.barColor,
    required this.topStart,
    required this.topEnd,
    required this.bottomStart,
    required this.bottomEnd,
    required this.hang,
    required this.tabSize,
    required this.element,
  });

  /// Words on the line that no mark covers, and the line's strut.
  final RunLook base;
  final double marginStart, marginEnd;
  final double paddingStart, paddingEnd, paddingTop, paddingBottom;
  final double borderTop, borderBottom;
  final double borderStart;
  final Color? borderStartColor;
  final Color? background;
  final double barWidth;
  final Color? barColor;

  /// The corners of the painted ground: the border box's radii less the borders.
  final Radius topStart, topEnd, bottomStart, bottomEnd;

  /// How far the first visual line starts before the rest (`text-indent` below zero, against the same padding).
  final double hang;
  final int tabSize;
  final LookElement element;

  /// The line's width outside its words: both sides.
  double get insetX => marginStart + marginEnd + borderStart + paddingStart + paddingEnd;
}

/// The stylesheets in force over one editor, and what they resolve to. Made again when the tokens, the sizes or
/// the sheets change; resolved looks are kept.
class Look {
  Look(this.env, List<LookSheet> sheets) : sheets = List<LookSheet>.unmodifiable(sheets) {
    var order = 0;
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        (rule.under ? _under : _own).putIfAbsent(rule.name, () => <(int, LookRule)>[]).add((order++, rule));
      }
    }
    _root = Props.root(env);
  }

  final LookEnv env;
  final List<LookSheet> sheets;
  final Map<String, List<(int, LookRule)>> _own = <String, List<(int, LookRule)>>{};
  final Map<String, List<(int, LookRule)>> _under = <String, List<(int, LookRule)>>{};
  late final Props _root;
  final Map<String, LineLook> _lines = <String, LineLook>{};
  final Map<LineLook, Map<String, RunLook>> _runs = Map<LineLook, Map<String, RunLook>>.identity();

  /// Whether `other` would resolve everything as this does.
  bool same(Look other) {
    if (env.key != other.env.key || sheets.length != other.sheets.length) return false;
    for (var i = 0; i < sheets.length; i++) {
      if (!identical(sheets[i], other.sheets[i])) return false;
    }
    return true;
  }

  List<(int, LookRule)> _matching(LookElement element, LineContext context, List<LookElement> ancestors) {
    final found = <(int, LookRule)>[];
    for (final name in element.classes) {
      final rules = _own[name];
      if (rules == null) continue;
      for (final rule in rules) {
        if (rule.$2.when == null || rule.$2.when!(element, context)) found.add(rule);
      }
    }
    for (final ancestor in ancestors) {
      for (final name in ancestor.classes) {
        final rules = _under[name];
        if (rules == null) continue;
        for (final rule in rules) {
          if (rule.$2.when == null || rule.$2.when!(ancestor, context)) found.add(rule);
        }
      }
    }
    found.sort((a, b) => a.$2.classes != b.$2.classes ? a.$2.classes - b.$2.classes : a.$1 - b.$1);
    return found;
  }

  Props _cascade(Props parent, LookElement element, LineContext context, List<LookElement> ancestors) {
    final props = Props.inherit(parent)..element = element;
    final rules = _matching(element, context, ancestors);
    for (final rule in rules) {
      rule.$2.apply?.call(props, env);
    }
    props._finish(env);
    for (final rule in rules) {
      rule.$2.box?.call(props, env);
    }
    return props;
  }

  TextStyle _style(Props p) {
    final fallbacks = <String>[...p.families.skip(1), for (final family in p.families) ...?env.t.typography.fallbacks[family]];
    final features = <FontFeature>[if (p.pageFeatures) ...env.t.typography.features, if (p.tabular) const FontFeature.tabularFigures()];
    final under = p.underline || p.underlineAbove, struck = p.lineThrough || p.lineThroughAbove;
    return TextStyle(
      inherit: false,
      fontFamily: p.families.isEmpty ? null : p.families.first,
      fontFamilyFallback: fallbacks.isEmpty ? null : fallbacks,
      fontSize: p.fontSize,
      fontWeight: FontWeight.values[((p.weight / 100).round() - 1).clamp(0, 8)],
      fontStyle: p.italic ? FontStyle.italic : FontStyle.normal,
      fontVariations: <FontVariation>[FontVariation('wght', p.weight), if (p.optical) FontVariation('opsz', p.fontSize)],
      fontFeatures: features.isEmpty ? null : features,
      letterSpacing: p.tracking,
      color: p.color,
      textBaseline: TextBaseline.alphabetic,
      decoration: under && struck
          ? TextDecoration.combine(const <TextDecoration>[TextDecoration.underline, TextDecoration.lineThrough])
          : under
          ? TextDecoration.underline
          : struck
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      decorationColor: p.color,
    );
  }

  /// What one inline box of `p` gives its line: above and below the line's baseline.
  ({double above, double below, double ascent, double descent}) _box(Props p, TextStyle style) {
    final face = FaceMetrics.of(style);
    final ascent = (face.ascent * p.fontSize).roundToDouble(), descent = (face.descent * p.fontSize).roundToDouble();
    final leading = layoutUnit(p.lineHeight * p.fontSize);
    final above = ascent + ((leading - (ascent + descent)) / 2).floorToDouble();
    return (above: above, below: leading - above, ascent: ascent, descent: descent);
  }

  RunLook _run(Props p, RunLook? outer, List<Color> grounds) {
    final style = _style(p);
    final box = _box(p, style);
    final shift = (outer?.shift ?? 0) + p.shift;
    var above = box.above + shift, below = box.below - shift;
    if (outer != null && outer.above > above) above = outer.above;
    if (outer != null && outer.below > below) below = outer.below;
    return RunLook(
      style: style,
      fontSize: p.fontSize,
      color: p.color,
      ascent: box.ascent,
      descent: box.descent,
      above: above,
      below: below,
      shift: shift,
      backgrounds: grounds,
      painter: p.painter,
      props: p,
    );
  }

  /// The look of a line with these classes and attributes, standing where `context` says.
  LineLook line(LookElement element, [LineContext context = LineContext.none]) {
    final key = '${element.key}#${context.key}';
    return _lines.putIfAbsent(key, () {
      // `.cm-line` is every line's own class.
      final el = LookElement.of(<String>['cm-line', ...element.classes], element.attrs);
      final p = _cascade(_root, el, context, const <LookElement>[]);
      final base = _run(p, null, const <Color>[]);
      final borderTop = env.border(p.borderTop), borderBottom = env.border(p.borderBottom), borderStart = env.border(p.borderStart);
      Radius inner(Radius r, double across, double down) =>
          r == Radius.zero ? r : Radius.elliptical((r.x - across).clamp(0, double.infinity).toDouble(), (r.y - down).clamp(0, double.infinity).toDouble());
      return LineLook(
        base: base,
        marginStart: layoutUnitFloor(p.marginStart),
        marginEnd: layoutUnitFloor(p.marginEnd),
        paddingStart: layoutUnitFloor(p.paddingStart),
        paddingEnd: layoutUnitFloor(p.paddingEnd),
        paddingTop: layoutUnitFloor(p.paddingTop),
        paddingBottom: layoutUnitFloor(p.paddingBottom),
        borderTop: borderTop,
        borderBottom: borderBottom,
        borderStart: borderStart,
        borderStartColor: p.borderStartColor?.call(p.color),
        background: p.background?.call(p.color),
        barWidth: p.barWidth,
        barColor: p.barColor,
        topStart: inner(p.topStart, borderStart, borderTop),
        topEnd: inner(p.topEnd, 0, borderTop),
        bottomStart: inner(p.bottomStart, borderStart, borderBottom),
        bottomEnd: inner(p.bottomEnd, 0, borderBottom),
        hang: p.textIndent < 0 ? -p.textIndent : 0,
        tabSize: p.tabSize ?? env.tabSize,
        element: el,
      );
    });
  }

  /// The look of a run on `line` inside these marks, outermost first. With no marks it is the line's own.
  RunLook run(LineLook line, List<LookElement> marks) {
    if (marks.isEmpty) return line.base;
    final known = _runs.putIfAbsent(line, () => <String, RunLook>{});
    final key = marks.length == 1 ? marks[0].key : marks.map((m) => m.key).join('>');
    final found = known[key];
    if (found != null) return found;
    final outer = marks.length == 1 ? line.base : run(line, marks.sublist(0, marks.length - 1));
    final ancestors = <LookElement>[line.element, ...marks.sublist(0, marks.length - 1)];
    final p = _cascade(outer.props, marks.last, LineContext.none, ancestors);
    final ground = p.background?.call(p.color);
    return known[key] = _run(p, outer, ground == null ? outer.backgrounds : <Color>[...outer.backgrounds, ground]);
  }

  /// The width of `text` set as a run of `look`: one line, as the page's ruler span measures it.
  double measure(List<(String text, RunLook look)> runs) {
    final painter = TextPainter(
      text: TextSpan(children: <InlineSpan>[for (final (text, look) in runs) TextSpan(text: text.replaceAll(' ', ' '), style: look.style)]),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
