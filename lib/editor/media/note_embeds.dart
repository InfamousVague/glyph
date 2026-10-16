/// Another note drawn inside this one, as Obsidian embeds one: `![[Note]]` on a line of its own draws that note's
/// words in place, read only, with its title over them small and an Open; `![[Note#Heading]]` draws the heading and
/// what is under it, `![[Note#^name]]` the one named line (lib/core/block_ids.dart), and `![[picture.png]]` a
/// picture this library keeps by that name, `![[picture.png|300]]` no wider than 300.
///
/// The line keeps its markdown, as a canvas's frame does (canvas_frames.dart, which draws an embed that names a
/// canvas; this draws every other): with the caret on it the drawing steps aside and the line shows as typed, and
/// anywhere else it is a link like any other. Nothing about the file changes.
///
/// **Two levels at most, and never round in a circle.** A note drawn here draws the notes it embeds in turn, and
/// those draw theirs as links: [mostEmbedDepth]. A note never draws itself, nor a note it is already drawn inside
/// of: that line stays its link.
///
/// What is drawn is the other note as the library has it now: a change to it is drawn again when the library says
/// so ([refreshCanvasFrames], which the desk sends for every `![[…]]` line). A section is read from the other
/// note's words once for each body and kept, so a caret moved in this note reads nothing of the other again.
///
/// A state field, as the canvas's frame is: a block widget's height has to be known before layout.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../canvas/json_canvas.dart' show isCanvasBody;
import '../../core/block_ids.dart';
import '../../core/front_matter.dart' show frontMatterOffset;
import '../../core/images.dart' show PictureStore;
import '../../core/note_text.dart' show noteTitle;
import '../../core/title_key.dart';
import '../editor.dart';
import '../items/anchors.dart' show itemAnchors;
import '../items/wiki_links.dart';
import '../looks/look.dart';
import '../looks/note_face.dart';
import '../markdown_view.dart' show PeekClip;
import '../syntax/language.dart' show InlineFormatSyntax;
import '../view/base.dart';
import '../view/blocks.dart' show ClassedBlockWidget;
import '../view/column.dart';
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/view_mode.dart';
import 'canvas_frames.dart' show refreshCanvasFrames;
import 'images.dart' show KeptPicture, pictureStore;

/// A line that is only an embed: `![[…]]`.
final RegExp _embed = RegExp(r'^\s*!\[\[([^\[\]\n]{1,200})\]\]\s*$');

/// A name that is a picture's, by its ending.
final RegExp _picture = RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic|avif)$', caseSensitive: false);

/// How deep embeds draw: a note in this one, and a note in that. The third is its link.
const int mostEmbedDepth = 2;

/// An embed as written: the note's title or the picture's name, what followed a `#`, and what followed a `|`.
typedef EmbedLine = ({String title, String? anchor, String? size, bool picture});

/// The embed a line is, when it is only an embed with a name in it.
EmbedLine? embedOf(String text) {
  final match = _embed.firstMatch(text);
  if (match == null) return null;
  final whole = (match.group(1) ?? '').trim();
  final bar = whole.indexOf('|');
  final inside = (bar >= 0 ? whole.substring(0, bar) : whole).trim();
  final size = bar >= 0 ? whole.substring(bar + 1).trim() : null;
  if (_picture.hasMatch(inside)) {
    final name = inside.startsWith('image/') ? inside.substring('image/'.length) : inside;
    return (title: name, anchor: null, size: size == null || size.isEmpty ? null : size, picture: true);
  }
  final hash = inside.indexOf('#');
  final title = (hash >= 0 ? inside.substring(0, hash) : inside).trim();
  if (title.isEmpty) return null;
  final anchor = hash >= 0 ? inside.substring(hash + 1).trim() : '';
  return (title: title, anchor: anchor.isEmpty ? null : anchor, size: null, picture: false);
}

/// The embeds of a document, by line, kept with its tree: a letter typed reads only the line it changed.
final LineFact<EmbedLine> _embeds = LineFact<EmbedLine>((text) => text.contains('![[') ? embedOf(text) : null);

/// What the editor's embeds are drawn with.
@immutable
class EmbedOptions {
  const EmbedOptions({required this.body, required this.open, this.formats = const <InlineFormatSyntax>[], this.depth = 0, this.within = const <String>{}});

  /// A note's words by its title (or an alias of it), or null where there is none.
  final String? Function(String title) body;

  /// Opens the note by that title, at the place an anchor names.
  final void Function(String title, [String? anchor]) open;

  /// The marks the note's own editor reads, so the note drawn here reads them too.
  final Iterable<InlineFormatSyntax> formats;

  /// How many embeds deep this editor is: 0 for the note on screen.
  final int depth;

  /// The notes this one is drawn inside of, by their titles' keys.
  final Set<String> within;

  /// The options for the note drawn inside, from inside [keys].
  EmbedOptions inside(Iterable<String> keys) => EmbedOptions(body: body, open: open, formats: formats, depth: depth + 1, within: {...within, ...keys});
}

/// The words a section is, kept by the body it was read from: a caret moved does not read the other note again.
final List<({String body, String? anchor, String? words})> _sections = [];

String? _sectionOf(String body, String? anchor) {
  for (final kept in _sections) {
    if (kept.anchor == anchor && (identical(kept.body, body) || kept.body == body)) return kept.words;
  }
  final words = anchor == null ? _withoutTitle(body.substring(frontMatterOffset(body)).trim(), noteTitle(body)) : sectionOf(body, anchor);
  _sections.add((body: body, anchor: anchor, words: words));
  if (_sections.length > 24) _sections.removeAt(0);
  return words;
}

final RegExp _headingLine = RegExp(r'^#{1,6}\s+');

/// A whole note's words with its title heading taken off: the embed's bar names it already.
String _withoutTitle(String words, String title) {
  final end = words.indexOf('\n');
  final first = end < 0 ? words : words.substring(0, end);
  if (!_headingLine.hasMatch(first) || titleKey(first) != titleKey(title)) return words;
  return end < 0 ? '' : words.substring(end + 1).trim();
}

/// The note's own title, from its first lines.
String _ownTitle(Doc doc) {
  final most = doc.lines < 45 ? doc.lines : 45;
  return noteTitle([for (var line = 1; line <= most; line += 1) doc.line(line).text].join('\n'));
}

/// A note drawn in this one.
class NoteEmbedWidget extends EditorWidget implements ClassedBlockWidget {
  const NoteEmbedWidget({required this.title, required this.anchor, required this.words, required this.from, required this.options});

  final String title;
  final String? anchor;

  /// What is drawn: the note's words, or its section; null where the anchor names nothing there.
  final String? words;
  final int from;

  /// The options of the note drawn inside.
  final EmbedOptions options;

  @override
  String get className => 'cm-noteEmbed';

  @override
  bool eq(NoteEmbedWidget other) => other.title == title && other.anchor == anchor && other.words == words && other.from == from && other.options.depth == options.depth;

  @override
  bool takesPointer(_) => true;

  @override
  Widget build(BuildContext context) => DrawnNoteEmbed(widget: this);
}

/// A picture the library keeps, drawn in place of `![[picture.png]]`.
class PictureEmbedWidget extends EditorWidget implements ClassedBlockWidget {
  const PictureEmbedWidget({required this.name, required this.size, required this.from});

  final String name;

  /// What followed a `|`: the most width, in pixels, as Obsidian reads `|300` (and `|300x200`'s first number).
  final String? size;
  final int from;

  @override
  String get className => 'cm-pictureEmbed';

  @override
  bool eq(PictureEmbedWidget other) => other.name == name && other.size == size && other.from == from;

  @override
  bool takesPointer(_) => true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.of(context);
    final store = view.state.facet(pictureStore);
    final look = view is EditorView ? view.look : null;
    final em = look?.env.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(look?.env.gutter ?? t.len('app-gutter'));
    final radius = t.radius('md');
    final paper = t.color('app-paper-2');
    final wide = double.tryParse(RegExp(r'^\d+').stringMatch(size ?? '') ?? '');
    final waiting = store?.pictureOf(name) == null;
    return Semantics(
      container: true,
      label: 'Picture: $name',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A tap puts the caret on the line, and the embed can be changed.
        onTap: () => openOnPress(view, from),
        child: Padding(
          // As a picture under its line is drawn ('.figure'): `margin: var(--glacier-space-2) 0 var(--glacier-space-3)`.
          padding: EdgeInsets.fromLTRB(gutter, t.space(2), gutter, t.space(3)),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ?? double.infinity),
              child: KeptPicture(
                name: name,
                store: store,
                label: name,
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                radius: radius,
                background: paper,
                waiting: waiting
                    ? DecoratedBox(
                        decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(radius)),
                        child: SizedBox(
                          width: double.infinity,
                          height: t.lenOf('3rem'),
                          child: Center(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: noteFace(t, look, 0.86 * em, color: t.color('app-ink-3')))),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The note drawn: its name and an Open over it, and its words in a frame, at most about half a screen tall and
/// faded where there is more.
class DrawnNoteEmbed extends StatefulWidget {
  const DrawnNoteEmbed({super.key, required this.widget});

  final NoteEmbedWidget widget;

  @override
  State<DrawnNoteEmbed> createState() => _DrawnNoteEmbedState();
}

class _DrawnNoteEmbedState extends State<DrawnNoteEmbed> {
  EditorView? _inner;
  String? _innerWords;

  /// One extension list for the embed's life: another would be another editor's state.
  late final List<Extension> _more = <Extension>[
    // A line's name drawn quiet, as in the note itself.
    itemAnchors,
    wikiLinks(WikiOptions(known: (title) => widget.widget.options.body(title) != null, open: widget.widget.options.open)),
    noteEmbeds(widget.widget.options),
  ];

  EditorView _viewFor(String words, PictureStore? store) {
    final had = _inner;
    if (had != null && _innerWords == words) return had;
    had?.destroy();
    _innerWords = words;
    return _inner = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: words,
        extensions: noteExtensions(formats: widget.widget.options.formats, display: NoteView.formatted, readOnly: true, more: <Extension>[..._more, if (store != null) pictureStore.of(store)]),
      ),
    );
  }

  @override
  void dispose() {
    _inner?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embed = widget.widget;
    final host = EditorViewScope.of(context);
    final t = context.tokens;
    final look = host is EditorView ? host.look : null;
    final env = look?.env;
    final em = env?.body ?? t.len('app-body');
    final gutter = layoutUnitFloor(env?.gutter ?? t.len('app-gutter'));
    final quiet = t.color('app-ink-3');
    final edge = t.color('glacier-border-subtle');
    final small = 0.86 * em;
    final words = noteFace(t, look, small, color: quiet);
    final place = embed.anchor == null ? '' : ' › ${embed.anchor!.startsWith('^') ? embed.anchor! : embed.anchor!}';
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final inside = embed.words;
    Widget body;
    if (inside == null) {
      final what = embed.anchor!.startsWith('^') ? 'no line named ${embed.anchor}' : 'no heading “${embed.anchor}”';
      body = Padding(padding: EdgeInsets.all(0.75 * em), child: Text('${embed.title} has $what.', style: words));
    } else if (inside.trim().isEmpty) {
      body = Padding(padding: EdgeInsets.all(0.75 * em), child: Text('${embed.title} has no words yet.', style: words));
    } else {
      final view = _viewFor(inside, host.state.facet(pictureStore));
      final innerEnv = LookEnv(
        t: t,
        body: em,
        headings: env?.headings ?? <double>[for (var level = 1; level <= 6; level++) t.len('app-h$level')],
        gutter: layoutUnitFloor(0.85 * em),
        devicePixelRatio: ratio,
        dark: t.isDark,
        attrs: env?.attrs ?? const <String, String>{},
        tabSize: view.state.tabSize,
        contentTop: 0.5 * em,
        contentBottom: 0.6 * em,
      );
      body = PeekClip(
        maxHeight: (MediaQuery.sizeOf(context).height * 0.55).clamp(200.0, 560.0),
        fade: 2.4 * em,
        child: ExcludeSemantics(child: IgnorePointer(child: EditorColumn(view: view, env: innerEnv))),
      );
    }
    void open() => embed.options.open(embed.title, embed.anchor);
    return Semantics(
      container: true,
      label: 'From ${embed.title}$place',
      child: Padding(
        // As a canvas's frame sits: '0.4em var(--app-gutter) 0.8em'.
        padding: EdgeInsets.fromLTRB(gutter, layoutUnitFloor(0.4 * em), gutter, layoutUnitFloor(0.8 * em)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 0.2 * small),
                child: Row(
                  spacing: 0.6 * small,
                  children: [
                    Expanded(
                      // A press on the name puts the caret on the line: the drawing steps aside and the embed can be
                      // changed, as a canvas's frame does.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openOnPress(host, embed.from),
                        child: Semantics(
                          tooltip: 'Edit the embed',
                          child: Text('${embed.title}$place', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: words),
                        ),
                      ),
                    ),
                    GlacierPressable(
                      semanticLabel: 'Open ${embed.title}',
                      onPressed: open,
                      builder: (context, state) => DecoratedBox(
                        decoration: ShapeDecoration(shape: StadiumBorder(side: BorderSide(color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 40%, transparent)') : edge))),
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 0.15 * small + 1, horizontal: 0.75 * small + 1),
                          child: ExcludeSemantics(child: Text('Open', style: state.hovered ? words.copyWith(color: t.color('app-ink')) : words)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 0.2 * small),
            // A tap on the words opens the note at the place, the way a link does.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: edge)),
                child: ClipRRect(borderRadius: BorderRadius.circular(t.radius('lg')), child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DecorationSet _build(EditorState state, EmbedOptions options) {
  final lines = _embeds.of(state.doc);
  if (lines.isEmpty) return Decoration.none;
  final editable = state.facet(EditorViewLike.editable);
  String? own;
  final ranges = <Range<Decoration>>[];
  for (final line in lines) {
    // The caret on the line: the embed itself, to edit.
    if (editable && caretIn(state, line.from, line.to)) continue;
    final fact = line.fact;
    if (fact.picture) {
      ranges.add(Decoration.replace(widget: PictureEmbedWidget(name: fact.title, size: fact.size, from: line.from), block: true).range(line.from, line.to));
      continue;
    }
    // Two levels down, an embed is its link.
    if (options.depth >= mostEmbedDepth) continue;
    final body = options.body(fact.title);
    // No such note: a link waiting to be written. A canvas: its frame's (canvas_frames.dart).
    if (body == null || isCanvasBody(body)) continue;
    own ??= titleKey(_ownTitle(state.doc));
    final named = titleKey(fact.title), its = titleKey(noteTitle(body));
    // Never itself, nor a note this one is already drawn inside of.
    if (named == own || its == own || options.within.contains(named) || options.within.contains(its)) continue;
    ranges.add(
      Decoration.replace(
        widget: NoteEmbedWidget(title: fact.title, anchor: fact.anchor, words: _sectionOf(body, fact.anchor), from: line.from, options: options.inside(<String>[own, named, its])),
        block: true,
      ).range(line.from, line.to),
    );
  }
  return ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
}

/// `![[Note]]`, `![[Note#Heading]]`, `![[Note#^name]]` and `![[picture.png]]`, each on a line of its own, draw what
/// they name in place.
Extension noteEmbeds(EmbedOptions options) {
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
