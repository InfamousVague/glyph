/// One card on the canvas, drawn by its kind where the file puts it, in the canvas's own pixels: a group's dashed
/// box and name; a card of words, which is the note's own editor; a link; one of Ghost.md's own pictures; or a note
/// by its file, drawn small. A port of `src/app/canvas/Card.tsx`, with `Near.tsx` and the cards' rules of
/// CanvasView.module.css.
///
/// Opened to be written in, a card of words becomes the note's editor in its own mode with the words going
/// straight into the canvas, and a group's name becomes a field. Its ring, its handles and what can be done to it
/// are the picked card's (selection.dart), drawn over it by the canvas.
///
/// What differs from the web:
/// - A card takes no taps of its own. The web's cards carried `data-card` and `data-card-title` for the canvas to
///   find under a press and opened themselves on a click; here the canvas asks the geometry ([cardTitleBox],
///   [groupNameBox]) and opens what a tap opens (canvas_view.dart `_tap`). Only an open editor and an open name
///   field take presses themselves.
/// - A group's name is a child of the world beside its box, not inside it: above the box is outside it, and a box
///   takes no presses outside itself.
/// - `Near.tsx` watched each card against the screen (`IntersectionObserver`, 300px of margin); the view works out
///   which cards are near from the camera and tells each ([CanvasCard.near]). Once made, a card's words stay made.
/// - A card of words is `MarkdownView`'s lines (lib/editor/markdown_view.dart) set as CanvasView.module.css
///   `.words.words` sets the peek: no cap on the height, and the card's ink, not the peek's grey. `MarkdownView`
///   has no way to be asked for either, so [CardWords] is its few lines again with those two changed.
/// - A chart is drawn as its diagram, read and open (`<Editor … diagrams />`: lib/editor/diagrams); a film card's
///   `videos` mode is not taken.
/// - `editedBy`, another member's ring and handle on a card they have open, is the team canvas's (piece 6G).
/// - Each card is a layer of its own (a [RepaintBoundary] under its place in the world): the page gave each card
///   its own compositing where it promoted one, and here it is what lets a pan or a pinch set the cards down again
///   without drawing one of them, and a card carried or written in be drawn alone.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Canvas, Decoration;
import 'package:glacier/glacier.dart';

import '../core/images.dart';
import '../core/short_url.dart';
import '../editor/diagrams/diagrams.dart' show drawnMermaid;
import '../editor/editor.dart';
import '../editor/editor_widget.dart';
import '../editor/items/items.dart' show itemExtensions;
import '../editor/looks/look.dart';
import '../editor/looks/peek_look.dart';
import '../editor/media/media.dart' show MediaSeams, mediaExtensions;
import '../editor/placeholder.dart';
import '../editor/tables/tables.dart' show drawnTables;
import '../editor/view/base.dart';
import '../editor/view/column.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/view_mode.dart';
import '../home/note_peek.dart';
import '../perf/frame_log.dart';
import '../sheet/css.dart';
import 'camera.dart';
import 'card_looks.dart';
import 'geometry.dart';
import 'json_canvas.dart';
import 'paint.dart';
import 'world.dart';

/// What a canvas asks of the notes round it (`CanvasWiki`).
class CanvasWiki {
  const CanvasWiki({required this.known, required this.open, this.body, this.titles});

  /// Whether a note by that title exists: a note card is drawn as a note, or as one waiting to be written.
  final bool Function(String title) known;

  /// Opens the note by that title, at an anchor when the card names one.
  final void Function(String title, [String? at]) open;

  /// The note's body by title, for drawing it small on its card; null where the note is not there.
  final String? Function(String title)? body;

  /// Every note's title, for choosing one to put on the canvas as a card.
  final List<String> Function()? titles;
}

// ---- where a card's parts are, for the canvas's presses ---------------------------------------------------------

TextStyle _titleStyle(Tokens t, {Color? color}) => t.textAt(t.fontSize('md'), weight: 'semibold', height: 1.25, color: color);

/// A link's or a note's title on its card, in the canvas's pixels (`[data-card-title]`): the card's width inside
/// its padding, and as tall as the title's lines.
BoxOf? cardTitleBox(Tokens t, CanvasNode node) {
  if (node.type != NodeType.link && node.type != NodeType.file) return null;
  final pad = t.space(3) + t.len('glacier-hairline');
  final width = node.width - pad * 2;
  if (width <= 0) return null;
  final words = node.type == NodeType.link ? shortUrl(node.url) : fileTitle(node.file);
  final painter = TextPainter(text: TextSpan(text: words, style: _titleStyle(t)), textDirection: TextDirection.ltr)..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return BoxOf(node.x + pad, node.y + pad, width, height);
}

TextStyle _nameStyle(Tokens t, {required bool named, Color? color}) {
  final size = t.fontSize('sm');
  return pageText(t, size, weight: named ? 'semibold' : 'regular', color: color, tracking: 0.02 * size);
}

/// What a group's name says: its label, or a faint "Group" while it is picked and has none; null for no name.
String? groupNameWords(CanvasNode node, {required bool selected}) => node.label ?? (selected ? 'Group' : null);

/// A group's name above its corner, in the canvas's pixels: what a group is taken by, with its border
/// (`[data-group-grip]`). On a canvas that can change it has room round it for a finger.
BoxOf? groupNameBox(Tokens t, CanvasNode node, {required bool editable, required bool selected}) {
  final words = groupNameWords(node, selected: selected);
  if (!node.isGroup || words == null) return null;
  final painter = TextPainter(text: TextSpan(text: words, style: _nameStyle(t, named: node.label != null)), textDirection: TextDirection.ltr, maxLines: 1)..layout();
  final line = t.len('glacier-hairline');
  final padX = editable ? t.space(2) : 0.0;
  final padY = editable ? t.space(1) : 0.0;
  final width = painter.width + padX * 2;
  final height = painter.height + padY * 2;
  painter.dispose();
  // `left: space-2; bottom: 100%; margin-block-end: space-1`, and on a canvas that can change `margin: 0 -space-2 0`.
  final left = node.x + line + (editable ? 0 : t.space(2));
  final bottom = node.y + line - (editable ? 0 : t.space(1));
  return BoxOf(left, bottom - height, width, height);
}

// ---- the card ------------------------------------------------------------------------------------------------

/// A card's children in the world: its box, and a group's name beside it.
class CanvasCard {
  const CanvasCard({
    required this.node,
    this.wiki,
    this.pictures,
    this.near = true,
    this.editable = false,
    this.editing = false,
    this.lifted = false,
    this.selected = false,
    this.lineFrom = false,
    this.onWrite,
    this.onName,
    this.own,
    this.camera,
  });

  final CanvasNode node;

  /// The view's camera, where the card is in a view that is moved by hand: the card is held still while the view is
  /// zoomed (world.dart `ZoomStill`).
  final CanvasCamera? camera;
  final CanvasWiki? wiki;
  final PictureStore? pictures;

  /// Near the screen, or has been: its words are drawn. A blank until then.
  final bool near;
  final bool editable;

  /// Open to be written in.
  final bool editing;

  /// Lifted by a held press and following the finger.
  final bool lifted;
  final bool selected;

  /// The card a line being drawn starts from.
  final bool lineFrom;
  final void Function(String id, String text)? onWrite;

  /// A group's name written.
  final void Function(String id, String label)? onName;

  /// Wraps what takes its own presses (an open editor, a name's field), so the canvas leaves them alone.
  final Widget Function(Widget child)? own;

  List<Widget> build(BuildContext context) {
    if (ghostPerf) Perf.count('canvas.card');
    final t = context.tokens;
    final at = Offset(node.x, node.y);
    final size = Size(node.width, node.height);
    final key = ValueKey('card ${node.id}');
    if (node.isGroup) {
      final name = groupNameBox(t, node, editable: editable, selected: selected);
      final line = t.len('glacier-hairline');
      return [
        Placed(key: key, at: at, size: size, child: RepaintBoundary(child: _Lift(lifted: lifted, child: _GroupBox(node: node, solid: editing)))),
        if (editing && onName != null)
          Placed(
            key: ValueKey('name ${node.id}'),
            at: Offset(node.x + line, node.y + line),
            anchor: Alignment.bottomLeft,
            child: _own(_NameField(node: node, onName: onName!)),
          )
        else if (name != null)
          Placed(
            key: ValueKey('name ${node.id}'),
            at: Offset(name.x, name.y),
            size: Size(name.width, name.height),
            child: RepaintBoundary(child: _GroupName(node: node, selected: selected, editable: editable)),
          ),
      ];
    }
    final Widget box = _Lift(
      lifted: lifted,
      child: _CardBox(node: node, lineFrom: lineFrom, table: !editing && node.type == NodeType.text && isOnlyTable(node.text), child: _content(context)),
    );
    final camera = this.camera;
    return [
      Placed(
        key: key,
        at: at,
        size: size,
        child: RepaintBoundary(child: camera == null ? box : ZoomStill(camera: camera, on: !lifted && !editing, child: box)),
      ),
    ];
  }

  Widget _own(Widget child) => own?.call(child) ?? child;

  Widget _content(BuildContext context) {
    switch (node.type) {
      case NodeType.text:
        if (editing) return _own(_CardEditor(key: ValueKey('editor ${node.id}'), node: node, onWrite: onWrite));
        return near ? CardWords(markdown: node.text, pictures: pictures) : const SizedBox.expand();
      case NodeType.link:
        return _LinkWords(node: node);
      case NodeType.file:
        final own = ownPicture(node);
        final store = pictures;
        if (own != null && store != null) {
          return ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final picture = store.pictureOf(own);
              return picture == null ? _FileWords(node: node, wiki: wiki, near: near) : _PictureFill(picture: picture);
            },
          );
        }
        return _FileWords(node: node, wiki: wiki, near: near);
      case NodeType.group:
        return const SizedBox.shrink();
    }
  }
}

/// `.card[data-lifted], .group[data-lifted]`: a little larger and off the page.
class _Lift extends StatelessWidget {
  const _Lift({required this.lifted, required this.child});
  final bool lifted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!lifted) return child;
    return Transform.scale(
      scale: 1.02,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.tokens.radius('lg')),
          boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 10), blurRadius: 28)],
        ),
        child: child,
      ),
    );
  }
}

/// `.card`: a box with a hairline, the page's ground, and its hue - when it has one - on the line and a wash of
/// the ground.
class _CardBox extends StatelessWidget {
  const _CardBox({required this.node, required this.lineFrom, required this.table, required this.child});
  final CanvasNode node;
  final bool lineFrom;
  final bool table;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final paint = paintOf(node.color);
    final line = t.len('glacier-hairline');
    final radius = BorderRadius.circular(t.radius('lg'));
    final border = paint == null ? t.color('glacier-border-subtle') : spaceColor(t, 'color-mix(in oklch, var(--app-space) 55%, transparent)', paint);
    final ground = paint == null ? t.color('glacier-bg') : spaceOver(t, paint, 0.07, 'glacier-bg');
    final picture = ownPicture(node) != null;
    Widget box = DecoratedBox(
      decoration: BoxDecoration(color: ground, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          // `.card[data-only='table']` and `.pictureCard` have no padding; the border is still the card's.
          padding: EdgeInsets.all(table || picture ? line : line + t.space(3)),
          child: DefaultTextStyle(style: t.textAt(t.fontSize('md'), color: t.color('glacier-text')), child: child),
        ),
      ),
    );
    box = CustomPaint(foregroundPainter: _BorderPainter(color: border, width: line, radius: t.radius('lg')), child: box);
    if (!lineFrom) return box;
    // `.card[data-line-from] { outline: 2px solid var(--app-ink); outline-offset: 2px }`
    return CustomPaint(foregroundPainter: _BorderPainter(color: t.color('app-ink'), width: 2, radius: t.radius('lg') + 4, outset: 3), child: box);
  }
}

/// A border as a stylesheet draws one: inside the box, or [outset] outside it for an outline; dashed for a group.
class _BorderPainter extends CustomPainter {
  const _BorderPainter({required this.color, required this.width, required this.radius, this.outset = 0, this.dashed = false});
  final Color color;
  final double width;
  final double radius;

  /// How far outside the box the middle of the line runs.
  final double outset;
  final bool dashed;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final inset = outset == 0 ? -width / 2 : outset;
    final rect = (Offset.zero & size).inflate(inset);
    final round = RRect.fromRectAndRadius(rect, Radius.circular((radius + inset).clamp(0, double.infinity)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    if (!dashed) {
      canvas.drawRRect(round, paint);
      return;
    }
    // `border-style: dashed`: dashes three of its widths long, as far apart.
    final path = Path()..addRRect(round);
    final dash = width * 3;
    for (final metric in path.computeMetrics()) {
      final count = (metric.length / (dash * 2)).round().clamp(1, 100000);
      final step = metric.length / count;
      for (var i = 0; i < count; i += 1) {
        canvas.drawPath(metric.extractPath(i * step, i * step + step / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BorderPainter old) => old.color != color || old.width != width || old.radius != radius || old.outset != outset || old.dashed != dashed;
}

/// `.group`: a wash and a dashed line around the cards it holds.
class _GroupBox extends StatelessWidget {
  const _GroupBox({required this.node, required this.solid});
  final CanvasNode node;

  /// Open to be named: `border-style: solid`.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final paint = paintOf(node.color);
    final radius = t.radius('lg') + 4;
    return CustomPaint(
      foregroundPainter: _BorderPainter(
        color: spaceColor(t, 'color-mix(in oklch, var(--app-space, var(--app-ink)) 35%, transparent)', paint),
        width: t.len('glacier-hairline'),
        radius: radius,
        dashed: !solid,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: spaceColor(t, 'color-mix(in oklch, var(--app-space, var(--app-ink)) 4%, transparent)', paint), borderRadius: BorderRadius.circular(radius)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// `.groupLabel`: the group's name above its top-left corner, as Obsidian puts it.
class _GroupName extends StatelessWidget {
  const _GroupName({required this.node, required this.selected, required this.editable});
  final CanvasNode node;
  final bool selected;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final named = node.label != null;
    final color = named ? spaceOver(t, paintOf(node.color), 0.8, 'glacier-text-muted') : t.color('glacier-text-subtle');
    return Padding(
      padding: editable ? EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)) : EdgeInsets.zero,
      child: Text(groupNameWords(node, selected: selected) ?? '', maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: _nameStyle(t, named: named, color: color)),
    );
  }
}

/// `.groupField`: a group's name being written. Handed on when the field is left, or on Enter.
class _NameField extends StatefulWidget {
  const _NameField({required this.node, required this.onName});
  final CanvasNode node;
  final void Function(String id, String label) onName;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _words = TextEditingController(text: widget.node.label ?? '');
  late final FocusNode _focus = FocusNode(debugLabel: 'canvas group name')..addListener(_left);
  bool _had = false;

  @override
  void initState() {
    super.initState();
    // The field takes the keyboard as it appears; the canvas had it, so it is asked for rather than waited for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _left() {
    if (_focus.hasFocus) {
      _had = true;
    } else if (_had) {
      _had = false;
      widget.onName(widget.node.id, _words.text);
    }
  }

  @override
  void dispose() {
    // Taken away while it was being written in (Done naming, a tap elsewhere): what was written is the name.
    if (_had) {
      final words = _words.text;
      final id = widget.node.id;
      final tell = widget.onName;
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(id, words));
    }
    _focus
      ..removeListener(_left)
      ..dispose();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('1rem');
    final style = pageText(t, size, color: t.color('app-ink'));
    return Semantics(
      label: 'The group’s name',
      textField: true,
      child: Container(
        width: 12 * size + 0.7 * size * 2,
        constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
        padding: EdgeInsets.symmetric(horizontal: 0.7 * size, vertical: 0.2 * size),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: t.color('glacier-bg'),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
        ),
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: _words,
              builder: (context, _) => _words.text.isEmpty ? Text('Name this group', maxLines: 1, style: style.copyWith(color: t.color('glacier-text-subtle'))) : const SizedBox.shrink(),
            ),
            EditableText(
              controller: _words,
              focusNode: _focus,
              style: style,
              cursorColor: t.color('app-ink'),
              backgroundCursorColor: t.color('glacier-text-subtle'),
              onSubmitted: (_) => _focus.unfocus(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines of a card's words. CanvasView.module.css `.words`: the note's editor the way a home card draws one
/// (the type at a fraction of the note's size, the editor's grounds made transparent) but the whole text, not a
/// few lines, in the card's own ink, filling the card and clipped by it.
LookEnv cardEnv(Tokens t, {double devicePixelRatio = 2}) {
  final scale = peekScale(t);
  return LookEnv(
    t: t,
    body: t.fontSize('lg') * scale,
    headings: <double>[for (final step in const ['3xl', '2xl', 'xl', 'lg', 'lg', 'md']) t.fontSize(step) * scale],
    gutter: 0,
    devicePixelRatio: devicePixelRatio,
    dark: t.isDark,
    ink: t.color('glacier-text'),
    contentTop: 0,
    contentBottom: 0,
  );
}

final List<Extension> _drawn = <Extension>[itemExtensions(peek: true), drawnTables(), drawnMermaid()];

/// The same with the pictures of one store: a picture under its line and a film as its still, as the page's card
/// draws them (`<Editor … peek />`: `inlineImages`, `videoCards`).
final Expando<List<Extension>> _drawnWith = Expando<List<Extension>>('card words');

List<Extension> _drawnFrom(PictureStore? store) =>
    store == null ? _drawn : _drawnWith[store] ??= <Extension>[itemExtensions(peek: true), drawnTables(), drawnMermaid(), mediaExtensions(seams: MediaSeams(pictures: store), peek: true)];

/// A card of words, to be read: the editor's own lines, taking no taps.
class CardWords extends StatefulWidget {
  const CardWords({super.key, required this.markdown, this.pictures});
  final String markdown;

  /// Where a picture in the words, and a film's still, are drawn from; without it each is its line.
  final PictureStore? pictures;

  @override
  State<CardWords> createState() => _CardWordsState();
}

class _CardWordsState extends State<CardWords> {
  late EditorView _view = _make();

  EditorView _make() {
    if (ghostPerf) Perf.count('canvas.words.made');
    return _made();
  }

  EditorView _made() => EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: widget.markdown, extensions: noteExtensions(display: NoteView.formatted, readOnly: true, more: _drawnFrom(widget.pictures))),
  );

  @override
  void didUpdateWidget(CardWords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown || !identical(oldWidget.pictures, widget.pictures)) {
      _view.destroy();
      _view = _make();
    }
  }

  @override
  void dispose() {
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('canvas.words.build');
    final env = cardEnv(context.tokens, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: 0,
            maxHeight: double.infinity,
            child: EditorColumn(view: _view, env: env, sheets: <LookSheet>[peekLook()]),
          ),
        ),
      ),
    );
  }
}

/// A card of words open to be written in: the note's own editor in its own mode, the words going straight into
/// the canvas as they are typed, the keyboard up with it.
class _CardEditor extends StatefulWidget {
  const _CardEditor({super.key, required this.node, required this.onWrite});
  final CanvasNode node;
  final void Function(String id, String text)? onWrite;

  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final EditorView _view = EditorView(
    state: EditorState.create(
      doc: widget.node.text,
      extensions: noteExtensions(
        display: NoteView.mixed,
        more: <Extension>[
          history(),
          // Card.tsx: `<Editor … placeholder="Write something." />`.
          placeholder('Write something.'),
          ..._drawnLive,
          EditorViewLike.updateListener.of((update) {
            if (update.docChanged) widget.onWrite?.call(widget.node.id, update.state.doc.toString());
          }),
        ],
      ),
    ),
  );

  static final List<Extension> _drawnLive = <Extension>[itemExtensions(), drawnTables(), drawnMermaid()];
  final EditorController _controller = EditorController();

  @override
  void initState() {
    super.initState();
    // The keyboard comes up with it (Matt: "a text card appears under the fingers, keyboard up"). Asked for: the
    // canvas has the focus, and an editor only takes it unasked where nothing has.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.focus();
    });
  }

  @override
  void dispose() {
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = cardEnv(context.tokens, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    return CustomScrollView(
      slivers: [Editor(view: _view, controller: _controller, env: env, sheets: <LookSheet>[peekLook()])],
    );
  }
}

/// `.linkCard`: a web address, by its short name and whole.
class _LinkWords extends StatelessWidget {
  const _LinkWords({required this.node});
  final CanvasNode node;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(shortUrl(node.url), style: _titleStyle(t, color: t.color('glacier-text'))),
        SizedBox(height: t.space(1)),
        _Hint(node.url),
      ],
    );
  }
}

/// `.cardHint`.
class _Hint extends StatelessWidget {
  const _Hint(this.words);
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle')));
  }
}

/// `.fileCard`: a note by that name in Ghost.md, drawn small; one it does not have yet, said to be waiting; or a
/// picture from the vault it came from, which it has no copy of.
class _FileWords extends StatelessWidget {
  const _FileWords({required this.node, required this.wiki, required this.near});
  final CanvasNode node;
  final CanvasWiki? wiki;
  final bool near;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = fileTitle(node.file);
    final picture = isImageFile(node.file);
    final known = !picture && (wiki?.known(title) ?? false);
    final body = known ? wiki?.body?.call(title) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _titleStyle(t, color: known || picture ? t.color('glacier-text') : t.color('glacier-text-subtle'))),
        SizedBox(height: t.space(1)),
        if (body != null)
          // `.cardPeek { flex: 1; min-block-size: 0 }` inside `.near { overflow: hidden }`.
          Expanded(
            child: ClipRect(
              child: OverflowBox(alignment: Alignment.topLeft, minHeight: 0, maxHeight: double.infinity, child: near ? NotePeek(body: body) : const SizedBox.shrink()),
            ),
          )
        else
          _Hint(picture ? 'A picture, in the vault it came from' : (known ? '' : 'Not in Ghost.md yet')),
      ],
    );
  }
}

/// `.picture`: the whole card is the picture, kept in shape and cropped to the card's own round.
class _PictureFill extends StatelessWidget {
  const _PictureFill({required this.picture});
  final Picture picture;

  @override
  Widget build(BuildContext context) {
    final bytes = picture.bytes;
    final image = bytes != null ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true) : Image.file(File(picture.path!), key: ValueKey(picture.version), fit: BoxFit.cover, gaplessPlayback: true);
    return SizedBox.expand(child: image);
  }
}
