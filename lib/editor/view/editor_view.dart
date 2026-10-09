/// The view: CodeMirror's `EditorView` (@codemirror/view, editorview.ts) without a DOM and without input.
///
/// An [EditorView] holds the state, takes transactions, runs the view plugins and the update listeners, keeps the
/// decorations for what is on screen, and knows where things are. It is not a widget: [EditorSliver]
/// (`sliver.dart`) draws it in a scroll view, line by line as they come on screen, and [EditorColumn]
/// (`column.dart`) draws all of it in a column, which is what a read-only preview wants. Either gives the view
/// its look ([setEnv]) from the tokens above it.
///
/// What the input layer (piece D) builds on, none of which this file does itself:
/// - [dispatch] and [dispatchTransactions]; [setFocused], [setComposing] to say what the keyboard is doing;
/// - [hitAt] and [posAtCoords] for a pointer, [coordsAtPos] for a caret's rectangle (and the IME's);
/// - [startHandleLink] and [endHandleLink], layer links at the selection's two ends, and [caretLink] is not
///   needed: `coordsAtPos(state.selection.main.head)` is the caret;
/// - [caretOpacity] to blink the caret and [selectionPainter] to draw the selection another way;
/// - [atomicRanges] for the ranges a caret steps over, also marked on each line's segments;
/// - [eventHandlers] and [eventObservers], what the plugins asked to be told;
/// - [lineAt], [lines]: the laid-out lines, each a `RenderEditorLine` with its own `visualLines`, `coordsAtPos`
///   and `hitAt`, for moving a caret by visual line.
///
/// What differs from CodeMirror:
/// - The update cycle has no DOM to read back, so there is no measure loop: the sliver measures lines as it lays
///   them out and tells the view ([measured]). A viewport that moved under a scroll is told to the plugins from
///   inside layout (they only make decorations), and to the update listeners after the frame.
/// - `requestMeasure` runs its request after the next frame.
/// - `visibleRanges` is the viewport less what block replacements cover; long-line gaps do not exist (a line is
///   laid out whole).
/// - `EditorViewLike.contentAttributes`, `editable` and the event handlers are read by the input layer; the view
///   only draws the caret when the state is editable and focused.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../looks/look.dart';
import '../looks/markdown_look.dart';
import '../looks/sheets.dart';
import '../state/change.dart';
import '../state/rangeset.dart';
import '../state/state.dart';
import 'blocks.dart';
import 'decoration.dart';
import 'glyph_theme.dart';
import 'line.dart';
import 'plugin.dart';
import 'projection.dart';
import 'widget.dart';

/// What scrolls the editor: the sliver, when the view is drawn in one.
abstract class EditorScroller {
  /// Brings `target` into view. Answers whether it will have to be asked again once more of the note has been
  /// measured.
  bool reveal(ScrollTarget target, EdgeInsets margins);
}

/// What a point of the screen is on.
class EditorHit {
  const EditorHit({required this.pos, this.assoc = 1, this.inside = true, this.line, this.widget, this.block});

  /// The document position.
  final int pos;

  /// Which side of a line wrap the point was on.
  final int assoc;

  /// Whether the point was on a line's or a block's own box, not just nearest to it.
  final bool inside;

  /// The line it is on, when it is on text.
  final RenderEditorLine? line;

  /// The inline widget under it.
  final EditorWidget? widget;

  /// The block widget under it.
  final EditorWidget? block;
}

class _PluginInstance {
  _PluginInstance(this.spec);
  final ViewPlugin<PluginValue> spec;
  PluginValue? value;
}

/// CodeMirror's `EditorView`.
class EditorView extends EditorViewLike implements EditorLineHost {
  EditorView({required EditorState state, this.wholeDocument = false, this.onDispatch}) : _state = state {
    _viewport = _firstViewport();
    _visible = <DocRange>[_viewport];
    _plugins = <_PluginInstance>[for (final spec in state.facet(viewPlugin)) _PluginInstance(spec)];
    for (final plugin in _plugins) {
      plugin.value = plugin.spec.create(this);
    }
    _heights = HeightMap(state.doc);
    _readDecorations(force: true);
  }

  /// Whether the view draws its whole document at once, with nothing held back for the screen: a preview.
  final bool wholeDocument;

  /// CodeMirror's `dispatchTransactions` option: called in place of [update] with what was dispatched, to apply it
  /// (or not) by calling [update] itself.
  final void Function(List<Transaction> trs, EditorView view)? onDispatch;

  EditorState _state;

  @override
  EditorState get state => _state;

  // -- plugins and decorations -----------------------------------------------------------------------------------

  late List<_PluginInstance> _plugins;
  List<DecorationSet> _decorations = const <DecorationSet>[];
  List<DecorationSet> _direct = const <DecorationSet>[];
  BlockStructure _blocks = BlockStructure.none;
  late HeightMap _heights;
  bool _updating = false;
  bool _destroyed = false;

  /// The decoration sets drawn now, in precedence order.
  List<DecorationSet> get decorations => _decorations;

  /// The editor's vertical structure.
  BlockStructure get blocks => _blocks;

  /// A height for every line.
  HeightMap get heights => _heights;

  @override
  V? plugin<V extends PluginValue>(ViewPlugin<V> plugin) {
    for (final instance in _plugins) {
      if (identical(instance.spec, plugin)) return instance.value as V?;
    }
    return null;
  }

  /// CodeMirror's `atomicRanges`, resolved: the ranges a caret steps over as one.
  List<RangeSet<RangeValue>> get atomicRanges => <RangeSet<RangeValue>>[for (final source in _state.facet(EditorViewLike.atomicRanges)) source(this)];

  /// The plugins' event handlers, in precedence order.
  List<EditorEventHandlers> get eventHandlers => <EditorEventHandlers>[
    for (final plugin in _plugins)
      if (plugin.spec.eventHandlers != null) plugin.spec.eventHandlers!,
  ];

  /// The plugins' event observers.
  List<EditorEventHandlers> get eventObservers => <EditorEventHandlers>[
    for (final plugin in _plugins)
      if (plugin.spec.eventObservers != null) plugin.spec.eventObservers!,
  ];

  void _readDecorations({bool force = false}) {
    final sources = _state.facet(EditorViewLike.decorations);
    final all = <DecorationSet>[], direct = <DecorationSet>[];
    for (final source in sources) {
      final set = EditorViewLike.resolveDecorations(source, this);
      all.add(set);
      if (source is DecorationSet) direct.add(set);
    }
    var sameDirect = !force && direct.length == _direct.length;
    for (var i = 0; sameDirect && i < direct.length; i++) {
      sameDirect = identical(direct[i], _direct[i]);
    }
    _decorations = all;
    _direct = direct;
    if (!sameDirect) _readBlocks();
  }

  void _readBlocks() {
    final before = _blocks;
    final doc = _state.doc;
    _blocks = BlockStructure.compute(doc, _direct);
    if (before.isEmpty && _blocks.isEmpty) return;
    // What was covered and is not any more has a height of its own again; what is covered now has none.
    before.forEachCovered((from, to) {
      for (var n = from; n <= to && n <= doc.lines; n++) {
        if (!_blocks.isCovered(n)) _heights.uncover(n, doc.line(n).length);
      }
    });
    _blocks.forEachCovered(_heights.cover);
    _visible = _visibleIn(_viewport);
  }

  // -- the look ----------------------------------------------------------------------------------------------------

  Look? _look;
  GlyphTheme? _theme;
  List<LookSheet> _moreSheets = const <LookSheet>[];
  LookEnv? _env;

  /// The stylesheets in force, resolved; null until something that draws the view has said what the tokens are.
  Look? get look => _look;

  /// glyphTheme.ts's values for the look's side.
  GlyphTheme? get theme => _theme;

  /// Says what the tokens and sizes are: whoever draws the view calls it when it builds. `more` are sheets of the
  /// host's own, over the extensions' (a card's preview takes the grounds off).
  void setEnv(LookEnv env, {List<LookSheet> more = const <LookSheet>[]}) {
    _moreSheets = more;
    _env = env;
    _makeLook(notify: false);
  }

  void _makeLook({required bool notify}) {
    final env = _env;
    if (env == null) return;
    // The editor's own attributes are read by the sheets (`[data-look='reading']`).
    final attrs = _state.facet(EditorViewLike.editorAttributes);
    final withAttrs = attrsEq(attrs, env.attrs)
        ? env
        : LookEnv(
            t: env.t,
            body: env.body,
            headings: env.headings,
            gutter: env.gutter,
            devicePixelRatio: env.devicePixelRatio,
            dark: env.dark,
            meHue: env.meHue,
            attrs: attrs,
            ink: env.ink,
            tabSize: env.tabSize,
            contentTop: env.contentTop,
            contentBottom: env.contentBottom,
          );
    final next = Look(withAttrs, <LookSheet>[markdownLook, ..._state.facet(lookSheets).reversed, ..._moreSheets]);
    if (_look != null && _look!.same(next)) return;
    _look = next;
    _theme = GlyphTheme.of(withAttrs);
    final base = next.line(LookElement(null)).base;
    _heights
      ..lineHeight = base.above + base.below
      ..invalidate(-1);
    // The markers' widths, and everything else measured in the old face, are stale: CodeMirror's geometry change.
    _updateWith(const <Transaction>[], flags: UpdateFlag.geometry, notify: notify);
  }

  /// The width of `runs` set on one line in the editor's face: a run's text and the classes on it. What
  /// glyphLines.ts measures with a ruler element in the scroller. Zero before the view has a look.
  double measureText(List<(String text, String? className)> runs) {
    final look = _look;
    if (look == null) return 0;
    final line = look.line(LookElement(null));
    return look.measure(<(String, RunLook)>[for (final (text, name) in runs) (text, name == null ? line.base : look.run(line, <LookElement>[LookElement(name)]))]);
  }

  // -- the viewport ------------------------------------------------------------------------------------------------

  late DocRange _viewport;
  late List<DocRange> _visible;

  @override
  DocRange get viewport => _viewport;

  @override
  List<DocRange> get visibleRanges => _visible;

  DocRange _firstViewport() {
    final doc = _state.doc;
    if (wholeDocument) return DocRange(0, doc.length);
    return DocRange(0, doc.line(math.min(doc.lines, 60)).to);
  }

  List<DocRange> _visibleIn(DocRange viewport) {
    if (_blocks.isEmpty) return <DocRange>[viewport];
    final doc = _state.doc;
    final ranges = <DocRange>[];
    var from = viewport.from;
    final first = doc.lineAt(viewport.from).number, last = doc.lineAt(viewport.to).number;
    final lines = _blocks.special.keys.where((n) => n <= last && _blocks.lastLineOf(n) >= first).toList()..sort();
    for (final n in lines) {
      final replace = _blocks.special[n]!.replace;
      if (replace == null) continue;
      if (replace.from > from) ranges.add(DocRange(from, math.min(replace.from, viewport.to)));
      from = math.max(from, replace.to);
    }
    if (from < viewport.to || ranges.isEmpty) ranges.add(DocRange(math.min(from, viewport.to), viewport.to));
    return ranges;
  }

  /// The sliver says which entries it is about to lay out (first lines, both included). The viewport is made to
  /// hold them with room to spare, and the plugins are told when it moved. Answers whether the decorations may
  /// have changed.
  bool ensureViewport(int firstLine, int lastLine) {
    if (wholeDocument) return false;
    final doc = _state.doc;
    firstLine = firstLine.clamp(1, doc.lines);
    lastLine = _blocks.lastLineOf(lastLine.clamp(firstLine, doc.lines)).clamp(firstLine, doc.lines);
    const margin = 24;
    final from = doc.line(firstLine).from, to = doc.line(lastLine).to;
    if (_viewport.from <= from && _viewport.to >= to) {
      // Still inside: kept unless it has grown far past what is wanted.
      final held = doc.lineAt(_viewport.to).number - doc.lineAt(_viewport.from).number;
      if (held <= (lastLine - firstLine) + margin * 6) return false;
    }
    final next = DocRange(doc.line(math.max(1, firstLine - margin)).from, doc.line(math.min(doc.lines, lastLine + margin)).to);
    if (next == _viewport) return false;
    _viewport = next;
    _visible = _visibleIn(next);
    _updateWith(const <Transaction>[], flags: UpdateFlag.viewport | UpdateFlag.viewportMoved, notify: false, inLayout: true);
    return true;
  }

  /// The sliver says lines were measured and some were not the height they were taken for.
  void measured() {
    if (_heightTold) return;
    _heightTold = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _heightTold = false;
      if (_destroyed) return;
      _updateWith(const <Transaction>[], flags: UpdateFlag.height, notify: true);
    });
  }

  bool _heightTold = false;

  // -- updates -----------------------------------------------------------------------------------------------------

  final List<VoidCallback> _listeners = <VoidCallback>[];
  ChangeDesc? _unsynced;
  bool _focusChanged = false;

  /// Called when the view has something new to draw.
  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// The document's changes since this was last asked, as one: whoever keeps things by line (the sliver's
  /// children) follows them through it. Null when the document has not changed.
  ChangeDesc? takeChanges() {
    final changes = _unsynced;
    _unsynced = null;
    return changes;
  }

  @override
  void dispatchTransactions(List<Transaction> trs) {
    if (onDispatch != null) {
      onDispatch!(trs, this);
    } else {
      update(trs);
    }
  }

  /// CodeMirror's `view.update(transactions)`: takes the state the transactions end in, tells the plugins, draws,
  /// tells the listeners.
  void update(List<Transaction> trs) {
    if (_destroyed) return;
    if (_updating) throw StateError('Calls to EditorView.update are not allowed while an update is in progress');
    if (trs.isEmpty) return;
    if (!identical(trs.first.startState, _state)) {
      throw RangeError("Trying to update state with a transaction that doesn't start from the previous state.");
    }
    _updateWith(trs, flags: 0, notify: true);
  }

  void _updateWith(List<Transaction> trs, {required int flags, required bool notify, bool inLayout = false}) {
    if (_destroyed) return;
    final wasUpdating = _updating;
    _updating = true;
    ViewUpdate update;
    try {
      final next = trs.isEmpty ? _state : trs.last.state;
      update = ViewUpdate.create(this, next, trs);
      update.flags = flags | (_focusChanged ? UpdateFlag.focus : 0);
      _focusChanged = false;
      final before = _state.doc;
      if (update.docChanged) {
        final changes = update.changes;
        _unsynced = _unsynced == null ? changes : _unsynced!.composeDesc(changes);
        _heights.applyChanges(changes, before, next.doc);
        // The viewport follows its text; the next layout says where it really is.
        final from = next.doc.lineAt(changes.mapPos(_viewport.from, -1)).from, to = next.doc.lineAt(changes.mapPos(_viewport.to, 1)).to;
        final moved = wholeDocument ? DocRange(0, next.doc.length) : DocRange(from, to);
        if (moved != _viewport) update.flags |= UpdateFlag.viewport;
        _viewport = moved;
      }
      final oldState = _state;
      _state = next;
      if (update.docChanged) _visible = _visibleIn(_viewport);
      for (final tr in trs) {
        if (tr.scrollIntoView) _scrollTarget = ScrollTarget(tr.newSelection.main, ScrollStrategy.nearest, ScrollStrategy.nearest, 5, 5);
        for (final effect in tr.effects) {
          final target = EditorViewLike.scrollIntoViewEffect.cast(effect);
          if (target != null) _scrollTarget = target.value;
        }
      }
      if (_scrollTarget != null && update.docChanged) _scrollTarget = _scrollTarget!.clip(next);

      // A reconfiguration may have added or dropped plugins.
      final specs = next.facet(viewPlugin);
      if (!identical(specs, oldState.facet(viewPlugin))) {
        final kept = <_PluginInstance>[];
        for (final spec in specs) {
          final had = _plugins.where((p) => identical(p.spec, spec)).firstOrNull;
          kept.add(had ?? _PluginInstance(spec));
        }
        for (final plugin in _plugins) {
          if (!kept.contains(plugin)) plugin.value?.destroy();
        }
        _plugins = kept;
      }
      for (final plugin in _plugins) {
        if (plugin.value == null) {
          plugin.value = plugin.spec.create(this);
        } else {
          plugin.value!.update(update);
        }
      }
      _readDecorations(force: update.docChanged);
      if (!identical(next.facet(lookSheets), oldState.facet(lookSheets)) || !identical(next.facet(EditorViewLike.editorAttributes), oldState.facet(EditorViewLike.editorAttributes))) {
        _updating = wasUpdating;
        _makeLook(notify: false);
        _updating = true;
      }
    } finally {
      _updating = wasUpdating;
    }
    if (notify) _notify();
    for (final plugin in _plugins) {
      plugin.value?.docViewUpdate(this);
    }
    final listeners = _state.facet(EditorViewLike.updateListener);
    if (listeners.isNotEmpty && !update.empty) {
      if (inLayout) {
        // Inside layout nothing outside the editor may be told to rebuild: after the frame.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_destroyed) return;
          for (final listener in listeners) {
            listener(update);
          }
        });
      } else {
        for (final listener in listeners) {
          listener(update);
        }
      }
    }
    if (_scrollTarget != null) _scheduleScroll();
  }

  /// CodeMirror's `view.destroy()`: the plugins are told and the view takes nothing more.
  void destroy() {
    if (_destroyed) return;
    for (final plugin in _plugins) {
      plugin.value?.destroy();
    }
    _plugins = <_PluginInstance>[];
    _destroyed = true;
    _listeners.clear();
    caretOpacity.dispose();
  }

  // -- focus and the keyboard --------------------------------------------------------------------------------------

  bool _hasFocus = false;
  bool _composing = false;
  bool _compositionStarted = false;
  VoidCallback? _focusRequest;

  @override
  bool get hasFocus => _hasFocus;

  @override
  bool get composing => _composing;

  @override
  bool get compositionStarted => _compositionStarted;

  /// The input layer says the editor gained or lost the keyboard's focus. The `focusChangeEffect`s are dispatched
  /// and the plugins see `focusChanged`, as when CodeMirror hears `focus` and `blur`.
  void setFocused(bool focused) {
    if (focused == _hasFocus || _destroyed) return;
    _hasFocus = focused;
    _focusChanged = true;
    final effects = <StateEffect<Object?>>[
      for (final source in _state.facet(EditorViewLike.focusChangeEffect))
        ?source(_state, focused),
    ];
    if (effects.isEmpty) {
      _updateWith(const <Transaction>[], flags: 0, notify: true);
    } else {
      dispatch(TransactionSpec(effects: effects));
    }
  }

  /// The input layer says whether the keyboard is composing.
  void setComposing(bool composing, {bool? started}) {
    _composing = composing;
    _compositionStarted = started ?? composing;
  }

  /// What [focus] calls: the input layer's way of taking the keyboard.
  set focusRequest(VoidCallback? request) => _focusRequest = request;

  @override
  void focus() => _focusRequest?.call();

  // -- the selection, drawn ----------------------------------------------------------------------------------------

  @override
  final LayerLink startHandleLink = LayerLink();

  @override
  final LayerLink endHandleLink = LayerLink();

  @override
  final ValueNotifier<double> caretOpacity = ValueNotifier<double>(1);

  @override
  EditorSelectionPainter selectionPainter = const EditorSelectionPainter();

  /// Whether a selection is drawn while the editor has no focus. A caret never is.
  bool selectionWithoutFocus = false;

  /// The part of the selection the line `from`-`to` draws.
  LineSelection selectionFor(int from, int to) {
    final show = _hasFocus || selectionWithoutFocus;
    if (!show) return LineSelection.none;
    final theme = _theme;
    final editable = _state.facet(EditorViewLike.editable);
    final ranges = <(int, int)>[], carets = <(int, int)>[];
    var pastEnd = false;
    int? start, end;
    final main = _state.selection.main;
    for (final range in _state.selection.ranges) {
      if (range.to < from || range.from > to) continue;
      if (range.empty) {
        if (_hasFocus && editable) carets.add((range.head - from, range.assoc == 0 ? 1 : range.assoc));
        continue;
      }
      ranges.add((math.max(range.from, from) - from, math.min(range.to, to) - from));
      if (range.to > to) pastEnd = true;
      if (identical(range, main)) {
        if (range.from >= from) start = range.from - from;
        if (range.to <= to) end = range.to - from;
      }
    }
    if (ranges.isEmpty && carets.isEmpty) return LineSelection.none;
    return LineSelection(
      ranges: ranges,
      carets: carets,
      pastEnd: pastEnd,
      ink: theme?.selectionInk ?? const Color(0xFF000000),
      paper: theme?.selectionPaper ?? const Color(0xFFFFFFFF),
      caretColor: theme?.caret ?? const Color(0xFF000000),
      startHandle: start,
      endHandle: end,
    );
  }

  // -- the lines, built --------------------------------------------------------------------------------------------

  final Set<RenderEditorLine> _lines = <RenderEditorLine>{};
  final Set<RenderEditorBlock> _blockBoxes = <RenderEditorBlock>{};

  @override
  void lineAttached(RenderEditorLine line) => _lines.add(line);

  @override
  void lineDetached(RenderEditorLine line) => _lines.remove(line);

  /// The lines laid out now, in document order.
  List<RenderEditorLine> get lines => _lines.where((line) => line.attached).toList()..sort((a, b) => a.from - b.from);

  /// The laid-out line `pos` is on, or null when it is not laid out (off screen, or under a block widget).
  RenderEditorLine? lineAt(int pos) {
    for (final line in _lines) {
      if (line.attached && line.from <= pos && pos <= line.to) return line;
    }
    return null;
  }

  List<(int, int)> _atomicIn(int from, int to) {
    final sources = _state.facet(EditorViewLike.atomicRanges);
    if (sources.isEmpty) return const <(int, int)>[];
    final found = <(int, int)>[];
    for (final source in sources) {
      source(this).between(from, to, (rangeFrom, rangeTo, _) {
        found.add((rangeFrom, rangeTo));
        return null;
      });
    }
    found.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return found;
  }

  /// What stands directly before entry `line`: nothing (the first thing in the editor), a block widget (its
  /// class), or another line.
  LineContext _contextOf(int line, EntryInfo? info, int to) {
    final doc = _state.doc;
    String? after;
    var first = line == 1;
    if (info != null && info.before.isNotEmpty) {
      after = info.before.last.className ?? '';
      first = false;
    } else if (line > 1) {
      final previous = _blocks.at(_blocks.entryOf(line - 1));
      if (previous != null) {
        if (previous.after.isNotEmpty) {
          after = previous.after.last.className ?? '';
        } else if (previous.replace != null) {
          after = previous.replace!.className ?? '';
        }
      }
    }
    return LineContext(first: first, last: to >= doc.length, after: after);
  }

  /// The widget for the entry that starts at line `line`: its line of text, or the block widget in its place, with
  /// the block widgets before and after. `line` must not be a covered line.
  Widget buildEntry(int line) {
    final look = _look;
    if (look == null) return const SizedBox.shrink();
    final doc = _state.doc;
    final info = _blocks.at(line);
    final first = doc.line(line);
    final lastLine = _blocks.lastLineOf(line);
    final to = lastLine == line ? first.to : doc.line(math.min(lastLine, doc.lines)).to;
    Widget body;
    final replace = info?.replace;
    if (replace != null) {
      body = EditorBlock(view: this, spec: replace);
    } else {
      final source = to == first.to ? first.text : doc.sliceString(first.from, to);
      final projection = LineProjection.build(source, first.from, _decorations, atomic: _atomicIn(first.from, to));
      final spec = LineSpec.resolve(projection, look, _contextOf(line, info, to));
      body = EditorLine(spec: spec, from: first.from, selection: selectionFor(first.from, to), host: this);
    }
    if (info == null || (info.before.isEmpty && info.after.isEmpty)) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final block in info.before) EditorBlock(view: this, spec: block),
        body,
        for (final block in info.after) EditorBlock(view: this, spec: block),
      ],
    );
  }

  // -- positions ---------------------------------------------------------------------------------------------------

  @override
  Rect? coordsAtPos(int pos, [int side = 1]) {
    final line = lineAt(pos);
    if (line != null) {
      final rect = line.coordsAtPos(pos - line.from, side);
      return rect == null ? null : MatrixUtils.transformRect(line.getTransformTo(null), rect);
    }
    for (final block in _blockBoxes) {
      if (!block.attached || !block.hasSize || pos < block.spec.from || pos > block.spec.to) continue;
      final own = block.spec.decoration.widget?.coordsAt(block, pos, side);
      final box = Offset.zero & block.size;
      // A position under a block widget is at its edge, as tall as the widget: the start edge for its first
      // position, the end edge for the rest (CodeMirror flattens the widget's rectangle the same way).
      final rect = own ?? (pos <= block.spec.from ? Rect.fromLTRB(box.left, box.top, box.left, box.bottom) : Rect.fromLTRB(box.right, box.top, box.right, box.bottom));
      return MatrixUtils.transformRect(block.getTransformTo(null), rect);
    }
    return null;
  }

  @override
  int? posAtCoords(Offset global, {bool precise = true}) {
    final hit = hitAt(global);
    if (hit == null || (precise && !hit.inside)) return null;
    return hit.pos;
  }

  /// What a point of the screen is on: the nearest position, the line or block under it, and an inline widget if
  /// the point is on one. Null when nothing is laid out.
  EditorHit? hitAt(Offset global) {
    RenderEditorLine? nearest;
    Offset? nearestLocal;
    var distance = double.infinity;
    for (final line in _lines) {
      if (!line.attached || !line.hasSize) continue;
      final local = line.globalToLocal(global);
      final away = local.dy < 0 ? -local.dy : (local.dy >= line.size.height ? local.dy - line.size.height + 0.001 : 0.0);
      if (away < distance) {
        distance = away;
        nearest = line;
        nearestLocal = local;
      }
    }
    RenderEditorBlock? nearestBlock;
    Offset? blockLocal;
    for (final block in _blockBoxes) {
      if (!block.attached || !block.hasSize) continue;
      final local = block.globalToLocal(global);
      final away = local.dy < 0 ? -local.dy : (local.dy >= block.size.height ? local.dy - block.size.height + 0.001 : 0.0);
      if (away < distance) {
        distance = away;
        nearestBlock = block;
        blockLocal = local;
      }
    }
    if (nearestBlock != null) {
      // On a block widget: its start above the middle, its end below.
      final local = blockLocal!;
      final inside = distance == 0 && local.dx >= 0 && local.dx <= nearestBlock.size.width;
      return EditorHit(pos: local.dy < nearestBlock.size.height / 2 ? nearestBlock.spec.from : nearestBlock.spec.to, inside: inside, block: nearestBlock.spec.decoration.widget);
    }
    if (nearest == null) return null;
    // Above the note's first line is its start, and under its last its end, wherever across the point is
    // (CodeMirror's `posAtCoords`: `yOffset < 0` and `yOffset > docHeight`).
    if (distance > 0 && nearest.from == 0 && nearestLocal!.dy < 0) return EditorHit(pos: 0, inside: false, line: nearest);
    if (distance > 0 && nearest.to >= _state.doc.length && nearestLocal!.dy >= nearest.size.height) return EditorHit(pos: _state.doc.length, assoc: -1, inside: false, line: nearest);
    final hit = nearest.hitAt(nearestLocal!);
    if (hit == null) return null;
    final widget = distance == 0 ? nearest.widgetAt(nearestLocal) : null;
    return EditorHit(pos: nearest.from + hit.pos, assoc: hit.assoc, inside: distance == 0 && hit.inside, line: nearest, widget: widget?.segment.widget);
  }

  // -- measuring and scrolling -------------------------------------------------------------------------------------

  final List<void Function()> _measureRuns = <void Function()>[];
  final List<Object?> _measureKeys = <Object?>[];
  bool _measureScheduled = false;

  @override
  void requestMeasure<T>([MeasureRequest<T>? request]) {
    if (request != null) {
      final key = request.key;
      void run() => request.run(this);
      final at = key == null ? -1 : _measureKeys.indexOf(key);
      if (at >= 0) {
        _measureRuns[at] = run;
      } else {
        _measureRuns.add(run);
        _measureKeys.add(key);
      }
    }
    if (_measureScheduled) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (_destroyed) return;
      final runs = List<void Function()>.of(_measureRuns);
      _measureRuns.clear();
      _measureKeys.clear();
      for (final run in runs) {
        run();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  ScrollTarget? _scrollTarget;
  bool _scrollScheduled = false;
  int _scrollTries = 0;

  /// What scrolls the view: set by the sliver while it is mounted.
  EditorScroller? scroller;

  void _scheduleScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      final target = _scrollTarget;
      if (_destroyed || target == null) return;
      final scroller = this.scroller;
      if (scroller == null) {
        _scrollTarget = null;
        return;
      }
      var margins = EdgeInsets.zero;
      for (final source in _state.facet(EditorViewLike.scrollMargins)) {
        final more = source(this);
        // CodeMirror's `getScrollMargins`: the most any source asks on each side, not their sum. The note's editor
        // asks the foot's smoke clear and so does the keyboard's layer over what the keyboard covers; added, a line
        // typed at the foot stood a second clearance (52px) higher over the keyboard than the page's.
        if (more != null) {
          margins = EdgeInsets.fromLTRB(
            math.max(margins.left, more.left),
            math.max(margins.top, more.top),
            math.max(margins.right, more.right),
            math.max(margins.bottom, more.bottom),
          );
        }
      }
      final again = scroller.reveal(target.clip(_state), margins);
      // A target in a part of the note never measured is found by estimate first, then again once it is laid out.
      if (again && _scrollTries < 3) {
        _scrollTries += 1;
        _scheduleScroll();
        SchedulerBinding.instance.ensureVisualUpdate();
      } else {
        _scrollTries = 0;
        _scrollTarget = null;
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// A block widget in the editor's column: builds the [EditorWidget], keeps what it built while the description
/// compares equal, and lets the view find it for a position.
class EditorBlock extends StatefulWidget {
  const EditorBlock({super.key, required this.view, required this.spec});

  final EditorView view;
  final BlockSpec spec;

  @override
  State<EditorBlock> createState() => _EditorBlockState();
}

class _EditorBlockState extends State<EditorBlock> {
  Widget? _built;
  EditorWidget? _from;

  @override
  void didUpdateWidget(EditorBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.spec.decoration.widget;
    if (_from != null && (next == null || !_from!.compare(next))) {
      _from!.destroy();
      _from = null;
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  void dispose() {
    _from?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final described = widget.spec.decoration.widget;
    if (described == null) return const SizedBox.shrink();
    if (_built == null) {
      _from = described;
      _built = described.build(context);
    }
    return _EditorBlockBox(view: widget.view, spec: widget.spec, child: _built);
  }
}

class _EditorBlockBox extends SingleChildRenderObjectWidget {
  const _EditorBlockBox({required this.view, required this.spec, super.child});

  final EditorView view;
  final BlockSpec spec;

  @override
  RenderEditorBlock createRenderObject(BuildContext context) => RenderEditorBlock(view, spec);

  @override
  void updateRenderObject(BuildContext context, RenderEditorBlock renderObject) => renderObject.spec = spec;
}

/// A block widget's box, known to the view by the range it stands for.
class RenderEditorBlock extends RenderProxyBox {
  RenderEditorBlock(this.view, this.spec);

  final EditorView view;
  BlockSpec spec;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    view._blockBoxes.add(this);
  }

  @override
  void detach() {
    view._blockBoxes.remove(this);
    super.detach();
  }
}
