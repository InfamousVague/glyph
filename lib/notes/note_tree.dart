import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/stored.dart';
import '../core/workspaces.dart' show Workspace, WorkspaceStore, Workspaces;
import '../perf/frame_log.dart';
import '../sheet/css.dart';
import '../sheet/flow.dart';
import 'book_place_mark.dart';
import 'note_peek.dart';
import 'org_mark.dart';
import 'tree.dart';
import 'workspace_sheet.dart';
import '../shell/wide_screen.dart' show hoverPointer;

/// The sidebar: one tree of notes, the same whether it sits beside the note on a desktop or opens over it on a phone
/// (Matt: "Make the sidebar on desktop the same sidebar that shows up in the pop-up sidebar. Make it more similar to
/// the obsidian sidebar"). A port of `src/app/notes/NoteTree.tsx` and `NoteTree.module.css`.
///
/// Shaped like Obsidian's file explorer: a row of small tools across the top, the workspaces as folders that fold
/// shut, the notes filed in none below them, the archive as a folder that starts shut, and the trash last, shut until
/// opened, where a note is brought back or deleted for good and Empty asks once on the button itself. Each note keeps
/// its drawing underneath its name unless names only is chosen, and the open one wears a ring rather than a fill.
///
/// [onClose] makes it the pop-up: a close button joins the tools. [notices] is what a docked sidebar must still
/// carry - an update waiting - and sits at the bottom, over the foot.
///
/// What differs from the web:
/// - The workspaces are the [workspaces] store it is handed, and which folders are shut, the trash and names only
///   are kept in [stored] (the app's own unless one is given), where the web's modules had one of each.
/// - A row's small drawing is [peek]: [NotePeek.plain] unless another is given, which is the note in the editor's
///   own lines as the page's is (`NotePeek.tsx`; lib/home/note_peek.dart).
/// - [emptyArt] is the ghost asleep on its blank sheet (`Ghost scene="no-notes"`), which is lib/art's to draw;
///   without it the words stand alone.
/// - Browse files is offered when [onBrowseFiles] is given, where the web asked the device itself
///   (`canBrowseFiles()`); the app's root asks for it (lib/core/library_files.dart `LibraryFiles.offered`).
/// - A row cannot be dragged onto a canvas (`draggable`, `application/x-glyph-note`): that comes with the canvas.
/// - A mouse's right-click on a row tells [onNoteMenu] which note and where; the menu itself (`notes/NoteMenu.tsx`)
///   is not ported.
/// - What a workspace's sheet does to notes is asked of the caller ([notesInWorkspace], [onTrashNotes]; see
///   workspace_sheet.dart).
/// - A folder's More and a note in the trash's two buttons are hidden until pointed at on a desktop, and always
///   shown on a phone, which is how `@media (hover: hover)` is answered on each (`hoverPointer`).
/// - [notices] is a list, spaced as the page's wrapper spaces its children; an empty one takes no room.
class NoteTree extends StatefulWidget {
  const NoteTree({
    super.key,
    required this.notes,
    required this.activeId,
    required this.onOpen,
    required this.onNew,
    required this.workspaces,
    this.onCommands,
    this.onSettings,
    this.onSpeak,
    this.onClose,
    this.notices = const [],
    this.trashed = const [],
    this.onRestore,
    this.onDestroy,
    this.onEmptyTrash,
    this.onOrganization,
    this.onBrowseFiles,
    this.onGraph,
    this.onNoteMenu,
    this.notesInWorkspace,
    this.onTrashNotes,
    this.stored,
    this.peek = NotePeek.plain,
    this.emptyArt,
  });

  final List<Note> notes;
  final String? activeId;
  final void Function(String id) onOpen;
  final VoidCallback onNew;
  final WorkspaceStore workspaces;
  final VoidCallback? onCommands;
  final VoidCallback? onSettings;
  final VoidCallback? onSpeak;
  final VoidCallback? onClose;
  final List<Widget> notices;

  /// The notes in the trash, newest first, and what can be done with them.
  final List<Note> trashed;
  final void Function(Note note)? onRestore;
  final void Function(Note note)? onDestroy;
  final VoidCallback? onEmptyTrash;

  /// An organization's own screen, from its folder's menu.
  final void Function(String orgId)? onOrganization;

  /// Shows the notes' folder in the Files app or Finder; the tool is there only when this is.
  final VoidCallback? onBrowseFiles;

  /// The graph of the notes and their links (lib/links/graph_view.dart); the tool is there only when this is.
  final VoidCallback? onGraph;

  /// A mouse's right-click on a note's row: the note, and where the pointer was.
  final void Function(String id, Offset at)? onNoteMenu;
  final List<String> Function(String workspaceId)? notesInWorkspace;
  final void Function(List<String> noteIds)? onTrashNotes;

  /// Where the folds, the trash's and names only are kept; the app's own memory when left out.
  final Stored? stored;

  /// A note drawn small under its name.
  final NotePeekBuilder peek;

  /// What is drawn over "No notes yet.".
  final Widget? emptyArt;

  @override
  State<NoteTree> createState() => _NoteTreeState();
}

/// Which workspace the sheet is up for: one that exists, or a new one.
class _Manage {
  const _Manage([this.space]);
  final Workspace? space;
}

class _NoteTreeState extends State<NoteTree> {
  late Set<String> _closed = readClosed(widget.stored);

  /// Names only (Matt: "Start with compact mode"): each note a line with its kind's mark, the way a file browser
  /// lists files, instead of its drawing. Kept to this device, as which folders are shut is.
  late bool _compact = readCompact(widget.stored);
  late bool _trashOpen = readTrashOpen(widget.stored);
  _Manage? _manage;

  /// Emptying asks once, on the button itself: the first press turns it into the question, a second press within a
  /// few seconds answers it.
  bool _asking = false;
  Timer? _askingFor;

  @override
  void dispose() {
    _askingFor?.cancel();
    super.dispose();
  }

  void _flipCompact() {
    writeCompact(!_compact, widget.stored);
    setState(() => _compact = !_compact);
  }

  void _setAndKeep(Set<String> next) {
    writeClosed(next, widget.stored);
    setState(() => _closed = next);
  }

  void _toggle(String id) {
    final next = {..._closed};
    if (!next.remove(id)) next.add(id);
    _setAndKeep(next);
  }

  void _ask(bool asking) {
    _askingFor?.cancel();
    _askingFor = asking ? Timer(const Duration(milliseconds: 4000), () => _ask(false)) : null;
    if (mounted) setState(() => _asking = asking);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Workspaces>(
      valueListenable: widget.workspaces,
      builder: (context, spaces, _) => _build(context, spaces),
    );
  }

  Widget _build(BuildContext context, Workspaces spaces) {
    final t = context.tokens;
    if (ghostPerf) Perf.count('tree.build');
    final look = _Look(context, t);
    final trashed = widget.trashed;
    final popup = widget.onClose != null;
    final compact = _compact;
    final nothing = widget.notes.isEmpty && trashed.isEmpty;

    // The list is kept from one build to the next, and made again only when something it draws changed: whoever
    // builds the sidebar builds it often (a line the phone wrote under a title, a sync's word), and the list is
    // every note there is.
    final had = _made;
    final drawn = (
      spaces: spaces,
      closed: _closed,
      trashOpen: _trashOpen,
      compact: compact,
      asking: _asking,
      active: widget.activeId,
      tokens: t,
      rule: look.rule,
      hairline: look.hairline,
      peek: widget.peek,
      // What the rows are handed, a bit each: a callback left out is a button not drawn.
      seams: (widget.onNoteMenu != null ? 1 : 0) | (widget.onOrganization != null ? 2 : 0) | (widget.onEmptyTrash != null ? 4 : 0) | (widget.onRestore != null ? 8 : 0) | (widget.onDestroy != null ? 16 : 0),
      // The ghost over an empty list is made anew by whoever hands it over: asked about only while it is drawn.
      art: nothing ? widget.emptyArt : null,
    );
    if (had != null && had.drawn == drawn && sameNotes(had.notes, widget.notes) && sameNotes(had.trashed, trashed)) {
      return _framed(context, t, look, had.tree, had.list, popup: popup, compact: compact);
    }
    if (ghostPerf) Perf.count('tree.list');
    final tree = noteTreeOf(widget.notes, spaces);

    /// Every page's book, for the rows' marks.
    final inBooks = bookIndex(widget.notes);

    Widget row(Note note) {
      if (ghostPerf) Perf.count('tree.row');
      // The note's words are read once and kept (lib/core/note_facts.dart): nothing of its body is read here.
      final facts = NoteFacts.of(note);
      final title = facts.title;
      final place = placeOf(inBooks, note);
      final active = note.id == widget.activeId;
      // The usual drawing is made from what the facts keep; another asked for is handed the body, as it asks.
      final small = compact ? null : (identical(widget.peek, NotePeek.plain) ? NotePeek.ofNote(context, note) : widget.peek(context, note.body));
      final name = cssLines(
        title.isEmpty ? 'Untitled' : title,
        look.rowTitle(untitled: title.isEmpty, weight: compact ? 'medium' : 'semibold'),
        // `-webkit-line-clamp: 2`; names only, `white-space: nowrap; text-overflow: ellipsis`.
        maxLines: compact ? 1 : 2,
        softWrap: !compact,
        overflow: TextOverflow.ellipsis,
      );
      return CssFlow.block(
        key: ValueKey('note-row-${note.id}'),
        // `.row { margin-block: 1px }`; `.tree[data-compact] .row { margin-block: 0 }`: kept by the list the row is
        // in ([rowsOf]), which lays out only the rows near the screen and so cannot leave the margins to a flow.
        child: Listener(
          // A mouse's right-click only: on a phone the same gesture is a press and hold, which the lists use.
          onPointerDown: widget.onNoteMenu == null
              ? null
              : (event) {
                  if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) widget.onNoteMenu!(note.id, event.position);
                },
          child: GlacierPressable(
            onPressed: () => widget.onOpen(note.id),
            // `aria-current="page"`
            selected: active ? true : null,
            builder: (context, state) => GlacierFocusRing(
              // `.row:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px }`
              visible: state.focused,
              offset: -2,
              radius: t.radius('md'),
              child: DecoratedBox(
                // `.row:hover { background: var(--app-paper-2) }`; `.row[data-active] { background: none }`
                decoration: BoxDecoration(color: state.hovered && !active ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('md'))),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  // The open note: a ring, not a fill.
                  // `box-shadow: inset 0 0 0 var(--app-line) color-mix(in oklch, var(--app-ink) 55%, transparent)`
                  decoration: BoxDecoration(
                    border: active ? Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)'), width: snapBorder(context, t.len('app-line'))) : null,
                    borderRadius: BorderRadius.circular(t.radius('md')),
                  ),
                  child: Padding(
                    // `padding: 0.5em 0.6em`; names only, `0.32em 0.6em`
                    padding: EdgeInsets.symmetric(vertical: (compact ? 0.32 : 0.5) * look.em, horizontal: 0.6 * look.em),
                    child: compact
                        // `grid-template-columns: auto minmax(0, 1fr); align-items: center; gap: 0.5em`
                        ? Row(
                            spacing: 0.5 * look.em,
                            children: [
                              _KindMark(book: facts.isBook, canvas: facts.isCanvas, color: t.color('app-ink-3')),
                              Expanded(child: name),
                            ],
                          )
                        // `display: grid; gap: 0.15em`
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            spacing: 0.15 * look.em,
                            children: [
                              name,
                              // A page of a book says which: the mark, and the book's name.
                              if (place != null) Align(alignment: AlignmentDirectional.centerStart, child: BookPlaceMark(place: place)),
                              // `.rowPeek { margin-block-start: var(--glacier-space-1) }`
                              if (small != null) Padding(padding: EdgeInsets.only(top: t.space(1)), child: small),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// `.inside`: a folder's notes sit in from its name, on a faint guide down the side - Obsidian's indent line.
    Widget inside(List<Widget> children) => CssFlow(
          // `margin-inline-start: 0.95em; padding-inline-start: 0.35em; border-inline-start: 1px solid var(--app-rule)`
          margin: EdgeInsets.only(left: 0.95 * look.em),
          padding: EdgeInsets.only(left: look.rule + 0.35 * look.em),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: t.color('app-rule'), width: look.rule))),
          collapse: true,
          children: children,
        );

    // The list, top to bottom, as the blocks a page lays one under another: each a sliver, so only the rows near the
    // screen are built. The margin between two blocks is the larger of the two that meet (`margin-block`
    // collapsing, lib/sheet/flow.dart), which a flow works out as it lays its children out; here each block is
    // told the room over it as it is added, by the same rule: [above] is its own top margin, and [pending] the
    // bottom margin of the block before it.
    final rowGap = compact ? 0.0 : 1.0;
    final slivers = <Widget>[];
    double? pending;
    double over(double above) => pending == null ? above : math.max(pending!, above);

    /// Notes' rows one under another, `margin-block` apart, the first [first] under what is over it.
    Widget rowsOf(List<Note> notes, {required double first}) => SliverList(
          delegate: SliverChildBuilderDelegate(
            // A row is made when it is laid out, not when the list is: a list made again (names only and back, a
            // folder shut or opened, a note changed) has every row it had built before any is laid out, and those
            // that turn out to be past the screen then, as most are when names give way to cards, were made, their
            // previews with them, and let go without being drawn (tool/perf.sh sidebar: of 25 to 29 cards made at
            // the switch back, about 7 are on the screen).
            (context, i) => LayoutBuilder(
              builder: (context, _) {
                final top = i == 0 ? first : rowGap;
                return top == 0 ? row(notes[i]) : Padding(padding: EdgeInsets.only(top: top), child: row(notes[i]));
              },
            ),
            childCount: notes.length,
            addAutomaticKeepAlives: false,
            // No layer of its own for a row: with one, the open note's row and a row whose preview opens with a
            // heading are drawn heavier in the card's pictures (test/sidebar, up to 226 steps of 255 on their
            // letters), and why was not found; without, every picture is byte for byte.
            addRepaintBoundaries: false,
            // The rows are said as they were: no place in a list is added to what a screen reader hears.
            addSemanticIndexes: false,
          ),
        );

    void folder(String id, String name, int count, List<Note> children, {String? hue, Workspace? space, LucideIcon? icon}) {
      final open = !_closed.contains(id);
      final org = space?.org;
      // `.folder { margin-block: 1px }`
      final gap = over(1);
      final parts = <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: gap),
            child: KeyedSubtree(
              key: ValueKey('folder-row-$id'),
              child: _FolderRow(
                look: look,
                open: open,
                onToggle: () => _toggle(id),
                lead: icon != null ? lucide(icon, size: 14, strokeWidth: 2.1, color: t.color('app-ink-3')) : _Hue(hue: hue ?? 'ink', em: look.folderSize),
                org: org != null,
                name: name,
                count: count,
                // A workspace's menu: its sheet, or for an organization's workspace the organization's own screen.
                end: space == null
                    ? null
                    : (hovered) => _Small(
                          look: look,
                          hides: true,
                          rowHovered: hovered,
                          label: org != null ? '${space.name}, organization settings' : 'Rename, recolour or delete ${space.name}',
                          icon: Lucide.ellipsis,
                          iconSize: 16,
                          stroke: 2.2,
                          onPressed: () {
                            if (org != null && widget.onOrganization != null) {
                              widget.onOrganization!(org);
                            } else {
                              setState(() => _manage = _Manage(space));
                            }
                          },
                        ),
              ),
            ),
          ),
        ),
      ];
      // The folder's own bottom margin, or the larger of it and its last child's, which collapses through it.
      pending = 1;
      if (open) {
        if (children.isNotEmpty) {
          // `.inside`: a folder's notes sit in from its name, on a faint guide down the side - Obsidian's indent
          // line. Its first row's margin collapses through its top, so the guide begins a row's margin under the
          // folder's name, and runs to the last row's foot.
          // `margin-inline-start: 0.95em; padding-inline-start: 0.35em; border-inline-start: 1px solid var(--app-rule)`
          parts.add(
            SliverPadding(
              padding: EdgeInsets.only(left: 0.95 * look.em, top: rowGap),
              sliver: _SliverGuide(
                side: BorderSide(color: t.color('app-rule'), width: look.rule),
                sliver: SliverPadding(padding: EdgeInsets.only(left: look.rule + 0.35 * look.em), sliver: rowsOf(children, first: 0)),
              ),
            ),
          );
        } else {
          // `.emptyFolder { margin: 0.2em 0 0.4em 1.3em; font-size: calc(var(--glacier-font-size-xs) * var(--app-text-scale)); color: var(--app-ink-4) }`
          parts.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(1.3 * look.smallSize, 0.2 * look.smallSize, 0, 0),
                child: Text('Nothing here yet.', style: pageText(t, look.smallSize, color: t.color('app-ink-4'))),
              ),
            ),
          );
          pending = math.max(1, 0.4 * look.smallSize);
        }
      }
      slivers.add(SliverMainAxisGroup(key: ValueKey('folder-$id'), slivers: parts));
    }

    /*
     * The trash (Matt: "Send deleted notes to a trash folder where we can empty it to perma delete notes or restore
     * notes"): last, under the archive, and shut until opened. A note in it is not opened from here - it has been
     * thrown away - but brought back, or deleted for good.
     */
    Widget trashFolder() => CssFlow(
          key: const ValueKey('folder-trash'),
          margin: const EdgeInsets.symmetric(vertical: 1),
          collapse: true,
          children: [
            _FolderRow(
              look: look,
              open: _trashOpen,
              onToggle: () {
                writeTrashOpen(!_trashOpen, widget.stored);
                setState(() => _trashOpen = !_trashOpen);
              },
              lead: lucide(Lucide.trash2, size: 14, strokeWidth: 2.1, color: t.color('app-ink-3')),
              org: false,
              name: 'Trash',
              count: trashed.length,
              end: widget.onEmptyTrash == null
                  ? null
                  : (_) => _EmptyTrash(
                        look: look,
                        asking: _asking,
                        count: trashed.length,
                        onPressed: () {
                          if (!_asking) return _ask(true);
                          _ask(false);
                          widget.onEmptyTrash!();
                        },
                      ),
            ),
            if (_trashOpen)
              inside([
                for (final note in trashed)
                  () {
                    final title = NoteFacts.of(note).title;
                    final said = title.isEmpty ? 'Untitled' : title;
                    return CssFlow.block(
                      key: ValueKey('trash-row-${note.id}'),
                      // `.trashRow { margin-block: 1px; padding: 0.35em 0.4em 0.35em 0.6em; display: flex; align-items: center; gap: 0.35em }`
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      child: _Hover(
                        builder: (context, hovered) => Padding(
                          padding: EdgeInsets.fromLTRB(0.6 * look.em, 0.35 * look.em, 0.4 * look.em, 0.35 * look.em),
                          child: Row(
                            spacing: 0.35 * look.em,
                            children: [
                              Expanded(
                                // `.trashRow .rowTitle { flex: 1; white-space: nowrap; text-overflow: ellipsis; color: var(--app-ink-2) }`,
                                // under `.rowTitle[data-untitled]`, which comes later in the sheet and so keeps its colour.
                                child: cssLines(
                                  said,
                                  look.rowTitle(untitled: title.isEmpty, weight: compact ? 'medium' : 'semibold', color: t.color('app-ink-2')),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.onRestore != null)
                                _Small(look: look, hides: false, rowHovered: hovered, label: 'Restore $said', icon: Lucide.rotateCcw, iconSize: 15, stroke: 2.2, onPressed: () => widget.onRestore!(note)),
                              if (widget.onDestroy != null)
                                _Small(look: look, hides: false, rowHovered: hovered, label: 'Delete $said for good', icon: Lucide.x, iconSize: 15, stroke: 2.4, danger: true, onPressed: () => widget.onDestroy!(note)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }(),
              ]),
          ],
        );

    Workspace? spaceOf(String id) {
      for (final space in spaces.list) {
        if (space.id == id) return space;
      }
      return null;
    }

    // The list as a sliver of the sidebar's scroller.
    final Widget list = nothing
        // `.empty { margin: var(--glacier-space-4) var(--glacier-space-2); color: var(--glacier-text-muted) }`
        ? SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(4), horizontal: t.space(2)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.emptyArt { margin-block-end: var(--glacier-space-3) }`
                  if (widget.emptyArt != null) Padding(padding: EdgeInsets.only(bottom: t.space(3)), child: widget.emptyArt),
                  Text('No notes yet.', style: pageText(t, look.em, color: t.color('glacier-text-muted'))),
                ],
              ),
            ),
          )
        : () {
            for (final f in tree.folders) {
              folder(f.id, f.name, f.notes.length, f.notes, hue: f.hue, space: spaceOf(f.id));
            }
            if (tree.loose.isNotEmpty) {
              slivers.add(rowsOf(tree.loose, first: over(rowGap)));
              pending = rowGap;
            }
            if (tree.archived.isNotEmpty) folder(archiveFolder, 'Archive', tree.archived.length, tree.archived, icon: Lucide.archive);
            if (trashed.isNotEmpty) {
              // The trash is built whole, a flow of its own in a flow that keeps its margin (1px) clear above and
              // below it: what is thrown away is few, and shut until it is opened.
              final gap = over(1);
              final trash = CssFlow(children: [trashFolder()]);
              slivers.add(SliverToBoxAdapter(child: gap > 1 ? Padding(padding: EdgeInsets.only(top: gap - 1), child: trash) : trash));
              pending = 0;
            } else if ((pending ?? 0) > 0) {
              // The last block's margin, under it.
              slivers.add(SliverToBoxAdapter(child: SizedBox(height: pending)));
            }
            return SliverSemantics(
              // `<ul aria-label="Your notes">`
              container: true,
              explicitChildNodes: true,
              label: 'Your notes',
              sliver: SliverMainAxisGroup(slivers: slivers),
            );
          }();

    // Lists of the tree's own: the ones handed over may be changed after.
    _made = (drawn: drawn, notes: List<Note>.of(widget.notes, growable: false), trashed: List<Note>.of(trashed, growable: false), tree: tree, list: list);
    return _framed(context, t, look, tree, list, popup: popup, compact: compact);
  }

  /// The list as it was made last, the tree it was made from, and everything it was made for.
  ({Object drawn, List<Note> notes, List<Note> trashed, Tree tree, Widget list})? _made;

  /// The sidebar round its [list]: the tools over it, the notices and the foot under it, and the workspace's sheet.
  Widget _framed(BuildContext context, Tokens t, _Look look, Tree tree, Widget list, {required bool popup, required bool compact}) {
    final every = [for (final folder in tree.folders) folder.id, if (tree.archived.isNotEmpty) archiveFolder];
    final allShut = every.isNotEmpty && every.every(_closed.contains);

    // Only the rows near the screen are built. In the card the scroller is as tall as its list, up to the room
    // there is; docked, it fills its column.
    final scroll = CustomScrollView(
      shrinkWrap: popup,
      slivers: [
        // `.scroll { overflow-y: auto; overscroll-behavior: contain; padding: 0 var(--glacier-space-2) var(--glacier-space-4) }`
        SliverPadding(padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(4)), sliver: list),
      ],
    );

    final manage = _manage;
    return DefaultTextStyle(
      // `.tree { color: var(--app-ink) }`
      style: pageText(t, look.em, color: t.color('app-ink')),
      child: Padding(
        // `.tree { padding-block-start: var(--app-safe-top) }`; `.tree[data-popup] { padding-block-start: 0 }`
        padding: EdgeInsets.only(top: popup ? 0 : t.len('app-safe-top')),
        child: Column(
          // `block-size: 100%`: docked, it fills its column; in the card, the card is as tall as it.
          mainAxisSize: popup ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `.tools { display: flex; align-items: center; gap: var(--glacier-space-1); padding: var(--glacier-space-2) var(--glacier-space-3) }`
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Notes',
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
                child: Row(
                  spacing: t.space(1),
                  children: [
                    _Tool(label: 'New note', icon: Lucide.squarePen, onPressed: widget.onNew),
                    _Tool(label: 'New workspace', icon: Lucide.folderPlus, onPressed: () => setState(() => _manage = const _Manage())),
                    if (widget.onCommands != null) _Tool(label: 'Search and commands', icon: Lucide.search, onPressed: widget.onCommands!),
                    _Tool(label: compact ? 'Show each note drawn small' : 'Show names only', icon: compact ? Lucide.layoutList : Lucide.list, onPressed: _flipCompact),
                    if (widget.onBrowseFiles != null) _Tool(label: 'Browse files', icon: Lucide.folderOpen, onPressed: widget.onBrowseFiles!),
                    if (every.isNotEmpty)
                      _Tool(
                        label: allShut ? 'Open every folder' : 'Fold every folder',
                        icon: allShut ? Lucide.chevronsUpDown : Lucide.chevronsDownUp,
                        onPressed: () => _setAndKeep(allShut ? {} : {...every}),
                      ),
                    // The last tool sits at the far end (`.tool[data-end] { margin-inline-start: auto }`).
                    if (popup) ...[const Spacer(), _Tool(label: 'Close', icon: Lucide.x, stroke: 2.2, onPressed: widget.onClose!)],
                  ],
                ),
              ),
            ),
            if (popup) Flexible(child: scroll) else Expanded(child: scroll),
            // At the bottom, over the foot, with room all round.
            // `.notices { display: flex; flex-direction: column; gap: var(--glacier-space-2); padding: var(--glacier-space-3) }`
            if (widget.notices.isNotEmpty)
              Padding(
                key: const ValueKey('tree-notices'),
                padding: EdgeInsets.all(t.space(3)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: t.space(2), children: widget.notices),
              ),
            if (widget.onSpeak != null || widget.onSettings != null || widget.onGraph != null)
              DecoratedBox(
                key: const ValueKey('tree-foot'),
                // `.foot { border-block-start: var(--glacier-hairline) solid var(--app-rule) }`
                decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule'), width: look.hairline))),
                child: Padding(
                  // `padding: var(--glacier-space-2) var(--glacier-space-3) calc(var(--app-safe-bottom) + var(--glacier-space-2))`
                  padding: EdgeInsets.fromLTRB(t.space(3), look.hairline + t.space(2), t.space(3), t.len('app-safe-bottom') + t.space(2)),
                  child: Row(
                    spacing: t.space(2),
                    children: [
                      if (widget.onSpeak != null) _Speak(onPressed: widget.onSpeak!),
                      // The graph of the notes, beside Settings at the foot: the tools over the notes are full on a phone.
                      if (widget.onGraph != null || widget.onSettings != null) const Spacer(),
                      if (widget.onGraph != null) _Tool(label: 'Graph of your notes', icon: Lucide.network, onPressed: widget.onGraph!),
                      if (widget.onSettings != null) _Tool(label: 'Settings', icon: Lucide.settings, onPressed: widget.onSettings!),
                    ],
                  ),
                ),
              ),
            if (manage != null)
              WorkspaceManageSheet(
                store: widget.workspaces,
                editing: manage.space,
                onClose: () => setState(() => _manage = null),
                onOrganization: widget.onOrganization,
                notesIn: widget.notesInWorkspace,
                onTrashNotes: widget.onTrashNotes,
              ),
          ],
        ),
      ),
    );
  }
}

/// A folder's guide down the side of its notes (`.inside { border-inline-start }`), for notes that are a sliver:
/// the line a box's left border was, drawn from the first row's top to the last row's foot whichever of them are
/// built. Past the rows laid out so far it runs on to where the rest are counted to end, which is off the screen.
class _SliverGuide extends SingleChildRenderObjectWidget {
  const _SliverGuide({required this.side, required Widget sliver}) : super(child: sliver);

  final BorderSide side;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSliverGuide(side, createLocalImageConfiguration(context));

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderSliverGuide)
      ..side = side
      ..configuration = createLocalImageConfiguration(context);
  }
}

class _RenderSliverGuide extends RenderProxySliver {
  _RenderSliverGuide(this._side, this._configuration);

  BorderSide _side;
  set side(BorderSide value) {
    if (value == _side) return;
    _side = value;
    _painter?.dispose();
    _painter = null;
    markNeedsPaint();
  }

  ImageConfiguration _configuration;
  set configuration(ImageConfiguration value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsPaint();
  }

  BoxPainter? _painter;

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sliver = child;
    if (sliver == null || !sliver.geometry!.visible) return;
    // The box the border was painted on: as wide as the rows' room, from where the first row begins (which may be
    // above the screen) for as far as the rows go.
    final painter = _painter ??= BoxDecoration(border: Border(left: _side)).createBoxPainter(markNeedsPaint);
    painter.paint(context.canvas, Offset(offset.dx, offset.dy - constraints.scrollOffset), _configuration.copyWith(size: Size(constraints.crossAxisExtent, sliver.geometry!.scrollExtent)));
    context.paintChild(sliver, offset);
  }
}

/// The sizes the tree's rules are written in, worked out once for a build.
class _Look {
  _Look(BuildContext context, this.t)
      // `1em` where nothing has set a size: the page's own.
      : em = t.lenOf('1rem'),
        scale = t.number('app-text-scale'),
        rule = snapBorder(context, 1),
        hairline = snapBorder(context, t.len('glacier-hairline'));

  final Tokens t;
  final double em;
  final double scale;
  final double rule;
  final double hairline;

  /// `1em` in a `<button>` that sets no font of its own: the browser's size for a control, which no token carries.
  static const double buttonEm = 13.3333;

  /// `.folderToggle { font-size: calc(var(--glacier-font-size-sm) * var(--app-text-scale)) }`
  double get folderSize => t.fontSize('sm') * scale;

  /// `calc(var(--glacier-font-size-xs) * var(--app-text-scale))`: Empty, and "Nothing here yet.".
  double get smallSize => t.fontSize('xs') * scale;

  /// `.rowTitle { font-size: calc(var(--glacier-font-size-sm) * var(--app-text-scale) * 1.06); line-height: 1.3 }`,
  /// and `.rowTitle[data-untitled] { color: var(--glacier-text-subtle) }`.
  TextStyle rowTitle({required bool untitled, required String weight, Color? color}) =>
      pageText(t, t.fontSize('sm') * scale * 1.06, weight: weight, height: 1.3, color: untitled ? t.color('glacier-text-subtle') : color ?? t.color('app-ink'));
}

/// Whether a control may wait to be pointed at (`@media (hover: hover)`): on a desktop, and never on a phone,
/// with a mouse joined to it or not, as the page's question is answered there (shell/wide_screen.dart
/// `hoverPointer`). It asked whether a mouse was connected, which hid a folder's More on a phone with a mouse where
/// the page keeps it shown.
bool _hovers() => hoverPointer;

/// Rebuilds with whether the pointer is over it.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// `Tool` (`.tool`): a small bare glyph in the row over the notes, as Obsidian has them over its files.
class _Tool extends StatelessWidget {
  const _Tool({required this.label, required this.icon, required this.onPressed, this.stroke = 2.1});
  final String label;
  final LucideIcon icon;

  /// `strokeWidth={…}`: 2.1 on every tool of the row and the foot's cog; the pop-up's Close asks for 2.2.
  final double stroke;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `inline-size: calc(var(--glacier-space-8) * 0.9); block-size: calc(var(--glacier-space-8) * 0.9)`
    final side = t.space(8) * 0.9;
    return GlacierPressable(
      onPressed: onPressed,
      // `aria-label={label} title={label}`
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        // `.tool:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px }`
        visible: state.focused,
        offset: -2,
        radius: t.radius('sm'),
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          // `border-radius: var(--glacier-radius-sm)`; `.tool:hover { background: var(--app-paper-2); color: var(--app-ink) }`
          decoration: BoxDecoration(color: state.hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
          child: lucide(icon, size: 17, strokeWidth: stroke, color: t.color(state.hovered ? 'app-ink' : 'app-ink-3')),
        ),
      ),
    );
  }
}

/// `KindMark` (`.kind`): a note's kind as a file browser would mark it: a book, a canvas, or a page of words.
class _KindMark extends StatelessWidget {
  const _KindMark({required this.book, required this.canvas, required this.color});

  /// Whether the note is a notebook, and whether it is a canvas, as its facts have them.
  final bool book;
  final bool canvas;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = book
        ? Lucide.bookOpen
        : canvas
            ? Lucide.workflow
            : Lucide.fileText;
    return ExcludeSemantics(child: KeyedSubtree(key: const ValueKey('kind-mark'), child: lucide(icon, size: 14, color: color)));
  }
}

/// `.hue`: the workspace's own colour, the same one its pill and its tabs wear (ink.css `[data-hue]`).
class _Hue extends StatelessWidget {
  const _Hue({required this.hue, required this.em});
  final String hue;
  final double em;

  @override
  Widget build(BuildContext context) {
    return GlacierScope(
      attrs: {'hue': hue},
      child: Builder(
        builder: (context) => ExcludeSemantics(
          // `inline-size: 0.55em; block-size: 0.55em; border-radius: 50%; background: var(--app-space, var(--app-ink-3))`
          child: Container(
            key: const ValueKey('folder-hue'),
            width: 0.55 * em,
            height: 0.55 * em,
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.tokens.colorOf('var(--app-space, var(--app-ink-3))')),
          ),
        ),
      ),
    );
  }
}

/// `.folderRow`: the folder's name, which folds it, and what stands at the row's end.
class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.look, required this.open, required this.onToggle, required this.lead, required this.org, required this.name, required this.count, required this.end});

  final _Look look;
  final bool open;
  final VoidCallback onToggle;

  /// The hue's dot, or the archive's or the trash's mark.
  final Widget lead;
  final bool org;
  final String name;
  final int count;

  /// A workspace's More, or the trash's Empty, told whether the row is pointed at.
  final Widget Function(bool hovered)? end;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final size = look.folderSize;
    final ink = t.color('app-ink');
    return _Hover(
      builder: (context, hovered) => DecoratedBox(
        // `.folderRow { border-radius: var(--glacier-radius-sm) }`; `.folderRow:hover { background: var(--app-paper-2) }`
        decoration: BoxDecoration(color: hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
        // `display: flex; align-items: center`
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                // `aria-expanded={open}`
                expanded: open,
                child: GlacierPressable(
                  onPressed: onToggle,
                  builder: (context, state) => GlacierFocusRing(
                    // `.folderToggle:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px; border-radius: var(--glacier-radius-sm) }`
                    visible: state.focused,
                    offset: -2,
                    radius: t.radius('sm'),
                    child: Padding(
                      // `.folderToggle { display: flex; align-items: center; gap: 0.45em; padding: 0.4em 0.35em }`
                      padding: EdgeInsets.symmetric(vertical: 0.4 * size, horizontal: 0.35 * size),
                      child: Row(
                        spacing: 0.45 * size,
                        children: [
                          // `.chevron { color: var(--app-ink-3); transition: transform 140ms var(--glacier-ease-out) }`,
                          // `.chevron[data-open] { transform: rotate(90deg) }`
                          ExcludeSemantics(
                            child: AnimatedRotation(
                              turns: open ? 0.25 : 0,
                              duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 140),
                              curve: t.curve('glacier-ease-out'),
                              child: lucide(Lucide.chevronRight, size: 15, strokeWidth: 2.2, color: t.color('app-ink-3')),
                            ),
                          ),
                          lead,
                          if (org) OrgMark(em: size, color: ink),
                          // `.folderName { min-inline-size: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis }`
                          Expanded(
                            child: Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, size, weight: 'semibold', color: ink)),
                          ),
                          // `.count { margin-inline-start: auto; padding-inline-start: 0.5em; font-weight: medium;
                          // font-variant-numeric: tabular-nums; color: var(--app-ink-4) }`
                          Padding(
                            padding: EdgeInsets.only(left: 0.5 * size),
                            child: Text(
                              '$count',
                              style: pageText(t, size, weight: 'medium', color: t.color('app-ink-4')).copyWith(fontFeatures: [...t.typography.features, const FontFeature.tabularFigures()]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (end != null) end!(hovered),
          ],
        ),
      ),
    );
  }
}

/// `.folderMore`, `.trashAction`: a small square button at a row's end: a folder's More, and a note in the trash's
/// two things to do.
class _Small extends StatelessWidget {
  const _Small({required this.look, required this.hides, required this.rowHovered, required this.label, required this.icon, required this.iconSize, required this.stroke, required this.onPressed, this.danger = false});

  final _Look look;

  /// A folder's More: there on a hover or a focus with a pointer, and always on a finger, which has no hover.
  final bool hides;
  final bool rowHovered;
  final String label;
  final LucideIcon icon;
  final double iconSize;

  /// `strokeWidth={…}` as the tree's JSX gives this button's icon.
  final double stroke;
  final VoidCallback onPressed;

  /// Delete for good: the kit's danger ink when pointed at.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    // `inline-size: 1.9em; block-size: 1.9em`, of a button's own size.
    const side = 1.9 * _Look.buttonEm;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        // `@media (hover: hover) { .folderMore { opacity: 0 } .folderRow:hover .folderMore, .folderMore:focus-visible { opacity: 1 } }`
        final shown = !hides || !_hovers() || rowHovered || state.focused;
        // `.trashAction:hover { color: var(--app-ink); background: color-mix(in oklch, var(--app-ink) 8%, transparent) }`,
        // `.trashAction[data-danger]:hover { color: var(--glacier-danger-text) }`
        final lit = !hides && state.hovered;
        return Opacity(
          opacity: shown ? 1 : 0,
          child: GlacierFocusRing(
            // `.trashAction:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 1px }`
            visible: state.focused,
            offset: 1,
            radius: t.radius('sm'),
            child: Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: lit ? t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: ExcludeSemantics(
                child: lucide(icon, size: iconSize, strokeWidth: stroke, color: t.color(lit ? (danger ? 'glacier-danger-text' : 'app-ink') : 'app-ink-3')),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.emptyTrash`: a quiet word at the folder's end, which turns into the question on the first press.
class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash({required this.look, required this.asking, required this.count, required this.onPressed});
  final _Look look;
  final bool asking;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final size = look.smallSize;
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) {
        // `.emptyTrash { color: var(--app-ink-3) }`,
        // `.emptyTrash:hover { color: var(--app-ink); background: color-mix(in oklch, var(--app-ink) 6%, transparent) }`,
        // `.emptyTrash[data-asking] { color: var(--glacier-danger-text); background: color-mix(in oklch, var(--glacier-danger-text) 14%, transparent) }`
        final color = asking
            ? t.color('glacier-danger-text')
            : state.hovered
                ? t.color('app-ink')
                : t.color('app-ink-3');
        final ground = asking
            ? t.colorOf('color-mix(in oklch, var(--glacier-danger-text) 14%, transparent)')
            : state.hovered
                ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)')
                : null;
        return GlacierFocusRing(
          visible: state.focused,
          offset: 1,
          radius: t.radius('sm'),
          child: Container(
            // `padding: 0.25em 0.6em; border-radius: var(--glacier-radius-sm)`
            padding: EdgeInsets.symmetric(vertical: 0.25 * size, horizontal: 0.6 * size),
            decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(t.radius('sm'))),
            child: Text(asking ? 'Delete $count for good?' : 'Empty', style: pageText(t, size, color: color)),
          ),
        );
      },
    );
  }
}

/// `.speak`: the foot's one filled button.
class _Speak extends StatelessWidget {
  const _Speak({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `font-size: var(--glacier-font-size-sm); font-weight: var(--glacier-font-weight-semibold)`
    final size = t.fontSize('sm');
    final paper = t.color('app-paper');
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) => GlacierFocusRing(
        // `.speak:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 2px }`
        visible: state.focused,
        child: Container(
          // `padding: 0.5em 0.95em; border-radius: var(--glacier-radius-full); background: var(--app-ink); color: var(--app-paper)`
          padding: EdgeInsets.symmetric(vertical: 0.5 * size, horizontal: 0.95 * size),
          decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
          // `display: inline-flex; align-items: center; gap: 0.45em`
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 0.45 * size,
            children: [
              ExcludeSemantics(child: lucide(Lucide.mic, size: 16, strokeWidth: 2.2, color: paper)),
              Text('Speak', style: pageText(t, size, weight: 'semibold', color: paper)),
            ],
          ),
        ),
      ),
    );
  }
}
