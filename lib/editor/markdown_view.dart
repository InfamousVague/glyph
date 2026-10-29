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
/// It says nothing to a screen reader and takes no taps, as the web's (`aria-hidden`, `pointer-events: none`), but
/// for one: drawn at the page's own sizes with [MarkdownView.links], a tap on a link in it opens the link
/// (media/links.dart `ReadLinks`), and every other press goes by it as before. A notebook's pages read straight
/// through are drawn so (Matt, 2026-10-29: "Allow opening web links in the book view").
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../perf/frame_log.dart';
import 'looks/look.dart';
import 'looks/peek_look.dart';
import 'media/links.dart' show ReadLinks;
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
    this.links = false,
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

  /// Drawn at the page's own sizes, a tap on a link opens it, by what [extensions] say opens one (an address by
  /// `linkTapOpener`, a `[[link]]` by `wikiOptions`). A peek's taps are always its card's.
  final bool links;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

/// The editor's state for each note drawn small lately: its Markdown read, and the extensions it is drawn with
/// worked out.
///
/// A list of cards builds only the ones near the screen (lib/home/lazy_page.dart), so a card scrolled away and back
/// is made again, and its preview with it: an editor's state for the same Markdown, the whole stack of extensions
/// resolved and the syntax read again, each time. A state does not change (a preview takes no input, and a state
/// is a value: a change makes another), so the one made for these words drawn this way does for every view of them,
/// two at once as well. The view itself, whose plugins listen and keep clocks, is still made for each drawing and
/// destroyed with it.
///
/// The [most] asked for last are kept.
abstract final class _States {
  static const int most = 160;

  static final List<({EditorState state, String markdown, NoteView display, String? look, Iterable<InlineFormatSyntax> formats, List<Extension> extensions})> _kept = [];

  /// The state for [of]'s Markdown drawn its way: the one kept, or made now and kept.
  static EditorState of(MarkdownView of) {
    // The last asked for is the likeliest asked for again: a row of cards scrolled just off the screen and back.
    for (var i = _kept.length - 1; i >= 0; i -= 1) {
      final kept = _kept[i];
      if (kept.display == of.display && kept.look == of.look && identical(kept.formats, of.formats) && identical(kept.extensions, of.extensions) && kept.markdown == of.markdown) {
        if (i != _kept.length - 1) {
          _kept.removeAt(i);
          _kept.add(kept);
        }
        if (ghostPerf) Perf.count('peek.kept');
        return kept.state;
      }
    }
    if (ghostPerf) Perf.count('peek.made');
    final state = EditorState.create(
      doc: of.markdown,
      extensions: noteExtensions(formats: of.formats, display: of.display, readOnly: true, look: of.look, more: of.extensions),
    );
    _kept.add((state: state, markdown: of.markdown, display: of.display, look: of.look, formats: of.formats, extensions: of.extensions));
    if (_kept.length > most) _kept.removeAt(0);
    return state;
  }
}

class _MarkdownViewState extends State<MarkdownView> {
  late EditorView _view = _make();

  EditorView _make() => EditorView(wholeDocument: true, state: _States.of(widget));

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
      final page = ExcludeSemantics(child: IgnorePointer(child: EditorColumn(view: _view, env: LookEnv.page(t, devicePixelRatio: ratio, tabSize: _view.state.tabSize))));
      return widget.links ? ReadLinks(view: _view, blocks: true, child: page) : page;
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

  /// The mask's layer and the clip's, kept from one paint to the next: a card is painted again for a pointer over
  /// it or its own entrance, and a new layer each time is a new one for the engine to take up and the old to let go.
  final LayerHandle<ShaderMaskLayer> _mask = LayerHandle<ShaderMaskLayer>();
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  /// The fade's gradient, made once for a size and a fade.
  Shader? _shader;
  Size? _shaderSize;
  double? _shaderFade;

  @override
  void dispose() {
    _mask.layer = null;
    _clip.layer = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
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
      _mask.layer = null;
      if (inner.size.height > size.height) {
        _clip.layer = context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) => context.paintChild(inner, offset), oldLayer: _clip.layer);
      } else {
        _clip.layer = null;
        context.paintChild(inner, offset);
      }
      return;
    }
    if (_shader == null || _shaderSize != size || _shaderFade != _fade) {
      _shader?.dispose();
      _shaderSize = size;
      _shaderFade = _fade;
      _shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const <Color>[Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: <double>[0, size.height == 0 ? 0 : ((size.height - _fade).clamp(0.0, size.height)) / size.height, 1],
      ).createShader(Offset.zero & size);
    }
    // A mask and never a painted shadow: the words themselves go to nothing over the last lines.
    final mask = (_mask.layer ??= ShaderMaskLayer())
      ..shader = _shader
      ..maskRect = bounds
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      mask,
      (context, offset) => _clip.layer = context.pushClipRect(true, offset, Offset.zero & size, (context, offset) => context.paintChild(inner, offset), oldLayer: _clip.layer),
      offset,
    );
  }

  @override
  bool get alwaysNeedsCompositing => _clipped;
}
