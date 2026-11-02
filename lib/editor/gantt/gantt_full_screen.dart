/// A Gantt chart full screen (Matt, 2026-10-16: "add the ability to view things like gantt charts in fullscreen";
/// 2026-11-02: "Clean up the gantt chart viewing experience to be scrolling on mobile and bigger"): the same chart as
/// the note's, the names in their column and the days scrolling sideways under the head, on the whole screen, its
/// rows scrolling up and down under a head that stays. The zoom is the chart's own: a pinch, − and +, and Week,
/// Month and Quarter where there is room. The layer is lib/editor/diagrams/full_screen.dart's: the app's topmost
/// overlay, a close in its corner, Escape and the phone's back closing it.
library;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/blur_edge.dart' show BlurEdgeClear;
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../../core/gantt/gantt.dart';
import '../queries/query_look.dart';
import 'gantt_chart.dart';

/// Opens [model]'s chart full screen over the app, drawn in [look] and read only. `label` is what a screen reader hears
/// it called.
void openGanttFullScreen(BuildContext context, {required QueryLook look, required GanttModel model, bool simple = false, String label = 'Gantt chart'}) {
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

  entry = OverlayEntry(builder: (context) => GanttLayer(look: look, model: model, simple: simple, label: '$label, full screen', onClose: shut));
  off = BackScope.of(context).onBack(() {
    shut();
    return true;
  });
  overlay.insert(entry);
}

/// The layer: the page's paper, a close, and the chart under it.
class GanttLayer extends StatefulWidget {
  const GanttLayer({super.key, required this.look, required this.model, required this.onClose, required this.label, this.simple = false});

  final QueryLook look;
  final GanttModel model;
  final VoidCallback onClose;
  final String label;
  final bool simple;

  @override
  State<GanttLayer> createState() => _GanttLayerState();
}

class _GanttLayerState extends State<GanttLayer> {
  final FocusNode _keys = FocusNode(debugLabel: 'gantt full screen');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final margin = t.space(4);
    final top = t.lenOf('var(--app-inset-top, 0px)');
    final close = Semantics(
      button: true,
      label: 'Close',
      child: GestureDetector(
        key: const ValueKey<String>('gantt-close'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: t.colorOf('color-mix(in srgb, var(--app-ink) 7%, transparent)'), shape: const CircleBorder()),
          child: SizedBox.square(
            dimension: t.lenOf('2.75rem'),
            child: Center(child: AppIcon(Lucide.x, size: t.lenOf('1.5rem'), color: t.color('app-ink'))),
          ),
        ),
      ),
    );
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
          key: const ValueKey<String>('gantt-layer'),
          color: t.color('app-paper'),
          child: Padding(
            padding: EdgeInsets.only(top: top, left: t.lenOf('var(--app-safe-left, 0px)'), right: t.lenOf('var(--app-safe-right, 0px)')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(margin, t.space(3), t.space(3), t.space(1)),
                  child: Row(
                    children: <Widget>[
                      if (widget.model.title case final title? when title.isNotEmpty)
                        Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: widget.look.sans(widget.look.note, weight: 'semibold', color: widget.look.ink)))
                      else
                        const Spacer(),
                      SizedBox(width: t.space(2)),
                      close,
                    ],
                  ),
                ),
                // The rows scroll up and down here, the head staying at the top (gantt_chart.dart `_follow`).
                Expanded(
                  child: BlurEdgeClear(
                    top: 0,
                    child: SingleChildScrollView(
                      key: const ValueKey<String>('gantt-full-scroll'),
                      padding: EdgeInsets.fromLTRB(margin, t.space(1), margin, t.lenOf('var(--app-safe-bottom, 0px)') + margin),
                      child: GanttChart(look: widget.look, model: widget.model, simple: widget.simple, label: widget.label, titled: false),
                    ),
                  ),
                ),
              ],
            ),
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
