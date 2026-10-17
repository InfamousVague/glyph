/// Mermaid diagrams, drawn (Matt: "Add support for Mermaid charts"). Ports `src/app/editor/mermaid.ts`.
///
/// A ```mermaid fence is markdown like any other: the text is what is kept, what is edited, and what another app
/// sees. A fence the caret is not in is drawn as the diagram it describes, the way a table is drawn as a table
/// (tables/tables.dart) and a board as a board (boards/boards.dart). Tapping it puts the caret at the fence's first
/// line and the drawing steps aside; leaving it draws it again.
///
/// **Mermaid itself is what draws it**, every diagram type it knows: the release tauri/ pins, in the phone's own
/// web view, off the screen (bridge.dart). It is made the first time a diagram is actually asked for, so a phone
/// that never draws one never pays for it.
///
/// **A diagram that cannot be drawn stays as its own text**, in the typewriter face, exactly as typed, with a quiet
/// line saying why: the diagram written wrong, or nothing here to draw it with. Nothing is ever lost, and nothing
/// spins for ever.
///
/// **In the app's two inks.** On a light page it is Mermaid's own grey theme (`neutral`); a dark page has Mermaid's
/// dark theme.
///
/// What it draws is kept by what it says and how the page is painted (store.dart), and a diagram's height is
/// remembered between launches (height.dart), so the editor knows how tall a diagram is before it has drawn it.
///
/// The pieces: where the fences are, kept with the state (fences.dart); who draws (bridge.dart); what is drawn and
/// what waits (store.dart); how tall (height.dart); and here, the extension and the block.
///
/// What differs:
/// - **The fences are kept, not found again** on every change and every move of the caret (fences.dart), and the
///   blocks drawn are the same set, not only an equal one, across a caret that moved without entering or leaving a
///   diagram.
/// - **`darkField`, `setDark` and `darkWatch` have no counterpart**: the block reads the page's colours from the
///   tokens over it and is built again when they change, and asks for the picture painted the other way then.
/// - **A picture, not an SVG**: made for the width the note has, at the device's ratio. A note shown at another
///   width asks again, once the width has been still for [diagramSettle] (a window being dragged, a phone
///   unfolding), and shows the picture it has, fitted, until the new one comes.
/// - **A block whose words change while it is drawn keeps its picture until the new one is made**, where the page
///   shows the words in between: a web view across a channel takes longer than a library in the page, and the
///   Academy's page, typed into, would flash at every letter. A block drawn before, and waiting only for its
///   picture to be read back, is its remembered height of nothing rather than its words.
/// - `ignoreEvent` left everything but a press to the picture (a wide diagram scrolled sideways); a picture here is
///   never wider than its block, and the block takes its taps.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor.dart';
import '../looks/look.dart';
import '../looks/note_face.dart';
import '../media/inline_box.dart' show InlineWords;
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import 'bridge.dart';
import 'fences.dart';
import 'full_screen.dart';
import 'height.dart';
import 'store.dart';

export 'bridge.dart';
export 'fences.dart';
export 'full_screen.dart';
export 'height.dart';
export 'store.dart';

/// A diagram drawn in place of its fence.
class MermaidWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const MermaidWidget({required this.code, required this.from});

  /// What is between the fences.
  final String code;

  /// Where the fence starts: a tap puts the caret there.
  final int from;

  @override
  String get className => 'cm-mermaid';

  @override
  bool eq(MermaidWidget other) => other.code == code && other.from == from;

  @override
  double get estimatedHeight => guessDiagramHeight(code);

  /// A tap is the block's, to open the fence for editing.
  @override
  bool takesPointer(PointerEvent event) => true;

  @override
  Widget build(BuildContext context) => DrawnDiagram(code: code, from: from);
}

/// A font-family as a stylesheet writes it, from the faces the app ships and the system's own after them.
String _family(List<String> families, {required bool mono}) =>
    <String>[for (final family in families) "'${family.replaceAll("'", '')}'", if (mono) ...const ['ui-monospace', 'monospace'] else ...const ['ui-sans-serif', 'system-ui', 'sans-serif']].join(', ');

/// What decides the picture of `code` drawn `room` wide where `context` is: the page's colours and faces, the
/// note's size and gutter there, the window and the device.
DiagramAsk diagramAsk(BuildContext context, String code, double room) {
  final t = context.tokens;
  final view = EditorViewScope.maybeOf(context);
  final env = view is EditorView ? view.look?.env : null;
  final coding = env?.codingFace ?? false;
  return DiagramAsk(
    code: code,
    dark: env?.dark ?? t.isDark,
    viewport: MediaQuery.sizeOf(context).width,
    room: room,
    gutter: env?.gutter ?? t.len('app-gutter'),
    em: env?.body ?? t.len('app-body'),
    ui: _family(t.families('glacier-font-sans'), mono: false),
    note: _family(env?.noteFamilies ?? t.families('glacier-font-sans'), mono: coding),
    coding: coding,
    ink: env?.ink ?? t.color('glacier-text'),
    // The picture's own pixels: the window's, or what a test whose layout is told another ratio says its
    // picture is taken at (looks/look.dart `debugPaintPixelRatio`).
    ratio: debugPaintPixelRatio ?? MediaQuery.devicePixelRatioOf(context),
  );
}

/// How long a drawn diagram's room has to be still before the picture made for that room is asked for.
const Duration diagramSettle = Duration(milliseconds: 160);

/// The block as it is drawn: the diagram's picture; until there is one, and if there never is, its own text.
class DrawnDiagram extends StatefulWidget {
  const DrawnDiagram({super.key, required this.code, required this.from});

  final String code;
  final int from;

  @override
  State<DrawnDiagram> createState() => DrawnDiagramState();
}

class DrawnDiagramState extends State<DrawnDiagram> {
  /// The picture shown: the one asked for, or the one before it while the one asked for is made.
  DiagramPicture? _picture;

  /// Why there is no picture of what is asked for now.
  DiagramMistake? _mistake;

  /// The key of what is asked for now, and whether its answer is here.
  String? _asked;
  bool _answered = false;

  /// Whether the picture shown is of what the block says now.
  bool get drawn => _picture != null && _answered;

  /// What the block says went wrong, or null.
  String? get failed => _mistake?.said;

  /// What the picture shown was asked with.
  DiagramAsk? _shownFor;

  /// Waiting for the room to stop changing before asking for the picture made for it.
  Timer? _settling;

  void _want(DiagramAsk ask) {
    final key = ask.key;
    if (key == _asked) return;
    _asked = key;
    _answered = false;
    _mistake = null;
    _settling?.cancel();
    _settling = null;
    final store = diagramStore;
    final kept = store.held(ask);
    if (kept != null) {
      store.forget(this);
      _take(kept, ask);
      return;
    }
    final shown = _shownFor;
    if (_picture != null && shown != null && shown.sameButRoom(ask)) {
      // Only the room changed under a picture: a window being dragged, a phone unfolding. Every width on the way is
      // not a picture worth making: the one it has is fitted, and the room's own is asked for once it is still.
      store.forget(this);
      _settling = Timer(diagramSettle, () {
        _settling = null;
        if (mounted && key == _asked) _ask(ask, key);
      });
      return;
    }
    _ask(ask, key);
  }

  void _ask(DiagramAsk ask, String key) {
    diagramStore.draw(ask, slot: this).then((made) {
      // Asked again since, or gone: the answer is somebody else's, or nobody's.
      if (!mounted || made == null || key != _asked) {
        if (made is DiagramPicture) made.dispose();
        return;
      }
      setState(() => _take(made, ask));
    });
  }

  void _take(DiagramDrawing made, DiagramAsk ask) {
    _answered = true;
    _picture?.dispose();
    switch (made) {
      case DiagramPicture():
        _picture = made;
        _shownFor = ask;
        _mistake = null;
        // So the next launch knows how tall this diagram is before drawing it.
        rememberDiagramHeight(widget.code, made.block.height);
      case DiagramMistake():
        _picture = null;
        _shownFor = null;
        _mistake = made;
    }
  }

  @override
  void dispose() {
    _settling?.cancel();
    diagramStore.forget(this);
    _picture?.dispose();
    _picture = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    // A view that cannot be edited keeps the drawing under a tap: there is nothing to type.
    final open = view != null && view.state.facet(EditorViewLike.editable) ? () => openOnPress(view, widget.from) : null;
    final block = LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        if (room.isFinite && room > 0) _want(diagramAsk(context, widget.code, room));
        final picture = _picture;
        if (picture != null) {
          // Its own button to see it full screen (full_screen.dart), over the block's tap that opens the fence.
          return WithFullScreen(
            onFullScreen: () => openDiagramFullScreen(context, ask: _shownFor ?? diagramAsk(context, widget.code, room), shown: picture, label: 'Diagram'),
            child: _DiagramPicture(picture: picture, room: room),
          );
        }
        final known = _mistake == null ? knownDiagramHeight(widget.code) : null;
        // Drawn here before, and on its way back: its room, kept, so the note does not move twice.
        if (known != null) return SizedBox(width: double.infinity, height: known);
        return _text(t, look, em, gutter);
      },
    );
    return Semantics(
      container: true,
      image: true,
      label: 'Diagram',
      child: open == null ? block : GestureDetector(behavior: HitTestBehavior.opaque, onTap: open, child: block),
    );
  }

  /// Not drawn yet, or not drawable: the diagram as it was typed, and a quiet line saying why.
  Widget _text(Tokens t, Look? look, double em, double gutter) {
    final small = 0.86 * em;
    final mistake = _mistake;
    return Padding(
      // '.cm-mermaid': { padding: '0.6em var(--app-gutter, 1rem)' }
      padding: EdgeInsets.symmetric(vertical: layoutUnitFloor(0.6 * em), horizontal: gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // '.cm-mermaidText': { margin: '0', textAlign: 'start', fontFamily: 'var(--glacier-font-mono, …)',
          //   fontSize: '0.86em', lineHeight: 'var(--glacier-leading-md, 1.5)', whiteSpace: 'pre',
          //   overflowX: 'auto', color: 'var(--app-ink-2, currentColor)' }
          // Each line as tall as the rule says, to the sixty-fourth of a pixel (22.5 px at 15.01), with its words
          // where the page's are in it: the text engine's own lines are whole pixels and the leading shared
          // otherwise, and a diagram of ten lines stood five pixels taller than the page's.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: InlineWords(
              widget.code,
              key: const ValueKey<String>('cm-mermaidText'),
              style: t.textAt(small, mono: true, color: t.color('app-ink-2')),
              lineHeight: small * t.len('glacier-leading-md'),
              maxLines: _anyLines,
            ),
          ),
          if (mistake != null)
            // '.cm-mermaidWhy': { margin: '0.4em 0 0', textAlign: 'start', fontSize: '0.86em',
            //   color: 'var(--app-ink-3, currentColor)' }, at the note's own leading (`.cm-scroller`, 1.6).
            Padding(
              padding: EdgeInsets.only(top: layoutUnitFloor(0.4 * small)),
              child: InlineWords(
                mistake.said.isEmpty ? 'This diagram could not be drawn here.' : 'That diagram has a mistake: ${firstLineOf(mistake.said)}',
                key: const ValueKey<String>('cm-mermaidWhy'),
                style: noteFace(t, look, small, color: t.color('app-ink-3')),
                lineHeight: small * 1.6,
                maxLines: _anyLines,
              ),
            ),
        ],
      ),
    );
  }
}

/// As many lines as the words come to: nothing is cut.
const int _anyLines = 1 << 20;

/// The first line of what Mermaid said went wrong: the rest is the diagram drawn in letters, which no one needs
/// here (`firstLine`).
String firstLineOf(String said) {
  final line = said.split('\n').first;
  return line.length > 120 ? line.substring(0, 120) : line;
}

/// A diagram's picture in its block: one image, where the page had it. In a room narrower than the one it was made
/// for (a note turned, a pane dragged) it is fitted, until the picture made for this room comes.
class _DiagramPicture extends StatelessWidget {
  const _DiagramPicture({required this.picture, required this.room});

  final DiagramPicture picture;
  final double room;

  @override
  Widget build(BuildContext context) {
    final block = picture.block, at = picture.at;
    final fit = room.isFinite && room < block.width ? room / block.width : 1.0;
    final across = room.isFinite ? room : block.width;
    return SizedBox(
      height: block.height * fit,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (across - block.width * fit) / 2 + at.left * fit,
            top: at.top * fit,
            width: at.width * fit,
            height: at.height * fit,
            child: RawImage(key: const ValueKey<String>('cm-mermaidPicture'), image: picture.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
        ],
      ),
    );
  }
}

DecorationSet _build(EditorState state) {
  final blocks = state.field(diagramBlocks);
  if (blocks.isEmpty) return Decoration.none;
  final ranges = <Range<Decoration>>[];
  final editable = state.facet(EditorViewLike.editable);
  for (final block in blocks) {
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the diagram.
    if ((editable && caretIn(state, block.from, block.to)) || block.code.trim().isEmpty) continue;
    ranges.add(Decoration.replace(widget: MermaidWidget(code: block.code, from: block.from), block: true).range(block.from, block.to));
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

/// Whether the same diagrams step aside for the caret in two states with the same diagrams.
bool _sameOpen(List<DiagramBlock> blocks, EditorState before, EditorState after) {
  for (final block in blocks) {
    if (caretIn(before, block.from, block.to) != caretIn(after, block.from, block.to)) return false;
  }
  return true;
}

final StateField<DecorationSet> _mermaidField = StateField.define<DecorationSet>(
  create: _build,
  update: (decorations, tr) {
    final blocks = tr.state.field(diagramBlocks);
    if (identical(blocks, tr.startState.fieldOrNull(diagramBlocks)) && !tr.reconfigured) {
      // No diagram was made, moved or changed. A note with none has nothing to do; one with some has only to see
      // whether the caret went into a diagram or out of one.
      if (blocks.isEmpty) return decorations;
      if (!(tr.selection != null || focusMoved(tr))) return decorations;
      if (_sameOpen(blocks, tr.startState, tr.state)) return decorations;
    }
    return _build(tr.state);
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// The diagrams drawn in `state` now: one block for each fence the caret is not in.
DecorationSet drawnMermaidIn(EditorState state) => state.fieldOrNull(_mermaidField) ?? Decoration.none;

/// ```mermaid fences drawn as their diagrams wherever the caret is not in them (`drawnMermaid()`).
Extension drawnMermaid() => Extension.list(<Extension>[trackFocus, diagramBlocks, _mermaidField]);
