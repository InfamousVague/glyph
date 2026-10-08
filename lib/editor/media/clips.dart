/// Voice memos in a note, playable where they sit. Ports `src/app/editor/clips.ts`.
///
/// A clip is markdown (clip_refs.dart): `![voice 0:12](tape:12000-19500)`, a stretch of the note's own tape. A
/// small player stands in its place: on its own line after a "- " it reads as a bullet with a player,
/// mid-sentence as a segment in the words (Matt: "allow for voice memos to be left as a bullet point or inline
/// audio segment"). The mark itself comes back on the line the caret is on, so it can still be read, moved or
/// deleted.
///
/// Only one plays at a time. Without a tape to play, a note whose recording was since removed or replaced, there
/// is no player at all: the clip is a quiet mark saying a memo was left here, and nothing to press.
///
/// What differs:
/// - THE SOUND IS A SEAM. The page made one `<audio>` per clip and watched its time to stop at the clip's end;
///   here a [ClipPlayer] is told to play a stretch of the tape and says what is sounding, through the facet
///   [clipPlayer]. With none, a memo with a tape is still drawn as its player, and a press does nothing. "Only one
///   plays at a time" is the player's own: it has one voice.
/// - The theme's rules are drawn by the widget, each cited where it is drawn. A `title` (why a quiet mark is
///   quiet, that a memo could not be played) is the widget's semantic hint; `cursor` and
///   `-webkit-tap-highlight-color` have no counterpart.
/// - A quiet mark in a list item is drawn whole. On the page the item's hanging `text-indent` is inherited by the
///   mark's box and moves its words left over its border, narrowing the pill by the hang (the bug links.ts fixed
///   on its own pill with `text-indent: 0`); seen in this piece's page fixtures, and not copied.
/// - The caret's line is asked of the selection whether or not the view has focus, exactly as on the page: a note
///   just opened, its caret at 0, shows a memo on its first line as written with the player after it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor.dart';
import '../looks/look.dart';
import '../view/editor_view.dart';
import '../view/line.dart' show EditorRunScope;
import 'clip_refs.dart';
import 'inline_box.dart';

/// The note's recording: where it is played from, and which tape it is (clip_refs.dart `TapeIds.tapeId`).
@immutable
class Tape {
  const Tape({this.src, this.id});

  final String? src;
  final String? id;

  static const Tape none = Tape();

  @override
  bool operator ==(Object other) => other is Tape && other.src == src && other.id == id;

  @override
  int get hashCode => Object.hash(src, id);
}

final Facet<Tape, Tape> tapeSource = Facet.define<Tape, Tape>(
  combine: (values) {
    for (final value in values) {
      if (value.src != null && value.src!.isNotEmpty) return value;
    }
    return Tape.none;
  },
  compare: (a, b) => a == b,
);

/// What plays a stretch of a recording. It has one voice: playing one clip stops any other. It tells its
/// listeners whenever what is sounding changes.
abstract class ClipPlayer implements Listenable {
  /// What is sounding now, or null.
  ({String src, Clip clip})? get playing;

  /// Plays `clip`'s stretch of the recording at `src`, from its start, and stops at its end. Completes with an
  /// error when it cannot be played.
  Future<void> play(String src, Clip clip);

  /// Stops what is sounding.
  void stop();
}

/// The player the editor's memos are played with: the first one given, or none.
final Facet<ClipPlayer, ClipPlayer?> clipPlayer = Facet.define<ClipPlayer, ClipPlayer?>(combine: (values) => values.isEmpty ? null : values.first);

/// A memo's player, or its quiet mark.
class ClipWidget extends EditorWidget {
  const ClipWidget(this.clip, this.src);

  final Clip clip;
  final String? src;

  @override
  bool eq(ClipWidget other) => other.clip.startMs == clip.startMs && other.clip.endMs == clip.endMs && other.src == src;

  @override
  bool takesPointer(_) => src != null;

  @override
  Widget build(BuildContext context) => _ClipBox(clip: clip, src: src, player: src == null ? null : EditorViewScope.maybeOf(context)?.state.facet(clipPlayer));
}

class _ClipBox extends StatefulWidget {
  const _ClipBox({required this.clip, required this.src, required this.player});

  final Clip clip;
  final String? src;
  final ClipPlayer? player;

  @override
  State<_ClipBox> createState() => _ClipBoxState();
}

class _ClipBoxState extends State<_ClipBox> {
  bool _failed = false;

  bool get _playing {
    final now = widget.player?.playing;
    return now != null && now.src == widget.src && now.clip.startMs == widget.clip.startMs && now.clip.endMs == widget.clip.endMs;
  }

  @override
  void initState() {
    super.initState();
    widget.player?.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ClipBox old) {
    super.didUpdateWidget(old);
    if (identical(old.player, widget.player)) return;
    old.player?.removeListener(_changed);
    widget.player?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.player?.removeListener(_changed);
    // A memo that leaves the note while it sounds is stopped.
    if (_playing) widget.player?.stop();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Plays the clip's stretch, or stops it.
  void _toggle() {
    final player = widget.player, src = widget.src;
    if (player == null || src == null) return;
    if (_playing) {
      player.stop();
      return;
    }
    if (_failed) setState(() => _failed = false);
    unawaited(
      player.play(src, widget.clip).catchError((Object _) {
        if (mounted) setState(() => _failed = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final view = EditorViewScope.maybeOf(context);
    final env = view is EditorView ? view.look?.env : null;
    final around = scope?.look.fontSize ?? t.len('app-body');
    final length = clipLength(widget.clip);
    final quiet = widget.src == null;
    // '.cm-clip': { display: 'inline-flex', alignItems: 'center', gap: '0.4em', verticalAlign: '-0.15em',
    //   margin: '0 0.15em', padding: '0.1em 0.7em 0.1em 0.5em', border: '1.5px solid var(--app-ink, currentColor)',
    //   borderRadius: '999px', background: 'none', color: 'var(--app-ink, var(--glacier-text))', font: 'inherit',
    //   fontSize: '0.78em' }
    // '.cm-clipQuiet': { borderStyle: 'dashed', borderColor: 'var(--app-ink-3, currentColor)',
    //   color: 'var(--app-ink-3, var(--glacier-text-muted))', cursor: 'default', paddingInline: '0.7em' }
    final size = around * 0.78;
    final ink = t.color(quiet ? 'app-ink-3' : 'app-ink');
    final face = (scope?.look.style ?? t.textAt(size, mono: true)).copyWith(fontSize: size, color: ink, decoration: TextDecoration.none);
    final border = env?.border(1.5) ?? 1.5;
    final lineHeight = size * (scope?.look.props.lineHeight ?? 1.6);
    final padTop = size * 0.1, padStart = size * (quiet ? 0.7 : 0.5), padEnd = size * 0.7;
    // '.cm-clipLength': { fontVariantNumeric: 'tabular-nums' }
    final words = InlineWords(
      quiet ? 'voice $length' : length,
      key: ValueKey<String>(quiet ? 'cm-clipQuiet-words' : 'cm-clipLength'),
      style: quiet ? face : face.copyWith(fontFeatures: <FontFeature>[...?face.fontFeatures, const FontFeature.tabularFigures()]),
      lineHeight: lineHeight,
    );
    // '.cm-clipMark': { display: 'inline-block', inlineSize: '0.7em', blockSize: '0.8em',
    //   background: 'currentColor', clipPath: 'polygon(0 0, 100% 50%, 0 100%)' }
    // '.cm-clip[data-state="playing"] .cm-clipMark': { clipPath: 'polygon(0 0, 35% 0, 35% 100%, 0 100%, 0 0,
    //   65% 0, 100% 0, 100% 100%, 65% 100%, 65% 0)' }
    final markHeight = layoutUnit(size * 0.8);
    final content = layoutUnitFloor(lineHeight);
    // An inline-flex box takes its baseline from its first item: the words', for the quiet mark; and for the
    // player the mark's foot, since a box with no words in it has no baseline of its own.
    final area = contentArea(face);
    final baseline = quiet
        ? border + padTop + ((content - (area.ascent + area.descent)) / 2).floorToDouble() + area.ascent
        : border + padTop + (content - markHeight) / 2 + markHeight;
    final box = CustomPaint(
      key: ValueKey<String>(quiet ? 'cm-clipQuiet' : 'cm-clip'),
      painter: _PillPainter(ink: ink, width: border, dashed: quiet),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(border + padStart, border + padTop, border + padEnd, border + padTop),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!quiet) ...<Widget>[
              CustomPaint(key: const ValueKey<String>('cm-clipMark'), size: Size(layoutUnit(size * 0.7), markHeight), painter: _ClipMark(ink, playing: _playing)),
              SizedBox(width: layoutUnit(size * 0.4)),
            ],
            words,
          ],
        ),
      ),
    );
    final placed = InlineRaise(
      by: -size * 0.15,
      from: baseline,
      child: Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.15), child: box),
    );
    if (quiet) {
      return Semantics(label: 'voice $length', hint: 'The recording this was a piece of is not on this note any more.', child: ExcludeSemantics(child: placed));
    }
    return Semantics(
      button: true,
      label: _playing ? 'Stop this voice memo, $length' : 'Play this voice memo, $length',
      hint: _failed ? 'This voice memo couldn’t be played.' : null,
      onTap: _toggle,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggle, child: ExcludeSemantics(child: placed)),
    );
  }
}

/// A triangle for still, two bars while it plays: the only two states it has.
class _ClipMark extends CustomPainter {
  const _ClipMark(this.ink, {required this.playing});

  final Color ink;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink;
    if (playing) {
      canvas
        ..drawRect(Rect.fromLTWH(0, 0, size.width * 0.35, size.height), paint)
        ..drawRect(Rect.fromLTWH(size.width * 0.65, 0, size.width * 0.35, size.height), paint);
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ClipMark old) => old.ink != ink || old.playing != playing;
}

/// The pill's border: solid, or dashed for the quiet mark.
class _PillPainter extends CustomPainter {
  const _PillPainter({required this.ink, required this.width, required this.dashed});

  final Color ink;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = ink;
    final rect = (Offset.zero & size).deflate(width / 2);
    final pill = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    if (!dashed) {
      canvas.drawRRect(pill, paint);
      return;
    }
    // A dashed border's dashes are three times its width, its gaps about as long, set evenly round the box.
    final path = Path()..addRRect(pill);
    for (final metric in path.computeMetrics()) {
      final count = (metric.length / (width * 6)).round().clamp(1, 1000);
      final step = metric.length / count;
      for (var i = 0; i < count; i++) {
        canvas.drawPath(metric.extractPath(i * step, i * step + step / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PillPainter old) => old.ink != ink || old.width != width || old.dashed != dashed;
}

/// The player in place of the mark, since the sound is the content and `![voice 0:12](tape:12000-19500)` in the
/// middle of a sentence is noise. The mark comes back on the line the caret is on, so it can be read, moved or
/// deleted like any other text.
DecorationSet _decorate(EditorState state) {
  final builder = RangeSetBuilder<Decoration>();
  final src = state.facet(tapeSource);
  final carets = state.selection.ranges;
  for (var n = 1; n <= state.doc.lines; n += 1) {
    final line = state.doc.line(n);
    if (!line.text.contains('](tape:')) continue;
    final showing = carets.any((range) => range.from <= line.to && range.to >= line.from);
    for (final clip in clipsIn(line.text)) {
      final from = line.from + clip.from;
      final to = line.from + clip.to;
      // A memo of a tape the note no longer has is drawn, not played: its times mean nothing on another
      // recording.
      final play = playsOn(clip, src.id) ? src.src : null;
      final widget = ClipWidget(Clip(startMs: clip.startMs, endMs: clip.endMs, tape: clip.tape), play);
      if (showing) {
        builder.add(to, to, Decoration.widget(widget: widget, side: 1));
      } else {
        builder.add(from, to, Decoration.replace(widget: widget));
      }
    }
  }
  return builder.finish();
}

final StateField<DecorationSet> _clipField = StateField.define<DecorationSet>(
  create: _decorate,
  update: (value, tr) {
    final caretMoved = tr.selection != null || tr.docChanged;
    return caretMoved || tr.startState.facet(tapeSource) != tr.state.facet(tapeSource) ? _decorate(tr.state) : value;
  },
  provide: (field) => Extension.list(<Extension>[
    EditorViewLike.decorations.from<DecorationSet>(field),
    // A hidden mark is one thing to the caret and to a delete, not twenty characters of markdown.
    EditorViewLike.atomicRanges.of((view) => view.state.field(field)),
  ]),
);

/// Voice memos drawn and played in the editor, from the note's recording as [tapeSource] names it.
Extension clips() => _clipField;
