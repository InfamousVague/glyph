/// Link preview cards (Matt: "add link preview cards"): a line that is only a link gets a card under it, with the
/// page's title, its site and a line of what it's about. Ports `src/app/editor/linkCards.ts`.
///
///     https://www.airbnb.com/rooms/1234
///     - [The cabin](https://www.airbnb.com/rooms/1234)
///
/// The line keeps its text, as a picture's line does (images.dart), and the card is a block widget under it, so
/// the caret and the saved note are exactly as before. A tap on the card opens the page. A link a plugin already
/// reads (a Notion task, a GitHub issue) has its own row, and a link in the middle of words stays a link.
///
/// The title comes from lib/core/link_preview.dart, and only for a card on screen; until then, or without it, the
/// card says the site and the path. Link previews off (Settings › Account › Privacy) draws no cards at all.
///
/// What differs:
/// - What the page reached for itself is told to the editor through [linkCards]: the previews (a
///   [LinkPreviewer]; [noLinkPreviews] by default, which is the page in a browser: the site and the path, and
///   nothing asked), how a page is opened ([LinkOpener]; nothing happens on a tap without one), whether cards are
///   drawn at all (`enabled`: `preferences().linkPreviews`), what says that switch changed (`switches`:
///   `onPreferences`) and whether a plugin reads a link (`reads`: `linkedOn(text) || markNameFor(url)`, the
///   plugins' registry, stage 9; nothing is read by default).
/// - The theme's rules are drawn by the card's own widgets, each cited where it is drawn.
///   `-webkit-tap-highlight-color`, `cursor` and `outline-offset` have no counterpart; the keyboard's Enter and
///   Space on a focused card are the semantics' tap.
/// - A `where` line too long for its card is cut with an ellipsis here, as the stylesheet asks
///   (`text-overflow: ellipsis`). On the page it never is: the line's `nowrap` width is the card's least width,
///   which widens the whole editor past the screen instead (seen at 390 px with a 38-character path).
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/item_syntax.dart' show boxPattern, jsTrim, markerPattern;
import '../../core/link_preview.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../view/editor_view.dart';
import '../view/lines.dart';
import 'images.dart' show gutterOf;
import 'inline_box.dart';

/// The whole line is a link: bare, `<bare>`, or `[words](address)`, optionally as a list item or a to-do.
final RegExp _onlyLink = RegExp('^\\s*(?:$markerPattern\\s+(?:$boxPattern\\s+)?)?(?:<?(https?:\\/\\/[^\\s<>]+?)>?|\\[([^\\]\\n]+)\\]\\((https?:\\/\\/[^\\s)]+)\\))\\s*\$');
final RegExp _trailing = RegExp(r'[.,;:!?]+$');

/// A line that is one link.
@immutable
class LinkLine {
  const LinkLine(this.url, this.words);

  final String url;

  /// The link's own words, for `[words](address)`.
  final String? words;

  @override
  bool operator ==(Object other) => other is LinkLine && other.url == url && other.words == words;

  @override
  int get hashCode => Object.hash(url, words);

  @override
  String toString() => 'LinkLine($url, $words)';
}

/// Whether a plugin reads the link at `url` on the line `text`, which then has its own row under the line.
typedef LinkRead = bool Function(String text, String url);

/// The link a line is, or null when the line is anything more or less than one link.
LinkLine? linkLine(String text, {LinkRead? reads}) {
  final link = _onlyLinkOn(text);
  if (link == null) return null;
  // A link a plugin reads has its own row under the line (editor/linkedRows.ts).
  if (reads != null && reads(text, link.url)) return null;
  return link;
}

/// The link a line is and nothing more, whoever reads it.
LinkLine? _onlyLinkOn(String text) {
  final found = _onlyLink.firstMatch(text);
  if (found == null) return null;
  final url = (found.group(1) ?? found.group(3) ?? '').replaceFirst(_trailing, '');
  if (url.isEmpty) return null;
  final words = jsTrim(found.group(2) ?? '');
  return LinkLine(url, words.isEmpty ? null : words);
}

/// The link each line is alone, kept for every line of a document (`LineFact`): whether a plugin reads it is asked
/// each time, since that changes, but the line is put to the pattern once.
final LineFact<LinkLine> _lone = LineFact<LinkLine>((text) => text.contains('http') ? _onlyLinkOn(text) : null);

/// What the cards are told by whoever makes the editor.
class LinkCardSeams {
  const LinkCardSeams({this.previewer = noLinkPreviews, this.open, this.enabled, this.switches, this.reads});

  final LinkPreviewer previewer;
  final LinkOpener? open;
  final bool Function()? enabled;
  final Listenable? switches;
  final LinkRead? reads;
}

final Facet<LinkCardSeams, LinkCardSeams> _seams = Facet.define<LinkCardSeams, LinkCardSeams>(combine: (values) => values.isEmpty ? const LinkCardSeams() : values.first);

final RegExp _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The card under a link's line.
class LinkCardWidget extends EditorWidget {
  LinkCardWidget(this.url, this.words, LinkPreviewer previewer) : face = _faceOf(previewer.previewFor(url));

  final String url;
  final String? words;

  /// What the card says of the page, for telling one drawing from the next.
  final String face;

  static String _faceOf(LinkPreview? known) => <String?>[known?.title, known?.site, known?.description].map((part) => part ?? '').join('|');

  @override
  bool eq(LinkCardWidget other) => other.url == url && other.words == words && other.face == face;

  @override
  Widget build(BuildContext context) => _LinkCard(url: url, words: words, seams: EditorViewScope.maybeOf(context)?.state.facet(_seams) ?? const LinkCardSeams());
}

class _LinkCard extends StatefulWidget {
  const _LinkCard({required this.url, required this.words, required this.seams});

  final String url;
  final String? words;
  final LinkCardSeams seams;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    widget.seams.previewer.wantPreview(widget.url);
  }

  /// Another link in this card's place is asked for in its turn.
  @override
  void didUpdateWidget(_LinkCard old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || !identical(old.seams.previewer, widget.seams.previewer)) widget.seams.previewer.wantPreview(widget.url);
  }

  void _open() {
    final open = widget.seams.open;
    if (open != null) unawaited(open(widget.url).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    // The card is in the note's own hand and size: nothing on it says another face.
    final base = look?.line(LookElement(null)).base;
    final em = base?.fontSize ?? t.len('app-body');
    final ink = base?.color ?? t.color('app-ink');
    final face = (base?.style ?? t.textAt(em, mono: true)).copyWith(color: ink, decoration: TextDecoration.none);
    final known = widget.seams.previewer.previewFor(widget.url);
    final knownSite = known?.site ?? '';
    final site = knownSite.isNotEmpty ? knownSite : siteOf(widget.url);
    final knownTitle = known?.title ?? '';
    final title = knownTitle.isNotEmpty ? knownTitle : (widget.words ?? site);
    final about = known?.description ?? '';
    final paper = t.color('app-paper-2');
    final border = look?.env.border(1) ?? 1.0;

    // '.cm-linkCard-badge': { flex: 'none', display: 'grid', placeItems: 'center', inlineSize: '2.1em',
    //   blockSize: '2.1em', borderRadius: '0.55em', background: 'color-mix(in srgb, currentColor 10%, transparent)',
    //   fontWeight: '600', fontSize: '0.9em' }
    final badgeSize = em * 0.9;
    final badge = ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey<String>('cm-linkCard-badge'),
        decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, currentColor 10%, transparent)', current: ink), borderRadius: BorderRadius.circular(badgeSize * 0.55)),
        child: SizedBox.square(
          dimension: layoutUnit(badgeSize * 2.1),
          child: Center(child: InlineWords((_letter.firstMatch(site)?.group(0) ?? '·').toUpperCase(), style: face.copyWith(fontSize: badgeSize, fontWeight: FontWeight.w600), lineHeight: badgeSize * 1.6)),
        ),
      ),
    );

    // '.cm-linkCard-body': { display: 'flex', flexDirection: 'column', minInlineSize: '0', gap: '0.1em' }
    final gap = SizedBox(height: layoutUnit(em * 0.1));
    final body = IntrinsicWidth(
      key: const ValueKey<String>('cm-linkCard-body'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // '.cm-linkCard-title': { fontWeight: '600', lineHeight: '1.3', overflow: 'hidden',
          //   display: '-webkit-box', WebkitLineClamp: '2', WebkitBoxOrient: 'vertical' }
          InlineWords(title, key: const ValueKey<String>('cm-linkCard-title'), style: face.copyWith(fontWeight: FontWeight.w600), lineHeight: em * 1.3, maxLines: 2),
          if (about.isNotEmpty) ...<Widget>[
            gap,
            // '.cm-linkCard-about': { fontSize: '0.86em', lineHeight: '1.35', color: 'var(--app-ink-2, inherit)',
            //   overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: '2', WebkitBoxOrient: 'vertical' }
            InlineWords(about, key: const ValueKey<String>('cm-linkCard-about'), style: face.copyWith(fontSize: em * 0.86, color: t.color('app-ink-2')), lineHeight: em * 0.86 * 1.35, maxLines: 2),
          ],
          gap,
          // '.cm-linkCard-where': { fontSize: '0.8em', color: 'var(--app-ink-3, inherit)', overflow: 'hidden',
          //   textOverflow: 'ellipsis', whiteSpace: 'nowrap' }
          InlineWords(
            '${siteOf(widget.url)}${pathOf(widget.url)}',
            key: const ValueKey<String>('cm-linkCard-where'),
            style: face.copyWith(fontSize: em * 0.8, color: t.color('app-ink-3')),
            // The line height is the note's own, which the card inherits.
            lineHeight: em * 0.8 * (base?.props.lineHeight ?? 1.6),
            ellipsis: true,
          ),
        ],
      ),
    );

    // '.cm-linkCard': { display: 'flex', alignItems: 'flex-start', gap: '0.7em', maxInlineSize: '32rem',
    //   padding: '0.6em 0.75em', borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    //   border: '1px solid var(--app-rule, var(--glacier-border-subtle))',
    //   background: 'var(--app-paper-2, var(--glacier-surface))' }
    // '.cm-linkCard:active': { background: 'color-mix(in srgb, currentColor 8%, var(--app-paper-2, transparent))' }
    final card = DecoratedBox(
      key: const ValueKey<String>('cm-linkCard'),
      decoration: BoxDecoration(
        color: _pressed ? t.colorOf('color-mix(in srgb, currentColor 8%, var(--app-paper-2, transparent))', current: ink) : paper,
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule'), width: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layoutUnit(em * 0.6) + border, horizontal: layoutUnit(em * 0.75) + border),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[badge, SizedBox(width: layoutUnit(em * 0.7)), Flexible(child: body)],
        ),
      ),
    );

    // '.cm-linkCardWrap': { paddingBlock: '0.25em 0.6em', paddingInline: 'calc(var(--app-safe-left, 0px) +
    //   var(--app-gutter, 0px)) calc(var(--app-safe-right, 0px) + var(--app-gutter, 0px))' }
    // Space above and below as padding on a wrapper: a block widget is measured whole, margins and all left out.
    final gutter = gutterOf(context);
    return Padding(
      key: const ValueKey<String>('cm-linkCardWrap'),
      padding: EdgeInsets.only(top: layoutUnit(em * 0.25), bottom: layoutUnit(em * 0.6), left: t.lenOf('var(--app-safe-left, 0px)') + gutter, right: t.lenOf('var(--app-safe-right, 0px)') + gutter),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.lenOf('32rem')),
          child: Semantics(
            link: true,
            label: 'Open $title',
            onTap: _open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: _open,
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}

/// A preview arrived, or the setting changed: rebuild the cards.
final StateEffectType<Null> refreshLinkCards = StateEffect.define<Null>();

DecorationSet _decorate(EditorState state) {
  final builder = RangeSetBuilder<Decoration>();
  final seams = state.facet(_seams);
  if (!(seams.enabled?.call() ?? true)) return builder.finish();
  // The lines that are a link alone are the tree's own keeping; whether a plugin reads one is asked each time.
  final lines = _lone.of(state.doc);
  if (lines.isEmpty) return builder.finish();
  // A link in fenced code is code, and gets no card.
  final fences = DocFences.of(state.doc);
  final reads = seams.reads;
  for (final line in lines) {
    if (fences.covers(line.number)) continue;
    final link = line.fact;
    // A link a plugin reads has its own row under the line (editor/linkedRows.ts).
    if (reads != null && reads(line.text, link.url)) continue;
    builder.add(line.to, line.to, Decoration.widget(widget: LinkCardWidget(link.url, link.words, seams.previewer), block: true, side: 1));
  }
  return builder.finish();
}

final StateField<DecorationSet> _cards = StateField.define<DecorationSet>(
  create: _decorate,
  update: (value, tr) {
    if (tr.docChanged || tr.reconfigured || tr.effects.any((e) => e.isOf(refreshLinkCards))) return _decorate(tr.state);
    return value;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// A preview arrived, or the setting changed: rebuild the cards.
class _Listen extends PluginValue {
  _Listen(this.view) {
    _hear(view.state.facet(_seams));
  }

  final EditorViewLike view;
  LinkCardSeams? _heard;
  bool _gone = false;
  bool _told = false;

  void _hear(LinkCardSeams seams) {
    if (identical(seams, _heard)) return;
    _heard?.previewer.removeListener(_onReady);
    _heard?.switches?.removeListener(_onReady);
    _heard = seams;
    seams.previewer.addListener(_onReady);
    seams.switches?.addListener(_onReady);
  }

  void _onReady() {
    // Told a turn later, once: a previewer may say so from inside the build that asked it.
    if (_told) return;
    _told = true;
    scheduleMicrotask(() {
      _told = false;
      if (!_gone) view.dispatch(TransactionSpec(effects: refreshLinkCards.of(null)));
    });
  }

  @override
  void update(ViewUpdate update) => _hear(update.state.facet(_seams));

  @override
  void destroy() {
    _gone = true;
    _heard?.previewer.removeListener(_onReady);
    _heard?.switches?.removeListener(_onReady);
  }
}

final ViewPlugin<_Listen> _listen = ViewPlugin.define<_Listen>(_Listen.new);

/// A card under each line that is only a link. `previewer` knows the pages' titles, `open` opens a page on a tap,
/// `enabled` is the Link previews switch, `switches` says when it changed, and `reads` says a plugin has the link.
Extension linkCards({LinkPreviewer previewer = noLinkPreviews, LinkOpener? open, bool Function()? enabled, Listenable? switches, LinkRead? reads}) =>
    Extension.list(<Extension>[_seams.of(LinkCardSeams(previewer: previewer, open: open, enabled: enabled, switches: switches, reads: reads)), _cards, _listen]);
