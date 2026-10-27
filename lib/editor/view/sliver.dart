/// The editor in a scroll view: a sliver that builds and lays out only the lines on screen. What CodeMirror's
/// `DocView` and `ViewState` do together (@codemirror/view, docview.ts and viewstate.ts): a viewport of real
/// lines, with the height of everything else taken from the height map.
///
/// [EditorSliver] goes in a `CustomScrollView` beside the page's other slivers (the note's title bar, a tape), so
/// the page scrolls the editor as the web's `grow` editor is scrolled by its page. For each layout it asks the
/// view's [HeightMap] which entries the scroll offset and the cache extent reach, tells the view
/// ([EditorView.ensureViewport], which is when the plugins hear the viewport moved), has its element build just
/// those ([EditorView.buildEntry]), lays them out, and writes their real heights back. A line that leaves the
/// screen is unbuilt. Nothing off screen is laid out, so a note of any length scrolls at the cost of a screenful.
///
/// Children are kept by the number of their first line and follow the document's changes
/// ([EditorView.takeChanges]): text typed above a line moves its child, state and layout with it rather than
/// drawing every line below again.
///
/// What differs from CodeMirror: there are no gap elements standing in for what is not built (the sliver's
/// geometry says how long the note is), and when lines above the screen turn out taller or shorter than their
/// estimate the difference is taken out of the scroll offset in the same layout (`scrollOffsetCorrection`), where
/// CodeMirror scrolls the page afterwards (`scrollAnchorPos`).
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../perf/frame_log.dart' show Perf, ghostPerf;
import '../looks/look.dart';
import 'editor_view.dart';
import 'entry_shade.dart';
import 'plugin.dart';

/// The editor as a sliver. `env` is the sizes and tokens it is drawn with: the page's own unless given.
class EditorSliver extends StatelessWidget {
  const EditorSliver({super.key, required this.view, this.env, this.sheets = const <LookSheet>[], this.meHue});

  final EditorView view;

  /// What the stylesheets read; the page's own sizes at the tokens above when null.
  final LookEnv? env;

  /// Stylesheets of the host's own, over the extensions'.
  final List<LookSheet> sheets;

  /// The hue the person wears, for the selection (`data-me-hue`).
  final String? meHue;

  @override
  Widget build(BuildContext context) {
    final env = this.env ?? LookEnv.page(context.tokens, devicePixelRatio: MediaQuery.devicePixelRatioOf(context), meHue: meHue, tabSize: view.state.tabSize);
    view.setEnv(env, more: sheets);
    // Put out of sight by the page (a note drawn as a canvas, or as a notebook's index, keeps its words' editor
    // under a `SliverOffstage`, which lays its sliver out all the same): nothing is built for a sliver nobody sees.
    final unseen = context.findAncestorWidgetOfExactType<SliverOffstage>()?.offstage ?? false;
    return EditorViewScope(view: view, child: _RawEditorSliver(view: view, look: view.look!, unseen: unseen));
  }
}

class _RawEditorSliver extends RenderObjectWidget {
  const _RawEditorSliver({required this.view, required this.look, this.unseen = false});

  final EditorView view;
  final Look look;
  final bool unseen;

  @override
  _EditorSliverElement createElement() => _EditorSliverElement(this);

  @override
  RenderSliverEditor createRenderObject(BuildContext context) => RenderSliverEditor(view)..unseen = unseen;

  @override
  void updateRenderObject(BuildContext context, RenderSliverEditor renderObject) {
    renderObject
      ..view = view
      ..unseen = unseen;
  }
}

class _EditorSliverElement extends RenderObjectElement {
  _EditorSliverElement(_RawEditorSliver super.widget);

  /// The built entries, by first line, and where each started in the document when it was built.
  final Map<int, Element> _children = <int, Element>{};
  final Map<int, int> _from = <int, int>{};

  /// What the view keeps of each built entry, to build it again for less (`EditorView.buildEntry`).
  final Map<int, EntryKeep> _kept = <int, EntryKeep>{};

  EditorView get _view => (widget as _RawEditorSliver).view;

  @override
  RenderSliverEditor get renderObject => super.renderObject as RenderSliverEditor;

  void _changed() {
    if (mounted) markNeedsBuild();
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject._element = this;
    _view.addListener(_changed);
    _view.scroller = renderObject;
  }

  @override
  void unmount() {
    _view.removeListener(_changed);
    if (identical(_view.scroller, renderObject)) _view.scroller = null;
    renderObject._element = null;
    super.unmount();
  }

  @override
  void update(_RawEditorSliver newWidget) {
    final old = widget as _RawEditorSliver;
    super.update(newWidget);
    if (!identical(old.view, newWidget.view)) {
      old.view.removeListener(_changed);
      if (identical(old.view.scroller, renderObject)) old.view.scroller = null;
      newWidget.view.addListener(_changed);
      newWidget.view.scroller = renderObject;
      // Another view's lines: nothing built is this one's.
      for (final line in _children.keys.toList()) {
        updateChild(_children[line], null, line);
      }
      _children.clear();
      _from.clear();
      _kept.clear();
    }
    performRebuild();
  }

  /// Moves the built entries to the lines they are on after the document's changes; one whose line is gone, or
  /// covered now, is unbuilt.
  void _follow() {
    final changes = _view.takeChanges();
    if (changes == null && _children.keys.every((line) => line <= _view.state.doc.lines && !_view.blocks.isCovered(line))) return;
    final doc = _view.state.doc;
    final moved = <int, Element>{}, from = <int, int>{};
    final kept = <int, EntryKeep>{};
    for (final entry in _children.entries.toList()..sort((a, b) => a.key - b.key)) {
      final was = _from[entry.key]!;
      final at = changes == null ? was : changes.mapPos(was, -1);
      final line = at > doc.length ? null : doc.lineAt(at);
      if (line == null || line.from != at || moved.containsKey(line.number) || _view.blocks.isCovered(line.number)) {
        updateChild(entry.value, null, entry.key);
        continue;
      }
      moved[line.number] = entry.value;
      from[line.number] = line.from;
      final keep = _kept[entry.key];
      if (keep != null) kept[line.number] = keep;
      if (line.number != entry.key) updateSlotForChild(entry.value, line.number);
    }
    _children
      ..clear()
      ..addAll(moved);
    _from
      ..clear()
      ..addAll(from);
    _kept
      ..clear()
      ..addAll(kept);
  }

  Widget? _build(int line, DirtyLines dirty) {
    final built = _view.buildEntry(line, keep: _kept[line] ??= EntryKeep(), dirty: dirty);
    return built == null ? null : EditorViewScope(view: _view, child: built);
  }

  /// Builds the built entries again where `dirty` says a line may show something else, where one has moved in the
  /// document, and where the selection on one has changed; the rest are left exactly as they are.
  void _rebuildAll(DirtyLines dirty) {
    for (final line in _children.keys.toList()) {
      final built = _build(line, dirty);
      if (built == null) continue;
      final child = updateChild(_children[line], built, line);
      if (child == null) {
        _children.remove(line);
        _from.remove(line);
        _kept.remove(line);
      } else {
        _children[line] = child;
        _from[line] = _view.state.doc.line(line).from;
      }
    }
  }

  @override
  void performRebuild() {
    super.performRebuild();
    final began = ghostPerf ? Perf.now() : 0;
    _follow();
    _rebuildAll(_view.takeDirty());
    renderObject.markNeedsLayout();
    if (ghostPerf) Perf.add('editor.sliver.rebuilt', began);
  }

  /// Called from layout: makes the built entries exactly `lines`, building what is missing (and everything again
  /// when `all`, the decorations having moved with the viewport).
  void sync(List<int> lines, {required bool all}) {
    owner!.buildScope(this, () {
      // With nothing built yet, every line built here is built from the view as it is now: what the view has
      // noted as changed since it was made (everything, to begin with) is no news to them, and is let go, where
      // it used to have every line of a note just opened built a second time in its second frame.
      final fresh = _children.isEmpty;
      final wanted = lines.toSet();
      for (final line in _children.keys.toList()) {
        if (wanted.contains(line)) continue;
        updateChild(_children[line], null, line);
        _children.remove(line);
        _from.remove(line);
        _kept.remove(line);
      }
      if (all) _rebuildAll(_view.takeDirty());
      for (final line in lines) {
        if (_children.containsKey(line)) continue;
        _kept.remove(line);
        final child = updateChild(null, _build(line, DirtyLines.everywhere), line);
        if (child != null) {
          _children[line] = child;
          _from[line] = _view.state.doc.line(line).from;
        }
      }
      if (fresh && !all) {
        _view.takeDirty();
        _view.takeChanges();
      }
    });
  }

  ScrollPosition? get scrollPosition => Scrollable.maybeOf(this)?.position;

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final child in _children.values.toList()) {
      visitor(child);
    }
  }

  @override
  void forgetChild(Element child) {
    _children.removeWhere((line, element) => identical(element, child));
    _kept.removeWhere((line, _) => !_children.containsKey(line));
    super.forgetChild(child);
  }

  @override
  void insertRenderObjectChild(RenderBox child, int slot) => renderObject._insert(child, slot);

  @override
  void moveRenderObjectChild(RenderBox child, int oldSlot, int newSlot) => renderObject._move(child, newSlot);

  @override
  void removeRenderObjectChild(RenderBox child, int slot) => renderObject._remove(child);
}

class _EntryParentData extends ParentData {
  /// The entry's first line.
  int line = 0;

  /// How far down the sliver it starts.
  double layoutOffset = 0;
}

/// The editor's sliver: see the library's note.
class RenderSliverEditor extends RenderSliver with RenderSliverHelpers implements EditorScroller {
  RenderSliverEditor(this._view);

  /// How many times any editor sliver was laid out, for a test to count.
  static int layouts = 0;

  EditorView _view;
  EditorView get view => _view;
  set view(EditorView value) {
    if (identical(value, _view)) return;
    _view = value;
    markNeedsLayout();
  }

  /// Whether what holds the sliver keeps it out of sight: no line is built or laid out for it, and it takes no
  /// room. The page's own words were built and laid out under a canvas and under a notebook's index, and again on
  /// every change to either, for nobody.
  bool _unseen = false;
  bool get unseen => _unseen;
  set unseen(bool value) {
    if (value == _unseen) return;
    _unseen = value;
    markNeedsLayout();
  }

  _EditorSliverElement? _element;
  final List<RenderBox> _kids = <RenderBox>[];

  static _EntryParentData _data(RenderBox child) => child.parentData! as _EntryParentData;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _EntryParentData) child.parentData = _EntryParentData();
  }

  void _insert(RenderBox child, int line) {
    adoptChild(child);
    _data(child).line = line;
    _kids.add(child);
  }

  void _move(RenderBox child, int line) {
    _data(child).line = line;
    markNeedsLayout();
  }

  void _remove(RenderBox child) {
    _kids.remove(child);
    _dims.remove(child)?.layer = null;
    dropChild(child);
  }

  RenderBox? _childAt(int line) {
    for (final child in _kids) {
      if (_data(child).line == line) return child;
    }
    return null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final child in _kids) {
      child.attach(owner);
    }
  }

  @override
  void detach() {
    super.detach();
    for (final child in _kids) {
      child.detach();
    }
    // Listened to again at the next paint, if it is ever attached again.
    _letShadesGo();
  }

  @override
  void redepthChildren() {
    for (final child in _kids) {
      redepthChild(child);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    for (final child in List<RenderBox>.of(_kids)) {
      visitor(child);
    }
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() => <DiagnosticsNode>[for (final child in _kids) child.toDiagnosticsNode(name: 'line ${_data(child).line}')];

  /// The entries (first lines) from the one at `first` to the one at `last`.
  List<int> _entries(int first, int last) {
    final blocks = _view.blocks;
    final lines = <int>[];
    for (var n = first; n <= last; n = blocks.lastLineOf(n) + 1) {
      lines.add(n);
    }
    return lines;
  }

  @override
  void performLayout() {
    if (!ghostPerf) return _layOut();
    final began = Perf.now();
    _layOut();
    Perf.add('editor.sliver.laidOut', began);
  }

  void _layOut() {
    layouts += 1;
    final c = constraints;
    assert(c.axis == Axis.vertical && c.growthDirection == GrowthDirection.forward, 'The editor scrolls down the page.');
    final look = _view.look;
    final element = _element;
    if (look == null || element == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    if (_unseen) {
      if (_kids.isNotEmpty) invokeLayoutCallback<SliverConstraints>((_) => element.sync(const <int>[], all: false));
      geometry = SliverGeometry.zero;
      return;
    }
    final heights = _view.heights;
    final width = c.crossAxisExtent;
    if (heights.width != width) {
      final base = look.line(LookElement(null));
      final inner = math.max(1.0, width - base.insetX);
      heights
        ..charsPerLine = math.max(1, inner / math.max(1, look.measure(<(String, RunLook)>[('0000000000', base.base)]) / 10))
        ..invalidate(width, again: heights.width < 0 ? _view.state.doc : null);
      // What an entry above covers has no height, whatever its length.
      _view.blocks.forEachCovered(heights.cover);
    }
    final top = look.env.contentTop, bottom = look.env.contentBottom;
    final wantFrom = math.max(0.0, c.scrollOffset + c.cacheOrigin - top);
    final wantTo = math.max(0.0, c.scrollOffset + c.cacheOrigin + c.remainingCacheExtent - top);
    final anchor = _view.blocks.entryOf(heights.lineAt(math.max(0.0, c.scrollOffset - top)));
    final anchorTop = heights.offsetOf(anchor);

    var lines = const <int>[];
    var changedAny = false;
    for (var pass = 0; pass < 6; pass++) {
      final blocks = _view.blocks;
      final first = blocks.entryOf(heights.lineAt(wantFrom)), last = blocks.entryOf(heights.lineAt(wantTo));
      final moved = _view.ensureViewport(first, last);
      lines = _entries(first, last);
      invokeLayoutCallback<SliverConstraints>((_) => element.sync(lines, all: moved));
      var changed = false;
      for (final line in lines) {
        final child = _childAt(line);
        if (child == null) continue;
        child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
        if (heights.setMeasured(line, child.size.height)) changed = true;
      }
      if (!changed) break;
      changedAny = true;
    }
    for (final child in _kids) {
      _data(child).layoutOffset = top + heights.offsetOf(_data(child).line);
    }

    // Lines above the screen were not as tall as they were taken to be: what is on screen stays where it was.
    if (c.scrollOffset > 0) {
      final delta = heights.offsetOf(anchor) - anchorTop;
      if (delta.abs() > 0.01) {
        geometry = SliverGeometry(scrollOffsetCorrection: delta);
        if (changedAny) _view.measured();
        return;
      }
    }
    final total = top + heights.total + bottom;
    final paintExtent = calculatePaintOffset(c, from: 0, to: total);
    final cacheExtent = calculateCacheOffset(c, from: 0, to: total);
    geometry = SliverGeometry(
      scrollExtent: total,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: total,
      hitTestExtent: paintExtent,
      hasVisualOverflow: total > c.remainingPaintExtent || c.scrollOffset > 0,
    );
    if (changedAny) _view.measured();
  }

  @override
  double childMainAxisPosition(RenderBox child) => _data(child).layoutOffset - constraints.scrollOffset;

  @override
  double childCrossAxisPosition(RenderBox child) => 0;

  @override
  double? childScrollOffset(RenderObject child) => _data(child as RenderBox).layoutOffset;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) => applyPaintTransformForBoxChild(child as RenderBox, transform);

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    final box = BoxHitTestResult.wrap(result);
    for (final child in _kids.reversed) {
      if (hitTestBoxChild(box, child, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition)) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final began = ghostPerf ? Perf.now() : 0;
    final extent = constraints.remainingPaintExtent;
    final shades = _shadesNow();
    for (final child in _kids) {
      final y = childMainAxisPosition(child);
      // What is wholly off the painted stretch is left out; the cache keeps it built.
      if (y < extent && y + child.size.height > 0) {
        final at = offset + Offset(0, y);
        final opacity = shades.isEmpty ? 1.0 : _opacityOf(child, shades);
        if (opacity >= 1) {
          _dims.remove(child)?.layer = null;
          context.paintChild(child, at);
        } else if (opacity > 0) {
          // An entry focus mode dims (lib/editor/view/entry_shade.dart): through a layer of its own, kept from frame
          // to frame of a fade.
          final handle = _dims[child] ??= LayerHandle<OpacityLayer>();
          handle.layer = context.pushOpacity(at, (opacity * 255).round(), (context, at) => context.paintChild(child, at), oldLayer: handle.layer);
        }
      }
    }
    if (ghostPerf) Perf.add('editor.sliver.painted', began);
  }

  // -- shades ------------------------------------------------------------------------------------------------------

  /// The layers of the entries drawn dimmed, by entry.
  final Map<RenderBox, LayerHandle<OpacityLayer>> _dims = <RenderBox, LayerHandle<OpacityLayer>>{};

  /// The shades this sliver listens to, so a fade's next frame paints it again.
  final Set<EntryShade> _heard = <EntryShade>{};

  /// The view's shades now, listened to; the ones it has let go of no longer.
  List<EntryShade> _shadesNow() {
    final shades = <EntryShade>[
      for (final source in _view.state.facet(entryShades)) ?source(_view),
    ];
    if (shades.isEmpty && _heard.isEmpty) return shades;
    for (final gone in _heard.where((shade) => !shades.contains(shade)).toList()) {
      gone.removeListener(_shadeChanged);
      _heard.remove(gone);
    }
    for (final shade in shades) {
      if (_heard.add(shade)) {
        shade.addListener(_shadeChanged);
        // Heard first while it already dims (the sliver attached again under a dimmed page): composited from the
        // next frame, its bits being settled for this one.
        if (shade.dims) SchedulerBinding.instance.addPostFrameCallback((_) => attached ? _shadeChanged() : null);
      }
    }
    if (shades.isEmpty) {
      for (final handle in _dims.values) {
        handle.layer = null;
      }
      _dims.clear();
    }
    return shades;
  }

  double _opacityOf(RenderBox child, List<EntryShade> shades) {
    final first = _data(child).line;
    final last = _view.blocks.lastLineOf(first);
    var opacity = 1.0;
    for (final shade in shades) {
      opacity *= shade.opacityOf(first, last);
    }
    return opacity;
  }

  /// A shade changed: painted again, and composited while any dims, since a dimmed entry is a layer of its own
  /// and a clip above has to be one too to clip it.
  void _shadeChanged() {
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _heard.any((shade) => shade.dims);

  void _letShadesGo() {
    for (final shade in _heard) {
      shade.removeListener(_shadeChanged);
    }
    _heard.clear();
    for (final handle in _dims.values) {
      handle.layer = null;
    }
    _dims.clear();
  }

  @override
  void dispose() {
    _letShadesGo();
    super.dispose();
  }

  // -- scrolling into view -----------------------------------------------------------------------------------------

  /// How far down the sliver `pos` is, top or bottom of its text, and whether that was measured or estimated.
  ({double y, bool exact}) _down(int pos, {required bool bottom}) {
    final line = _view.lineAt(pos);
    final rect = line?.coordsAtPos(pos - line.from, 1);
    if (line != null && rect != null) {
      final here = MatrixUtils.transformRect(line.getTransformTo(this), rect);
      return (y: (bottom ? here.bottom : here.top) + constraints.scrollOffset, exact: true);
    }
    final look = _view.look!;
    final entry = _view.blocks.entryOf(_view.state.doc.lineAt(pos).number);
    final y = look.env.contentTop + _view.heights.offsetOf(entry);
    return (y: bottom ? y + _view.heights.heightOf(entry) : y, exact: false);
  }

  @override
  bool reveal(ScrollTarget target, EdgeInsets margins) {
    final position = _element?.scrollPosition;
    if (position == null || !attached || _view.look == null) return false;
    final from = _down(target.range.from, bottom: false), to = _down(target.range.to, bottom: true);
    // Where the sliver starts in the scroll view's own offsets.
    final start = position.minScrollExtent + constraints.precedingScrollExtent;
    final room = position.viewportDimension;
    final top = start + from.y - target.yMargin - margins.top, foot = start + to.y + target.yMargin + margins.bottom;
    var pixels = position.pixels;
    switch (target.y) {
      case ScrollStrategy.start:
        pixels = top;
      case ScrollStrategy.end:
        pixels = foot - room;
      case ScrollStrategy.center:
        pixels = (top + foot) / 2 - room / 2;
      case ScrollStrategy.nearest:
        // CodeMirror's `scrollRectIntoView` for "nearest": the range itself is held against the room the margins
        // leave, and `yMargin` is only how far past the edge it is brought once it is out. Counting the margin in
        // the test moved a caret that was in plain sight: a new note's first line went up under the tabs as the
        // keyboard rose, where the page's stays (seen beside the web app on the emulator).
        final rangeTop = start + from.y, rangeFoot = start + to.y;
        final roomTop = pixels + margins.top, roomFoot = pixels + room - margins.bottom;
        final side = target.range.empty ? 0 : (target.range.head == target.range.to ? 1 : -1);
        var move = 0.0;
        if (rangeTop < roomTop) {
          move = rangeTop - (roomTop + target.yMargin);
          if (side > 0 && rangeFoot > roomFoot + move) move = rangeFoot - roomFoot + target.yMargin;
        } else if (rangeFoot > roomFoot) {
          move = rangeFoot - roomFoot + target.yMargin;
          if (side < 0 && rangeTop - move < roomTop) move = rangeTop - (roomTop + target.yMargin);
        }
        pixels += move;
    }
    pixels = pixels.clamp(position.minScrollExtent, math.max(position.minScrollExtent, position.maxScrollExtent));
    if ((pixels - position.pixels).abs() > 0.5) position.jumpTo(pixels);
    return !(from.exact && to.exact);
  }
}
