/// What a note is linked to, worn on the note: a small mark per link, with the name of the thing (the Notion board
/// its list goes to, the GitHub repo the AI reads for it). A port of `src/app/plugins/LinkMarks.tsx` with
/// `LinkMarks.module.css`, and of `useNoteLinks` from `src/app/plugins/hooks.ts`.
///
/// Each link's plugin says what the note is linked to (`NoteLink.linked`, types.dart); a plugin switched off says
/// nothing, and its marks go. A tap opens the cog sheet, where the link is changed or removed. The workspace the
/// note is filed in is not worn here: its tab wears it.
///
/// What differs:
/// - `useNoteLinks` is [NoteLinksBuilder], a widget that reads the links again when a plugin writes its storage or
///   its secrets ([onPluginStorage]) and when the registry changes. `usePlugins()` of hooks.ts has no widget of its
///   own: the registry is a [Listenable], so it is a `ListenableBuilder` over it.
/// - Both take the registry they read, which is the app's ([plugins]) unless one is given, and follow the app's when
///   another is put in place.
/// - The page's `title` on each mark ("Notion board: Roadmap", a tooltip under a mouse) is what a screen reader is
///   told for the mark in the row that cannot be pressed; the row that can says them all at once, as the page's.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'host.dart';
import 'registry.dart';

/// The links of [noteId], kept current (`useNoteLinks`): read again when a plugin writes what a note is linked to
/// (a board chosen, a repo unlinked) or is switched on or off.
class NoteLinksBuilder extends StatefulWidget {
  const NoteLinksBuilder({super.key, required this.noteId, this.registry, required this.builder});

  final String noteId;

  /// The registry asked; the app's ([plugins]) when null.
  final Registry? registry;
  final Widget Function(BuildContext context, List<NoteLinked> links) builder;

  @override
  State<NoteLinksBuilder> createState() => _NoteLinksBuilderState();
}

class _NoteLinksBuilderState extends State<NoteLinksBuilder> {
  Registry? _heard;
  VoidCallback? _offStorage;
  late List<NoteLinked> _links;

  Registry get _registry => widget.registry ?? plugins;

  @override
  void initState() {
    super.initState();
    _offStorage = onPluginStorage(_read);
    _hear();
    _links = _registry.linksOf(widget.noteId);
  }

  /// Listens to the registry in force, which is another once the app's is put in place.
  void _hear() {
    final now = _registry;
    if (identical(now, _heard)) return;
    _heard?.removeListener(_read);
    _heard = now..addListener(_read);
  }

  void _read() {
    if (!mounted) return;
    setState(() => _links = _registry.linksOf(widget.noteId));
  }

  @override
  void didUpdateWidget(NoteLinksBuilder old) {
    super.didUpdateWidget(old);
    _hear();
    _links = _registry.linksOf(widget.noteId);
  }

  @override
  void dispose() {
    _offStorage?.call();
    _heard?.removeListener(_read);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app's registry may have been put in place since this was last drawn (built_in.dart, a test's usePlugins).
    if (!identical(_registry, _heard)) {
      _hear();
      _links = _registry.linksOf(widget.noteId);
    }
    return widget.builder(context, _links);
  }
}

/// The marks a linked note carries at its top and in the list (`LinkMarks`): nothing at all for a note with no
/// links. With [onPress] the row is a button, set in from the page's edges as the note's own lines are; without, it
/// is a plain row with nothing to press.
class LinkMarks extends StatelessWidget {
  const LinkMarks({super.key, required this.noteId, this.onPress, this.registry});

  final String noteId;

  /// Opens the note's settings, where a link is changed or removed.
  final VoidCallback? onPress;

  /// The registry asked; the app's ([plugins]) when null.
  final Registry? registry;

  /// What a screen reader is told for the row that can be pressed (`aria-label`).
  static String said(List<NoteLinked> links) => 'Linked to ${links.map((l) => '${l.link.label} ${l.name}').join(' and ')}. Change in this note’s settings.';

  @override
  Widget build(BuildContext context) => NoteLinksBuilder(
        noteId: noteId,
        registry: registry,
        builder: (context, links) {
          if (links.isEmpty) return const SizedBox.shrink();
          final t = context.tokens;
          final press = onPress;
          if (press == null) return _row(t, links, t.color('app-ink-3'), named: true);
          return GlacierPressable(
            onPressed: press,
            semanticLabel: said(links),
            builder: (context, state) => Padding(
              // `button.row`: `padding-inline: var(--app-gutter-start) var(--app-gutter-end); padding-block: 0 var(--glacier-space-2)`
              padding: EdgeInsetsDirectional.only(start: t.len('app-gutter-start'), end: t.len('app-gutter-end'), bottom: t.space(2)),
              // `button.row:active { color: var(--app-ink) }`
              // One thing to a screen reader, said whole by the button: the marks are not read again inside it.
              child: ExcludeSemantics(child: _row(t, links, t.color(state.pressed ? 'app-ink' : 'app-ink-3'), named: false)),
            ),
          );
        },
      );

  /// `.row`: the marks in a line that wraps, `--glacier-space-3` apart and `--glacier-space-2` between lines.
  Widget _row(Tokens t, List<NoteLinked> links, Color ink, {required bool named}) => Wrap(
        spacing: t.space(3),
        runSpacing: t.space(2),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (final linked in links) LinkMark(key: ValueKey(linked.link.id), linked: linked, ink: ink, named: named)],
      );
}

/// One link's mark (`.mark`): the plugin's mark in a ring, the way the header draws its cog, and the name of the
/// thing beside it, on one line and cut short past 14rem.
class LinkMark extends StatelessWidget {
  const LinkMark({super.key, required this.linked, required this.ink, this.named = true});

  final NoteLinked linked;

  /// `currentColor`: the ring, the mark and the name are one ink.
  final Color ink;

  /// Whether a screen reader is told the mark by itself ("Notion board: Roadmap", the page's `title`).
  final bool named;

  /// The ring, for a test to find.
  static const Key ringKey = ValueKey<String>('link-mark-ring');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `.mark { font-size: var(--glacier-font-size-sm); line-height: 1.4; gap: 0.4em }`
    final size = t.fontSize('sm');
    // `.icon { font-size: 0.85em; inline-size: 1.5em; block-size: 1.5em }`, and the mark inside it is 1em of that.
    final em = 0.85 * size;
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: ringKey,
          width: 1.5 * em,
          height: 1.5 * em,
          alignment: Alignment.center,
          // `border: var(--app-line) solid currentColor; border-radius: var(--glacier-radius-full)`. The page draws
          // the 1.5px line of this ring as one pixel (measured: its computed border is 1px), as it does the round of
          // a note's settings (lib/note/note_settings.dart).
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: t.len('app-line').floorToDouble())),
          child: IconTheme(
            data: IconThemeData(color: ink, size: em),
            child: DefaultTextStyle(style: t.textAt(em, color: ink), child: Builder(builder: (context) => linked.link.icon(context, em))),
          ),
        ),
        SizedBox(width: 0.4 * size),
        Flexible(
          child: ConstrainedBox(
            // `.name { max-inline-size: 14rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`
            constraints: BoxConstraints(maxWidth: t.lenOf('14rem')),
            child: Text(linked.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: t.textAt(size, height: 1.4, color: ink)),
          ),
        ),
      ],
    );
    if (!named) return mark;
    return Semantics(label: '${linked.link.label}: ${linked.name}', child: ExcludeSemantics(child: mark));
  }
}
