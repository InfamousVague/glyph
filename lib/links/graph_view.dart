/// The graph of the notes and the links between them: every note in the library (from the palette's Graph of your
/// notes and the sidebar's), or the notes within one or two links of the open one (its More sheet's Local graph).
/// A dot a note, sized by how many links it has and coloured by the hue of the workspace it is filed in, as a
/// canvas's cards wear the page's hues; a note with no links at all is drawn dim. Pinch or wheel to zoom, drag to
/// move about, tap a note to open it, hold one to light it and the notes it links with. Names are drawn once the
/// graph is close enough to read them.
///
/// **Laid out once, then only drawn.** Where the notes stand is worked out off the UI isolate
/// (lib/links/graph_layout.dart); the dots and lines are then recorded into one picture, which each frame of a
/// pinch or a drag only draws again under the new transform. The picture is recorded again only when the graph,
/// the light or the theme changes; a name is laid out once, the first time it is drawn.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/link_index.dart';
import 'graph_layout.dart';

/// A note's workspace hue, or null for none (ink).
typedef GraphHue = String? Function(String id);

/// How many notes are laid out where they are drawn: past this, a worker isolate lays them out.
const int layOutHereUpTo = 160;

/// The zoom past which names are drawn: a dot is then some 12 pixels across.
const double namesFrom = 0.75;

/// A note's dot, in the graph's units: bigger the more links it has.
double nodeRadius(int degree) => 6 + math.sqrt(degree.toDouble()) * 2.4;

/// The graph, drawn and moved about.
class GraphView extends StatefulWidget {
  const GraphView({super.key, required this.graph, required this.onOpen, this.hueOf, this.focus, this.layOut});

  final LinkGraph graph;
  final void Function(String id) onOpen;
  final GraphHue? hueOf;

  /// The note a local graph is round: drawn ringed.
  final String? focus;

  /// What lays the graph out; the worker past [layOutHereUpTo] notes unless given (a test).
  final Future<Float64List> Function(GraphInput input)? layOut;

  @override
  State<GraphView> createState() => GraphViewState();
}

class GraphViewState extends State<GraphView> {
  Float64List? _at;
  List<int> _degrees = const [];
  List<List<int>> _next = const [];

  /// The graph's transform: a point of the graph is at `point * scale + shift` on the view.
  final ValueNotifier<({double scale, Offset shift})> _view = ValueNotifier((scale: 1, shift: Offset.zero));
  Size _size = Size.zero;
  bool _fitted = false;

  /// The note held, and so lit with its neighbours; -1 for none.
  int _lit = -1;
  int _laying = 0;

  /// Where the notes stand, once laid out: for a test.
  Float64List? get positions => _at;
  ({double scale, Offset shift}) get transform => _view.value;
  int get lit => _lit;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.graph, widget.graph)) _read();
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  void _read() {
    final graph = widget.graph;
    _degrees = graph.degrees;
    _next = List<List<int>>.generate(graph.length, (_) => <int>[]);
    for (var e = 0; e < graph.from.length; e += 1) {
      _next[graph.from[e]].add(graph.to[e]);
      _next[graph.to[e]].add(graph.from[e]);
    }
    _lit = -1;
    final input = (ids: graph.ids, from: graph.from, to: graph.to);
    final ask = widget.layOut ?? (graph.length <= layOutHereUpTo ? (GraphInput input) async => layOutGraph(input) : layOutGraphElsewhere);
    if (widget.layOut == null && graph.length <= layOutHereUpTo) {
      _at = layOutGraph(input);
      _fitted = false;
      return;
    }
    _at = null;
    final laying = _laying += 1;
    unawaited(ask(input).then((at) {
      if (!mounted || laying != _laying) return;
      setState(() {
        _at = at;
        _fitted = false;
      });
    }));
  }

  /// The view fitted to the graph, with room round it.
  void _fit(Size size) {
    final at = _at;
    if (at == null || size.isEmpty) return;
    // The box the notes are in; where a few strays far out would shrink the rest to dust, the box most are in.
    final n = at.length ~/ 2;
    final xs = [for (var i = 0; i < n; i += 1) at[2 * i]]..sort();
    final ys = [for (var i = 0; i < n; i += 1) at[2 * i + 1]]..sort();
    var minX = xs.first, maxX = xs.last, minY = ys.first, maxY = ys.last;
    if (n >= 60) {
      final cut = (n * 0.01).floor();
      final most = math.max(xs[n - 1 - cut] - xs[cut], ys[n - 1 - cut] - ys[cut]);
      if (most < 0.6 * math.max(maxX - minX, maxY - minY)) {
        final grow = most * 0.08;
        minX = xs[cut] - grow;
        maxX = xs[n - 1 - cut] + grow;
        minY = ys[cut] - grow;
        maxY = ys[n - 1 - cut] + grow;
      }
    }
    if (!minX.isFinite || !maxX.isFinite) return;
    final wide = math.max(maxX - minX, 1.0) + linkLength, tall = math.max(maxY - minY, 1.0) + linkLength;
    final scale = math.min(size.width / wide, size.height / tall).clamp(0.05, 3.0);
    final middle = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    _view.value = (scale: scale, shift: size.center(Offset.zero) - middle * scale);
    _fitted = true;
  }

  Offset _toGraph(Offset local) {
    final now = _view.value;
    return (local - now.shift) / now.scale;
  }

  /// The note at [local], within a finger's reach of its dot; -1 for none.
  int noteAt(Offset local) {
    final at = _at;
    if (at == null) return -1;
    final point = _toGraph(local);
    final reach = 18 / _view.value.scale;
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < at.length ~/ 2; i += 1) {
      final dx = at[2 * i] - point.dx, dy = at[2 * i + 1] - point.dy;
      final d = dx * dx + dy * dy;
      final r = _radius(i) + reach;
      if (d < r * r && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  double _radius(int i) => nodeRadius(_degrees.isEmpty ? 0 : _degrees[i]);

  // ---- moving about --------------------------------------------------------------------------------------------

  ({double scale, Offset shift})? _startView;
  Offset _startFocal = Offset.zero;

  void _scaleStart(ScaleStartDetails details) {
    _startView = _view.value;
    _startFocal = details.localFocalPoint;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    final start = _startView;
    if (start == null) return;
    final scale = (start.scale * details.scale).clamp(0.04, 8.0);
    // The point under the fingers stays under them.
    final graphPoint = (_startFocal - start.shift) / start.scale;
    _view.value = (scale: scale, shift: details.localFocalPoint - graphPoint * scale);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = _view.value;
    final factor = math.exp(-event.scrollDelta.dy / 300);
    final scale = (now.scale * factor).clamp(0.04, 8.0);
    final graphPoint = (event.localPosition - now.shift) / now.scale;
    _view.value = (scale: scale, shift: event.localPosition - graphPoint * scale);
  }

  void _tap(TapUpDetails details) {
    final i = noteAt(details.localPosition);
    if (i < 0) {
      if (_lit >= 0) setState(() => _lit = -1);
      return;
    }
    widget.onOpen(widget.graph.ids[i]);
  }

  void _hold(LongPressStartDetails details) {
    final i = noteAt(details.localPosition);
    HapticsProvider.of(context)(HapticKind.selection);
    setState(() => _lit = i == _lit ? -1 : i);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final at = _at;
    if (at == null) {
      return Center(child: Text('Laying out ${widget.graph.length} notes', style: t.textAt(t.fontSize('sm'), color: t.color('glacier-text-muted'))));
    }
    final graph = widget.graph;
    final ink = t.color('app-ink');
    final colours = <Color>[
      for (final id in graph.ids)
        switch (widget.hueOf?.call(id)) {
          final hue? => t.child(attrs: {'hue': hue}).color('app-space'),
          null => ink,
        },
    ];
    final focus = widget.focus == null ? -1 : graph.ids.indexOf(widget.focus!);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (!_fitted || size != _size) {
          _size = size;
          _fit(size);
        }
        return Listener(
          onPointerSignal: _wheel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _scaleStart,
            onScaleUpdate: _scaleUpdate,
            onTapUp: _tap,
            onLongPressStart: _hold,
            child: Semantics(
              label: 'A graph of ${graph.length} ${graph.length == 1 ? 'note' : 'notes'} and ${graph.from.length} ${graph.from.length == 1 ? 'link' : 'links'}',
              child: CustomPaint(
                size: size,
                isComplex: true,
                painter: GraphPainter(
                  view: _view,
                  at: at,
                  from: graph.from,
                  to: graph.to,
                  titles: graph.titles,
                  degrees: _degrees,
                  next: _next,
                  colours: colours,
                  ink: ink,
                  paper: t.color('app-paper'),
                  label: t.textAt(11.5, color: t.color('glacier-text-subtle')),
                  litLabel: t.textAt(12.5, weight: 'semibold', color: t.color('glacier-text')),
                  lit: _lit,
                  focus: focus,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The graph drawn: its dots and lines from one picture recorded for them, under the view's transform, and the
/// names over them once close enough.
class GraphPainter extends CustomPainter {
  GraphPainter({
    required this.view,
    required this.at,
    required this.from,
    required this.to,
    required this.titles,
    required this.degrees,
    required this.next,
    required this.colours,
    required this.ink,
    required this.paper,
    required this.label,
    required this.litLabel,
    required this.lit,
    required this.focus,
  }) : super(repaint: view);

  final ValueListenable<({double scale, Offset shift})> view;
  final Float64List at;
  final List<int> from;
  final List<int> to;
  final List<String> titles;
  final List<int> degrees;
  final List<List<int>> next;
  final List<Color> colours;
  final Color ink;
  final Color paper;
  final TextStyle label;
  final TextStyle litLabel;
  final int lit;
  final int focus;

  /// The names laid out, by the painter's positions and the note.
  static final Expando<Map<int, TextPainter>> _names = Expando<Map<int, TextPainter>>('the graph names');

  /// How many times a picture was recorded: for a test that holds a pinch to drawing alone.
  static int debugRecorded = 0;

  double radiusOf(int i) => nodeRadius(degrees[i]);

  bool _near(int i) => lit < 0 || i == lit || next[lit].contains(i);

  /// What the picture is kept by: the positions, the light, the colours and the focus.
  late final Object _key = Object.hash(identityHashCode(at), lit, focus, Object.hashAll(colours), ink, paper);

  ui.Picture _picture() {
    final kept = _kept[at];
    if (kept != null && kept.key == _key) return kept.picture;
    debugRecorded += 1;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final n = at.length ~/ 2;
    // The lines: the lit note's own bright, the rest faint; all of them fainter while one is lit.
    final faint = Path(), bright = Path();
    for (var e = 0; e < from.length; e += 1) {
      final a = from[e], b = to[e];
      final path = lit >= 0 && (a == lit || b == lit) ? bright : faint;
      path
        ..moveTo(at[2 * a], at[2 * a + 1])
        ..lineTo(at[2 * b], at[2 * b + 1]);
    }
    // Hairlines: a device pixel wide at any zoom.
    canvas.drawPath(faint, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = ink.withValues(alpha: lit >= 0 ? 0.1 : 0.32));
    if (lit >= 0) {
      canvas.drawPath(bright, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: 0.75));
    }
    final dot = Paint();
    for (var i = 0; i < n; i += 1) {
      final alone = degrees[i] == 0;
      final near = _near(i);
      final alpha = !near ? 0.12 : (alone ? 0.35 : 1.0);
      dot.color = colours[i].withValues(alpha: colours[i].a * alpha);
      canvas.drawCircle(Offset(at[2 * i], at[2 * i + 1]), radiusOf(i), dot);
    }
    // The note a local graph is round, and the one held: a ring.
    for (final ringed in {focus, lit}) {
      if (ringed < 0) continue;
      canvas.drawCircle(Offset(at[2 * ringed], at[2 * ringed + 1]), radiusOf(ringed) + 5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ink.withValues(alpha: 0.9));
    }
    final picture = recorder.endRecording();
    // One picture kept for a graph's positions: the last light's. The one it replaces is let go.
    kept?.picture.dispose();
    _kept[at] = (key: _key, picture: picture);
    return picture;
  }

  /// The picture recorded for a graph's positions, by what it was recorded from: a pinch draws the one it has.
  static final Expando<({Object key, ui.Picture picture})> _kept = Expando<({Object key, ui.Picture picture})>('the graph drawn');

  TextPainter _name(int i, bool bright) {
    final names = _names[at] ??= <int, TextPainter>{};
    final key = bright ? -i - 1 : i;
    return names[key] ??= (TextPainter(
      text: TextSpan(text: titles[i].isEmpty ? 'Untitled' : titles[i], style: bright ? litLabel : label),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 180));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final now = view.value;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(now.shift.dx, now.shift.dy)
      ..scale(now.scale)
      ..drawPicture(_picture())
      ..restore();
    // The names, close enough to read, of the notes on screen: the busiest notes' first, none over another, a
    // hundred and fifty at most.
    final names = now.scale >= namesFrom;
    if (!names && lit < 0 && focus < 0) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final taken = <Rect>[];
    for (final i in _byDegree()) {
      if (taken.length >= 150) break;
      final bright = lit >= 0 && _near(i);
      if (!names && !bright && i != focus) continue;
      if (lit >= 0 && !bright) continue;
      final x = at[2 * i] * now.scale + now.shift.dx, y = at[2 * i + 1] * now.scale + now.shift.dy;
      if (x < -200 || x > size.width + 200 || y < -20 || y > size.height + 20) continue;
      final painter = _name(i, bright || i == focus);
      final r = radiusOf(i) * now.scale;
      final where = Offset(x - painter.width / 2, y + r + 3);
      final box = Rect.fromLTWH(where.dx - 3, where.dy - 1, painter.width + 6, painter.height + 2);
      if (i != focus && i != lit && taken.any((other) => other.overlaps(box))) continue;
      taken.add(box);
      // A halo of paper behind a name, so it reads over the lines.
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = paper.withValues(alpha: 0.72));
      painter.paint(canvas, where);
    }
    canvas.restore();
  }

  /// The notes by how many links each has, the most first, then the note held and the focus: whose names go first.
  List<int> _byDegree() => _order[at] ??= ([for (var i = 0; i < at.length ~/ 2; i += 1) i]..sort((a, b) => degrees[b] - degrees[a]));

  static final Expando<List<int>> _order = Expando<List<int>>('the graph names order');

  @override
  bool shouldRepaint(GraphPainter old) =>
      !identical(old.at, at) || old.lit != lit || old.focus != focus || old.ink != ink || old.paper != paper || old.label != label || !_sameColours(old.colours, colours);

  static bool _sameColours(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The graph on a page of its own, over the app: its name and what it holds at the top with the way back, the
/// graph under them, and for a note's local graph the choice of one link out or two.
class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key, required this.indexer, required this.onOpen, required this.onClose, this.hueOf, this.focus, this.focusTitle, this.keep});

  final LinkIndexer indexer;

  /// Opens a note (the page goes first).
  final void Function(String id) onOpen;
  final VoidCallback onClose;
  final GraphHue? hueOf;

  /// The note a local graph is round; null for the whole library.
  final String? focus;
  final String? focusTitle;

  /// Which notes are in the graph: none in the Trash, none archived, unless it says otherwise.
  final bool Function(String id)? keep;

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  int _depth = 1;
  LinkGraph? _graph;
  int _version = -1;
  LinkIndex? _from;

  @override
  void initState() {
    super.initState();
    widget.indexer.addListener(_changed);
  }

  @override
  void dispose() {
    widget.indexer.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  LinkGraph get _now {
    final index = widget.indexer.index;
    if (_graph == null || _version != index.version || !identical(_from, index)) {
      _whole = index.graph(keep: widget.keep);
      _version = index.version;
      _from = index;
      _graph = null;
    }
    final focus = widget.focus;
    return _graph ??= focus == null ? _whole! : _whole!.around(focus, _depth);
  }

  LinkGraph? _whole;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final graph = _now;
    final padding = MediaQuery.paddingOf(context);
    final local = widget.focus != null;
    final title = local ? 'Around ${widget.focusTitle?.isNotEmpty ?? false ? widget.focusTitle : 'this note'}' : 'Graph of your notes';
    final counts = '${graph.length} ${graph.length == 1 ? 'note' : 'notes'}, ${graph.from.length} ${graph.from.length == 1 ? 'link' : 'links'}';
    final muted = t.color('glacier-text-muted');
    return ColoredBox(
      color: t.color('app-paper'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(2) + padding.left, padding.top + t.space(2), t.space(3) + padding.right, t.space(1)),
            child: Row(
              spacing: t.space(2),
              children: [
                GlacierPressable(
                  onPressed: widget.onClose,
                  semanticLabel: 'Close the graph',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    child: SizedBox.square(dimension: t.len('app-bar-ring'), child: Center(child: AppIcon(Lucide.x, size: 20, strokeWidth: 2.2, color: t.color('glacier-text')))),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(t.fontSize('md'), weight: 'semibold', color: t.color('glacier-text')))),
                      Text(counts, style: t.textAt(t.fontSize('xs'), color: muted)),
                    ],
                  ),
                ),
                if (local)
                  GlacierSegmentedControl(
                    value: '$_depth',
                    ariaLabel: 'How many links out',
                    size: GlacierSegmentedSize.sm,
                    options: const [GlacierSegmentedOption(value: '1', label: Text('1 link')), GlacierSegmentedOption(value: '2', label: Text('2 links'))],
                    onValueChange: (depth) => setState(() {
                      _depth = int.parse(depth);
                      _graph = null;
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: graph.length == 0
                ? Center(child: Text('No notes to draw yet.', style: t.textAt(t.fontSize('sm'), color: muted)))
                : GraphView(key: ValueKey('graph:${widget.focus}:$_depth'), graph: graph, focus: widget.focus, hueOf: widget.hueOf, onOpen: widget.onOpen),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), padding.bottom + t.space(3)),
            child: Text('Pinch to zoom. Tap a note to open it, hold one to light its links.', textAlign: TextAlign.center, style: t.textAt(t.fontSize('xs'), color: muted)),
          ),
        ],
      ),
    );
  }
}

/// The graph's page put over the app, and taken away when it closes or a note is opened from it.
Future<void> showGraph(
  BuildContext context, {
  required LinkIndexer indexer,
  required void Function(String id) onOpen,
  GraphHue? hueOf,
  String? focus,
  String? focusTitle,
  bool Function(String id)? keep,
}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
        pageBuilder: (route, _, _) => GraphScreen(
          indexer: indexer,
          hueOf: hueOf,
          focus: focus,
          focusTitle: focusTitle,
          keep: keep,
          onClose: () => Navigator.of(route).maybePop(),
          onOpen: (id) {
            Navigator.of(route).maybePop();
            onOpen(id);
          },
        ),
      ),
    );
