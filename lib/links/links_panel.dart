/// A note's links from other notes, as Obsidian's backlinks pane shows them: "Linked from", every note that links
/// to this one by its title or an alias (any `[[…]]`, with words after a `|`, a heading or a named line after a
/// `#`, an embed, a Markdown link to its file), each with the line round the link and a tap that opens it there;
/// and under it "Mentioned in", the notes that say this note's title or an alias as words and do not link it, each
/// with Link, which makes that mention a `[[link]]` in the other note.
///
/// Read from the app's one index (lib/core/link_index.dart) while the panel is up, and again when the index says
/// the library moved; nothing of the library is read for a panel nobody has open. On the More sheet's Links page
/// it is drawn in the sheet's own rows; in the side panel ([LinksPanel.compact]), smaller.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../core/link_index.dart';
import '../sheet/css.dart';
import '../sheet/kit.dart';

/// What the panel shows of a note: who links to it, and who says its name.
typedef NoteLinksRead = ({List<Backlink> backlinks, List<Mention> mentions});

/// [noteId]'s links, read from [index] with each note's words from [bodyOf].
NoteLinksRead readLinks(LinkIndex index, String noteId, String? Function(String id) bodyOf) => (backlinks: index.backlinksOf(noteId, bodyOf), mentions: index.mentionsOf(noteId, bodyOf));

class LinksPanel extends StatefulWidget {
  const LinksPanel({super.key, required this.indexer, required this.noteId, required this.title, required this.onOpen, this.onLink, this.compact = false});

  final LinkIndexer indexer;
  final String noteId;

  /// The note's title, for what the empty panel says.
  final String title;

  /// Opens a note at a line, from 0.
  final void Function(String id, int line) onOpen;

  /// Makes a mention a link in its note, answering whether it did; absent where the other notes cannot be written
  /// (a note in the Trash), and there is no Link.
  final Future<bool> Function(Mention mention, LinkPlace place)? onLink;

  /// The side panel's smaller type.
  final bool compact;

  @override
  State<LinksPanel> createState() => _LinksPanelState();
}

class _LinksPanelState extends State<LinksPanel> {
  NoteLinksRead? _read;
  int _version = -1;
  LinkIndex? _from;
  final Set<String> _linking = <String>{};

  @override
  void initState() {
    super.initState();
    widget.indexer.addListener(_changed);
  }

  @override
  void didUpdateWidget(LinksPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.indexer, widget.indexer)) {
      old.indexer.removeListener(_changed);
      widget.indexer.addListener(_changed);
    }
    if (old.noteId != widget.noteId) _version = -1;
  }

  @override
  void dispose() {
    widget.indexer.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  NoteLinksRead get _now {
    final index = widget.indexer.index;
    if (_read == null || _version != index.version || !identical(_from, index)) {
      _read = readLinks(index, widget.noteId, widget.indexer.bodyOf);
      _version = index.version;
      _from = index;
    }
    return _read!;
  }

  Future<void> _link(Mention mention, LinkPlace place) async {
    final link = widget.onLink;
    if (link == null || !_linking.add('${mention.id}:${place.from}')) return;
    setState(() {});
    try {
      await link(mention, place);
    } finally {
      _linking.remove('${mention.id}:${place.from}');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final read = _now;
    final name = widget.title.isEmpty ? 'this note' : '“${widget.title}”';
    final compact = widget.compact;
    Widget heading(String text) => compact ? _Eyebrow(text) : SheetHeading(text);
    Widget quiet(String text) => compact ? _Quiet(text) : SheetNote(text);
    Widget group(List<Widget> rows) => compact ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 1, children: rows) : SheetGroup(children: rows);
    final count = read.backlinks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading(count == 0 ? 'Linked from' : 'Linked from $count ${count == 1 ? 'note' : 'notes'}'),
        if (read.backlinks.isEmpty)
          quiet('No other note links to $name yet. A link is a title in double brackets, like [[${widget.title.isEmpty ? 'Title' : widget.title}]].')
        else
          group([
            for (final back in read.backlinks)
              for (final (i, place) in back.links.take(3).indexed)
                _PlaceRow(
                  key: ValueKey('back:${back.id}:${place.from}'),
                  title: i == 0 ? (back.title.isEmpty ? 'Untitled' : back.title) : null,
                  place: place,
                  compact: compact,
                  onPress: () => widget.onOpen(back.id, place.line),
                ),
          ]),
        if (!compact) SizedBox(height: t.space(2)) else SizedBox(height: t.space(3)),
        heading('Mentioned in'),
        if (read.mentions.isEmpty)
          quiet('No other note says $name without linking it.')
        else
          group([
            for (final mention in read.mentions)
              for (final (i, place) in mention.places.indexed)
                _PlaceRow(
                  key: ValueKey('mention:${mention.id}:${place.from}'),
                  title: i == 0 ? (mention.title.isEmpty ? 'Untitled' : mention.title) : null,
                  place: place,
                  compact: compact,
                  onPress: () => widget.onOpen(mention.id, place.line),
                  linking: _linking.contains('${mention.id}:${place.from}'),
                  onLink: widget.onLink == null ? null : () => _link(mention, place),
                ),
          ]),
      ],
    );
  }
}

/// One place another note links here, or says this note's name: the note's title over the first of its places,
/// the line round it, a tap that opens it there, and for a mention, Link.
class _PlaceRow extends StatelessWidget implements SheetRuled {
  const _PlaceRow({super.key, required this.title, required this.place, required this.compact, required this.onPress, this.onLink, this.linking = false});

  /// The note's title, on its first place's row; null on the rows of its other places.
  final String? title;
  final LinkPlace place;
  final bool compact;
  final VoidCallback onPress;
  final VoidCallback? onLink;
  final bool linking;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final big = t.fontSize(compact ? 'sm' : 'md');
    final small = t.fontSize(compact ? 'xs' : 'sm');
    final line = place.text.isEmpty ? (place.embed ? 'Drawn in it' : 'A link on its own') : place.text;
    final said = '${title ?? ''}${title == null ? '' : ': '}$line';
    final link = onLink;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          Expanded(
            child: GlacierPressable(
              onPressed: onPress,
              semanticLabel: 'Open at $said',
              builder: (context, state) => Container(
                constraints: BoxConstraints(minHeight: compact ? 0 : t.space(12)),
                padding: compact ? EdgeInsets.symmetric(vertical: 0.45 * big, horizontal: 0.6 * big) : EdgeInsets.fromLTRB(t.space(4), t.space(3), link == null ? t.space(4) : t.space(2), t.space(3)),
                decoration: BoxDecoration(
                  color: state.pressed ? t.color('app-wash') : (compact && state.hovered ? t.colorOf('color-mix(in srgb, var(--glacier-text) 6%, transparent)') : null),
                  borderRadius: compact ? BorderRadius.circular(t.radius('sm')) : null,
                ),
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      if (title != null) Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, big, weight: compact ? 'semibold' : 'medium', color: t.color('glacier-text'))),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (place.embed) ...[
                            Padding(padding: EdgeInsets.only(top: 0.15 * small), child: AppIcon(Lucide.squareDashed, size: small, color: t.color('glacier-text-subtle'))),
                            SizedBox(width: 0.4 * small),
                          ],
                          Expanded(child: _marked(t, line, place.text.isEmpty ? null : place.mark, pageText(t, small, color: t.color('glacier-text-subtle')))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (link != null)
            Padding(
              padding: EdgeInsetsDirectional.only(end: compact ? 0 : t.space(3), start: t.space(1)),
              child: GlacierPressable(
                onPressed: linking ? null : link,
                semanticLabel: 'Link this mention in ${title ?? 'the note'}',
                builder: (context, state) => DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: StadiumBorder(side: BorderSide(color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 40%, transparent)') : t.color('glacier-border-subtle'))),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 0.25 * small + 1, horizontal: 0.8 * small + 1),
                    child: ExcludeSemantics(child: Text(linking ? 'Linking' : 'Link', style: pageText(t, small, weight: 'medium', color: t.color(linking ? 'glacier-text-muted' : 'glacier-text')))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The line round a place, the place itself in the full ink: which of two mentions on one line a Link makes.
Widget _marked(Tokens t, String line, (int, int)? mark, TextStyle style) {
  if (mark == null) return Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
  final (from, to) = mark;
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: line.substring(0, from)),
      TextSpan(text: line.substring(from, to), style: style.copyWith(color: t.color('glacier-text'))),
      TextSpan(text: line.substring(to)),
    ]),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

/// The side panel's heading: small spaced capitals, as a journal's month is.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(1), t.space(1), t.space(1), t.space(1)),
      child: Semantics(
        header: true,
        label: text,
        child: ExcludeSemantics(child: Text(text.toUpperCase(), style: t.text('xs', weight: 'bold', color: t.color('app-ink-3')).copyWith(letterSpacing: t.len('app-tracking-caps', em: size)))),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(1)),
      child: Text(text, style: t.textAt(t.fontSize('sm'), color: t.color('glacier-text-muted'))),
    );
  }
}

/// [body] with the mention at [from]-[to] made a link, its words kept as written: `[[launch week]]` finds Launch
/// week as a link does. Null where the words there are no longer the name [name] (the note moved on).
String? linkMention(String body, int from, int to, String name) {
  if (from < 0 || to > body.length || from >= to) return null;
  final words = body.substring(from, to);
  if (mentionPattern(name).matchAsPrefix(words) == null) return null;
  return '${body.substring(0, from)}[[$words]]${body.substring(to)}';
}

/// [body] with that link taken back to its words, where it is still there: the Undo.
String? unlinkMention(String body, int from, String words) {
  final link = '[[$words]]';
  if (from < 0 || from + link.length > body.length || body.substring(from, from + link.length) != link) return null;
  return '${body.substring(0, from)}$words${body.substring(from + link.length)}';
}
