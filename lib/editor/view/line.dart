/// One line of the editor, drawn: what CodeMirror's `LineView` is to the page (@codemirror/view, blockview.ts), and
/// the browser's inline layout under it.
///
/// A [RenderEditorLine] is given a [LineSpec] (what the line shows, [LineProjection], and how, [LineLook] and a
/// [RunLook] for each segment) and a width. It lays the words out, paints its own ground (a quote's bar, a block of
/// code's card and corners), the selection and the caret, and answers [RenderEditorLine.coordsAtPos] and
/// [RenderEditorLine.posAtCoords]. Inline widgets are its children.
///
/// How the page's line is reproduced, where Flutter's paragraph would not:
/// - **Line boxes are worked out here.** A paragraph of Flutter's rounds every line to a whole pixel, and stacks
///   the boxes its own way; the page's are 27.92 px, with each inline box's leading split as Blink splits it
///   (`look.dart`). So the paragraph is used for shaping, breaking and horizontal positions only: each of its lines
///   is painted, clipped to itself, at the baseline the page's line boxes put it on.
/// - **`white-space: break-spaces`** is [PaintText].
/// - **A list item's hang** (`padding-inline-start` with a negative `text-indent`, glyphLines.ts) is two
///   paragraphs: the marker at the gutter and the words on the hang, wrapping under their own first letter. The
///   marker is the text before `data-hang-chars`, which glyph_lines.dart says beside `--hang`.
/// - **`vertical-align: super` and `sub`** have no counterpart in a Flutter text style: a raised run keeps its
///   place in the paragraph, drawn clear, and is painted again above or below the baseline.
///
/// THE WORDS ARE DRAWN ONCE AND KEPT. Putting a paragraph on the canvas is the dear part of a line's paint (the
/// engine walks every run of it, and a wrapped paragraph is put there once for each of its lines), and a line is
/// painted whenever anything in its page is: at every frame of a scroll, at every turn of a caret some other line
/// draws, at every frame of an effect elsewhere. So what each visual line's words drew is kept as a picture
/// ([_Kept]) and put on the canvas again while the line is laid out as it was. Each visual line has a picture
/// of its own because each is put on a device pixel of its own (`_snap`): a picture of several would hold them
/// a fixed distance apart, where on the page they close up and open by a pixel as the page moves. Carried along
/// a scroll, a picture is moved by whole device pixels, which is where drawing the line afresh would put it; at
/// rest it is drawn afresh wherever it is not where it was drawn, so that a page standing still is, op for op,
/// what it always was ([_AtRest]). The grounds, the selection, the caret and what a mark's painter draws are
/// cheap and are drawn each time, as before.
///
/// Not here: bidirectional lines are laid out by the paragraph but the hang and the gutters are left-to-right, as
/// the web app's own layout is in practice; nothing of the keyboard, gestures or the IME (the input layer's).
library;

import 'dart:math' as math;
import 'dart:ui' as ui show LineMetrics, Picture, PictureRecorder, PlaceholderAlignment;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../perf/frame_log.dart' show Perf, ghostPerf;
import '../looks/look.dart';
import '../semantics/line_semantics.dart' show assembleLine, describeLine;
import 'line_breaks.dart' show blinkBreaks;
import 'projection.dart';
import 'widget.dart';

/// What a line shows and how: everything its layout depends on but its width.
class LineSpec {
  LineSpec({required this.projection, required this.look, required this.runs, this.hangChars = 0});

  /// Resolves the looks of `projection`'s line and runs through `look`.
  factory LineSpec.resolve(LineProjection projection, Look look, [LineContext context = LineContext.none]) {
    final element = LookElement(projection.className, projection.attributes);
    final line = look.line(element, LineContext(first: context.first, last: context.last, after: context.after, empty: projection.isEmpty));
    final runs = <RunLook>[
      for (final seg in projection.segments)
        seg.marks.isEmpty ? line.base : look.run(line, <LookElement>[for (final mark in seg.marks) LookElement(mark.attrs['class'], mark.attrs)]),
    ];
    final hang = line.hang > 0 ? int.tryParse(projection.attributes['data-hang-chars'] ?? '') ?? 0 : 0;
    return LineSpec(projection: projection, look: line, runs: runs, hangChars: hang);
  }

  final LineProjection projection;
  final LineLook look;

  /// The look of each of the projection's segments.
  final List<RunLook> runs;

  /// How much of the line's start is its marker, drawn at the gutter: document units from the line's start. Zero
  /// for a line with no hang.
  final int hangChars;

  /// Whether `other` lays out and paints the same.
  bool same(LineSpec other) {
    if (identical(this, other)) return true;
    if (!identical(look, other.look) || hangChars != other.hangChars || runs.length != other.runs.length) return false;
    for (var i = 0; i < runs.length; i++) {
      if (!identical(runs[i], other.runs[i])) return false;
    }
    return projection.same(other.projection);
  }
}

/// How the selection and the caret are painted: the hook the input layer and a theme draw through. The default is
/// glyphTheme.ts's: solid ink behind the words and the words in paper, and a caret in the accent.
class EditorSelectionPainter {
  const EditorSelectionPainter();

  /// Paints the ground of a selection on one line. `rects` are in the canvas's coordinates.
  void paintSelection(Canvas canvas, List<Rect> rects, Color ink) {
    final paint = Paint()..color = ink;
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
  }

  /// Paints a caret. `caret` is the rectangle `coordsAtPos` answers, with no width.
  void paintCaret(Canvas canvas, Rect caret, Color color, double opacity) {
    if (opacity <= 0) return;
    // A browser's own caret is one CSS pixel wide (2 to 3 device pixels on the phone, measured beside the page, where
    // two logical pixels here were 5).
    canvas.drawRect(Rect.fromLTWH(caret.left - 0.5, caret.top, 1, caret.height), Paint()..color = color.withValues(alpha: color.a * opacity));
  }
}

/// The part of the editor's selection a line draws. Offsets are document units from the line's start.
class LineSelection {
  const LineSelection({
    this.ranges = const <(int, int)>[],
    this.carets = const <(int, int)>[],
    this.pastEnd = false,
    this.ink = const Color(0xFF000000),
    this.paper = const Color(0xFFFFFFFF),
    this.caretColor = const Color(0xFF000000),
    this.startHandle,
    this.endHandle,
  });

  /// The selected stretches on this line.
  final List<(int, int)> ranges;

  /// Carets to draw: a position and which side it leans (`assoc`).
  final List<(int, int)> carets;

  /// Whether a selection runs on past the line's end, over its break.
  final bool pastEnd;

  /// The ground and the words of selected text.
  final Color ink;
  final Color paper;
  final Color caretColor;

  /// Where the selection's start and end handles hang, when they are on this line.
  final int? startHandle;
  final int? endHandle;

  bool get isEmpty => ranges.isEmpty && carets.isEmpty && startHandle == null && endHandle == null;

  bool same(LineSelection other) {
    if (pastEnd != other.pastEnd || ink != other.ink || paper != other.paper || caretColor != other.caretColor) return false;
    if (startHandle != other.startHandle || endHandle != other.endHandle) return false;
    if (ranges.length != other.ranges.length || carets.length != other.carets.length) return false;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges[i] != other.ranges[i]) return false;
    }
    for (var i = 0; i < carets.length; i++) {
      if (carets[i] != other.carets[i]) return false;
    }
    return true;
  }

  static const LineSelection none = LineSelection();
}

/// What a line's render object tells whoever holds the lines: the view, which finds a line by its place in the
/// document.
abstract class EditorLineHost {
  void lineAttached(RenderEditorLine line);
  void lineDetached(RenderEditorLine line);

  /// The links the selection's handles follow.
  LayerLink get startHandleLink;
  LayerLink get endHandleLink;

  /// How visible the caret is now (a blink), and who paints it.
  ValueNotifier<double> get caretOpacity;
  EditorSelectionPainter get selectionPainter;
}

/// A position found from a point: the document offset from the line's start, which side of a wrap or a widget it
/// is on, and whether the point was on the line's own box.
class LineHit {
  const LineHit(this.pos, this.assoc, {this.inside = true});

  final int pos;
  final int assoc;
  final bool inside;
}

/// One visual line of a wrapped line.
class VisualLine {
  VisualLine({required this.start, required this.end, required this.top, required this.above, required this.below, required this.ascent, required this.descent, required this.fTop, required this.fBottom, required this.fBaseline});

  /// Its stretch of the words' paint text.
  final int start;
  final int end;

  /// The line box: its top in the render object's box, and how far it reaches above and below its baseline.
  final double top;
  final double above;
  final double below;

  /// The tallest content area on the line above its baseline: a face's ascent, which a tight leading leaves
  /// standing over the line box's top. A point there is on this line, as it is on the page.
  final double ascent;

  /// And below it: the deepest descent.
  final double descent;

  /// The top and the foot of the words' own boxes, which is what a point is nearest to or on.
  double get contentTop => baseline - ascent;
  double get contentBottom => baseline + descent;

  /// The same line in the paragraph's own coordinates.
  final double fTop;
  final double fBottom;
  final double fBaseline;

  double get baseline => top + above;
  double get bottom => top + above + below;
}

class EditorInlineParentData extends ContainerBoxParentData<RenderBox> {}

/// The line widget: a [LineSpec], the selection on it, and its inline widgets as children, in the order of the
/// projection's widget segments.
class EditorLine extends MultiChildRenderObjectWidget {
  EditorLine({super.key, required this.spec, required this.from, this.selection = LineSelection.none, this.host})
    : super(
        children: <Widget>[
          for (var i = 0; i < spec.projection.segments.length; i++)
            if (spec.projection.segments[i].kind == SegmentKind.widget) EditorRunScope(look: spec.runs[i], line: spec.look, child: InlineWidgetHost(widget: spec.projection.segments[i].widget!)),
        ],
      );

  final LineSpec spec;

  /// Where the line starts in the document.
  final int from;
  final LineSelection selection;
  final EditorLineHost? host;

  @override
  RenderEditorLine createRenderObject(BuildContext context) => RenderEditorLine(spec: spec, from: from, selection: selection, host: host);

  @override
  void updateRenderObject(BuildContext context, RenderEditorLine renderObject) {
    renderObject
      ..host = host
      ..from = from
      ..spec = spec
      ..selection = selection;
  }
}

/// What an inline widget stands in: the look of the run round it (the size and ink a chip is drawn against, as an
/// `em` and `currentColor` are on the page) and of its line. `EditorRunScope.of(context)` in an `EditorWidget`'s
/// `build`.
class EditorRunScope extends InheritedWidget {
  const EditorRunScope({super.key, required this.look, required this.line, required super.child});

  /// The run the widget is in: the marks round it, or the line's own.
  final RunLook look;
  final LineLook line;

  static EditorRunScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EditorRunScope>();

  @override
  bool updateShouldNotify(EditorRunScope oldWidget) => !identical(oldWidget.look, look) || !identical(oldWidget.line, line);
}

/// Builds an [EditorWidget] once, keeps what it built while the description compares equal, and tells it when it
/// leaves: `toDOM`, `eq` and `destroy`.
class InlineWidgetHost extends StatefulWidget {
  const InlineWidgetHost({super.key, required this.widget});

  final EditorWidget widget;

  @override
  State<InlineWidgetHost> createState() => _InlineWidgetHostState();
}

class _InlineWidgetHostState extends State<InlineWidgetHost> {
  Widget? _built;
  EditorWidget? _from;

  @override
  void didUpdateWidget(InlineWidgetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_from != null && !_from!.compare(widget.widget)) {
      _from!.destroy();
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // What the widget read from above it (the tokens, the view) may have changed.
    _built = null;
  }

  @override
  void dispose() {
    _from?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_built == null) {
      _from = widget.widget;
      _built = widget.widget.build(context);
    }
    return _built!;
  }
}

/// What a visual line's words drew, and where on its canvas: the canvas's own `x` of the line and the device
/// pixel its top fell on.
class _Kept {
  _Kept(this.picture, this.x, this.y);

  final ui.Picture picture;
  final double x;
  final double y;
}

/// The lines a scroll carried are drawn afresh when it comes to rest. A picture moved by whole device pixels
/// stands where drawing its line afresh would stand it, but it is not the same instruction to the engine (a
/// place added to a move, where it was one place), and the page at rest is held to being exactly what it always
/// was: so the scroll's ending paints its view once more, and each line that is not where its picture was drawn
/// draws itself there.
class _AtRest {
  _AtRest(this.position) {
    position.isScrollingNotifier.addListener(_heard);
  }

  static final Expando<_AtRest> _of = Expando<_AtRest>('lines carried by a scroll');

  static void owe(ScrollPosition position, RenderObject view) => (_of[position] ??= _AtRest(position))._owed.add(view);

  final ScrollPosition position;
  final Set<RenderObject> _owed = <RenderObject>{};

  void _heard() {
    if (position.isScrollingNotifier.value || _owed.isEmpty) return;
    for (final view in _owed) {
      if (view.attached) view.markNeedsPaint();
    }
    _owed.clear();
  }
}

/// The line's render object.
class RenderEditorLine extends RenderBox with ContainerRenderObjectMixin<RenderBox, EditorInlineParentData>, RenderBoxContainerDefaultsMixin<RenderBox, EditorInlineParentData> {
  RenderEditorLine({required LineSpec spec, this.from = 0, LineSelection selection = LineSelection.none, EditorLineHost? host})
    : _spec = spec,
      _selection = selection,
      _host = host;

  /// How many times any line was laid out, for a test to count.
  static int layouts = 0;

  /// How many paragraphs of a line's words were made and laid out, for a test to count: one for a line, whether
  /// its height was asked for before it was laid out or not.
  static int paragraphs = 0;

  /// How many times a visual line's words were put on a canvas afresh, and how many times from the picture kept of
  /// them (and of those, how many times moved from where the picture was drawn: carried by a scroll), for a test
  /// to count.
  static int wordsDrawn = 0;
  static int wordsKept = 0;
  static int wordsCarried = 0;

  /// Whether the words are kept as pictures (the header's note). Off, every paint draws them afresh, as the line
  /// did before it kept anything: for a test to hold the two drawings against each other, and for a walk to be
  /// measured both ways from one tree (`--dart-define=GHOST_WORDS_AFRESH=true`).
  static bool keepsWords = !const bool.fromEnvironment('GHOST_WORDS_AFRESH');

  LineSpec _spec;
  LineSpec get spec => _spec;
  set spec(LineSpec value) {
    if (identical(value, _spec)) return;
    final same = value.same(_spec);
    _spec = value;
    if (!same) {
      _disposePainters();
      markNeedsLayout();
    }
  }

  /// Where the line starts in the document.
  int from;

  /// Where the line ends in the document.
  int get to => from + _spec.projection.length;

  LineSelection _selection;
  LineSelection get selection => _selection;
  set selection(LineSelection value) {
    if (value.same(_selection)) return;
    _selection = value;
    _selected?.dispose();
    _selected = null;
    _hearBlink();
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
    // What a screen reader was told of the caret is old; nothing at all while none is listening.
    markNeedsSemanticsUpdate();
  }

  EditorLineHost? _host;
  EditorLineHost? get host => _host;
  set host(EditorLineHost? value) {
    if (identical(value, _host)) return;
    if (attached) {
      _host?.lineDetached(this);
      _deafToBlink();
    }
    _host = value;
    if (attached) {
      value?.lineAttached(this);
      _hearBlink();
    }
  }

  /// The caret's blink is heard by the line the caret is on and by no other: every line on screen used to be
  /// painted again each time it turned, twice a second, for a caret one of them draws.
  ValueNotifier<double>? _blink;

  void _hearBlink() {
    final wanted = attached && _selection.carets.isNotEmpty ? _host?.caretOpacity : null;
    if (identical(wanted, _blink)) return;
    _blink?.removeListener(markNeedsPaint);
    _blink = wanted;
    wanted?.addListener(markNeedsPaint);
  }

  void _deafToBlink() {
    _blink?.removeListener(markNeedsPaint);
    _blink = null;
  }

  // -- what layout made -------------------------------------------------------------------------------------------
  /// The paint text [_words] was laid out from: the spec's own ([_plain]), or that with the visual lines the
  /// page would have begun before a word too long for its line ([_lateBreak]).
  PaintText? _paint;

  /// The spec's paint text, with no line begun by hand.
  PaintText? _plain;
  TextPainter? _words;
  TextPainter? _marker;
  TextPainter? _selected;
  int _split = 0;

  /// One when the words' paragraph starts with a spacer: a marker drawn wider than the hang it was measured for
  /// (figures of one width, in a face whose own are not) pushes the first line's words along by the difference, as
  /// on the page, and the spacer is that difference.
  int _lead = 0;

  /// What a paint offset loses to become an offset in the words' paragraph.
  int get _base => _split - _lead;
  double _contentLeft = 0;
  double _contentWidth = 0;
  List<VisualLine> _lines = const <VisualLine>[];
  List<_Raised> _raised = const <_Raised>[];
  double _laidOutWidth = -1;
  PlaceholderDimensions? _leadSize;

  /// Whether [_plain] was made from the spec in force: it is made once for a spec, not at every layout and every
  /// asking of a height.
  bool _paintFits = false;

  /// The words' paragraph a height was asked with before the line was laid out (a column of lines is measured for
  /// its card's box, then laid out), the content width it was made at and how many lines it came to: taken by the
  /// layout that follows, which made the same paragraph a second time.
  TextPainter? _dry;
  PaintText? _dryPaint;
  List<int>? _dryEnds;
  double _dryWidth = -1;
  int _dryCount = 1;

  PaintText _paintText() {
    final had = _plain;
    if (had != null && _paintFits) return had;
    _paintFits = true;
    return _plain = PaintText(_spec.projection.display, tabSize: _spec.look.tabSize, breaks: _spec.projection.hiddenBreaks);
  }

  /// How many lines may be begun by hand in one line of the note: each is another paragraph laid out.
  static const int _mostLate = 24;

  /// Whether the page may end a visual line before paint offset `at` of `text`: after a zero-width space (which
  /// every space is followed by, and every pair the page may part) or a line feed, between two characters the
  /// page's own table lets a line part, or beside a character the table does not know. Never inside a word.
  static bool _mayBreak(String text, int at) {
    if (at <= 0 || at >= text.length) return true;
    final before = text.codeUnitAt(at - 1), after = text.codeUnitAt(at);
    if (before == 0x0a || before == 0x200b) return true;
    if (before == 0x2060 || after == 0x2060 || before == 0xa0 || after == 0x200b) return false;
    final known = blinkBreaks(at > 1 ? text.codeUnitAt(at - 2) : -1, before, after);
    return known ?? true;
  }

  /// Where the page would have begun a visual line and `words` did not, as a display offset; null where every
  /// line of `words` ends where a line may.
  ///
  /// The lines wrap `overflow-wrap: anywhere`: a word that does not fit in what is left of its line goes to the
  /// next line whole, and only a word longer than a whole line is cut where the line ends. A paragraph of
  /// Flutter's cuts such a word where it stands, on the line it began on (a long address after "See", a long
  /// string after `const s =`). So a visual line that ends inside a word, and had a place to end before that
  /// word, is where the two part: the line is begun there by hand ([PaintText.forced]) and laid out again.
  /// `ends` are the ends of the paragraph's lines but the last, as offsets in it; `base` is what a paint offset
  /// loses to become one.
  static int? _lateBreak(PaintText paint, List<int> ends, int base) {
    final text = paint.text;
    var start = 0;
    for (final end in ends) {
      final at = end + base;
      if (!_mayBreak(text, at)) {
        for (var back = at - 1; back > start + base; back--) {
          if (!_mayBreak(text, back)) continue;
          final display = paint.toDisplay(back);
          // Not where a line is begun already, nor before everything.
          if (display > 0 && !paint.forced.contains(display)) return display;
          break;
        }
      }
      start = end;
    }
    return null;
  }

  /// The ends of the lines of `words` but the last, as offsets in the paragraph. `count` is how many lines it has;
  /// `base` is what a paint offset of `paint` loses to become one.
  static List<int> _lineEnds(TextPainter words, int count, int length, PaintText paint, int base) {
    if (count < 2) return const <int>[];
    final ends = <int>[];
    var start = 0;
    for (var i = 0; i < count - 1; i++) {
      var end = words.getLineBoundary(TextPosition(offset: start)).end;
      // A line feed that begins the next line by hand is the last thing on its own: the paragraph answers the
      // line without it.
      if (paint.feedAt(end + base)) end += 1;
      if (end <= start) end = math.min(length, start + 1);
      ends.add(end);
      start = end;
    }
    return ends;
  }

  static const WidgetSpan _spacer = WidgetSpan(child: SizedBox.shrink(), alignment: ui.PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic);

  /// The visual lines of the last layout.
  List<VisualLine> get visualLines => _lines;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EditorInlineParentData) child.parentData = EditorInlineParentData();
  }

  void _fontsChanged() {
    _disposePainters();
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _host?.lineAttached(this);
    _hearBlink();
    // A face that arrives later is a different layout.
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void detach() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _host?.lineDetached(this);
    _deafToBlink();
    _scrollerKnown = false;
    _scroller = null;
    super.detach();
  }

  @override
  void dispose() {
    _disposePainters();
    _startHandle.layer = null;
    _endHandle.layer = null;
    super.dispose();
  }

  void _disposePainters() {
    _words?.dispose();
    _marker?.dispose();
    _selected?.dispose();
    for (final raised in _raised) {
      raised.painter.dispose();
    }
    _words = _marker = _selected = null;
    _raised = const <_Raised>[];
    _forget();
    _laidOutWidth = -1;
    _dry?.dispose();
    _dry = null;
    _dryPaint = null;
    _dryEnds = null;
    _dryWidth = -1;
    _paintFits = false;
    _paint = null;
  }

  // -- layout ------------------------------------------------------------------------------------------------------

  /// The spans of the paint text from `from` to `to`. `ink` sets every run in one colour (selected words).
  List<InlineSpan> _spans(PaintText paint, int from, int to, {Color? ink, bool placeholders = true}) {
    final proj = _spec.projection;
    final spans = <InlineSpan>[];
    for (var i = 0; i < proj.segments.length; i++) {
      final seg = proj.segments[i];
      if (seg.kind == SegmentKind.hidden) continue;
      final a = math.max(from, paint.toPaint(seg.displayFrom)), b = math.min(to, paint.toPaint(seg.displayTo));
      if (b <= a) continue;
      final look = _spec.runs[i];
      if (seg.kind == SegmentKind.widget) {
        if (placeholders) {
          spans.add(const WidgetSpan(child: SizedBox.shrink(), alignment: ui.PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic));
        } else {
          spans.add(TextSpan(text: '​', style: look.style));
        }
        continue;
      }
      var style = look.style;
      if (look.shift != 0 && ink == null) {
        style = style.copyWith(color: const Color(0x00000000), decorationColor: const Color(0x00000000));
      } else if (ink != null) {
        style = style.copyWith(color: look.shift != 0 ? const Color(0x00000000) : ink, decorationColor: ink);
      } else if (look.painter != null && !look.painter!.drawsWords) {
        style = style.copyWith(color: const Color(0x00000000), decorationColor: const Color(0x00000000));
      }
      final text = paint.text.substring(a, b);
      if ((style.letterSpacing ?? 0) != 0 && _zeroWidth.hasMatch(text)) {
        // A zero-width space is a glyph to the paragraph, and would take a letter's spacing: it is set without.
        final bare = style.copyWith(letterSpacing: 0);
        var from = 0;
        for (final found in _zeroWidth.allMatches(text)) {
          if (found.start > from) spans.add(TextSpan(text: text.substring(from, found.start), style: style));
          spans.add(TextSpan(text: found.group(0), style: bare));
          from = found.end;
        }
        if (from < text.length) spans.add(TextSpan(text: text.substring(from), style: style));
      } else {
        spans.add(TextSpan(text: text, style: style));
      }
    }
    return spans;
  }

  static final RegExp _zeroWidth = RegExp('[\u200B\u2060]+');

  double _width(BoxConstraints constraints) => constraints.hasBoundedWidth ? constraints.maxWidth : constraints.constrainWidth(0);

  @override
  void performLayout() {
    layouts += 1;
    if (ghostPerf) Perf.count('editor.lines.laidOut');
    // What was drawn was drawn for the layout before.
    _forget();
    final look = _spec.look, proj = _spec.projection;
    final width = _width(constraints);
    _contentLeft = look.marginStart + look.borderStart + look.paddingStart;
    _contentWidth = math.max(0, width - look.insetX);
    // The text the words were laid out from at this width, if they were; the spec's own otherwise.
    var paint = _words != null && _laidOutWidth == _contentWidth && _paint != null ? _paint! : _paintText();

    // The inline widgets first: the paragraph needs their sizes.
    final sizes = <PlaceholderDimensions>[];
    var widgetAt = <int>[];
    var child = firstChild;
    for (final seg in proj.segments) {
      if (seg.kind != SegmentKind.widget) continue;
      if (child == null) {
        sizes.add(PlaceholderDimensions.empty);
      } else {
        child.layout(BoxConstraints(maxWidth: _contentWidth), parentUsesSize: true);
        final baseline = child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? child.size.height;
        sizes.add(PlaceholderDimensions(size: child.size, alignment: ui.PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: baseline));
        child = childAfter(child);
      }
      widgetAt.add(paint.toPaint(seg.displayFrom));
    }

    for (final raised in _raised) {
      raised.painter.dispose();
    }
    _raised = const <_Raised>[];
    List<int>? ends;
    List<ui.LineMetrics>? measured;
    if (_laidOutWidth != _contentWidth || _words == null || sizes.isNotEmpty) {
      if (paint.forced.isNotEmpty) {
        // Another width, or other widgets: where a line is begun by hand is found again.
        paint = _paintText();
        widgetAt = <int>[
          for (final seg in proj.segments)
            if (seg.kind == SegmentKind.widget) paint.toPaint(seg.displayFrom),
        ];
      }
      _words?.dispose();
      _marker?.dispose();
      _selected?.dispose();
      _selected = null;
      _split = look.hang > 0 && _spec.hangChars > 0 ? paint.toPaint(proj.toDisplay(_spec.hangChars, -1)) : 0;
      final paintLength = paint.text.length;
      if (_split > 0) {
        final marker = _marker = TextPainter(text: TextSpan(children: _spans(paint, 0, _split)), textDirection: TextDirection.ltr);
        marker.setPlaceholderDimensions(<PlaceholderDimensions>[
          for (var i = 0; i < sizes.length; i++)
            if (widgetAt[i] < _split) sizes[i],
        ]);
        marker.layout();
      } else {
        _marker = null;
      }
      final over = _marker == null ? 0.0 : layoutUnitCeil(_marker!.width) - look.hang;
      _lead = over > 1 / 64 && paintLength > _split ? 1 : 0;
      _leadSize = _lead == 0 ? null : PlaceholderDimensions(size: Size(over, 0), alignment: ui.PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 0);
      final dry = _dry;
      if (dry != null && _dryWidth == _contentWidth && _lead == 0 && sizes.isEmpty) {
        // The paragraph a height was asked with, at this width: the same words under the same looks, with no
        // widget among them and no spacer before them, laid out in the same room.
        _words = dry;
        _dry = null;
        paint = _dryPaint ?? paint;
        ends = _dryEnds;
      } else {
        TextPainter make(PaintText paint) {
          assert(_counted());
          if (ghostPerf) Perf.count('editor.lines.paragraphs');
          final words = TextPainter(text: TextSpan(children: <InlineSpan>[if (_lead > 0) _spacer, ..._spans(paint, _split, paint.text.length)]), textDirection: TextDirection.ltr);
          words.setPlaceholderDimensions(<PlaceholderDimensions>[
            ?_leadSize,
            for (var i = 0; i < sizes.length; i++)
              if (widgetAt[i] >= _split) sizes[i],
          ]);
          // A sixty-fourth of room: a line that fits to the unit on the page fits here.
          return words..layout(maxWidth: math.max(1, _contentWidth + 1 / 64));
        }

        var words = make(paint);
        // A word too long for its line goes to the next line before it is cut, as on the page ([_lateBreak]).
        // Nothing more is done for a paragraph of one line, and one look at each line's end for any other.
        for (var pass = 0; proj.display.isNotEmpty; pass++) {
          measured = words.computeLineMetrics();
          ends = _lineEnds(words, measured.length, paint.text.length - _base, paint, _base);
          final late = pass < _mostLate ? _lateBreak(paint, ends, _base) : null;
          if (late == null) break;
          words.dispose();
          paint = PaintText(proj.display, tabSize: look.tabSize, breaks: proj.hiddenBreaks, forced: <int>{...paint.forced, late});
          words = make(paint);
        }
        _words = words;
      }
      _paint = paint;
      if (paint.forced.isNotEmpty) {
        // Every widget after a line begun by hand is one place further on in the text.
        widgetAt = <int>[
          for (final seg in proj.segments)
            if (seg.kind == SegmentKind.widget) paint.toPaint(seg.displayFrom),
        ];
      }
      _laidOutWidth = _contentWidth;
    }
    // One asked with at another width, or for a line with a widget on it, is no use to anyone now.
    _dry?.dispose();
    _dry = null;
    _dryPaint = null;
    _dryEnds = null;
    final words = _words!;

    // The paragraph's lines, and the page's line box for each.
    final metrics = proj.display.isEmpty ? const <ui.LineMetrics>[] : (measured ?? words.computeLineMetrics());
    final length = paint.text.length - _base;
    final lines = <VisualLine>[];
    var y = look.borderTop + look.paddingTop;
    var start = 0;
    var fTop = 0.0;
    final count = math.max(1, metrics.length);
    ends ??= _lineEnds(words, count, length, paint, _base);
    for (var i = 0; i < count; i++) {
      final end = i < count - 1 ? ends[i] : length;
      var above = look.base.above, below = look.base.below, ascent = 0.0, descent = 0.0;
      void reach(double a, double b) {
        if (a > above) above = a;
        if (b > below) below = b;
      }

      var widget = 0;
      for (var s = 0; s < proj.segments.length; s++) {
        final seg = proj.segments[s];
        if (seg.kind == SegmentKind.hidden) continue;
        final a = paint.toPaint(seg.displayFrom) - _base, b = paint.toPaint(seg.displayTo) - _base;
        // What is all in the marker is on the first line; the rest is on the lines it reaches.
        final onLine = b <= _lead ? i == 0 : (b > start && a < end);
        if (seg.kind == SegmentKind.widget) {
          if (onLine) {
            final size = sizes[widget];
            reach(size.baselineOffset ?? size.size.height, size.size.height - (size.baselineOffset ?? size.size.height));
            reach(_spec.runs[s].above, _spec.runs[s].below);
          }
          widget += 1;
        } else if (onLine) {
          reach(_spec.runs[s].above, _spec.runs[s].below);
          if (_spec.runs[s].ascent + _spec.runs[s].shift > ascent) ascent = _spec.runs[s].ascent + _spec.runs[s].shift;
          if (_spec.runs[s].descent - _spec.runs[s].shift > descent) descent = _spec.runs[s].descent - _spec.runs[s].shift;
        }
      }
      // A line with nothing on it is the line's own face.
      if (ascent == 0 && descent == 0) {
        ascent = look.base.ascent;
        descent = look.base.descent;
      }
      final m = i < metrics.length ? metrics[i] : null;
      final fHeight = m?.height ?? 0;
      lines.add(VisualLine(start: start, end: end, top: y, above: above, below: below, ascent: ascent, descent: descent, fTop: fTop, fBottom: fTop + fHeight, fBaseline: m?.baseline ?? 0));
      y += above + below;
      fTop += fHeight;
      start = end;
    }
    _lines = lines;
    size = constraints.constrain(Size(width, y + look.paddingBottom + look.borderBottom));

    // Where the inline widgets sit.
    child = firstChild;
    var markerBox = 0, wordsBox = _lead;
    final markerBoxes = _marker?.inlinePlaceholderBoxes ?? const <TextBox>[], wordsBoxes = words.inlinePlaceholderBoxes ?? const <TextBox>[];
    for (var i = 0; i < sizes.length && child != null; i++) {
      final data = child.parentData! as EditorInlineParentData;
      final baselineOffset = sizes[i].baselineOffset ?? child.size.height;
      if (widgetAt[i] < _split) {
        final box = markerBox < markerBoxes.length ? markerBoxes[markerBox] : null;
        markerBox += 1;
        data.offset = Offset(_contentLeft - look.hang + (box?.left ?? 0), lines.first.baseline - baselineOffset);
      } else {
        final box = wordsBox < wordsBoxes.length ? wordsBoxes[wordsBox] : null;
        wordsBox += 1;
        final line = _lineOfPaint(widgetAt[i] - _base, 1);
        data.offset = Offset(_contentLeft + (box?.left ?? 0), line.baseline - baselineOffset);
      }
      child = childAfter(child);
    }

    // Raised and lowered runs, to be painted off the baseline.
    final raised = <_Raised>[];
    for (var s = 0; s < proj.segments.length; s++) {
      final seg = proj.segments[s], run = _spec.runs[s];
      if (seg.kind != SegmentKind.text || run.shift == 0) continue;
      final a = paint.toPaint(seg.displayFrom), b = paint.toPaint(seg.displayTo);
      for (final line in lines) {
        final from = math.max(a - _base, line.start), to = math.min(b - _base, line.end);
        if (to <= from) continue;
        final painter = TextPainter(text: TextSpan(text: paint.text.substring(from + _base, to + _base), style: run.style), textDirection: TextDirection.ltr)..layout();
        final x = words.getOffsetForCaret(TextPosition(offset: from), Rect.zero).dx;
        raised.add(_Raised(painter, Offset(_contentLeft + x, line.baseline - run.shift - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic))));
      }
    }
    _raised = raised;
  }

  VisualLine _lineOfPaint(int offset, int side) {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (offset < line.end || i == _lines.length - 1) return line;
      if (offset == line.end && side < 0) return line;
    }
    return _lines.last;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    final look = _spec.look;
    final painter = TextPainter(text: TextSpan(children: _spans(_paintText(), 0, 1 << 30, placeholders: false)), textDirection: TextDirection.ltr)..layout();
    final width = painter.width + look.insetX;
    painter.dispose();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _dryHeight(width);

  static bool _counted() {
    paragraphs += 1;
    return true;
  }

  double _dryHeight(double width) {
    // The words alone: an inline widget's height is not asked for outside a real layout.
    final look = _spec.look, proj = _spec.projection;
    final content = math.max(0.0, width - look.insetX);
    var plain = true;
    for (final segment in proj.segments) {
      if (segment.kind == SegmentKind.widget) {
        plain = false;
        break;
      }
    }
    int count;
    if (plain && _words != null && _laidOutWidth == content && _lead == 0 && _lines.isNotEmpty) {
      // Laid out at this width already: the words' paragraph is the one that would be made here.
      count = _lines.length;
    } else if (_dry != null && _dryWidth == content) {
      count = _dryCount;
    } else {
      var paint = _paintText();
      final split = look.hang > 0 && _spec.hangChars > 0 ? paint.toPaint(proj.toDisplay(_spec.hangChars, -1)) : 0;
      TextPainter make(PaintText paint) {
        assert(_counted());
        if (ghostPerf) Perf.count('editor.lines.paragraphs');
        return TextPainter(text: TextSpan(children: _spans(paint, split, paint.text.length, placeholders: false)), textDirection: TextDirection.ltr)
          ..layout(maxWidth: math.max(1, width - look.insetX + 1 / 64));
      }

      var painter = make(paint);
      count = 1;
      List<int>? ends;
      // As a layout makes it: a word too long for its line goes to the next before it is cut ([_lateBreak]).
      for (var pass = 0; proj.display.isNotEmpty; pass++) {
        count = math.max(1, painter.computeLineMetrics().length);
        ends = _lineEnds(painter, count, paint.text.length - split, paint, split);
        final late = pass < _mostLate ? _lateBreak(paint, ends, split) : null;
        if (late == null) break;
        painter.dispose();
        paint = PaintText(proj.display, tabSize: look.tabSize, breaks: proj.hiddenBreaks, forced: <int>{...paint.forced, late});
        painter = make(paint);
      }
      if (plain) {
        // Kept for the layout that follows a height asked for (`performLayout` takes it).
        _dry?.dispose();
        _dry = painter;
        _dryPaint = paint;
        _dryEnds = ends;
        _dryWidth = content;
        _dryCount = count;
      } else {
        painter.dispose();
      }
    }
    var above = look.base.above, below = look.base.below;
    for (var s = 0; s < proj.segments.length; s++) {
      if (proj.segments[s].kind == SegmentKind.hidden) continue;
      if (_spec.runs[s].above > above) above = _spec.runs[s].above;
      if (_spec.runs[s].below > below) below = _spec.runs[s].below;
    }
    return look.borderTop + look.paddingTop + count * (above + below) + look.paddingBottom + look.borderBottom;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _width(constraints);
    return constraints.constrain(Size(width, _dryHeight(width)));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _lines.isEmpty ? null : _lines.first.baseline;

  // -- positions ---------------------------------------------------------------------------------------------------

  /// Where document offset `pos` (from the line's start) is, in this box: a rectangle with no width, from the top
  /// to the bottom of the text there. `side` picks the end of one visual line (below zero) or the start of the
  /// next where a position is both. Null before the line has been laid out.
  Rect? coordsAtPos(int pos, [int side = 1]) {
    final paint = _paint, words = _words;
    if (paint == null || words == null || _lines.isEmpty) return null;
    final proj = _spec.projection;
    pos = pos.clamp(0, proj.length);
    final seg = proj.segmentAt(pos, side);
    // A hidden range and a widget are in the line's own face; text is in its run's.
    var look = _spec.look.base;
    if (seg != null && seg.kind == SegmentKind.text) look = _spec.runs[proj.segments.indexOf(seg)];
    final offset = paint.toPaint(proj.toDisplay(pos, side));
    // What is hidden has no width and stays at the end of the line before a wrap, where the page's empty element
    // for it is.
    final lineSide = seg != null && seg.kind == SegmentKind.hidden ? -1 : side;
    if (seg != null && seg.kind == SegmentKind.widget && seg.widget != null) {
      final box = _childFor(seg);
      if (box != null) {
        final own = seg.widget!.coordsAt(box, from + pos, side);
        if (own != null) return own.shift((box.parentData! as EditorInlineParentData).offset);
      }
    }
    double x;
    VisualLine line;
    final marker = _marker;
    if (marker != null && offset < _split) {
      line = _lines.first;
      x = _contentLeft - _spec.look.hang + marker.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dx;
    } else {
      final rel = offset - _base;
      line = _lineOfPaint(rel, lineSide);
      if (proj.display.isEmpty || paint.text.length == _split) {
        x = _contentLeft;
      } else {
        final atEnd = rel >= line.end && !identical(line, _lines.last) || (rel == line.end && lineSide < 0);
        // Where a line was begun by hand (a line feed, `PaintText.forced`), the end of the line above is the
        // place before the feed: the paragraph answers the start of the next line for the place after one,
        // whichever way it is asked.
        final fed = atEnd && rel > 0 && paint.feedAt(offset - 1);
        final caret = words.getOffsetForCaret(TextPosition(offset: fed ? rel - 1 : rel, affinity: atEnd && !fed ? TextAffinity.upstream : TextAffinity.downstream), Rect.zero);
        x = _contentLeft + caret.dx;
        // A paragraph of Flutter's sets half a letter's spacing either side of it where the page sets it all after:
        // past a spaced letter the place between two letters is half the spacing further on.
        if (rel > line.start) {
          final before = proj.segmentAt(pos, -1);
          if (before != null && before.kind == SegmentKind.text && before.from < pos) x -= _spec.runs[proj.segments.indexOf(before)].props.tracking / 2;
        }
      }
    }
    final baseline = line.baseline - look.shift;
    return Rect.fromLTRB(x, baseline - look.ascent, x, baseline + look.descent);
  }

  RenderBox? _childFor(Segment target) {
    var child = firstChild;
    for (final seg in _spec.projection.segments) {
      if (seg.kind != SegmentKind.widget) continue;
      if (identical(seg, target)) return child;
      if (child == null) return null;
      child = childAfter(child);
    }
    return null;
  }

  /// The position nearest a point of this box, as a document offset from the line's start. Null when `precise`
  /// and the point is outside the box, or before layout.
  int? posAtCoords(Offset local, {bool precise = true}) => hitAt(local, precise: precise)?.pos;

  /// As [posAtCoords], with the side of a wrap the point was on.
  LineHit? hitAt(Offset local, {bool precise = false}) {
    final paint = _paint, words = _words;
    if (paint == null || words == null || _lines.isEmpty) return null;
    final inside = local.dy >= 0 && local.dy < size.height && local.dx >= 0 && local.dx <= size.width;
    if (precise && !inside) return null;
    final proj = _spec.projection;
    // The last visual line that has started by the point: where a tight leading lets one line's letters stand over
    // the foot of the line above, the page gives the point to the lower line.
    // Which visual line a point is on is decided by the words' own boxes, as the page decides it: between two
    // lines it is the nearer one's, and where a tight leading lets one line's letters stand over the foot of the
    // line above, the lower line's from where its letters start.
    var index = 0;
    for (var i = 1; i < _lines.length; i++) {
      final over = _lines[i - 1].contentBottom, under = _lines[i].contentTop;
      if (local.dy + 0.001 >= (under <= over ? under : (over + under) / 2)) index = i;
    }
    final line = _lines[index];
    final length = paint.text.length - _base;
    int offset;
    var assoc = 1;
    var onward = false;
    final marker = _marker;
    if (proj.display.isEmpty) {
      offset = 0;
    } else if (marker != null && index == 0 && local.dx < _contentLeft) {
      offset = marker.getPositionForOffset(Offset(local.dx - (_contentLeft - _spec.look.hang), marker.height / 2)).offset.clamp(0, _split);
    } else if (paint.text.length == _split) {
      offset = _split;
    } else {
      final middle = (line.fTop + line.fBottom) / 2;
      var at = words.getPositionForOffset(Offset(local.dx - _contentLeft, middle));
      // Spaced letters stand half their spacing off where the page has them (see `coordsAtPos`): the point is
      // moved as much before it is asked about again.
      final near = proj.segmentAt(proj.toDoc(paint.toDisplay(math.min(math.max(at.offset, _lead), length) + _base), -1), 1);
      final spacing = near != null && near.kind == SegmentKind.text ? _spec.runs[proj.segments.indexOf(near)].props.tracking : 0.0;
      if (spacing != 0) at = words.getPositionForOffset(Offset(local.dx - _contentLeft + spacing / 2, middle));
      final rel = math.min(math.max(at.offset, math.max(line.start, _lead)), line.end);
      // The end of a wrapped line is before the break: the caret stays on this line. (Before a line feed that
      // begins the next line by hand, the place found is the feed's own.)
      if ((rel == line.end || (rel == line.end - 1 && paint.feedAt(rel + _base))) && index < _lines.length - 1) assoc = -1;
      if (rel == line.start && index > 0) assoc = 1;
      offset = rel + _base;
      // Which letter the point was on: the one after the place found (the paragraph says so by leaning the
      // position downstream), or the one before.
      onward = at.affinity == TextAffinity.downstream && rel == at.offset;
    }
    final display = paint.toDisplay(offset);
    // Where marks are hidden several document positions are one place on screen. A point on the letter after
    // them means the position that letter starts at, past the hidden marks; a point on the letter before means
    // the position it ends at. Off either end of the words it is the far side of whatever is hidden there, as the
    // page answers.
    final bias = display == 0 || display >= proj.display.length || onward ? 1 : -1;
    final pos = proj.toDoc(display, bias);
    return LineHit(pos, assoc, inside: inside);
  }

  /// The rectangles of a stretch of the line (document offsets from its start), one for each visual line it is on,
  /// each as tall as its line box.
  List<Rect> rectsForRange(int from, int to, {bool pastEnd = false}) {
    final paint = _paint, words = _words;
    if (paint == null || words == null || _lines.isEmpty) return const <Rect>[];
    final proj = _spec.projection;
    final a = paint.toPaint(proj.toDisplay(from.clamp(0, proj.length), 1)), b = paint.toPaint(proj.toDisplay(to.clamp(0, proj.length), -1));
    final rects = <Rect>[];
    void addLine(VisualLine line, double left, double right) {
      // As tall as the line box, and as the letters where a tight leading lets them stand past it: what the page's
      // own selection covers.
      final top = math.min(line.top, line.contentTop), bottom = math.max(line.bottom, line.contentBottom);
      for (var i = 0; i < rects.length; i++) {
        if (rects[i].top == top) {
          rects[i] = Rect.fromLTRB(math.min(rects[i].left, left), top, math.max(rects[i].right, right), bottom);
          return;
        }
      }
      rects.add(Rect.fromLTRB(left, top, right, bottom));
    }

    final marker = _marker;
    if (marker != null && a < _split) {
      final x0 = _contentLeft - _spec.look.hang;
      for (final box in marker.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: math.min(b, _split)))) {
        addLine(_lines.first, x0 + box.left, x0 + box.right);
      }
    }
    final ra = math.max(_lead, a - _base), rb = b - _base;
    if (rb > ra) {
      for (final box in words.getBoxesForSelection(TextSelection(baseOffset: ra, extentOffset: rb))) {
        final middle = (box.top + box.bottom) / 2;
        var line = _lines.last;
        for (final each in _lines) {
          if (middle < each.fBottom) {
            line = each;
            break;
          }
        }
        addLine(line, _contentLeft + box.left, _contentLeft + box.right);
      }
    }
    if (pastEnd) {
      // The line's break is selected too: a space's width past its last letter.
      final end = coordsAtPos(proj.length, 1);
      final last = proj.segmentAt(proj.length, -1);
      final look = last != null && last.kind == SegmentKind.text ? _spec.runs[proj.segments.indexOf(last)] : _spec.look.base;
      if (end != null) addLine(_lines.last, end.left, end.left + _spaceWidth(look));
    }
    return rects;
  }

  static final Expando<double> _spaces = Expando<double>('space width');

  static double _spaceWidth(RunLook look) {
    final known = _spaces[look];
    if (known != null) return known;
    final painter = TextPainter(text: TextSpan(text: '\u00A0', style: look.style), textDirection: TextDirection.ltr)..layout();
    final width = painter.width;
    painter.dispose();
    return _spaces[look] = width;
  }

  // -- paint -------------------------------------------------------------------------------------------------------

  /// A position down the canvas on a whole device pixel: where the page puts a box's edge and a line of text, so
  /// two grounds that meet leave no seam and letters are not drawn between two rows of pixels.
  static double _snap(double value) => snapToDevicePixel(value);

  static Rect _snapRect(Rect rect) => Rect.fromLTRB(_snap(rect.left), _snap(rect.top), _snap(rect.right), _snap(rect.bottom));

  final LayerHandle<LeaderLayer> _startHandle = LayerHandle<LeaderLayer>();
  final LayerHandle<LeaderLayer> _endHandle = LayerHandle<LeaderLayer>();

  @override
  bool get alwaysNeedsCompositing => _selection.startHandle != null || _selection.endHandle != null;

  // -- the words, kept (the header's note) ---------------------------------------------------------------------------

  /// What each visual line's words drew, and the marker before them.
  List<_Kept?> _kept = const <_Kept?>[];
  _Kept? _keptMarker;

  /// Where each run's words are, for the grounds and the painters of the runs that have them (`paint`).
  List<List<Rect>?>? _runBoxes;

  void _forget() {
    for (final kept in _kept) {
      kept?.picture.dispose();
    }
    _kept = const <_Kept?>[];
    _keptMarker?.picture.dispose();
    _keptMarker = null;
    _runBoxes = null;
  }

  /// The scroll view the line moves in: the nearest above it with nothing between that keeps a layer of its own
  /// (a line under such a thing never moves on its canvas when the page does). Looked for once a stay in the tree.
  RenderViewportBase? _scroller;
  bool _scrollerKnown = false;

  /// Whether the page is being moved now: by a finger, a fling or an animation of its own. Nothing else moves a
  /// line for long (a jump, a keyboard coming up), and then it is drawn afresh as it always was. Asked once a
  /// paint, of the first picture that is not where it was drawn.
  bool _carried() {
    if (_carriedKnown) return _carriedNow;
    _carriedKnown = true;
    if (!_scrollerKnown) {
      _scrollerKnown = true;
      _scroller = null;
      for (RenderObject? up = parent; up != null; up = up.parent) {
        if (up is RenderViewportBase) {
          _scroller = up;
          break;
        }
        if (up.isRepaintBoundary) break;
      }
    }
    final scroller = _scroller;
    if (scroller == null) return _carriedNow = false;
    final position = scroller.offset;
    if (position is! ScrollPosition || !position.isScrollingNotifier.value) return _carriedNow = false;
    _AtRest.owe(position, scroller);
    return _carriedNow = true;
  }

  bool _carriedKnown = false;
  bool _carriedNow = false;

  /// How far down the canvas has been moved for the pictures being put back ([_put]), until [_unmoved].
  double _movedBy = 0;

  void _unmoved(Canvas canvas) {
    if (_movedBy == 0) return;
    canvas.restore();
    _movedBy = 0;
  }

  /// Puts `kept` on the canvas where its line now stands, `y` being the device pixel the line's top falls on:
  /// as it is where the line has not moved, moved by the whole pixels the line has while the page is being moved
  /// (the canvas is left moved for the next picture, which has most often moved as far: [_unmoved] puts it back).
  /// False where it has to be drawn afresh.
  bool _put(Canvas canvas, _Kept? kept, double x, double y) {
    if (kept == null || kept.x != x) return false;
    final by = y - kept.y;
    if (by != 0 && !_carried()) return false;
    if (by != _movedBy) {
      _unmoved(canvas);
      if (by != 0) {
        canvas.save();
        canvas.translate(0, by);
        _movedBy = by;
      }
    }
    canvas.drawPicture(kept.picture);
    if (by != 0) wordsCarried += 1;
    wordsKept += 1;
    return true;
  }

  /// One visual line of `painter`, clipped to itself where the paragraph has more than one, on the baseline the
  /// page's line boxes put it on. `top` is the device pixel the line's top falls on.
  void _drawLine(Canvas canvas, Offset offset, TextPainter painter, VisualLine line, double top, {required bool alone}) {
    final x = offset.dx + _contentLeft;
    final dy = top + line.above - line.fBaseline;
    if (alone) {
      painter.paint(canvas, Offset(x, dy));
      return;
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(offset.dx - 4096, line.fTop + dy, offset.dx + size.width + 4096, line.fBottom + dy));
    painter.paint(canvas, Offset(x, dy));
    canvas.restore();
  }

  void _paintParagraph(Canvas canvas, Offset offset, TextPainter painter) {
    if (_spec.projection.display.isEmpty || _paint!.text.length == _split) return;
    final alone = _lines.length == 1;
    // The words themselves are kept; the same words in the selection's paper are a few lines for a moment.
    if (!keepsWords || !identical(painter, _words)) {
      for (final line in _lines) {
        _drawLine(canvas, offset, painter, line, _snap(offset.dy + line.top), alone: alone);
      }
      if (identical(painter, _words)) wordsDrawn += _lines.length;
      return;
    }
    if (_kept.length != _lines.length) {
      _forget();
      _kept = List<_Kept?>.filled(_lines.length, null);
    }
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final top = _snap(offset.dy + line.top);
      if (_put(canvas, _kept[i], offset.dx, top)) continue;
      _unmoved(canvas);
      _kept[i]?.picture.dispose();
      final recorder = ui.PictureRecorder();
      _drawLine(Canvas(recorder), offset, painter, line, top, alone: alone);
      final kept = _kept[i] = _Kept(recorder.endRecording(), offset.dx, top);
      canvas.drawPicture(kept.picture);
      wordsDrawn += 1;
    }
    _unmoved(canvas);
  }

  /// The marker of a list item, at the gutter, on the first line's baseline.
  void _paintMarker(Canvas canvas, Offset offset, TextPainter marker) {
    final top = _snap(offset.dy + _lines.first.top);
    if (keepsWords && _put(canvas, _keptMarker, offset.dx, top)) return _unmoved(canvas);
    final at = Offset(offset.dx + _contentLeft - _spec.look.hang, top + _lines.first.above - marker.computeDistanceToActualBaseline(TextBaseline.alphabetic));
    if (!keepsWords) {
      marker.paint(canvas, at);
      return;
    }
    _keptMarker?.picture.dispose();
    final recorder = ui.PictureRecorder();
    marker.paint(Canvas(recorder), at);
    final kept = _keptMarker = _Kept(recorder.endRecording(), offset.dx, top);
    canvas.drawPicture(kept.picture);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final drawnBefore = wordsDrawn;
    _carriedKnown = false;
    final look = _spec.look;
    final canvas = context.canvas;
    final words = _words;
    if (words == null) return;

    // The line's own ground: inside its margins and its transparent borders.
    if (look.background != null || look.barColor != null || look.borderStart > 0) {
      final box = _snapRect(Rect.fromLTRB(look.marginStart, look.borderTop, size.width - look.marginEnd, size.height - look.borderBottom).shift(offset));
      final shape = RRect.fromRectAndCorners(box, topLeft: look.topStart, topRight: look.topEnd, bottomLeft: look.bottomStart, bottomRight: look.bottomEnd);
      final round = look.topStart != Radius.zero || look.topEnd != Radius.zero || look.bottomStart != Radius.zero || look.bottomEnd != Radius.zero;
      if (round) {
        canvas.save();
        canvas.clipRRect(shape);
      }
      if (look.background != null) canvas.drawRect(box, Paint()..color = look.background!);
      if (look.borderStart > 0 && look.borderStartColor != null) {
        canvas.drawRect(Rect.fromLTWH(box.left, box.top, look.borderStart, box.height), Paint()..color = look.borderStartColor!);
      }
      if (look.barColor != null && look.barWidth > 0) {
        canvas.drawRect(Rect.fromLTWH(box.left + look.borderStart, box.top, look.barWidth, box.height), Paint()..color = look.barColor!);
      }
      if (round) canvas.restore();
    }

    // The runs' own grounds, and what a format's painter draws behind the words.
    final proj = _spec.projection;
    // Where a run's words are, a box to each visual line it is on: asked of the paragraph once for a layout, not
    // at every paint (twice, for a run with a painter).
    List<Rect> boxesOf(int s, Segment seg, RunLook run) {
      final all = _runBoxes ??= List<List<Rect>?>.filled(proj.segments.length, null);
      final own = all[s] ??= <Rect>[
        for (final rect in rectsForRange(seg.from, seg.to))
          for (final line in _lines)
            if (math.min(line.top, line.contentTop) == rect.top) Rect.fromLTRB(rect.left, line.baseline - run.shift - run.ascent, rect.right, line.baseline - run.shift + run.descent),
      ];
      return <Rect>[for (final box in own) box.shift(offset)];
    }

    List<(List<Rect>, double)>? faded;
    for (var s = 0; s < proj.segments.length; s++) {
      final seg = proj.segments[s], run = _spec.runs[s];
      if (seg.kind != SegmentKind.text || (run.backgrounds.isEmpty && run.painter == null)) continue;
      final boxes = boxesOf(s, seg, run);
      for (final ground in run.backgrounds) {
        final paint = Paint()..color = ground;
        for (final box in boxes) {
          canvas.drawRect(box, paint);
        }
      }
      run.painter?.paintBehind(canvas, boxes, run);
      // Words whose painter fades them now (`RunPainter.wordsOpacity`).
      final opacity = run.painter?.wordsOpacity ?? 1;
      if (opacity < 1 && boxes.isNotEmpty) (faded ??= <(List<Rect>, double)>[]).add((boxes, opacity));
    }

    // The selection's ground.
    final selection = _selection;
    final selected = <Rect>[
      for (final (from, to) in selection.ranges) ...rectsForRange(from, to, pastEnd: selection.pastEnd && to >= proj.length),
    ];
    final host = _host;
    final painter = host?.selectionPainter ?? const EditorSelectionPainter();
    if (selected.isNotEmpty) painter.paintSelection(canvas, <Rect>[for (final rect in selected) _snapRect(rect.shift(offset))], selection.ink);

    // The words.
    final marker = _marker;
    if (marker != null) _paintMarker(canvas, offset, marker);
    if (faded == null) {
      _paintParagraph(canvas, offset, words);
    } else {
      // A run that fades its words: the paragraph is drawn once without them and once for each of them, through
      // a layer of its opacity, so no word is laid out again for a frame of a fade.
      final rest = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTRB(offset.dx - 4096, offset.dy - 4096, offset.dx + size.width + 4096, offset.dy + size.height + 4096));
      for (final (boxes, _) in faded) {
        for (final box in boxes) {
          rest.addRect(box);
        }
      }
      canvas.save();
      canvas.clipPath(rest, doAntiAlias: false);
      _paintParagraph(canvas, offset, words);
      canvas.restore();
      for (final (boxes, opacity) in faded) {
        var bounds = boxes.first;
        final own = Path();
        for (final box in boxes) {
          bounds = bounds.expandToInclude(box);
          own.addRect(box);
        }
        canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
        canvas.clipPath(own, doAntiAlias: false);
        _paintParagraph(canvas, offset, words);
        canvas.restore();
      }
    }
    for (final raised in _raised) {
      raised.painter.paint(canvas, Offset(offset.dx + raised.offset.dx, _snap(offset.dy + raised.offset.dy)));
    }
    // A line whose words were put on the canvas afresh, or one whose words were there to be put back.
    if (ghostPerf) Perf.count(wordsDrawn != drawnBefore ? 'editor.lines.painted' : 'editor.lines.kept');

    // The selected words again, in paper, where the ground is.
    if (selected.isNotEmpty && proj.display.isNotEmpty) {
      final paint = _paint!;
      canvas.save();
      final clip = Path();
      for (final rect in selected) {
        clip.addRect(_snapRect(rect.shift(offset)));
      }
      canvas.clipPath(clip);
      if (marker != null) {
        final over = TextPainter(text: TextSpan(children: _spans(paint, 0, _split, ink: selection.paper)), textDirection: TextDirection.ltr);
        over.setPlaceholderDimensions(<PlaceholderDimensions>[for (final _ in marker.inlinePlaceholderBoxes ?? const <TextBox>[]) PlaceholderDimensions.empty]);
        over.layout();
        over.paint(canvas, Offset(offset.dx + _contentLeft - look.hang, _snap(offset.dy + _lines.first.top) + _lines.first.above - over.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
        over.dispose();
      }
      if (paint.text.length > _split) {
        var over = _selected;
        if (over == null) {
          over = _selected = TextPainter(text: TextSpan(children: <InlineSpan>[if (_lead > 0) _spacer, ..._spans(paint, _split, paint.text.length, ink: selection.paper)]), textDirection: TextDirection.ltr);
          final dims = <PlaceholderDimensions>[?_leadSize];
          var child = firstChild;
          for (final seg in proj.segments) {
            if (seg.kind != SegmentKind.widget) continue;
            if (paint.toPaint(seg.displayFrom) >= _split) {
              final baseline = child == null ? 0.0 : (child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? child.size.height);
              dims.add(child == null ? PlaceholderDimensions.empty : PlaceholderDimensions(size: child.size, alignment: ui.PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: baseline));
            }
            if (child != null) child = childAfter(child);
          }
          over.setPlaceholderDimensions(dims);
          over.layout(maxWidth: math.max(1, _contentWidth + 1 / 64));
        }
        _paintParagraph(canvas, offset, over);
        for (final raised in _raised) {
          final again = TextPainter(text: TextSpan(text: raised.painter.plainText, style: (raised.painter.text! as TextSpan).style!.copyWith(color: selection.paper, decorationColor: selection.paper)), textDirection: TextDirection.ltr)..layout();
          again.paint(canvas, Offset(offset.dx + raised.offset.dx, _snap(offset.dy + raised.offset.dy)));
          again.dispose();
        }
      }
      canvas.restore();
    }

    for (var s = 0; s < proj.segments.length; s++) {
      final seg = proj.segments[s], run = _spec.runs[s];
      if (seg.kind == SegmentKind.text && run.painter != null) run.painter!.paintOver(canvas, boxesOf(s, seg, run), run);
    }

    // The inline widgets.
    defaultPaint(context, offset);

    // The carets, and where the handles hang.
    final opacity = host?.caretOpacity.value ?? 1;
    for (final (pos, assoc) in selection.carets) {
      final caret = coordsAtPos(pos, assoc);
      if (caret != null) painter.paintCaret(context.canvas, caret.shift(offset), selection.caretColor, opacity);
    }
    if (host != null) {
      _leader(context, offset, _startHandle, host.startHandleLink, selection.startHandle, 1);
      _leader(context, offset, _endHandle, host.endHandleLink, selection.endHandle, -1);
    } else {
      _startHandle.layer = null;
      _endHandle.layer = null;
    }
  }

  void _leader(PaintingContext context, Offset offset, LayerHandle<LeaderLayer> handle, LayerLink link, int? pos, int side) {
    final at = pos == null ? null : coordsAtPos(pos, side);
    if (at == null) {
      handle.layer = null;
      return;
    }
    // A handle hangs from the foot of the text at its end of the selection.
    final anchor = offset + at.bottomLeft;
    final layer = handle.layer;
    if (layer == null) {
      handle.layer = LeaderLayer(link: link, offset: anchor);
    } else {
      layer
        ..link = link
        ..offset = anchor;
    }
    context.pushLayer(handle.layer!, (context, offset) {}, Offset.zero);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  // What a screen reader is told of the line (../semantics/line_semantics.dart). Flutter calls these only while
  // one is listening.
  final List<SemanticsNode> _linkNodes = <SemanticsNode>[];

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    describeLine(this, config);
  }

  @override
  void assembleSemanticsNode(SemanticsNode node, SemanticsConfiguration config, Iterable<SemanticsNode> children) => assembleLine(this, node, config, children, _linkNodes);

  @override
  void clearSemantics() {
    super.clearSemantics();
    _linkNodes.clear();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  /// The inline widget under a point of this box, with its segment: for whoever handles a press to ask
  /// `takesPointer`.
  ({Segment segment, RenderBox box})? widgetAt(Offset local) {
    var child = firstChild;
    for (final seg in _spec.projection.segments) {
      if (seg.kind != SegmentKind.widget) continue;
      if (child == null) return null;
      final data = child.parentData! as EditorInlineParentData;
      if ((data.offset & child.size).contains(local)) return (segment: seg, box: child);
      child = childAfter(child);
    }
    return null;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('from', from))
      ..add(StringProperty('text', _spec.projection.display))
      ..add(StringProperty('class', _spec.projection.className));
  }
}

class _Raised {
  _Raised(this.painter, this.offset);
  final TextPainter painter;
  final Offset offset;
}
