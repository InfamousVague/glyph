/// A note drawn to be read: the same lines the editor draws, in a column, with no scroll view and no input. What
/// the web app gets by mounting its `Editor` read-only with `peek` set (`src/app/notes/NotePeek.tsx`, and the other
/// surfaces that show a note without editing it: a template's card, a canvas card, the guide's examples).
///
/// [MarkdownView] makes an editor state for its Markdown with the base extensions (`view/base.dart`), a view over
/// the whole of it, and an `EditorColumn`. Drawn as a `peek` (the default) it is the web's `.peek` box
/// (`looks/peek_look.dart`): the note's sizes at the card's scale, the third ink, the page's grounds and paddings
/// off, clipped to a few lines' height with the last one fading where there is more. With `peek: false` it is the
/// note at the page's own sizes, whole.
///
/// The web's `peek` options and where each went:
/// - `whole`: [MarkdownView.whole]. The words as they are from their first line, in the note's own ink and heading
///   proportions, held to 10rem.
/// - `look`: [MarkdownView.look].
/// - the clipped height and its fade: [MarkdownView.lines] (6.2 of the words' lines; a dense card 4.2), with
///   [MarkdownView.fill] for a card stretched in its row.
/// - `openHeading` (`A name` in an open first heading) is `openHeading.ts`'s and comes with it, through
///   [MarkdownView.extensions].
/// - `eager`, the one-at-a-time queue, the screen watcher and the kept HTML are there because an editor costs the
///   web 25 to 30 ms; here a card's lines are made in well under a millisecond and nothing is queued or kept.
///
/// It says nothing to a screen reader and takes no taps, as the web's (`aria-hidden`, `pointer-events: none`).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'looks/look.dart';
import 'looks/peek_look.dart';
import 'state/state.dart';
import 'syntax/language.dart' show InlineFormatSyntax;
import 'view/base.dart';
import 'view/column.dart';
import 'view/editor_view.dart';
import 'view/view_mode.dart';

class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.markdown,
    this.display = NoteView.formatted,
    this.peek = true,
    this.whole = false,
    this.look,
    this.lines = 6.2,
    this.fill = false,
    this.formats = const <InlineFormatSyntax>[],
    this.extensions = const <Extension>[],
  });

  /// The Markdown to draw.
  final String markdown;

  /// Formatted, as a card's preview is, or with its marks.
  final NoteView display;

  /// Drawn small on a card (`.peek`), or at the page's own sizes.
  final bool peek;

  /// A template's card: the top of the note it makes (`data-whole`).
  final bool whole;

  /// How the note it depicts looks (`data-look`): `reading`, or null for the usual look.
  final String? look;

  /// How many of the words' lines a peek may be tall (`max-block-size: calc(1.6em * 6.2)`); null for no cap. A
  /// whole peek is held to 10rem instead.
  final double? lines;

  /// Stretched in its card: the preview takes the room it is given, up to its cap.
  final bool fill;

  /// The switched-on plugins' inline formattings.
  final Iterable<InlineFormatSyntax> formats;

  /// More extensions, after the base ones.
  final List<Extension> extensions;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  late EditorView _view = _make();

  EditorView _make() => EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: widget.markdown,
      extensions: noteExtensions(formats: widget.formats, display: widget.display, readOnly: true, look: widget.look, more: widget.extensions),
    ),
  );

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown ||
        oldWidget.display != widget.display ||
        oldWidget.look != widget.look ||
        !identical(oldWidget.formats, widget.formats) ||
        !identical(oldWidget.extensions, widget.extensions)) {
      _view.destroy();
      _view = _make();
    }
  }

  @override
  void dispose() {
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (!widget.peek) {
      return ExcludeSemantics(child: IgnorePointer(child: EditorColumn(view: _view, env: LookEnv.page(t, devicePixelRatio: ratio, tabSize: _view.state.tabSize))));
    }
    final env = peekEnv(t, whole: widget.whole, look: widget.look, devicePixelRatio: ratio);
    final em = env.body;
    final column = EditorColumn(view: _view, env: env, sheets: <LookSheet>[peekLook(whole: widget.whole)]);
    // `.peek { max-block-size: calc(1.6em * 6.2) }`, `.peek[data-whole] { max-block-size: 10rem }`; the fade is
    // `calc(100% - 1.8em)` to the foot, `3em` for a whole one.
    final most = widget.whole ? t.lenOf('10rem') : (widget.lines == null ? double.infinity : 1.6 * em * widget.lines!);
    return ExcludeSemantics(
      child: PeekClip(maxHeight: most, fade: (widget.whole ? 3 : 1.8) * em, fill: widget.fill, child: column),
    );
  }
}

/// `max-block-size` with `overflow: hidden`, and `.peek[data-clipped]`'s mask: the child is as tall as its lines,
/// this is no taller than [maxHeight], and where the child is cut the last [fade] of it goes to nothing. It takes
/// no taps (`pointer-events: none`).
class PeekClip extends SingleChildRenderObjectWidget {
  const PeekClip({super.key, required this.maxHeight, required this.fade, this.fill = false, required Widget super.child});

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

  /// `scrollHeight > clientHeight + 1` (NotePeek.tsx `check`).
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
    // Stretched in its card, the preview takes the room it is given, up to its cap; alone, its own lines.
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
    context.pushLayer(
      ShaderMaskLayer()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: <double>[0, size.height == 0 ? 0 : ((size.height - _fade).clamp(0.0, size.height)) / size.height, 1],
        ).createShader(Offset.zero & size)
        ..maskRect = bounds
        ..blendMode = BlendMode.dstIn,
      (context, offset) => context.pushClipRect(true, offset, Offset.zero & size, (context, offset) => context.paintChild(inner, offset)),
      offset,
    );
  }

  @override
  bool get alwaysNeedsCompositing => _clipped;
}
