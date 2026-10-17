/// A diagram full screen: a gantt, a flowchart or a query's timeline, over the whole app, as large as the screen
/// allows, to pinch, pan and read (Matt, 2026-10-16: "add the ability to view things like gantt charts in
/// fullscreen"). The page has no counterpart; a film's Full screen (lib/editor/media/videos.dart) is its model: a
/// button in the block's corner, a layer in the app's topmost overlay, a close in its corner, and the phone's back
/// closing it first.
///
/// The picture in a note is made for the note's column. The layer asks for its own, from the same store and the
/// same renderer: the diagram drawn on a page as wide as the screen, and never narrower than [fullScreenLeast], so a
/// gantt's days spread out on a phone held upright too. Until it comes, the note's picture is shown fitted. It
/// opens fitted to the screen whole; a pinch zooms up to [_mostZoom] times, a drag pans, and a double tap zooms in
/// on where it was tapped, or back out to the whole. Turned or unfolded, the screen's new width asks again.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import 'bridge.dart';
import 'store.dart';

/// The narrowest page a diagram is drawn on full screen, in logical pixels: on a phone upright a gantt drawn at the
/// screen's 412 has its months a thumb apart.
const double fullScreenLeast = 760;

const double _mostZoom = 8;

/// The full-screen button in a drawn diagram's corner: `.full`, as a film card's is, in the diagram's top corner,
/// where a film's sits at its foot under the length.
class DiagramFullButton extends StatelessWidget {
  const DiagramFullButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Full screen',
      child: GestureDetector(
        key: const ValueKey<String>('diagram-full'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          // '.full': { inline-size: 2.25rem; block-size: 2.25rem; border-radius: var(--glacier-radius-full);
          //   background: color-mix(in srgb, var(--app-paper) 85%, transparent); color: var(--app-ink) }
          decoration: ShapeDecoration(color: t.colorOf('color-mix(in srgb, var(--app-paper) 85%, transparent)'), shape: const CircleBorder()),
          child: SizedBox.square(
            dimension: t.lenOf('2.25rem'),
            child: Center(child: AppIcon(Lucide.maximize, size: t.lenOf('1.05rem'), color: t.color('app-ink'))),
          ),
        ),
      ),
    );
  }
}

/// Opens `ask`'s diagram full screen over the app, `shown` (the block's own picture) in it until the full-screen one
/// is made. `label` is what a screen reader hears it called. Closes on the close, on Escape and on the phone's back.
void openDiagramFullScreen(BuildContext context, {required DiagramAsk ask, DiagramPicture? shown, String label = 'Diagram'}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  VoidCallback? off;
  var open = true;
  void shut() {
    if (!open) return;
    open = false;
    off?.call();
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(builder: (context) => DiagramLayer(ask: ask, shown: shown, label: '$label, full screen', onClose: shut));
  off = BackScope.of(context).onBack(() {
    shut();
    return true;
  });
  overlay.insert(entry);
}

/// The layer itself: the page's paper, the diagram, and a close.
class DiagramLayer extends StatefulWidget {
  const DiagramLayer({super.key, required this.ask, required this.onClose, required this.label, this.shown});

  /// The diagram as the block asked for it: widened here to the screen.
  final DiagramAsk ask;

  /// The block's picture, fitted until the layer's own is made. The block owns it, and may let it go while the
  /// layer is up (a sync redraws the note under it): the layer draws its own handle on the image.
  final DiagramPicture? shown;
  final VoidCallback onClose;
  final String label;

  @override
  State<DiagramLayer> createState() => DiagramLayerState();
}

class DiagramLayerState extends State<DiagramLayer> {
  final TransformationController _zoom = TransformationController();
  final FocusNode _keys = FocusNode(debugLabel: 'diagram full screen');

  /// The layer's own picture, of [_asked]; null until it is made.
  DiagramPicture? _picture;
  String? _asked;
  bool _failed = false;

  /// The screen and the picture the zoom was last fitted to: fitted again when either changes.
  Size? _fittedScreen;
  Object? _fittedPicture;

  /// Where a double tap landed, to zoom in on it.
  Offset? _tappedAt;

  /// The layer's own handle on the block's picture, and its size, until the full-size one comes.
  late final ui.Image? _borrowed = widget.shown?.image.clone();
  late final Size? _borrowedSize = widget.shown?.at.size;

  /// Whether the picture here is the layer's own, made for this screen.
  bool get drawn => _picture != null;

  void _want(double width) {
    final t = context.tokens;
    final room = math.max(width, fullScreenLeast).floorToDouble();
    final ask = widget.ask.widened(room, gutter: t.space(4));
    final key = ask.key;
    if (key == _asked) return;
    _asked = key;
    _failed = false;
    final store = diagramStore;
    final kept = store.held(ask);
    if (kept != null) {
      store.forget(this);
      _take(kept);
      return;
    }
    store.draw(ask, slot: this).then((made) {
      if (!mounted || made == null || key != _asked) {
        if (made is DiagramPicture) made.dispose();
        return;
      }
      setState(() => _take(made));
    });
  }

  void _take(DiagramDrawing made) {
    switch (made) {
      case DiagramPicture():
        _picture?.dispose();
        _picture = made;
      case DiagramMistake():
        // The block drew it, so the page can: what failed is the wider one. The block's picture stays.
        _failed = true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    diagramStore.forget(this);
    _picture?.dispose();
    _picture = null;
    _borrowed?.dispose();
    _zoom.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// How much `drawn` is scaled to show all of it inside `screen` with `margin` round it.
  static double _wholeScale(Size screen, Size drawn, double margin) =>
      math.min(math.max(1.0, screen.width - 2 * margin) / drawn.width, math.max(1.0, screen.height - 2 * margin) / drawn.height);

  /// The zoom that shows all of `drawn` inside `screen` with `margin` round it, centred.
  Matrix4 _fit(Size screen, Size drawn, double margin) {
    final scale = _wholeScale(screen, drawn, margin);
    final dx = (screen.width - drawn.width * scale) / 2;
    final dy = (screen.height - drawn.height * scale) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _doubleTap(Size screen, Size drawn, double margin) {
    final fitted = _fit(screen, drawn, margin);
    // The zoom is only ever a scale and a move: its scale is its first entry.
    final now = _zoom.value.entry(0, 0);
    final whole = _wholeScale(screen, drawn, margin);
    // Zoomed in already: back out to the whole. Otherwise three times as close, round where the tap was.
    if (now > whole * 1.05) {
      _zoom.value = fitted;
      return;
    }
    final at = _tappedAt ?? screen.center(Offset.zero);
    final scene = _zoom.toScene(at);
    final scale = math.min(whole * 3, _mostZoom);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(at.dx - scene.dx * scale, at.dy - scene.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final space3 = t.space(3);
    // The full-size picture once made; the block's until then.
    final ui.Image? image = _picture?.image ?? _borrowed;
    final Size? size = _picture?.at.size ?? _borrowedSize;
    final layer = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.label,
      child: Focus(
        focusNode: _keys,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ColoredBox(
          key: const ValueKey<String>('diagram-layer'),
          color: t.color('app-paper'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screen = constraints.biggest;
              if (screen.width.isFinite && screen.width > 0) _want(screen.width);
              final margin = t.space(4);
              Widget body;
              if (image == null || size == null) {
                body = Center(child: Text('Drawing it full size…', style: t.textAt(t.len('glacier-font-size-sm'), color: t.color('app-ink-3'))));
              } else {
                final drawn = size;
                // Fitted to the screen whole when it opens, when the screen turns, and when the full-size picture
                // takes the place of the block's; a pinch or a pan after that is left where it is put.
                if (_fittedScreen != screen || !identical(_fittedPicture, image)) {
                  _fittedScreen = screen;
                  _fittedPicture = image;
                  _zoom.value = _fit(screen, drawn, margin);
                }
                final whole = _wholeScale(screen, drawn, margin);
                body = GestureDetector(
                  onDoubleTapDown: (details) => _tappedAt = details.localPosition,
                  onDoubleTap: () => _doubleTap(screen, drawn, margin),
                  child: InteractiveViewer(
                    key: const ValueKey<String>('diagram-zoom'),
                    transformationController: _zoom,
                    constrained: false,
                    boundaryMargin: EdgeInsets.all(math.max(screen.width, screen.height)),
                    minScale: math.min(whole, 1) * 0.8,
                    maxScale: _mostZoom,
                    child: SizedBox.fromSize(
                      size: drawn,
                      child: RawImage(key: const ValueKey<String>('diagram-full-picture'), image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    ),
                  ),
                );
              }
              return Stack(
                children: <Widget>[
                  Positioned.fill(child: body),
                  if (_failed)
                    Positioned(
                      left: margin,
                      right: margin,
                      bottom: t.lenOf('var(--app-safe-bottom, 0px)') + margin,
                      child: Text('This could not be drawn larger here; this is the note\'s picture.', textAlign: TextAlign.center, style: t.textAt(t.len('glacier-font-size-sm'), color: t.color('app-ink-3'))),
                    ),
                  // '.close': as the film's layer has it, in the page's ink rather than white.
                  PositionedDirectional(
                    top: t.lenOf('var(--app-inset-top, 0px)') + space3,
                    end: t.lenOf('var(--app-safe-right, 0px)') + space3,
                    child: Semantics(
                      button: true,
                      label: 'Close',
                      child: GestureDetector(
                        key: const ValueKey<String>('diagram-close'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(color: t.colorOf('color-mix(in srgb, var(--app-paper) 85%, transparent)'), shape: const CircleBorder()),
                          child: SizedBox.square(
                            dimension: t.lenOf('2.75rem'),
                            child: Center(child: AppIcon(Lucide.x, size: t.lenOf('1.5rem'), color: t.color('app-ink'))),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (t.reducedMotion) return layer;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: t.duration('glacier-duration-fast'),
      curve: t.curve('glacier-ease-out'),
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
      child: layer,
    );
  }
}

/// Whether drawn diagrams carry their full-screen button. The tests that lay a diagram's block over the web page's
/// own (test/editor/blocks/reference_test.dart) turn it off: the page has no such button, and the drawing under it is
/// what they hold to the page.
@visibleForTesting
bool diagramFullScreenButtons = true;

/// A drawn picture with the full-screen button in its top corner: what a diagram's block and a query's timeline
/// wrap their picture in.
class WithFullScreen extends StatelessWidget {
  const WithFullScreen({super.key, required this.child, required this.onFullScreen});

  final Widget child;
  final VoidCallback onFullScreen;

  @override
  Widget build(BuildContext context) {
    if (!diagramFullScreenButtons) return child;
    final space1 = context.tokens.space(1);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        PositionedDirectional(top: space1, end: space1, child: DiagramFullButton(onPressed: onFullScreen)),
      ],
    );
  }
}
