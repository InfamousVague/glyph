/// "Linked from" at the foot of a note (Matt, 2026-10-30, "add all 12"): every note whose `[[link]]` points here, drawn
/// under the note's last line, never written into its Markdown. Read from the app's one link index
/// (lib/core/link_index.dart), as the Links panel is (lib/links/links_panel.dart), so `[[Note|words]]`,
/// `[[Note#Heading]]`, `[[Note#^line]]`, an embed `![[Note]]` and a Markdown link to the note's file all count.
///
/// - **Each note that links here** is one row: its title, where it is kept (its workspace, an organization's as
///   "Ghost.md › Clients", else its folder), and the line round its first link, the link itself in the full ink. A
///   press opens it at that line.
/// - **Many** ([BacklinksFoot.most] or more) are folded to their count and Show all, and Show fewer folds them again.
/// - **Mentioned in**, under it: the notes that say this note's title or an alias as words and do not link it, each
///   with Link it, which makes that mention a `[[link]]` in the other note (an edit through the library, with its
///   Undo). Cheap, as the index keeps every note's words by word: a name is looked for only in the notes that hold
///   its rarest word. Folded to its count when there are more than three.
/// - **Team notes** are among them as the library has them: a note this device could not open is not in the library
///   at all, and one in an organization the account is no longer in is left out ([BacklinksFoot.readable]).
/// - **Not drawn** for a note no other note links to, a notebook's index, a canvas, or a meeting's Transcript: the
///   note's screen asks for the foot only under a note's words (lib/note/note_screen.dart `NoteSeams.foot`).
///
/// Simple mode has it as it is: it is a list of notes, and a press opens one.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../core/link_index.dart';
import '../sheet/css.dart';

/// What the foot shows of a note: who links to it, and who says its name.
typedef FootLinks = ({List<Backlink> backlinks, List<Mention> mentions});

/// [noteId]'s links as the foot draws them: those [readable] leaves in.
FootLinks footLinks(LinkIndex index, String noteId, String? Function(String id) bodyOf, {bool Function(String id)? readable}) {
  bool keep(String id) => readable?.call(id) ?? true;
  final backlinks = [
    for (final back in index.backlinksOf(noteId, bodyOf))
      if (back.links.isNotEmpty && keep(back.id)) back,
  ];
  if (backlinks.isEmpty) return (backlinks: const [], mentions: const []);
  return (
    backlinks: backlinks,
    mentions: [
      for (final mention in index.mentionsOf(noteId, bodyOf, most: 1))
        if (keep(mention.id)) mention,
    ],
  );
}

class BacklinksFoot extends StatefulWidget {
  const BacklinksFoot({super.key, required this.indexer, required this.noteId, required this.onOpen, this.onLink, this.placeOf, this.readable, this.start, this.end, this.most = 6, this.mostMentions = 3});

  final LinkIndexer indexer;
  final String noteId;

  /// Opens a note at a line, from 0.
  final void Function(String id, int line) onOpen;

  /// Makes a mention a link in its note, answering whether it did; absent where the other notes cannot be written,
  /// and there is no Link it.
  final Future<bool> Function(Mention mention, LinkPlace place)? onLink;

  /// Where a note is kept, in words: its workspace, or its folder; null for nothing to say.
  final String? Function(String id)? placeOf;

  /// Whether a note may be shown here: a team note of an organization the account is in, any note of its own.
  final bool Function(String id)? readable;

  /// The column's own edges, where they are not the page's gutter (a page to read on a wide window).
  final double? start;
  final double? end;

  /// From how many rows a group is folded to its count.
  final int most;
  final int mostMentions;

  @override
  State<BacklinksFoot> createState() => BacklinksFootState();
}

class BacklinksFootState extends State<BacklinksFoot> {
  FootLinks? _read;
  int _version = -1;
  LinkIndex? _from;
  bool _all = false;
  bool _allMentions = false;
  final Set<String> _linking = <String>{};

  /// What is drawn now, for a test.
  FootLinks get links => _now;

  @override
  void initState() {
    super.initState();
    widget.indexer.addListener(_changed);
  }

  @override
  void didUpdateWidget(BacklinksFoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.indexer, widget.indexer)) {
      oldWidget.indexer.removeListener(_changed);
      widget.indexer.addListener(_changed);
    }
    if (oldWidget.noteId != widget.noteId) {
      _version = -1;
      _all = _allMentions = false;
    }
  }

  @override
  void dispose() {
    widget.indexer.removeListener(_changed);
    super.dispose();
  }

  /// The index moved: drawn again, after the frame where it was told while the tree was being built.
  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  FootLinks get _now {
    final index = widget.indexer.index;
    if (_read == null || _version != index.version || !identical(_from, index)) {
      _read = footLinks(index, widget.noteId, widget.indexer.bodyOf, readable: widget.readable);
      _version = index.version;
      _from = index;
    }
    return _read!;
  }

  Future<void> _link(Mention mention, LinkPlace place) async {
    final link = widget.onLink;
    if (link == null || !_linking.add(mention.id)) return;
    setState(() {});
    try {
      await link(mention, place);
    } finally {
      _linking.remove(mention.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = _now;
    if (read.backlinks.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final count = read.backlinks.length;
    final folded = count >= widget.most && !_all;
    final mentions = read.mentions;
    final mentionsFolded = mentions.length > widget.mostMentions && !_allMentions;
    return Padding(
      key: const ValueKey<String>('backlinks-foot'),
      padding: EdgeInsets.fromLTRB(widget.start ?? gutter, t.space(4), widget.end ?? gutter, t.space(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 1, child: ColoredBox(color: t.color('glacier-border-subtle'))),
          SizedBox(height: t.space(3)),
          _Heading(
            text: 'Linked from ${_notes(count)}',
            action: count >= widget.most ? (_all ? 'Show fewer' : 'Show all') : null,
            onAction: () => setState(() => _all = !_all),
          ),
          if (!folded)
            for (final back in read.backlinks)
              _Row(
                key: ValueKey<String>('backlink:${back.id}'),
                title: back.title,
                place: widget.placeOf?.call(back.id),
                at: back.links.first,
                more: back.links.length - 1,
                onPress: () => widget.onOpen(back.id, back.links.first.line),
              ),
          if (mentions.isNotEmpty) ...[
            SizedBox(height: t.space(4)),
            _Heading(
              text: 'Mentioned in ${_notes(mentions.length)}',
              action: mentions.length > widget.mostMentions ? (_allMentions ? 'Show fewer' : 'Show all') : null,
              onAction: () => setState(() => _allMentions = !_allMentions),
            ),
            if (!mentionsFolded)
              for (final mention in mentions)
                _Row(
                  key: ValueKey<String>('mention:${mention.id}'),
                  title: mention.title,
                  place: widget.placeOf?.call(mention.id),
                  at: mention.places.first,
                  onPress: () => widget.onOpen(mention.id, mention.places.first.line),
                  linking: _linking.contains(mention.id),
                  onLink: widget.onLink == null ? null : () => _link(mention, mention.places.first),
                ),
          ],
        ],
      ),
    );
  }
}

String _notes(int count) => count == 1 ? '1 note' : '$count notes';

/// A group's heading: small spaced capitals, and Show all at its end where the group is long.
class _Heading extends StatelessWidget {
  const _Heading({required this.text, this.action, required this.onAction});
  final String text;
  final String? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    final action = this.action;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(1)),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              label: text,
              child: ExcludeSemantics(child: Text(text.toUpperCase(), style: t.text('xs', weight: 'bold', color: t.color('app-ink-3')).copyWith(letterSpacing: t.len('app-tracking-caps', em: size)))),
            ),
          ),
          if (action != null)
            GlacierPressable(
              onPressed: onAction,
              semanticLabel: action,
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(1)),
                child: ExcludeSemantics(child: Text(action, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.hovered || state.pressed ? 'glacier-text' : 'glacier-text-muted')))),
              ),
            ),
        ],
      ),
    );
  }
}

/// One note: its title and where it is kept over the line round its link, a press that opens it there, and for a
/// mention, Link it.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.title, required this.place, required this.at, required this.onPress, this.more = 0, this.onLink, this.linking = false});

  final String title;
  final String? place;
  final LinkPlace at;
  final int more;
  final VoidCallback onPress;
  final VoidCallback? onLink;
  final bool linking;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final big = t.fontSize('md');
    final small = t.fontSize('sm');
    final name = title.isEmpty ? 'Untitled' : title;
    final line = at.text.isEmpty ? (at.embed ? 'Drawn in it' : 'A link on its own') : at.text;
    final where = place;
    final link = onLink;
    final quiet = pageText(t, small, color: t.color('glacier-text-subtle'));
    return Row(
      children: [
        Expanded(
          child: GlacierPressable(
            onPressed: onPress,
            semanticLabel: 'Open $name${where == null ? '' : ', in $where'}, at: $line',
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(2)),
              decoration: BoxDecoration(
                color: state.pressed ? t.color('app-wash') : (state.hovered ? t.colorOf('color-mix(in srgb, var(--glacier-text) 5%, transparent)') : null),
                borderRadius: BorderRadius.circular(t.radius('md')),
              ),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      spacing: t.space(2),
                      children: [
                        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, big, weight: 'medium', color: t.color('glacier-text')))),
                        if (where != null && where.isNotEmpty)
                          Flexible(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')))),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (at.embed) ...[
                          Padding(padding: EdgeInsets.only(top: 0.2 * small), child: AppIcon(Lucide.squareDashed, size: small, color: t.color('glacier-text-subtle'))),
                          SizedBox(width: 0.4 * small),
                        ],
                        Expanded(child: _marked(t, line, at.text.isEmpty ? null : at.mark, quiet)),
                        if (more > 0) Text('  +$more', style: quiet),
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
            padding: EdgeInsetsDirectional.only(start: t.space(1)),
            child: GlacierPressable(
              onPressed: linking ? null : link,
              semanticLabel: 'Link it in $name',
              builder: (context, state) => DecoratedBox(
                decoration: ShapeDecoration(
                  shape: StadiumBorder(side: BorderSide(color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 40%, transparent)') : t.color('glacier-border-subtle'))),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 0.25 * small + 1, horizontal: 0.8 * small + 1),
                  child: ExcludeSemantics(child: Text(linking ? 'Linking' : 'Link it', style: pageText(t, small, weight: 'medium', color: t.color(linking ? 'glacier-text-muted' : 'glacier-text')))),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The line round a link, on one line, the link itself in the full ink.
Widget _marked(Tokens t, String text, (int, int)? mark, TextStyle style) {
  if (mark == null) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  var (from, to) = mark;
  var line = text;
  // A link far into its line is brought near the start, so a phone's one line still shows it.
  if (from > 28) {
    final cut = line.indexOf(' ', from - 22);
    final at = cut < 0 || cut >= from ? from - 18 : cut + 1;
    line = '…${line.substring(at)}';
    from = from - at + 1;
    to = to - at + 1;
  }
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: line.substring(0, from)),
      TextSpan(text: line.substring(from, to), style: style.copyWith(color: t.color('glacier-text'))),
      TextSpan(text: line.substring(to)),
    ]),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}
