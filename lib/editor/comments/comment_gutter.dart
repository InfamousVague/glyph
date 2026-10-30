/// The comment glyph beside a line, in its gutter (Matt, 2026-10-30: "When hovering a line show the comment icon in the
/// gutter"). The note's screen puts [CommentGutter] round the box its editor is in, as it puts the + round it
/// (lib/editor/plus/plus_layer.dart), and the glyphs are drawn over the editor, never in its lines, so no word moves.
///
/// - **Where.** In the gutter every line already leaves (`--app-gutter`), at its inner edge, against the words: a
///   note's own column on a phone, the reading column's start on a wide one. Level with the middle of the line's
///   first row, however many rows it wraps to.
/// - **A pointer over a line** of words brings the comment glyph, Comment's own (`message-square-plus`) in the
///   chosen pack and style, in the third ink, the second under the pointer, with "Comment on this line" over it after
///   a rest. It comes and goes in a beat; where the device asks for less motion it is there or not. A press starts a
///   comment on that line as Comment does with nothing selected (lib/comments/ui/note_comments.dart
///   [ScreenComments.start]): after the line's words, the sheet's field open over the note. A selection on that line
///   is what the comment is about instead, as it is for Comment.
/// - **A line with a thread** wears the glyph filled, in the thread's author's colour, with the count of comments
///   in its threads, all the time, a pointer over it or not; a press opens its first open thread (or its first, if
///   all are resolved), whose card has the way to any other. A line whose threads are all resolved wears it faded.
/// - **Not** beside an empty line (the + is there, and there are no words to comment on), the front matter, fenced
///   code (a diagram's, a query's and the comments' own fence are fenced too), a table's rows, or anything drawn as
///   a block of its own (a table, a board, a picture, a summary being written, the transcript folded away): a
///   pointer over those is theirs. Nothing at all while the screen says no ([CommentGutter.allowed]: a canvas, a
///   notebook's index, a meeting's Transcript), nor where there is no pointer: a phone under a finger has the
///   threads' rounds in the words to press. A Fold or a tablet with a mouse has the glyphs from the first move of
///   the mouse until a finger is used again.
/// - **A note that cannot be written in** (the Trash, a read-only share) has no glyph to start a comment, and keeps
///   its threads' filled glyphs, which open them.
///
/// Simple mode has it too: commenting on a line is one of the basics, and the glyph is all there is of it.
///
/// **A heading's fold triangle shares the gutter** (lib/editor/view/section_folds.dart), before the comment glyph: a
/// pointer over a heading that folds brings it as it brings the glyph, a folded heading wears it all the time, and
/// under a finger (where there is no comment glyph) every heading that folds wears it, the gutter's whole square
/// its target. Where the gutter has room for both side by side (a page to read on a wide window) the triangle stands
/// before the glyph's square; where it is one square wide (a phone, the usual column), a heading's square is split,
/// the triangle at its outer edge and the comment glyph, a little smaller, against the words. Never one over the other.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/icon_packs.dart';
import '../../art/lucide.g.dart';
import '../../comments/format.dart';
import '../../comments/ui/card.dart' show hued;
import '../../core/front_matter.dart';
import '../../core/item_syntax.dart' show jsTrim, lineWords;
import '../../shell/wide_screen.dart' show mousePointer;
import '../editor.dart';
import '../view/editor_view.dart';
import '../view/lines.dart' show docLineInFence;
import '../view/section_folds.dart' show FoldTriangle, gutterFolds, toggleFold;
import 'comments.dart' show commentsOf;

/// The glyph arriving and leaving: a beat, quicker than the +'s rise.
const Duration commentGlyphFade = Duration(milliseconds: 120);

/// What "Comment on this line" waits for under a resting pointer, as the band's tips do.
const Duration commentGlyphTipWait = Duration(milliseconds: 450);

/// What the glyph says, to a pointer and to a screen reader.
const String commentGlyphTip = 'Comment on this line';

/// Whether line [number] of [state] can have the glyph that starts a comment: a line of words, outside the front
/// matter, fenced code and a table. What is drawn as a block of its own is told by the view, not the text.
bool commentableLine(EditorState state, int number) {
  final doc = state.doc;
  if (number < 1 || number > doc.lines) return false;
  final text = doc.line(number).text;
  if (lineWords(text).isEmpty) return false;
  if (jsTrim(text).startsWith('|')) return false;
  if (docLineInFence(doc, number)) return false;
  final most = doc.lines < frontMatterLines ? doc.lines : frontMatterLines;
  if (number <= most && number <= frontMatterEnd(<String>[for (var i = 1; i <= most; i += 1) doc.line(i).text])) return false;
  return true;
}

/// The threads anchored on each line of a note, by line number, in the note's order.
Map<int, List<Thread>> threadsByLine(EditorState state) {
  final comments = commentsOf(state.doc);
  if (comments.anchors.isEmpty) return const <int, List<Thread>>{};
  final found = <int, List<Thread>>{};
  for (final anchor in comments.anchors) {
    final thread = threadOf(comments, anchor.id);
    if (thread == null) continue;
    final at = anchor.from < state.doc.length ? anchor.from : state.doc.length;
    (found[state.doc.lineAt(at).number] ??= <Thread>[]).add(thread);
  }
  return found;
}

/// What the fold's triangle says, to a pointer and to a screen reader.
const String foldGlyphTip = 'Fold this section';
const String unfoldGlyphTip = 'Unfold this section';

/// The fold triangle's width beside the comment glyph, from the gutter's square.
double foldGlyphWidth(double box) => (box * 0.42).clamp(9.0, 12.0);

/// What stands in the gutter beside a line.
enum GutterSlot { comment, fold }

/// "1 comment", "3 comments".
String commentCountWords(int count) => count == 1 ? '1 comment' : '$count comments';

/// Draws the glyphs over [child] (the box the editor is in: the page's scroll view) beside the lines of [view].
class CommentGutter extends StatefulWidget {
  const CommentGutter({super.key, required this.view, required this.child, required this.onStart, required this.onOpen, this.allowed, this.colour});

  /// The note's editor; null while there is none yet, when [child] is drawn alone, in the same place in the tree.
  final EditorView? view;

  /// A comment started: on [range], the line's start for the line itself (`ScreenComments.start`).
  final void Function(({int from, int to}) range) onStart;

  /// A thread's card opened.
  final void Function(String id) onOpen;

  /// Whether the screen shows the note's words to comment on now; asked as it is drawn.
  final bool Function()? allowed;

  /// Whose colour a handle wears here (lib/comments/colours.dart); the ink's without.
  final String Function(String handle)? colour;
  final Widget child;

  @override
  State<CommentGutter> createState() => CommentGutterState();
}

class CommentGutterState extends State<CommentGutter> {
  /// Moved to have the glyphs painted again where their lines are now: a scroll, the editor laid out again.
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  /// A pointer that can rest over the screen: a desktop's, or a mouse moved on a phone or a tablet.
  bool _fine = mousePointer;

  /// The line under the pointer that can be commented on, and the line the glyph was last drawn beside (kept
  /// while it fades).
  int? _hover;
  int? _shown;

  Doc? _doc;
  Map<int, List<Thread>> _threads = const <int, List<Thread>>{};

  /// The headings that fold, as the gutter draws them now.
  List<({int line, int from, bool folded})> _folds = const [];

  /// The line the glyph that starts a comment is shown beside now, for a test; null when none is.
  int? get hoveredLine => _canAdd ? _hover : null;

  /// The lines that wear a filled glyph, for a test.
  Iterable<int> get threadLines => _threads.keys;

  /// The headings whose fold triangle is shown now, for a test.
  Iterable<int> get foldLines => [
        if (_foldsShown)
          for (final fold in _folds)
            if (!_fine || fold.folded || fold.line == _hover) fold.line,
      ];

  EditorView? get _view => widget.view;

  bool get _canAdd {
    final view = _view;
    return view != null && view.state.facet(EditorViewLike.editable) && !view.state.readOnly;
  }

  bool get _allowed => _view != null && _fine && (widget.allowed?.call() ?? true);

  /// The fold triangles are drawn under a finger as well as beside a pointer.
  bool get _foldsShown => _view != null && (widget.allowed?.call() ?? true);

  void _read() {
    final view = _view;
    final doc = view?.state.doc;
    _folds = view == null ? const [] : gutterFolds(view.state);
    if (identical(doc, _doc)) return;
    _doc = doc;
    _threads = view == null ? const <int, List<Thread>>{} : threadsByLine(view.state);
  }

  void _viewChanged() {
    if (!mounted) return;
    _repaint.value += 1;
    final view = _view;
    if (identical(view?.state.doc, _doc) && (view == null || listEquals(gutterFolds(view.state), _folds))) return;
    // During a frame's build or layout (the editor tells its listeners of a measure from inside one) this waits for
    // the frame to end.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _viewChanged());
      return;
    }
    setState(() {
      // The lines moved under the pointer: the glyph waits for it to move again.
      _hover = null;
      _shown = null;
      _read();
    });
  }

  @override
  void initState() {
    super.initState();
    _view?.addListener(_viewChanged);
    _read();
  }

  @override
  void didUpdateWidget(CommentGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      oldWidget.view?.removeListener(_viewChanged);
      widget.view?.addListener(_viewChanged);
      _hover = null;
      _shown = null;
      _read();
    }
  }

  @override
  void dispose() {
    _view?.removeListener(_viewChanged);
    _repaint.dispose();
    super.dispose();
  }

  /// The line of words under a point of the screen that a comment can be started on, or null.
  int? _lineUnder(Offset global) {
    final view = _view;
    if (view == null) return null;
    final hit = view.hitAt(global);
    final line = hit?.line;
    if (hit == null || hit.block != null || line == null || !line.attached || !line.hasSize) return null;
    final local = line.globalToLocal(global);
    if (local.dy < 0 || local.dy >= line.size.height || local.dx < 0 || local.dx > line.size.width) return null;
    final state = view.state;
    final number = state.doc.lineAt(line.from).number;
    return commentableLine(state, number) ? number : null;
  }

  void _hovered(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) return;
    final line = _lineUnder(event.position);
    if (_fine && line == _hover) return;
    setState(() {
      _fine = true;
      _hover = line;
      if (line != null) _shown = line;
    });
  }

  void _left() {
    if (_hover == null) return;
    setState(() => _hover = null);
  }

  /// A finger on the screen: the pointer is put away, and so are the glyphs, until it moves again.
  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || mousePointer || !_fine) return;
    setState(() {
      _fine = false;
      _hover = null;
    });
  }

  /// Where the glyph for line [number] stands on the screen: a square [box] wide whose end is the words' start,
  /// level with the middle of the line's first row. Null where the line is not drawn.
  Rect? _placeOf(int number, double box, [GutterSlot kind = GutterSlot.comment]) {
    final view = _view;
    if (view == null || number > view.state.doc.lines) return null;
    final line = view.lineAt(view.state.doc.line(number).from);
    if (line == null || !line.attached || !line.hasSize) return null;
    final rows = line.visualLines;
    final middle = rows.isEmpty ? line.size.height / 2 : (rows.first.top + rows.first.bottom) / 2;
    final at = line.localToGlobal(Offset(0, middle));
    final gutter = view.look?.env.gutter ?? box;
    final square = at.dx + (gutter > box ? gutter - box : 0);
    final top = at.dy - box / 2;
    // A heading beside a pointer has its triangle before the comment glyph's square (see the header).
    if (_fine && _folds.any((each) => each.line == number)) {
      final fold = foldGlyphWidth(box);
      final roomy = gutter >= box + fold;
      if (kind == GutterSlot.fold) return Rect.fromLTWH(roomy ? square - fold : at.dx, top, fold, box);
      if (!roomy) return Rect.fromLTWH(at.dx + fold, top, gutter - fold, box);
    }
    return Rect.fromLTWH(square, top, box, box);
  }

  /// What the page keeps clear above and below the words (the header's glass, the foot's smoke): no glyph is drawn
  /// there, as no glyph would stand over the header.
  EdgeInsets _clear() {
    final view = _view;
    if (view == null) return EdgeInsets.zero;
    var top = 0.0, bottom = 0.0;
    for (final source in view.state.facet(EditorViewLike.scrollMargins)) {
      final margins = source(view);
      if (margins == null) continue;
      if (margins.top > top) top = margins.top;
      if (margins.bottom > bottom) bottom = margins.bottom;
    }
    return EdgeInsets.only(top: top, bottom: bottom);
  }

  void _start(int number) {
    final view = _view;
    if (view == null || number > view.state.doc.lines) return;
    final line = view.state.doc.line(number);
    final main = view.state.selection.main;
    // Words selected on this line are what the comment is about, as they are for Comment; else the line.
    final picked = !main.empty && main.from >= line.from && main.to <= line.to;
    widget.onStart(picked ? (from: main.from, to: main.to) : (from: line.from, to: line.from));
  }

  void _open(List<Thread> threads) {
    final open = threads.where((thread) => thread.resolved == null).firstOrNull ?? threads.first;
    widget.onOpen(open.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = t.len('app-gutter');
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _read();
    final slots = <Widget>[];
    final gutter = _view?.look?.env.gutter ?? box;
    final fold = foldGlyphWidth(box);
    final narrow = gutter < box + fold;
    final foldLines = {for (final each in _folds) each.line};
    // The comment glyph's square, split with a heading's triangle where the gutter is one square wide.
    double commentWidth(int line) => _fine && narrow && foldLines.contains(line) ? gutter - fold : box;
    if (_foldsShown) {
      final view = _view!;
      for (final each in _folds) {
        final shown = !_fine || each.folded || each.line == _hover;
        slots.add(
          _Slot(
            key: ValueKey<String>('fold-gutter-${each.line}'),
            line: each.line,
            kind: GutterSlot.fold,
            width: _fine ? fold : box,
            child: _FoldGlyph(height: box, folded: each.folded, visible: shown, still: still, onPress: () => toggleFold(view, each.from)),
          ),
        );
      }
    }
    if (_allowed) {
      for (final MapEntry(key: line, value: threads) in _threads.entries) {
        final open = threads.where((thread) => thread.resolved == null).toList();
        final count = threads.fold<int>(0, (sum, thread) => sum + 1 + thread.replies.length);
        final hue = widget.colour?.call((open.firstOrNull ?? threads.first).head.by) ?? 'ink';
        slots.add(
          _Slot(
            key: ValueKey<String>('comment-gutter-thread-$line'),
            line: line,
            width: commentWidth(line),
            child: _ThreadGlyph(box: commentWidth(line), count: count, hue: hue, resolved: open.isEmpty, onPress: () => _open(threads)),
          ),
        );
      }
      final shown = _shown;
      if (_canAdd && shown != null && !_threads.containsKey(shown)) {
        slots.add(
          _Slot(
            key: const ValueKey<String>('comment-gutter-add'),
            line: shown,
            width: commentWidth(shown),
            child: _AddGlyph(box: commentWidth(shown), visible: _hover == shown, still: still, onPress: () => _start(shown)),
          ),
        );
      }
    }
    return NotificationListener<ScrollNotification>(
      // The note scrolled: the glyphs go with their lines, in the same frame.
      onNotification: (_) {
        _repaint.value += 1;
        return false;
      },
      child: MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onExit: (_) => _left(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: _hovered,
          onPointerDown: _down,
          child: Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              widget.child,
              Positioned.fill(
                child: _Follower(repaint: _repaint, box: box, place: _placeOf, clear: _clear, children: slots),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glyph that starts a comment (`message-square-plus`), muted, darker under the pointer.
class _AddGlyph extends StatefulWidget {
  const _AddGlyph({required this.box, required this.visible, required this.still, required this.onPress});

  final double box;
  final bool visible;
  final bool still;
  final VoidCallback onPress;

  @override
  State<_AddGlyph> createState() => _AddGlyphState();
}

class _AddGlyphState extends State<_AddGlyph> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = (widget.box - 6).clamp(12.0, 16.0);
    final ink = _over ? t.color('app-ink-2') : t.color('app-ink-3');
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: widget.still ? Duration.zero : commentGlyphFade,
        curve: Curves.easeOut,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: Semantics(
            button: true,
            label: commentGlyphTip,
            onTap: widget.onPress,
            excludeSemantics: true,
            child: _GutterTip(
              message: commentGlyphTip,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _over = true),
                onExit: (_) => setState(() => _over = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onPress,
                  // A long press here is not press and hold's.
                  onLongPress: () {},
                  child: Center(
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: ink),
                      duration: widget.still ? Duration.zero : commentGlyphFade,
                      builder: (context, color, _) => AppIcon(Lucide.messageSquarePlus, size: size, strokeWidth: 2.2, color: color ?? ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading's fold triangle: muted, darker under the pointer; down while open, at the words while folded.
class _FoldGlyph extends StatefulWidget {
  const _FoldGlyph({required this.height, required this.folded, required this.visible, required this.still, required this.onPress});

  final double height;
  final bool folded;
  final bool visible;
  final bool still;
  final VoidCallback onPress;

  @override
  State<_FoldGlyph> createState() => _FoldGlyphState();
}

class _FoldGlyphState extends State<_FoldGlyph> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = (widget.height * 0.42).clamp(8.0, 11.0);
    final ink = _over ? t.color('app-ink-2') : t.color('app-ink-3');
    final said = widget.folded ? unfoldGlyphTip : foldGlyphTip;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: widget.still ? Duration.zero : commentGlyphFade,
        curve: Curves.easeOut,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: Semantics(
            button: true,
            expanded: !widget.folded,
            label: said,
            onTap: widget.onPress,
            excludeSemantics: true,
            child: _GutterTip(
              message: said,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _over = true),
                onExit: (_) => setState(() => _over = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onPress,
                  onLongPress: () {},
                  child: Center(child: FoldTriangle(folded: widget.folded, size: size, color: ink)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line's threads: the bubble filled in the author's colour, the count of their comments in it.
class _ThreadGlyph extends StatefulWidget {
  const _ThreadGlyph({required this.box, required this.count, required this.hue, required this.resolved, required this.onPress});

  final double box;
  final int count;
  final String hue;
  final bool resolved;
  final VoidCallback onPress;

  @override
  State<_ThreadGlyph> createState() => _ThreadGlyphState();
}

class _ThreadGlyphState extends State<_ThreadGlyph> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = (widget.box - 4).clamp(13.0, 18.0);
    final look = IconLook.of(context);
    final fill = hued(t, widget.hue).color('app-space');
    final words = widget.count > 9 ? '9+' : '${widget.count}';
    final said = '${commentCountWords(widget.count)} on this line${widget.resolved ? ', resolved' : ''}';
    return Semantics(
      button: true,
      label: said,
      onTap: widget.onPress,
      excludeSemantics: true,
      child: _GutterTip(
        message: said,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _over = true),
          onExit: (_) => setState(() => _over = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPress,
            onLongPress: () {},
            child: Center(
              child: Opacity(
                opacity: widget.resolved ? (_over ? 0.75 : 0.5) : (_over ? 1 : 0.85),
                child: SizedBox.square(
                  dimension: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      AppIcon(Lucide.messageSquare, size: size, strokeWidth: 2, color: fill, look: IconLook(look.pack, IconStyle.filled)),
                      // In the bubble's body, over its tail: the body is the 24 grid's 3 to 19.
                      Align(
                        alignment: const Alignment(0.08, -0.12),
                        child: Text(
                          words,
                          key: const ValueKey<String>('comment-gutter-count'),
                          maxLines: 1,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: t.textAt(size * (words.length > 1 ? 0.46 : 0.56), weight: 'bold', height: 1, color: t.color('app-paper')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of words over the glyph while a pointer rests on it, from the glyph's start so it is never cut by the
/// window's edge: the band's tip (lib/editor/band/menu_band.dart `BandTip`) for wherever there is a pointer.
class _GutterTip extends StatefulWidget {
  const _GutterTip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<_GutterTip> createState() => _GutterTipState();
}

class _GutterTipState extends State<_GutterTip> {
  final OverlayPortalController _portal = OverlayPortalController(debugLabel: 'comment gutter tip');
  final LayerLink _link = LayerLink();
  Timer? _waiting;

  @override
  void dispose() {
    _waiting?.cancel();
    super.dispose();
  }

  void _enter() {
    _waiting?.cancel();
    _waiting = Timer(commentGlyphTipWait, () {
      if (mounted && Overlay.maybeOf(context) != null) _portal.show();
    });
  }

  void _exit() {
    _waiting?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Listener(
        onPointerDown: (_) => _exit(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: Offset(0, -t.space(1)),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('comment-gutter-tip'),
                    padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                    decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('sm'))),
                    child: Text(widget.message, maxLines: 1, softWrap: false, style: t.textAt(t.fontSize('xs'), weight: 'medium', height: 1.3, color: t.color('app-paper'))),
                  ),
                ),
              ),
            ),
          ),
          child: CompositedTransformTarget(link: _link, child: widget.child),
        ),
      ),
    );
  }
}

/// A glyph and the line it stands beside.
class _Slot extends ParentDataWidget<_SlotData> {
  const _Slot({super.key, required this.line, required this.width, this.kind = GutterSlot.comment, required super.child});

  final int line;

  /// How wide its place is: the gutter's square, or less beside a heading's triangle.
  final double width;
  final GutterSlot kind;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _SlotData;
    if (data.line == line && data.width == width && data.kind == kind) return;
    final wider = data.width != width;
    data
      ..line = line
      ..width = width
      ..kind = kind;
    if (wider) renderObject.parent?.markNeedsLayout();
    renderObject.parent?.markNeedsPaint();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _Follower;
}

class _SlotData extends ContainerBoxParentData<RenderBox> {
  int line = 0;
  double width = 0;
  GutterSlot kind = GutterSlot.comment;
  bool drawn = false;
}

/// Puts each glyph beside its line's row, wherever the editor has it now.
class _Follower extends MultiChildRenderObjectWidget {
  const _Follower({required this.repaint, required this.box, required this.place, required this.clear, required super.children});

  final Listenable repaint;
  final double box;
  final Rect? Function(int line, double box, GutterSlot kind) place;
  final EdgeInsets Function() clear;

  @override
  RenderCommentGutter createRenderObject(BuildContext context) => RenderCommentGutter(repaint: repaint, box: box, place: place, clear: clear);

  @override
  void updateRenderObject(BuildContext context, RenderCommentGutter renderObject) {
    renderObject
      ..repaint = repaint
      ..box = box
      ..place = place
      ..clear = clear;
  }
}

/// Fills the box over the editor and lays each glyph out a gutter square, placed at its line as it paints: the
/// editor is asked where the line is each time, so a scroll moves the glyphs in the same frame and none is drawn
/// beside the place its line last stood.
class RenderCommentGutter extends RenderBox with ContainerRenderObjectMixin<RenderBox, _SlotData>, RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  RenderCommentGutter({required Listenable repaint, required double box, required this.place, required this.clear}) : _repaint = repaint, _box = box;

  Listenable _repaint;
  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  double _box;
  set box(double value) {
    if (value == _box) return;
    _box = value;
    markNeedsLayout();
  }

  Rect? Function(int line, double box, GutterSlot kind) place;
  EdgeInsets Function() clear;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    for (var child = firstChild; child != null; child = (child.parentData! as _SlotData).nextSibling) {
      final width = (child.parentData! as _SlotData).width;
      child.layout(BoxConstraints.tight(Size(width > 0 ? width : _box, _box)));
    }
  }

  /// Where the glyphs may be: the box less what the page keeps clear.
  Rect _room() {
    final margins = clear();
    return Rect.fromLTRB(0, margins.top, size.width, size.height - margins.bottom);
  }

  /// Every glyph put at its line: drawn where its line is drawn, inside the room.
  void _placeAll(Rect room) {
    for (var child = firstChild; child != null; child = (child.parentData! as _SlotData).nextSibling) {
      final data = child.parentData! as _SlotData;
      final rect = attached ? place(data.line, _box, data.kind) : null;
      if (rect == null) {
        data.drawn = false;
        continue;
      }
      final at = globalToLocal(rect.topLeft);
      data.offset = at;
      final middle = at.dy + _box / 2;
      data.drawn = middle >= room.top && middle <= room.bottom;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    final room = _room();
    _placeAll(room);
    context.pushClipRect(needsCompositing, offset, room, (context, offset) {
      for (var child = firstChild; child != null; child = (child.parentData! as _SlotData).nextSibling) {
        final data = child.parentData! as _SlotData;
        if (data.drawn) context.paintChild(child, offset + data.offset);
      }
    });
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (firstChild == null) return false;
    final room = _room();
    if (!room.contains(position)) return false;
    _placeAll(room);
    for (var child = lastChild; child != null; child = (child.parentData! as _SlotData).previousSibling) {
      final data = child.parentData! as _SlotData;
      if (!data.drawn) continue;
      final glyph = child;
      final hit = result.addWithPaintOffset(offset: data.offset, position: position, hitTest: (result, position) => glyph.hitTest(result, position: position));
      if (hit) return true;
    }
    return false;
  }
}
