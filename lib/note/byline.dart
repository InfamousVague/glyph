/// Who wrote a note: each author's mark, then their names, "By matt and Claude". A port of
/// `src/app/authors/Byline.tsx` with `Byline.module.css`, placed as the note's screen places it
/// (`NoteScreen.module.css` `.byline`: in the note's own column, over its first line), and of the two readers of
/// `src/app/core/authors.ts` it needs ([authorsOf], [isKnownAi]).
///
/// A person is their initial in a ring. An AI the app knows draws its sign, a spark, the same for every AI; one it
/// doesn't know, its initial. Nothing is drawn for a note with no authors, which is the person's own. Everyone is
/// named, but no more than four marks are drawn.
///
/// What differs: `core/authors.ts` also writes authors (`withAuthor`) and names an AI from an MCP client; those
/// come with the connector and the AI (stages 7 and 8). The reading look's wider start (`.page[data-look='reading']
/// > .byline`) is taken as [NoteByline.start].
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/front_matter.dart';
import '../sheet/css.dart';

final RegExp _quoted = RegExp(r'''^(["'])(.*)\1$''');

/// The note's authors as its front matter names them, `authors: matt, Claude`: in order, none twice (`authorsOf`).
List<String> authorsOf(String body) {
  final said = frontMatterValue(body, 'authors');
  if (said == null || said.isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final part in said.split(',')) {
    final name = part.trim().replaceFirstMapped(_quoted, (m) => m.group(2)!).trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    out.add(name);
  }
  return out;
}

/// The AIs the app knows by name (`KNOWN`, and `AI_AUTHOR`, the name the app's own model signs with).
const List<String> knownAis = ['Ghost', 'Claude', 'ChatGPT', 'Gemini', 'Copilot', 'Cursor'];

/// Whether [name] is an AI the app knows, which wears the spark (`isKnownAi`).
bool isKnownAi(String name) => knownAis.any((known) => known.toLowerCase() == name.toLowerCase());

/// Names as a sentence says them: "a", "a and b", "a, b and c" (`spoken`).
String spokenNames(List<String> names) {
  if (names.length <= 1) return names.isEmpty ? '' : names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

class NoteByline extends StatelessWidget {
  const NoteByline({super.key, required this.authors, this.start});

  final List<String> authors;

  /// The column's own left edge, where it is not the page's gutter (a page to read, from 600px).
  final double? start;

  @override
  Widget build(BuildContext context) {
    if (authors.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final gutter = t.len('app-gutter');
    // `.mark { font-size: 0.85em; inline-size: 1.5em; block-size: 1.5em }`
    final markEm = 0.85 * sm;
    final ring = 1.5 * markEm;
    final shown = authors.take(4).toList();
    return Padding(
      // `.byline { padding-inline: var(--app-gutter); margin-block: var(--glacier-space-2) 0 }`
      padding: EdgeInsets.only(left: start ?? gutter, right: gutter, top: t.space(2)),
      child: Semantics(
        label: 'Written by ${spokenNames(authors)}',
        child: ExcludeSemantics(
          // `display: flex; align-items: center; gap: 0.5em; font-size: sm; color: var(--glacier-text-muted)`
          child: Row(
            spacing: 0.5 * sm,
            children: [
              // `.mark + .mark { margin-inline-start: -0.35em }`: each tucks under the one before.
              SizedBox(
                width: ring + (shown.length - 1) * (ring - 0.35 * markEm),
                height: ring,
                child: Stack(
                  children: [
                    for (final (at, name) in shown.indexed) Positioned(left: at * (ring - 0.35 * markEm), top: 0, child: _AuthorMark(key: ValueKey('author:$name'), name: name, ring: ring, em: markEm)),
                  ],
                ),
              ),
              // `.names { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`
              Flexible(
                child: Text('By ${spokenNames(authors)}', key: const ValueKey('byline-names'), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('glacier-text-muted'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One author's mark: an AI's spark, or a person's initial, in a ring.
class _AuthorMark extends StatelessWidget {
  const _AuthorMark({super.key, required this.name, required this.ring, required this.em});
  final String name;
  final double ring;
  final double em;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = isKnownAi(name);
    final ink = t.color('glacier-text'), paper = t.color('glacier-bg');
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
    return Container(
      width: ring,
      height: ring,
      alignment: Alignment.center,
      // `border: 1px solid var(--glacier-border-strong); background: var(--glacier-bg)`, and for an AI the ink.
      decoration: BoxDecoration(shape: BoxShape.circle, color: ai ? ink : paper, border: Border.all(color: ai ? ink : t.color('glacier-border-strong'), width: snapBorder(context, 1))),
      child: ai
          ? CustomPaint(size: const Size.square(12), painter: _SparkPainter(paper))
          // `.initial { line-height: 1 }`, `font-weight: semibold`
          : Text(initial, style: t.textAt(em, weight: 'semibold', color: ink, height: 1)),
    );
  }
}

/// A spark of eight tapering rays: the sign an AI author wears (`Spark`).
class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()..color = color;
    // `M12 12 L11.1 3.6 Q12 2.2 12.9 3.6 Z`, turned eight times round the middle.
    final ray = Path()
      ..moveTo(12, 12)
      ..lineTo(11.1, 3.6)
      ..quadraticBezierTo(12, 2.2, 12.9, 3.6)
      ..close();
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(12, 12);
      canvas.rotate(i * math.pi / 4);
      canvas.translate(-12, -12);
      canvas.drawPath(ray, paint);
      canvas.restore();
    }
    canvas.drawCircle(const Offset(12, 12), 1.6, paint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color;
}

/// A note's authors as their marks alone, each tucked under the one before, for a list's row: as many whole marks
/// as the room it is given holds, [most] at the most, and none where there is no room for one. The port's own (Matt,
/// 2026-10-12: "if space is available show the avatar icons for editors of a note"); the marks are the byline's.
class AuthorMarks extends StatelessWidget {
  const AuthorMarks({super.key, required this.authors, required this.em, this.most = 3});

  final List<String> authors;

  /// The size of the text it stands beside; a mark is 0.85 of it, in a ring half as wide again.
  final double em;
  final int most;

  @override
  Widget build(BuildContext context) {
    final markEm = 0.85 * em;
    final ring = 1.5 * markEm;
    return ExcludeSemantics(
      child: WholeMarks(
        step: ring - 0.35 * markEm,
        children: [for (final name in authors.take(most)) _AuthorMark(key: ValueKey('author:$name'), name: name, ring: ring, em: markEm)],
      ),
    );
  }
}

/// Children in a row, each [step] on from the one before, of which only those that fit whole in the width allowed
/// are drawn. It asks for the width of them all.
class WholeMarks extends MultiChildRenderObjectWidget {
  const WholeMarks({super.key, required this.step, super.children});
  final double step;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWholeMarks(step);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderWholeMarks).step = step;
}

class _WholeData extends ContainerBoxParentData<RenderBox> {}

class _RenderWholeMarks extends RenderBox with ContainerRenderObjectMixin<RenderBox, _WholeData>, RenderBoxContainerDefaultsMixin<RenderBox, _WholeData> {
  _RenderWholeMarks(this._step);

  double _step;
  set step(double value) {
    if (value == _step) return;
    _step = value;
    markNeedsLayout();
  }

  /// How many of the children are drawn.
  int _shown = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WholeData) child.parentData = _WholeData();
  }

  double get _one => firstChild?.getMaxIntrinsicWidth(double.infinity) ?? 0;
  double _across(int count) => count <= 0 ? 0 : _one + (count - 1) * _step;
  int _fits(double width) {
    var count = 0;
    while (count < childCount && _across(count + 1) <= width + 0.01) {
      count += 1;
    }
    return count;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _across(childCount);

  @override
  double computeMinIntrinsicHeight(double width) => firstChild?.getMaxIntrinsicHeight(double.infinity) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(_across(_fits(constraints.maxWidth)), computeMinIntrinsicHeight(0)));

  @override
  void performLayout() {
    var height = 0.0, at = 0;
    for (var child = firstChild; child != null; child = childAfter(child), at += 1) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      (child.parentData! as _WholeData).offset = Offset(at * _step, 0);
      if (child.size.height > height) height = child.size.height;
    }
    _shown = _fits(constraints.maxWidth);
    size = constraints.constrain(Size(_across(_shown), height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var at = 0;
    for (var child = firstChild; child != null && at < _shown; child = childAfter(child), at += 1) {
      context.paintChild(child, offset + (child.parentData! as _WholeData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;
}

/// [first], and [then] after it only in the room [first] leaves: [first] is as wide as it wants, up to the whole
/// width, and [then] is given what is left past a [gap]. Its baseline is [first]'s.
class ThenIfRoom extends MultiChildRenderObjectWidget {
  ThenIfRoom({super.key, required Widget first, required Widget then, this.gap = 0, this.toEnd = false}) : super(children: [first, then]);
  final double gap;

  /// [then] stands at the far edge of the width allowed, not straight after [first].
  final bool toEnd;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderThenIfRoom(gap, toEnd);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderThenIfRoom)
    ..gap = gap
    ..toEnd = toEnd;
}

class _RenderThenIfRoom extends RenderBox with ContainerRenderObjectMixin<RenderBox, _WholeData>, RenderBoxContainerDefaultsMixin<RenderBox, _WholeData> {
  _RenderThenIfRoom(this._gap, this._toEnd);

  bool _toEnd;
  set toEnd(bool value) {
    if (value == _toEnd) return;
    _toEnd = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WholeData) child.parentData = _WholeData();
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => firstChild!.getMaxIntrinsicWidth(height) + _gap + lastChild!.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => firstChild!.getMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => firstChild!.getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => firstChild!.getDistanceToActualBaseline(baseline);

  @override
  void performLayout() {
    final first = firstChild!, then = lastChild!;
    first.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
    final room = math.max(0.0, constraints.maxWidth - first.size.width - _gap);
    then.layout(BoxConstraints(maxWidth: room), parentUsesSize: true);
    final height = math.max(first.size.height, then.size.height);
    (first.parentData! as _WholeData).offset = Offset(0, (height - first.size.height) / 2);
    final shown = then.size.width > 0;
    final atEnd = _toEnd && shown && constraints.maxWidth.isFinite;
    (then.parentData! as _WholeData).offset = Offset(atEnd ? constraints.maxWidth - then.size.width : first.size.width + _gap, (height - then.size.height) / 2);
    size = constraints.constrain(Size(atEnd ? constraints.maxWidth : first.size.width + (shown ? _gap + then.size.width : 0), height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
