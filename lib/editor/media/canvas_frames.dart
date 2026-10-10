/// A canvas in a frame inside a note (Matt: "embed a frame of a canvas within another note so we can browse the
/// canvas from within a frame inside the note"). Ports `src/app/editor/canvasFrames.ts`.
///
///     ![[Cabin weekend, laid out]]
///
/// A line that is only that (a wiki link with `!` before it, which is how Obsidian embeds one note in another) is
/// drawn as the canvas it names, in a frame the note's width and a screen's third tall, browsable as the canvas
/// itself is: a finger or a wheel pans, a pinch or the modifier and wheel zooms, the minimap sits in the corner,
/// and the whole canvas is fitted to the frame to begin with. It is the canvas note's own view
/// (lib/canvas/canvas_view.dart) with no way to change it, so what is drawn is what is on the canvas note now, and
/// a card that is a note draws that note small as it does there. Over the frame, the canvas's name and an Open,
/// which opens the canvas note.
///
/// The line keeps its markdown: with the caret on it the frame steps aside and the line shows as typed, the way a
/// query's fence does, and leaving it draws the frame again. The words are a wiki link like any other
/// (items/wiki_links.dart), so the note reads as a link to the canvas anywhere else, and a title that names no
/// canvas (no note, or a note of words) is left as the link it is.
///
/// A state field, as pictures and queries are: a block widget's height has to be known before layout, and a
/// plugin's decorations cannot say. The document is scanned whole; embeds are rare and notes are short.
///
/// What differs:
/// - **`dark`** is not asked: the canvas reads its colours from the tokens over it, so the app painted the other
///   way draws the frame again by itself. [refreshCanvasFrames] is still what a changed library sends.
/// - **The frame's gestures are the canvas's, never the note's scroll** (`touch-action: none` on the page): the box
///   takes the page's drag for itself, and hands it to nobody, since the canvas hears the finger without it.
/// - A canvas read is kept by its body in a small map, as there, so a keystroke elsewhere in the note does not
///   read every canvas again; the view itself is handed the body, which is what it reads.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../canvas/canvas_view.dart';
import '../../canvas/json_canvas.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/note_face.dart';
import '../view/blocks.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';

/// A line that is only an embed: `![[Title]]`, with whatever `#anchor` the link carries.
final RegExp _frame = RegExp(r'^\s*!\[\[([^\]\n]{1,120})\]\]\s*$');

/// An embed: its line, counting from 1, and the title as written, which is everything before a `#`.
typedef Frame = ({int line, String title});

/// The title a line embeds, when the line is only an embed and its title has words.
String? _titleOf(String text) {
  final match = _frame.firstMatch(text);
  if (match == null) return null;
  final inside = (match.group(1) ?? '').trim();
  final hash = inside.indexOf('#');
  final title = (hash >= 0 ? inside.substring(0, hash) : inside).trim();
  return title.isEmpty ? null : title;
}

/// Every embed in the note, in order (`framesIn`).
List<Frame> framesIn(String doc) {
  final found = <Frame>[];
  final lines = doc.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final title = _titleOf(lines[i]);
    if (title != null) found.add((line: i + 1, title: title));
  }
  return found;
}

/// The title each embedding line embeds, kept for every line of a document (`LineFact`): a letter typed and a
/// caret moved read nothing of the note again for an embed.
final LineFact<String> _frames = LineFact<String>((text) => text.contains('![[') ? _titleOf(text) : null);

/// Whether a document embeds anything: one that does not has no frame to look at again when the library changes.
bool hasFrames(Doc doc) => !_frames.nowhere(doc);

/// What the screen hands the editor for its frames (`FrameOptions`).
class FrameOptions {
  const FrameOptions({required this.body, required this.known, required this.open});

  /// A note's body by its title, or null where there is no note: the canvas is read from it.
  final String? Function(String title) body;

  /// For the canvas's own note cards: whether a note exists, and opening one. [open] also opens the canvas note.
  final bool Function(String title) known;
  final void Function(String title, [String? anchor]) open;
}

/// How tall a frame is, in logical pixels, at most; never under 220, and 42 parts in a hundred of the screen
/// between (`clamp(220px, 42vh, 360px)`).
const double frameHeight = 360;

/// The bar over the frame: its name and the Open.
const double barHeight = 30;

/// Canvas notes read, by body: a keystroke elsewhere in the note must not parse every canvas again.
final Map<String, Canvas?> _parsed = <String, Canvas?>{};

Canvas? _canvasIn(String body) {
  if (_parsed.containsKey(body)) return _parsed[body];
  final canvas = canvasOf(body);
  if (_parsed.length > 32) _parsed.clear();
  return _parsed[body] = canvas;
}

class FrameWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const FrameWidget({required this.title, required this.body, required this.from, required this.options});

  final String title;

  /// The canvas note's body, which is what says whether the frame is the same one.
  final String body;

  /// Where the embed's line starts.
  final int from;
  final FrameOptions options;

  @override
  String get className => 'cm-canvasFrame';

  @override
  bool eq(FrameWidget other) => other.title == title && other.body == body && other.from == from;

  @override
  double get estimatedHeight => frameHeight + barHeight;

  /// Every gesture in the frame is the canvas's: a drag pans it, a wheel too, and the name and Open have their own.
  @override
  bool takesPointer(_) => true;

  @override
  Widget build(BuildContext context) => DrawnFrame(widget: this);
}

/// The frame as it is drawn: its bar, and the canvas in its box.
class DrawnFrame extends StatelessWidget {
  const DrawnFrame({super.key, required this.widget});

  final FrameWidget widget;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.of(context);
    final t = context.tokens;
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    final quiet = t.color('app-ink-3');
    final edge = t.color('glacier-border-subtle');
    final small = 0.86 * em;
    final words = noteFace(t, look, small, color: quiet);
    final options = widget.options;
    final tall = (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, frameHeight);
    return Semantics(
      container: true,
      label: 'Canvas: ${widget.title}',
      child: Padding(
        // '.cm-canvasFrame': { padding: '0.4em var(--app-gutter, 1rem) 0.8em' }
        padding: EdgeInsets.fromLTRB(gutter, layoutUnitFloor(0.4 * em), gutter, layoutUnitFloor(0.8 * em)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // '.cm-canvasFrameBar': { display: 'flex', alignItems: 'center', gap: '0.6em', blockSize: '30px',
            //   padding: '0 0.2em', fontSize: '0.86em', color: 'var(--app-ink-3, var(--glacier-text-muted))' }
            // The Open is a hair taller than the bar at the editor's leading, and stands over its edges as it does
            // on the page, where nothing clips it.
            SizedBox(
              height: barHeight,
              child: OverflowBox(
                maxHeight: barHeight * 2,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 0.2 * small),
                  child: Row(
                    spacing: 0.6 * small,
                    children: [
                      // '.cm-canvasFrameName': { flex: '1', overflow: 'hidden', textOverflow: 'ellipsis',
                      //   whiteSpace: 'nowrap', cursor: 'text' }
                      Expanded(
                        // A press on the name puts the caret on the line: the frame steps aside and the link can be
                        // edited.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => openOnPress(view, widget.from),
                          child: Semantics(
                            tooltip: 'Edit the link',
                            child: Text(widget.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: words),
                          ),
                        ),
                      ),
                      GlacierPressable(
                        semanticLabel: 'Open the canvas ${widget.title}',
                        onPressed: () => options.open(widget.title),
                        // '.cm-canvasFrameOpen': { padding: '0.15em 0.75em',
                        //   border: '1px solid var(--glacier-border-subtle)', borderRadius: '999px', color: 'inherit' }
                        // '.cm-canvasFrameOpen:hover': { color: 'var(--app-ink, currentColor)',
                        //   borderColor: 'color-mix(in oklch, var(--app-ink, currentColor) 40%, transparent)' }
                        builder: (context, state) => DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(side: BorderSide(color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 40%, transparent)') : edge)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 0.15 * small + 1, horizontal: 0.75 * small + 1),
                            child: Text('Open', style: state.hovered ? words.copyWith(color: t.color('app-ink')) : words),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // '.cm-canvasFrameBox': { blockSize: 'clamp(220px, 42vh, 360px)',
            //   border: '1px solid var(--glacier-border-subtle)', borderRadius: 'var(--glacier-radius-lg, 16px)',
            //   overflow: 'hidden', touchAction: 'none' }
            SizedBox(
              height: tall,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.radius('lg')),
                  border: Border.all(color: edge),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.radius('lg')),
                  // The page's own drag, taken here and given to nobody: the canvas hears the finger by itself.
                  child: GestureDetector(
                    onVerticalDragStart: (_) {},
                    onVerticalDragUpdate: (_) {},
                    // The canvas note's own view, with no way to write it: browsable, not changeable.
                    child: CanvasView(
                      body: widget.body,
                      wiki: CanvasWiki(known: options.known, open: options.open, body: options.body),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A note changed: every frame is looked at again, and redrawn where it differs.
final StateEffectType<Null> refreshCanvasFrames = StateEffect.define<Null>();

DecorationSet _build(EditorState state, FrameOptions options) {
  final frames = _frames.of(state.doc);
  if (frames.isEmpty) return Decoration.none;
  final ranges = <Range<Decoration>>[];
  final editable = state.facet(EditorViewLike.editable);
  for (final line in frames) {
    // The caret on the line: the link itself, to edit. Elsewhere, and in a view with no caret, the canvas.
    if (editable && caretIn(state, line.from, line.to)) continue;
    final body = options.body(line.fact);
    if (body == null || _canvasIn(body) == null) continue;
    ranges.add(
      Decoration.replace(
        widget: FrameWidget(title: line.fact, body: body, from: line.from, options: options),
        block: true,
      ).range(line.from, line.to),
    );
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

/// `![[A canvas]]` on a line of its own draws that canvas in a frame.
Extension canvasFrames(FrameOptions options) {
  final field = StateField.define<DecorationSet>(
    create: (state) => _build(state, options),
    update: (decorations, tr) {
      final poked = focusMoved(tr) || tr.effects.any((effect) => effect.isOf(refreshCanvasFrames));
      if (tr.docChanged || tr.selection != null || poked || tr.reconfigured) return _build(tr.state, options);
      return decorations;
    },
    provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field, (value) => value),
  );
  return Extension.list(<Extension>[trackFocus, field]);
}
