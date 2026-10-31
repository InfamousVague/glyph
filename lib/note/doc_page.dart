/// A note that is a page of the page tree, drawn as a doc (docs/TEAMSPACES.md; Matt, 2026-10-31: "think about how we
/// can build better docs UIs and sidebar navigation for orgs and team members into our app so we better are able to
/// handle a notion like setup in teams", and of what to build first, "all four: the sidebar and page tree, the doc
/// page UI, the teamspace home and members, presence"). What the note's screen draws round a page's words, every
/// part read from the one model (lib/core/page_tree.dart) and the page's own front matter, nothing kept beside it:
///
///     DocCrumbs      Space › the pages above › this page, each a way there; the middle folded into … on a phone
///     DocIcon        the page's `icon:`, large, over its title, and on a desktop Add icon and Add cover on hover
///     DocEditedLine  "Edited 2 hr ago by ana · Owner: bo", under the title, from its versions and `owner:`
///     DocOutlineRail the headings beside the page on a wide window, the one being read marked (lib/links/outline.dart)
///     DocModeButton  Edit, on a page of a teamspace whose Home.md says `docs: read`; Read to go back
///     DocPages       "Pages in this page": a folder page's sub-pages as cards, one a row on a phone, a grid wide
///     DocSteps       the pages before and after in reading order, at the foot
///
/// **Which notes are pages.** Every note with a file is in the tree, but a note in Inbox is not a doc: the parts are
/// drawn for a note in an organization's space, and for a personal note that has a page above it or pages under it
/// ([DocPlace.of]). A note at the top of a personal workspace stays the plain note it was, with no crumbs naming
/// "Personal › Inbox" over every quick thought.
///
/// **Read or edit.** A teamspace's `docs: read` (its Home.md, [TeamspaceSettings]) opens its pages to be read: the
/// editor read-only and formatted, with Edit to start writing; the choice is the visit's, never stored (Matt: "A
/// per-space setting"). Personal is always edit. [withDocsMode] writes the setting.
///
/// **Simple mode** (GHST-103's rule: fancy things behind a More row that opens in place) keeps the crumbs, the steps,
/// the cards, the icon itself and Edit; the outline, the icon and cover's affordances and the edited line are the
/// More sheet's "This page" rows, behind More….
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/front_matter.dart' show frontMatterValue;
import '../core/library.dart' show NoteLibrary;
import '../core/note_text.dart' show firstLine;
import '../core/page_tree.dart';
import '../core/properties.dart' show linkTargets;
import '../core/versions_file.dart' show Version;
import '../core/versions_record.dart';
import '../core/workspaces.dart' show WorkspaceStore;
import '../editor/view/editor_view.dart';
import '../links/outline.dart';
import '../sheet/css.dart';
import '../sheet/kit.dart';
import 'version_history.dart' show agoText;

/// How wide the note's page must be before a doc page's outline stands beside its words, and the rail's width.
const double docRailFrom = 960;
const double docRailWidth = 240;

/// The More sheet's Add icon row, by its id: a desktop's Add icon, and a press on the icon, open the sheet at it.
const String docIconItem = 'doc-icon';

// ---- the tree the screen reads -------------------------------------------------------------------------------------

final Expando<PageTreeWatch> _trees = Expando<PageTreeWatch>('page tree');

/// The page tree over [library] and [workspaces], one for the pair however many notes are open: a [PageTreeWatch],
/// which listens only while a screen listens to it and builds only when a page's place could have changed.
ValueListenable<PageTree> pageTreeOver(NoteLibrary library, WorkspaceStore workspaces) {
  final kept = _trees[library];
  if (kept != null && identical(kept.workspaces, workspaces)) return kept;
  return _trees[library] = PageTreeWatch(library, workspaces);
}

// ---- where a page is -----------------------------------------------------------------------------------------------

/// One crumb: a space or a page above this one, or this page ([here]). [noteId] is the page to open; null for a
/// crumb that is no page (Personal, a folder with no page of its own) and for this page.
@immutable
class DocCrumb {
  const DocCrumb({required this.title, this.icon, this.noteId, this.here = false});

  final String title;
  final PageIcon? icon;
  final String? noteId;
  final bool here;

  @override
  bool operator ==(Object other) => other is DocCrumb && other.title == title && other.icon == icon && other.noteId == noteId && other.here == here;

  @override
  int get hashCode => Object.hash(title, icon, noteId, here);

  @override
  String toString() => 'DocCrumb($title${here ? ', here' : ''})';
}

/// A note's place as a doc: its node, its space and the space's settings, its crumbs, the pages either side and
/// those under it. Worked out again at each build from the tree, which is a walk up a few parents.
@immutable
class DocPlace {
  const DocPlace._(this.node, this.settings, this.crumbs);

  final PageNode node;
  final TeamspaceSettings settings;

  /// The space, the pages above, and this page last.
  final List<DocCrumb> crumbs;

  Space get space => node.space;

  /// The pages before and after in reading order (the tree's, as the sidebar lists them).
  PageNode? get previous => node.previous;
  PageNode? get next => node.next;

  /// The pages under it ("Pages in this page"): its children that are pages, a folder with no page left out.
  List<PageNode> get pages => [
        for (final child in node.children)
          if (child.note != null) child,
      ];

  /// Whether it opens to be read: a teamspace that says `docs: read`; never Personal.
  bool get readFirst => !space.isPersonal && settings.docs == DocsMode.read;

  /// The note as a doc page, or null where it is none (see the library's doc).
  static DocPlace? of(PageTree tree, String noteId) {
    final node = tree.nodeOf(noteId);
    if (node == null || node.note == null) return null;
    final space = node.space;
    final up = node.ancestors;
    if (space.isPersonal && !up.any((page) => page.note != null) && !node.children.any((child) => child.note != null)) return null;
    final settings = tree.settingsOf(space);
    final home = tree.homeOf(space);
    final crumbs = <DocCrumb>[
      if (home?.id != noteId) DocCrumb(title: space.name, icon: settings.icon, noteId: home?.id),
      for (final page in up) DocCrumb(title: page.title, icon: page.icon, noteId: page.note?.id),
      DocCrumb(title: node.title, icon: node.icon, here: true),
    ];
    return DocPlace._(node, settings, List.unmodifiable(crumbs));
  }
}

/// The crumbs as drawn: all of them, or on a phone ([compact]) the first, a fold (null) and the last two, where
/// there are more than three.
List<DocCrumb?> foldedCrumbs(List<DocCrumb> crumbs, {required bool compact}) =>
    !compact || crumbs.length <= 3 ? crumbs : <DocCrumb?>[crumbs.first, null, crumbs[crumbs.length - 2], crumbs.last];

/// Who a version names, as a sentence says it: "you" for this account's own (`me`, or [self]).
String editorName(String by, {String? self}) => by == 'me' || (self != null && by == self) ? 'you' : by;

/// The page's owner as its front matter says it (`owner: ana`, `owner: "[[Ana]]"`), or null.
String? ownerOf(String body) {
  final said = frontMatterValue(body, 'owner');
  if (said == null || said.trim().isEmpty) return null;
  final names = linkTargets(said);
  return names.isEmpty ? said.trim() : names.join(', ');
}

/// "Edited 2 hr ago by ana · Owner: bo": when the page last changed and who changed it (its last version, where it
/// keeps them; the note's own time, with no name, where it does not), and its owner where `owner:` names one.
String editedWords({required int at, String? by, String? owner, int? now, String? self}) {
  final who = by == null || by.isEmpty ? '' : ' by ${editorName(by, self: self)}';
  // A note that has never said when it changed (a time of 0) says only its owner.
  final edited = at <= 0 ? '' : 'Edited ${agoText(at, now: now)}$who';
  if (owner == null) return edited;
  return edited.isEmpty ? 'Owner: $owner' : '$edited · Owner: $owner';
}

// ---- drawing -------------------------------------------------------------------------------------------------------

Color _wash(Tokens t, [double part = 0.06]) {
  final ink = t.color('glacier-text');
  return ink.withValues(alpha: part * ink.a);
}

/// A page's icon at [size]: the emoji, or the icon pack's glyph by its name (Lucide's names), or a page's mark for a
/// name no pack here knows.
class DocIconMark extends StatelessWidget {
  const DocIconMark({super.key, required this.icon, required this.size, this.color});

  final PageIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final emoji = icon.emoji;
    if (emoji != null) {
      return Text(emoji, textScaler: TextScaler.noScaling, style: TextStyle(fontSize: size, height: 1.15, color: t.color('glacier-text')));
    }
    final glyph = Lucide.all[icon.name!.toLowerCase()] ?? Lucide.fileText;
    return lucide(glyph, size: size, color: color ?? t.color('glacier-text'), strokeWidth: size > 24 ? 1.6 : 2);
  }
}

/// A small word-button of the doc's own (a crumb, Add icon, Edit): muted, washed under a pointer.
class _Small extends StatelessWidget {
  const _Small({super.key, required this.label, this.onPressed, this.leading, this.semantic, this.strong = false, this.bordered = false});

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final String? semantic;
  final bool strong;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final ink = t.color('glacier-text');
    final text = Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, em, weight: strong ? 'medium' : 'regular', color: strong ? ink : muted));
    final row = Row(mainAxisSize: MainAxisSize.min, spacing: 0.35 * em, children: [?leading, Flexible(child: text)]);
    if (onPressed == null) return Padding(padding: EdgeInsets.symmetric(vertical: 0.3 * em, horizontal: 0.2 * em), child: row);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: semantic ?? label,
      excludeSemantics: true,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius('sm')),
            color: state.hovered || state.pressed ? _wash(t) : null,
            border: bordered ? Border.all(color: t.color('glacier-border-subtle'), width: snapBorder(context, 1)) : null,
          ),
          child: Padding(padding: EdgeInsets.symmetric(vertical: 0.3 * em, horizontal: (bordered ? 0.7 : 0.35) * em), child: row),
        ),
      ),
    );
  }
}

/// The crumbs over a page: Space › the pages above › this page. A crumb that is a page opens it; the fold (…) opens
/// out in place.
class DocCrumbs extends StatefulWidget {
  const DocCrumbs({super.key, required this.crumbs, required this.compact, this.open, this.trailing});

  final List<DocCrumb> crumbs;

  /// A phone's width: the middle crumbs folded into one … ([foldedCrumbs]).
  final bool compact;
  final ValueChanged<String>? open;

  /// What stands at the row's end: Edit, on a page to be read.
  final Widget? trailing;

  @override
  State<DocCrumbs> createState() => _DocCrumbsState();
}

class _DocCrumbsState extends State<DocCrumbs> {
  bool _unfolded = false;

  @override
  void didUpdateWidget(DocCrumbs old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.crumbs, widget.crumbs)) _unfolded = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final shown = foldedCrumbs(widget.crumbs, compact: widget.compact && !_unfolded);
    final row = <Widget>[];
    for (final (i, crumb) in shown.indexed) {
      if (i > 0) row.add(Padding(padding: EdgeInsets.symmetric(horizontal: 0.1 * em), child: lucide(Lucide.chevronRight, size: 12, color: muted)));
      if (crumb == null) {
        row.add(_Small(key: const ValueKey('doc-crumbs-fold'), label: '…', semantic: 'Show every page above this one', onPressed: () => setState(() => _unfolded = true)));
        continue;
      }
      final open = widget.open;
      final id = crumb.noteId;
      final icon = crumb.icon;
      row.add(Flexible(
        child: _Small(
          key: ValueKey('doc-crumb:$i'),
          label: crumb.title.isEmpty ? 'Untitled' : crumb.title,
          strong: crumb.here,
          leading: icon == null ? null : DocIconMark(icon: icon, size: 13, color: muted),
          semantic: crumb.here ? '${crumb.title}, this page' : 'Open ${crumb.title}',
          onPressed: crumb.here || id == null || open == null ? null : () => open(id),
        ),
      ));
    }
    return Semantics(
      container: true,
      label: 'Where this page is',
      child: Row(
        children: [
          Expanded(child: Row(children: row)),
          if (widget.trailing != null) Padding(padding: EdgeInsets.only(left: t.space(2)), child: widget.trailing),
        ],
      ),
    );
  }
}

/// Edit on a page opened to be read, Read on one being written in a space that reads first: the visit's choice.
class DocModeButton extends StatelessWidget {
  const DocModeButton({super.key, required this.reading, required this.onPressed});

  final bool reading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color(reading ? 'glacier-text' : 'glacier-text-muted');
    return _Small(
      key: ValueKey(reading ? 'doc-edit' : 'doc-read'),
      label: reading ? 'Edit' : 'Read',
      strong: reading,
      bordered: true,
      semantic: reading ? 'Edit this page' : 'Read this page',
      leading: lucide(reading ? Lucide.pencil : Lucide.bookOpen, size: 13, color: ink),
      onPressed: onPressed,
    );
  }
}

/// The page's icon, large over its title, and on a desktop the two ways to add what it lacks while the pointer is
/// over the page's head (Notion's "Add icon" and "Add cover").
class DocIcon extends StatefulWidget {
  const DocIcon({super.key, required this.icon, this.onIcon, this.onCover, this.hovering = false, this.start});

  final PageIcon? icon;

  /// Add icon (or the icon's own press, to change it) and Add cover; null where there is no such way here.
  final VoidCallback? onIcon;
  final VoidCallback? onCover;

  /// Whether the affordances wait for the pointer (a desktop); without it they are not drawn at all.
  final bool hovering;
  final double? start;

  @override
  State<DocIcon> createState() => _DocIconState();
}

class _DocIconState extends State<DocIcon> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final icon = widget.icon;
    final offers = widget.hovering && (widget.onCover != null || (icon == null && widget.onIcon != null));
    if (icon == null && !offers) return const SizedBox.shrink();
    final muted = t.color('glacier-text-muted');
    final drawn = icon == null
        ? null
        : GlacierPressable(
            key: const ValueKey('doc-icon'),
            onPressed: widget.onIcon,
            semanticLabel: widget.onIcon == null ? 'Page icon' : 'Change the page icon',
            excludeSemantics: true,
            builder: (context, state) => DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered && widget.onIcon != null ? _wash(t) : null),
              child: Padding(padding: const EdgeInsets.all(4), child: DocIconMark(icon: icon, size: 44)),
            ),
          );
    final row = offers
        ? AnimatedOpacity(
            opacity: _over ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Row(
              key: const ValueKey('doc-affordances'),
              spacing: t.space(1),
              children: [
                if (icon == null && widget.onIcon != null)
                  _Small(key: const ValueKey('doc-add-icon'), label: 'Add icon', leading: lucide(Lucide.sticker, size: 13, color: muted), onPressed: widget.onIcon),
                if (widget.onCover != null)
                  _Small(key: const ValueKey('doc-add-cover'), label: 'Add cover', leading: lucide(Lucide.image, size: 13, color: muted), onPressed: widget.onCover),
              ],
            ),
          )
        : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: Padding(
        padding: EdgeInsets.only(left: (widget.start ?? gutter) - 4, right: gutter, top: t.space(1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [?drawn, ?row]),
      ),
    );
  }
}

/// "Edited 2 hr ago by ana · Owner: bo", from the page's last version (read now and again as its file changes), or
/// the note's own time where it keeps none.
class DocEditedLine extends StatefulWidget {
  const DocEditedLine({super.key, required this.noteId, required this.updatedAt, this.owner, this.versions, this.self, this.now});

  final String noteId;
  final int updatedAt;
  final String? owner;
  final VersionsRecord? versions;

  /// This account's handle, which a version names as "you".
  final String? self;

  /// The time, for a test.
  final int Function()? now;

  @override
  State<DocEditedLine> createState() => _DocEditedLineState();
}

class _DocEditedLineState extends State<DocEditedLine> {
  Version? _last;
  StreamSubscription<VersionsRead>? _reads;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _reads?.cancel();
    _reads = widget.versions?.watch(widget.noteId).listen((read) {
      final last = read.versions.isEmpty ? null : read.versions.last;
      if (mounted && last?.n != _last?.n) setState(() => _last = last);
    });
  }

  @override
  void didUpdateWidget(DocEditedLine old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId || !identical(old.versions, widget.versions)) {
      _last = null;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_reads?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final last = _last;
    // The later of the two: a version is kept after a pause, so the words may have changed since.
    final useVersion = last != null && last.at >= widget.updatedAt - 60000;
    final words = editedWords(at: useVersion ? last.at : widget.updatedAt, by: useVersion ? last.by : null, owner: widget.owner, now: widget.now?.call(), self: widget.self);
    if (words.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: t.space(1), bottom: t.space(2)),
      child: Text(words, key: const ValueKey('doc-edited'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-muted'))),
    );
  }
}

/// The outline beside the page on a wide window: "On this page", then the headings, the one being read marked, a
/// press scrolling to it (lib/links/outline.dart's [LiveOutline], quiet where there is no heading).
class DocOutlineRail extends StatefulWidget {
  const DocOutlineRail({super.key, required this.view, required this.page});

  final EditorView view;
  final ScrollPosition page;

  @override
  State<DocOutlineRail> createState() => _DocOutlineRailState();
}

class _DocOutlineRailState extends State<DocOutlineRail> {
  late bool _any = outlineOf(widget.view.state.doc).isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
  }

  @override
  void didUpdateWidget(DocOutlineRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.view, widget.view)) {
      old.view.removeListener(_changed);
      widget.view.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    super.dispose();
  }

  /// Whether there is a heading to list, read again as the words change (the headings are the editor's kept lines).
  void _changed() {
    final any = outlineOf(widget.view.state.doc).isNotEmpty;
    if (any != _any && mounted) setState(() => _any = any);
  }

  @override
  Widget build(BuildContext context) {
    if (!_any) return const SizedBox.shrink();
    final t = context.tokens;
    return Column(
      key: const ValueKey('doc-outline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 0.6 * t.fontSize('sm'), bottom: t.space(1)),
          child: Text('On this page', style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('glacier-text-muted'))),
        ),
        LiveOutline(view: widget.view, page: widget.page, compact: true, quiet: true),
      ],
    );
  }
}

/// "Pages in this page": a folder page's sub-pages as cards, each its icon, its title and how it starts; one a row on
/// a phone (Matt, 2026-09-27: "one card per row on a phone" is the rule), two or three across wider.
class DocPages extends StatelessWidget {
  const DocPages({super.key, required this.pages, required this.open, this.start});

  final List<PageNode> pages;
  final ValueChanged<String>? open;
  final double? start;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final sm = t.fontSize('sm');
    final rule = t.color('glacier-border-subtle');
    final line = snapBorder(context, 1);
    return Semantics(
      container: true,
      label: 'Pages in this page',
      child: Padding(
        key: const ValueKey('doc-pages'),
        padding: EdgeInsets.fromLTRB(start ?? gutter, t.space(4), gutter, 0),
        child: LayoutBuilder(
          builder: (context, box) {
            final gap = t.space(2);
            final across = box.maxWidth >= 840 ? 3 : (box.maxWidth >= 520 ? 2 : 1);
            final width = (box.maxWidth - gap * (across - 1)) / across;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: t.space(2)),
                  child: Text('Pages in this page', style: pageText(t, sm, weight: 'medium', color: t.color('glacier-text-muted'))),
                ),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final page in pages)
                      SizedBox(
                        width: width,
                        child: GlacierPressable(
                          key: ValueKey('doc-page:${page.note!.id}'),
                          onPressed: open == null ? null : () => open!(page.note!.id),
                          semanticLabel: 'Open ${page.title}',
                          excludeSemantics: true,
                          builder: (context, state) {
                            final peek = firstLine(page.note!.body, 140);
                            return GlacierFocusRing(
                              visible: state.focused,
                              radius: t.radius('md'),
                              child: DecoratedBox(
                                decoration: BoxDecoration(border: Border.all(color: rule, width: line), borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered ? _wash(t) : null),
                                child: Padding(
                                  padding: EdgeInsets.all(t.space(3)),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    spacing: t.space(2),
                                    children: [
                                      if (page.icon case final icon?) DocIconMark(icon: icon, size: 20) else lucide(page.isFolder ? Lucide.folder : Lucide.fileText, size: 18, color: t.color('glacier-text-muted')),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          spacing: 2,
                                          children: [
                                            Text(page.title.isEmpty ? 'Untitled' : page.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, 16, weight: 'medium', color: t.color('glacier-text'))),
                                            if (peek.isNotEmpty) Text(peek, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('glacier-text-muted'))),
                                            if (page.children.isNotEmpty)
                                              Text('${page.children.length} ${page.children.length == 1 ? 'page' : 'pages'} inside', style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-muted'))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The pages before and after this one in reading order, at the foot: two wide buttons, Previous keeping the left
/// and Next the right (a notebook's chapter has the book's own foot, lib/book/book_nav.dart `BookFoot`, instead).
class DocSteps extends StatelessWidget {
  const DocSteps({super.key, this.previous, this.next, required this.open, this.start});

  final PageNode? previous;
  final PageNode? next;
  final ValueChanged<String>? open;
  final double? start;

  @override
  Widget build(BuildContext context) {
    if (previous == null && next == null) return const SizedBox.shrink();
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final line = snapBorder(context, 1);
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final rule = t.color('glacier-border-subtle');

    Widget step(PageNode page, {required bool forward}) {
      final arrow = lucide(forward ? Lucide.chevronRight : Lucide.chevronLeft, size: 14, color: muted);
      final word = Text(forward ? 'Next' : 'Previous', maxLines: 1, softWrap: false, style: pageText(t, sm, color: muted));
      final id = page.note!.id;
      return GlacierPressable(
        key: ValueKey(forward ? 'doc-next' : 'doc-prev'),
        semanticLabel: '${forward ? 'Next' : 'Previous'}: ${page.title}',
        excludeSemantics: true,
        onPressed: open == null ? null : () => open!(id),
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('md'),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: rule, width: line), borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered ? _wash(t) : null),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 11.2 + line, horizontal: 14.4 + line),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: forward ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                spacing: 3.2,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, spacing: 0.25 * sm, children: forward ? [Flexible(child: word), arrow] : [arrow, Flexible(child: word)]),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      if (page.icon case final icon?) DocIconMark(icon: icon, size: 15),
                      Flexible(
                        child: Text(page.title.isEmpty ? 'Untitled' : page.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, textAlign: forward ? TextAlign.end : TextAlign.start, style: pageText(t, 16, weight: 'medium', color: t.color('glacier-text'))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Previous and next page',
      child: Padding(
        padding: EdgeInsets.fromLTRB(start ?? gutter, t.space(4), gutter, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: line))),
          child: Padding(
            padding: EdgeInsets.only(top: t.space(4) + line, bottom: t.len('app-safe-bottom') + t.space(6)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                Expanded(child: previous == null ? const SizedBox.shrink() : step(previous!, forward: false)),
                Expanded(child: next == null ? const SizedBox.shrink() : step(next!, forward: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- the icon chooser (the More sheet's page) ----------------------------------------------------------------------

/// The emoji a page is most often given, first in the chooser.
const List<String> docIconChoices = ['📄', '📝', '📌', '📚', '🗂️', '📋', '✅', '💡', '🚀', '🎯', '📅', '🏠', '⭐', '🔥', '🧭', '🛠️', '📈', '🧪', '🎨', '💬', '🔒', '🌱', '🐛', '📦'];

/// The chooser's page in the More sheet: the common emoji, a field for any other (an emoji, a `:shortcode:` or an
/// icon's name, as `icon:` takes them), and Remove icon where the page has one.
class DocIconChooser extends StatefulWidget {
  const DocIconChooser({super.key, required this.current, required this.choose, required this.close});

  final PageIcon? current;
  final ValueChanged<String?> choose;
  final VoidCallback close;

  @override
  State<DocIconChooser> createState() => _DocIconChooserState();
}

class _DocIconChooserState extends State<DocIconChooser> {
  late String _typed = widget.current?.written ?? '';

  void _pick(String? icon) {
    widget.choose(icon);
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = widget.current?.written;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
          child: Wrap(
            spacing: t.space(1),
            runSpacing: t.space(1),
            children: [
              for (final emoji in docIconChoices)
                GlacierPressable(
                  key: ValueKey('doc-icon-choice:$emoji'),
                  onPressed: () => _pick(emoji),
                  semanticLabel: emoji,
                  selected: emoji == current ? true : null,
                  builder: (context, state) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.radius('sm')),
                      color: state.hovered || state.pressed || emoji == current ? _wash(t, 0.1) : null,
                    ),
                    child: SizedBox(width: 40, height: 40, child: Center(child: Text(emoji, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 24, height: 1)))),
                  ),
                ),
            ],
          ),
        ),
        SheetGroup(
          children: [
            SheetField(
              label: 'Or type one',
              value: _typed,
              placeholder: 'An emoji, :rocket: or an icon’s name',
              autoCorrect: false,
              autoCapitalize: TextCapitalization.none,
              onChange: (typed) => setState(() => _typed = typed),
              onSubmitted: (typed) => _pick(typed.trim().isEmpty ? null : typed.trim()),
            ),
            if (_typed.trim().isNotEmpty && _typed.trim() != current) SheetRow(key: const ValueKey('doc-icon-use'), label: 'Use “${_typed.trim()}”', onPress: () => _pick(_typed.trim())),
            if (current != null) SheetRow(key: const ValueKey('doc-icon-remove'), label: 'Remove icon', danger: true, onPress: () => _pick(null)),
          ],
        ),
      ],
    );
  }
}
