part of 'note_tree.dart';

// The sidebar as spaces and pages (docs/TEAMSPACES.md; Matt, 2026-10-31: "A space switcher at the top (Personal,
// then each organization) scoping the tree; above the tree, fixed rows: Home, Search, My tickets, Triage, Updates;
// then sections: Favorites, Teamspace (the organization's pages) or Private (your own), Shared with me").
//
// The same NoteTree, handed a SidebarSpaces (lib/notes/space_pages.dart), draws this in place of the folders, docked
// or in its card, on a phone and a desktop alike:
//
// - **The switcher**, over the tools: the space shown, Personal or an organization with its hue and its mark
//   (org_mark.dart); pressed, the spaces are listed under it in place. Which one is shown is this device's
//   (`glyph-sidebar-space`), never synced: a phone may be on the team while the Mac is on Personal.
// - **The fixed rows**: Home (Personal's home page, or the organization's own page), Search (the palette), My tickets,
//   Triage and Updates (the bell's card), each there only where the root gives it.
// - **Favorites**, the account's (lib/core/favorites.dart), those of the space shown, from a page's … menu.
// - **Private** or **Teamspace**: the space's page tree (lib/core/page_tree.dart), each page a row at its depth
//   with its `icon:` (an emoji, or an icon's name: lucide.g.dart `Lucide.all`), a notebook's or a canvas's mark
//   or a folder's otherwise; folded shut until opened, the folds this device's (`glyph-tree-pages-open`). A page's
//   + makes a page inside it ([newPageIn]: a plain note becomes its folder's page first) and its … is its menu:
//   Open, Favorites, Rename…, Add a page inside, Move to, Delete, and on a folder's page the folder's Remove folder,
//   keep its notes… and Delete folder and its notes… (lib/notes/folder_menu.dart). A row is dragged (a finger holds first, a mouse
//   just drags): let go over the top or the foot of another row it goes before or after it, which writes the
//   folder's `order:` ([PageMover.setOrder]); over its middle it goes into that page ([planMoveInto],
//   [PageMover.run]), and a move the plan refuses says why in a toast ([refusalWords]). A note with no file yet,
//   or in a folder the tree has no space for, is listed after Personal's pages so that nothing is out of reach.
// - **Shared with me** is not drawn: nothing yet says a note came from someone else (space_pages.dart's doc).
// - **The rest**: the Tags row, the Market, the smart notebooks, the archive and the trash, the old sidebar's own
//   rows (NoteTree `_list`, extras only); in simple mode behind a More row that opens in place, with Triage.
//
// Every row is at least a finger's 44 across where there is no mouse (`hoverPointer`); a page's + and … wait to be
// pointed at on a desktop and are always there on a phone. The presence marks (lib/team/presence_avatars.dart
// `PresenceMarked`) and a note's sync (lib/activity/sync_mark.dart) stand after a page's name as on the folders'.

/// A page lifted from its row.
@immutable
class _PageCarry {
  const _PageCarry(this.node);
  final PageNode node;
}

/// Where over a row a carried page is let go: before it, into it, after it.
enum _Drop { before, into, after }

/// One line of the pages' list: a page at its depth; a note the tree has no place for ([node] null); or the words
/// under an open folder with nothing in it ([empty]).
typedef _PageLine = ({PageNode? node, Note? note, int depth, bool empty});

/// Where the pointer is in a carried page's pill: a little off it, under and to the right of a mouse's arrow, above
/// a finger (as folder_drag.dart's pill is).
Offset get _pageGrip => mousePointer ? const Offset(-14, -14) : const Offset(24, 64);

const String _favoritesSection = 'section:favorites';

extension _SpacesTree on _NoteTreeState {
  /// The page tree of the notes handed over now.
  PageTree _pageTree() {
    if (!identical(_noteList.value, widget.notes)) _noteList.value = widget.notes;
    return _pages.value;
  }

  Map<String, Note> _notesById() {
    if (!identical(_byIdOf, widget.notes)) {
      _byIdOf = widget.notes;
      _byId = {for (final note in widget.notes) note.id: note};
    }
    return _byId;
  }

  Space _shownSpace(PageTree tree) => tree.spaces.firstWhere((space) => space.id == _spaceId, orElse: () => tree.spaces.first);

  /// The space a note is drawn in: the tree's, else Personal for one with no place in it that is not a team's.
  String? _spaceIdOf(PageTree tree, Note note) {
    final known = tree.spaceOf(note.id);
    if (known != null) return known.id;
    final path = note.path ?? '';
    return path == orgsFolder || path.startsWith('$orgsFolder/') ? null : personalSpaceId;
  }

  void _chooseSpace(Space space) {
    writeSidebarSpace(space.id, widget.stored);
    _set(() {
      _spaceId = space.id;
      _switching = false;
    });
  }

  void _keepOpen(Set<String> next) {
    writeOpenPages(next, widget.stored);
    _set(() => _pageOpen = next);
  }

  void _flipPage(String id) {
    final next = {..._pageOpen};
    if (!next.remove(id)) next.add(id);
    _keepOpen(next);
  }

  /// Says [words]: the root's toast, or the kit's where the root gives none, and aloud.
  void _sayIt(String words) {
    final say = widget.spaces?.onSay;
    if (say != null) {
      say(words);
      return;
    }
    try {
      GlacierToast.of(context).toast(message: Text(words));
    } on FlutterError {
      // No toasts over this sidebar (a test of its own): said aloud only.
    }
    final view = View.maybeOf(context);
    if (view != null) unawaited(SemanticsService.sendAnnouncement(view, words, Directionality.maybeOf(context) ?? TextDirection.ltr));
  }

  /// A page made inside [under], or at the top of [space], and opened.
  Future<void> _newPage(PageTree tree, Space space, PageNode? under) async {
    final mover = widget.spaces?.mover;
    if (mover == null) return;
    final id = await newPageIn(mover, tree, space, under: under);
    if (!mounted) return;
    if (id == null) return _sayIt(under != null && under.folder == null && under.path == null ? refusalWords(MoveRefusal.noFile) : 'The page could not be made there.');
    if (under != null && !_pageOpen.contains(under.id)) _flipPage(under.id);
    widget.onOpen(id);
  }

  /// [moved] let go [where] over [target]'s row.
  Future<void> _dropPage(PageTree tree, PageNode moved, PageNode target, _Drop where) async {
    final mover = widget.spaces?.mover;
    if (mover == null || moved.id == target.id) return;
    if (where == _Drop.into) {
      final plan = planMoveInto(tree, moved, target);
      if (!plan.ok) return _sayIt(refusalWords(plan.refused!));
      final ok = await mover.run(plan);
      if (!mounted) return;
      if (!ok) return _sayIt('${moved.title} changed while it was carried: try again.');
      if (!_pageOpen.contains(target.id)) _flipPage(target.id);
      return _sayIt('Moved ${moved.title} into ${target.title}');
    }
    final container = tree.containerOf(target);
    if (container == null) return;
    final rest = [for (final node in container.children) if (node.id != moved.id) node];
    var index = rest.indexWhere((node) => node.id == target.id);
    if (index < 0) return;
    if (where == _Drop.after) index += 1;
    final order = orderAfterDrop(container.children, moved, index);
    if (!identical(tree.containerOf(moved), container)) {
      final plan = planMoveInto(tree, moved, container);
      if (!plan.ok) return _sayIt(refusalWords(plan.refused!));
      if (!await mover.run(plan)) {
        if (mounted) _sayIt('${moved.title} changed while it was carried: try again.');
        return;
      }
    }
    final written = await mover.setOrder(container, order);
    if (!mounted || written) return;
    _sayIt(container.note == null && container.folder == null ? "Personal's top keeps your folders' own order." : 'The order could not be written.');
  }

  // ---- drawing ----

  Widget _buildSpaces(BuildContext context, Workspaces spaces, _Look look, SidebarSpaces given) {
    final t = look.t;
    if (ghostPerf) Perf.count('tree.spaces');
    final popup = widget.onClose != null;
    final coarse = !_hovers();
    final tree = _pageTree();
    final space = _shownSpace(tree);
    final byId = _notesById();
    final ink3 = t.color('app-ink-3');
    final byFolder = <String, Workspace>{
      for (final w in spaces.list) ?folderFor(w, spaces.list): w,
    };

    final slivers = <Widget>[];
    void add(Key key, Widget child) => slivers.add(SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 1), child: KeyedSubtree(key: key, child: child))));

    // The fixed rows.
    final onHome = given.onHome;
    if (onHome != null) {
      add(const ValueKey('space-home'), _ShelfRow(look: look, lead: HouseIcon(size: 14, strokeWidth: 2.1, color: ink3), name: 'Home', tall: coarse, onPressed: () => onHome(space)));
    }
    final onCommands = widget.onCommands;
    if (onCommands != null) add(const ValueKey('space-search'), _ShelfRow(look: look, icon: Lucide.search, name: 'Search', tall: coarse, onPressed: onCommands));
    final onTickets = widget.onTickets;
    if (onTickets != null) {
      final count = widget.ticketCount;
      add(
        const ValueKey('tree-tickets'),
        _ShelfRow(look: look, icon: Lucide.ticket, name: 'My tickets', count: count == null || count.all == 0 ? null : count.all, late: count != null && count.overdue > 0, tall: coarse, onPressed: onTickets),
      );
    }
    final onTriage = given.onTriage;
    Widget triage() => _ShelfRow(look: look, icon: Lucide.listFilter, name: 'Triage', tall: coarse, onPressed: onTriage!);
    if (onTriage != null && !widget.simple) add(const ValueKey('space-triage'), triage());
    final onUpdates = given.onUpdates;
    if (onUpdates != null) add(const ValueKey('space-updates'), _ShelfRow(look: look, icon: Lucide.bell, name: 'Updates', tall: coarse, onPressed: onUpdates));

    // Favorites: the account's, those of the space shown.
    final favorites = [
      for (final id in given.favorites)
        if (byId[id] case final note? when note.archivedAt == null && !note.inTrash && _spaceIdOf(tree, note) == space.id) note,
    ];
    if (favorites.isNotEmpty) {
      final open = !_closed.contains(_favoritesSection);
      add(const ValueKey('section-favorites'), _SectionHead(look: look, name: 'Favorites', open: open, coarse: coarse, onToggle: () => _toggle(_favoritesSection)));
      if (open) {
        for (final note in favorites) {
          add(ValueKey('favorite-row-${note.id}'), _lineOf(context, look, tree, space, (node: tree.nodeOf(note.id), note: note, depth: 0, empty: false), byFolder, given, coarse: coarse, nested: false));
        }
      }
    }

    // The space's pages.
    final section = 'section:pages:${space.id}';
    final open = !_closed.contains(section);
    final sectionName = space.isPersonal ? 'Private' : 'Teamspace';
    add(
      const ValueKey('section-pages'),
      _SectionHead(
        look: look,
        name: sectionName,
        open: open,
        coarse: coarse,
        onToggle: () => _toggle(section),
        addLabel: 'New page in ${space.isPersonal ? 'Private' : space.name}',
        onAdd: given.mover == null ? null : () => unawaited(_newPage(tree, space, null)),
      ),
    );
    if (open) {
      final lines = <_PageLine>[];
      void walk(List<PageNode> nodes, int depth) {
        for (final node in nodes) {
          lines.add((node: node, note: null, depth: depth, empty: false));
          if (!_pageOpen.contains(node.id)) continue;
          if (node.children.isNotEmpty) {
            walk(node.children, depth + 1);
          } else if (node.isFolder) {
            lines.add((node: null, note: null, depth: depth + 1, empty: true));
          }
        }
      }

      walk(tree.rootsOf(space), 0);
      if (space.isPersonal) {
        for (final note in widget.notes) {
          if (note.archivedAt != null || note.inTrash || tree.nodeOf(note.id) != null || _spaceIdOf(tree, note) == null) continue;
          lines.add((node: null, note: note, depth: 0, empty: false));
        }
      }
      if (lines.isEmpty) {
        add(
          const ValueKey('pages-none'),
          Padding(
            padding: EdgeInsets.fromLTRB(1.3 * look.smallSize, 0.3 * look.smallSize, 0, 0.4 * look.smallSize),
            child: Text('No pages yet.', style: pageText(t, look.smallSize, color: t.color('app-ink-4'))),
          ),
        );
      } else {
        slivers.add(
          SliverList(
            key: ValueKey('pages-$section'),
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(padding: const EdgeInsets.only(top: 1), child: _lineOf(context, look, tree, space, lines[i], byFolder, given, coarse: coarse, nested: true)),
              childCount: lines.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
            ),
          ),
        );
      }
    }

    // The rest of the old sidebar: in simple mode behind More, which opens in place.
    final extras = _list(context, spaces, look, extrasOnly: true, compact: true);
    if (widget.simple) {
      add(
        const ValueKey('space-more'),
        Semantics(
          expanded: _moreOpen,
          child: _ShelfRow(look: look, icon: _moreOpen ? Lucide.chevronUp : Lucide.ellipsis, name: _moreOpen ? 'Less' : 'More', tall: coarse, onPressed: () => _set(() => _moreOpen = !_moreOpen)),
        ),
      );
      if (_moreOpen) {
        if (onTriage != null) add(const ValueKey('space-triage'), triage());
        slivers.add(extras.list);
      }
    } else {
      slivers.add(SliverPadding(padding: EdgeInsets.only(top: t.space(3)), sliver: extras.list));
    }

    final list = SliverSemantics(container: true, explicitChildNodes: true, label: 'Your pages', sliver: SliverMainAxisGroup(slivers: slivers));

    // Open or Fold every folder: the pages of the space shown that hold any.
    final foldable = [for (final node in tree.readingOrder(space)) if (node.children.isNotEmpty) node.id];
    final shut = foldable.every((id) => !_pageOpen.contains(id));
    return _framed(
      context,
      t,
      look,
      extras.tree,
      list,
      popup: popup,
      compact: true,
      top: _switcher(context, look, tree.spaces, space, coarse: coarse),
      fold: (
        allShut: shut,
        onPressed: foldable.isEmpty ? null : () => _keepOpen(shut ? {..._pageOpen, ...foldable} : {..._pageOpen}..removeAll(foldable)),
      ),
      overlay: [?_pageMenuOf(context, tree, space, byFolder, given)],
    );
  }

  /// The switcher: the space shown, and pressed, every space under it.
  Widget _switcher(BuildContext context, _Look look, List<Space> all, Space space, {required bool coarse}) {
    final t = look.t;
    final size = look.folderSize;
    final ink = t.color('app-ink');
    final many = all.length > 1;
    Widget mark(Space each) => each.isPersonal
        ? lucide(Lucide.userRound, size: 15, strokeWidth: 2.1, color: t.color('app-ink-3'))
        : Row(mainAxisSize: MainAxisSize.min, spacing: 0.45 * size, children: [_Hue(hue: each.hue ?? 'ink', em: size * 1.3), OrgMark(em: size, color: ink)]);
    Widget line(Space each, {required bool head, required PressState state}) => Container(
          constraints: BoxConstraints(minHeight: coarse ? 44 : 32),
          padding: EdgeInsets.symmetric(horizontal: 0.6 * size, vertical: 0.3 * size),
          decoration: BoxDecoration(color: state.hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Row(
            spacing: 0.55 * size,
            children: [
              mark(each),
              Expanded(child: Text(each.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, head ? size * 1.08 : size, weight: 'semibold', color: ink))),
              if (head && many) lucide(Lucide.chevronsUpDown, size: 15, strokeWidth: 2.1, color: t.color('app-ink-3')),
              if (!head && each.id == space.id) lucide(Lucide.check, size: 15, strokeWidth: 2.4, color: ink),
            ],
          ),
        );
    return Padding(
      key: const ValueKey('space-switcher'),
      padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(2), 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: many ? _switching : null,
            child: GlacierPressable(
              key: const ValueKey('space-switcher-head'),
              onPressed: many ? () => _set(() => _switching = !_switching) : null,
              semanticLabel: many ? '${space.name}, switch space' : space.name,
              builder: (context, state) => GlacierFocusRing(visible: state.focused, offset: -2, radius: t.radius('md'), child: ExcludeSemantics(child: line(space, head: true, state: state))),
            ),
          ),
          if (_switching && many)
            for (final each in all)
              GlacierPressable(
                key: ValueKey('space-choice-${each.id}'),
                onPressed: () => _chooseSpace(each),
                selected: each.id == space.id,
                semanticLabel: each.name,
                builder: (context, state) => GlacierFocusRing(visible: state.focused, offset: -2, radius: t.radius('md'), child: ExcludeSemantics(child: line(each, head: false, state: state))),
              ),
        ],
      ),
    );
  }

  /// A page's mark before its name: its `icon:`, else a folder's, a notebook's, a canvas's or a page's.
  Widget _leadOf(_Look look, PageNode? node, Note? note, Workspace? folder, {required bool open}) {
    final t = look.t;
    final ink3 = t.color('app-ink-3');
    final icon = node?.icon;
    final emoji = icon?.emoji;
    if (emoji != null) {
      return SizedBox(width: 16, child: Text(emoji, key: const ValueKey('page-emoji'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.1, color: t.color('app-ink'))));
    }
    final named = icon?.name == null ? null : Lucide.all[icon!.name!.toLowerCase()];
    if (named != null) return KeyedSubtree(key: const ValueKey('page-icon'), child: lucide(named, size: 14, strokeWidth: 2.1, color: ink3));
    if (node != null && node.isPlainFolder) {
      if (folder != null) return SizedBox(width: 14, child: Center(child: _Hue(hue: folder.hue ?? 'ink', em: look.folderSize)));
      return lucide(open ? Lucide.folderOpen : Lucide.folder, size: 14, strokeWidth: 2.1, color: ink3);
    }
    final facts = note == null ? null : NoteFacts.of(note);
    return _KindMark(book: facts?.isBook ?? false, canvas: facts?.isCanvas ?? false, color: ink3);
  }

  /// One line of the pages' list, or of the favorites ([nested] false: no fold, no +, no drag).
  Widget _lineOf(BuildContext context, _Look look, PageTree tree, Space space, _PageLine line, Map<String, Workspace> byFolder, SidebarSpaces given, {required bool coarse, required bool nested}) {
    final t = look.t;
    if (line.empty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(_indent(look, line.depth) + 1.3 * look.smallSize, 0.25 * look.smallSize, 0, 0.25 * look.smallSize),
        child: Text('No pages inside', style: pageText(t, look.smallSize, color: t.color('app-ink-4'))),
      );
    }
    final node = line.node;
    final listed = node?.note ?? line.note;
    final note = listed == null ? null : (_notesById()[listed.id] ?? listed);
    final id = node?.id ?? note!.id;
    final title = node?.title ?? NoteFacts.of(note!).title;
    final said = title.trim().isEmpty ? 'Untitled' : title;
    final foldable = nested && node != null && (node.children.isNotEmpty || node.isFolder);
    final open = _pageOpen.contains(id);
    final folder = node?.folder == null ? null : byFolder[node!.folder];
    final mover = given.mover;
    final onAdd = nested && mover != null && node != null && (node.isFolder || node.path != null) ? () => unawaited(_newPage(tree, space, node)) : null;
    ValueChanged<Offset>? onMore;
    if (note != null) {
      onMore = (at) => _set(() => _pageMenu = (node: node, note: note, at: at));
    } else if (folder != null && folder.org == null) {
      onMore = (_) => _set(() => _manage = _Manage(folder));
    }
    final onNoteMenu = widget.onNoteMenu;
    Widget face(_Drop? zone) => _PageRowFace(
          look: look,
          title: said,
          untitled: title.trim().isEmpty,
          depth: line.depth,
          lead: _leadOf(look, node, note, folder, open: open),
          foldable: foldable,
          open: open,
          active: note != null && note.id == widget.activeId,
          coarse: coarse,
          note: note,
          zone: zone,
          onOpen: note != null ? () => widget.onOpen(note.id) : (foldable ? () => _flipPage(id) : null),
          onToggle: foldable ? () => _flipPage(id) : null,
          onAdd: onAdd,
          onMore: onMore,
          onMenu: note == null || onNoteMenu == null ? null : (at) => onNoteMenu(note.id, at),
          renaming: note != null && _renaming == note.id,
          onRenamed: (text) {
            _set(() => _renaming = null);
            final rename = given.onRename;
            if (text == null || note == null || rename == null) return;
            final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (clean.isNotEmpty && clean != title) rename(note.id, clean);
          },
        );
    final Widget row = !nested || node == null || mover == null
        ? face(null)
        : _PageCarrySource(
            node: node,
            enabled: _renaming != id,
            child: _PageDropTarget(target: node, onDrop: (moved, where) => unawaited(_dropPage(tree, moved, node, where)), builder: (context, zone) => face(zone)),
          );
    return KeyedSubtree(key: ValueKey(nested ? 'page-row-$id' : 'favorite-$id'), child: row);
  }

  /// A page's menu while it is up: what its … offers.
  Widget? _pageMenuOf(BuildContext context, PageTree tree, Space space, Map<String, Workspace> byFolder, SidebarSpaces given) {
    final at = _pageMenu;
    if (at == null) return null;
    final note = at.note, node = at.node;
    final t = context.tokens;
    final em = coarsePointer ? t.fontSize('md') : t.fontSize('sm');
    Widget icon(LucideIcon which) => AppIcon(which, size: em);
    final title = node?.title ?? NoteFacts.of(note).title;
    final said = title.trim().isEmpty ? 'Untitled' : title;
    final favorite = given.favorites.contains(note.id);
    final onFavorite = given.onFavorite, onRename = given.onRename, onTrash = widget.onTrashNotes;
    final folder = node?.folder == null ? null : byFolder[node!.folder];
    // A folder's page: the folder's own two deletes after the page's (Matt, 2026-11-01: "add ability to context menu
    // delete folders and items inside them"), never an organization's own workspace's.
    final folderScope = folder == null || folder.org != null ? null : FolderMenuScope.maybeOf(context);
    return PopMenu(
      key: ValueKey('page-menu:${note.id}:${at.at.dx}:${at.at.dy}'),
      anchor: GlacierAnchor.point(at.at),
      onDismiss: () {
        if (identical(_pageMenu, at)) _set(() => _pageMenu = null);
      },
      ariaLabel: '$said, page',
      children: [
        GlacierMenuItem(icon: icon(Lucide.externalLink), onSelect: () => widget.onOpen(note.id), child: const Text('Open')),
        if (onFavorite != null)
          GlacierMenuItem(
            key: const ValueKey('page-menu-favorite'),
            icon: icon(favorite ? Lucide.bookmarkCheck : Lucide.bookmark),
            onSelect: () => onFavorite(note.id, !favorite),
            child: Text(favorite ? 'Remove from Favorites' : 'Add to Favorites'),
          ),
        if (onRename != null) GlacierMenuItem(key: const ValueKey('page-menu-rename'), icon: icon(Lucide.pencil), onSelect: () => _set(() => _renaming = note.id), child: const Text('Rename…')),
        if (given.mover != null && node != null && (node.isFolder || node.path != null))
          GlacierMenuItem(key: const ValueKey('page-menu-add'), icon: icon(Lucide.filePlus), onSelect: () => unawaited(_newPage(tree, space, node)), child: const Text('Add a page inside')),
        if (folder != null && folder.org == null)
          GlacierMenuItem(icon: icon(Lucide.folderOpen), onSelect: () => _set(() => _manage = _Manage(folder)), child: Text('${folder.name}, folder settings…')),
        ...folderMoveRows(context, widget.workspaces, FolderCarry.note(note.id, said)),
        if (onTrash != null || folderScope != null) const GlacierMenuSeparator(),
        if (onTrash != null)
          GlacierMenuItem(key: const ValueKey('page-menu-delete'), danger: true, style: dangerRowStyle(t), icon: icon(Lucide.trash2), onSelect: () => onTrash([note.id]), child: const Text('Delete')),
        if (folderScope != null) ...folderDeleteRows(folderScope, folder!, icon: icon, t: t),
      ],
    );
  }
}

/// How far a row at [depth] stands in from the list's edge.
double _indent(_Look look, int depth) => depth * 0.9 * look.em;

/// A section's head: its name in the quiet ink, folding what is under it, and a + for a new page at its top.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.look, required this.name, required this.open, required this.coarse, required this.onToggle, this.onAdd, this.addLabel = 'New page'});

  final _Look look;
  final String name;
  final bool open;
  final bool coarse;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final size = look.smallSize;
    return _Hover(
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(top: t.space(2)),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                expanded: open,
                child: GlacierPressable(
                  onPressed: onToggle,
                  semanticLabel: name,
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    offset: -2,
                    radius: t.radius('sm'),
                    child: Container(
                      constraints: BoxConstraints(minHeight: coarse ? 44 : 26),
                      padding: EdgeInsets.symmetric(horizontal: 0.6 * look.em, vertical: 0.2 * size),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(color: state.hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
                      child: ExcludeSemantics(
                        child: Row(
                          spacing: 0.35 * size,
                          children: [
                            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, size, weight: 'semibold', color: t.color('app-ink-3')))),
                            Opacity(
                              opacity: !_hovers() || hovered || !open ? 1 : 0,
                              child: AnimatedRotation(
                                turns: open ? 0.25 : 0,
                                duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 140),
                                child: lucide(Lucide.chevronRight, size: 12, strokeWidth: 2.4, color: t.color('app-ink-4')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onAdd != null) _RowButton(look: look, coarse: coarse, rowHovered: hovered, label: addLabel, icon: Lucide.plus, onPressed: (_) => onAdd!()),
          ],
        ),
      ),
    );
  }
}

/// A row's + or …: waits to be pointed at with a mouse, always there for a finger, a finger's 44 across.
class _RowButton extends StatelessWidget {
  const _RowButton({required this.look, required this.coarse, required this.rowHovered, required this.label, required this.icon, required this.onPressed});

  final _Look look;
  final bool coarse;
  final bool rowHovered;
  final String label;
  final LucideIcon icon;

  /// Told where the button's foot is, for a menu to hang from.
  final ValueChanged<Offset> onPressed;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final side = coarse ? 44.0 : 1.7 * _Look.buttonEm;
    return Builder(
      builder: (context) => GlacierPressable(
        onPressed: () {
          final box = context.findRenderObject() as RenderBox?;
          onPressed(box == null || !box.hasSize ? Offset.zero : box.localToGlobal(Offset(0, box.size.height)));
        },
        semanticLabel: label,
        builder: (context, state) => Opacity(
          opacity: !_hovers() || rowHovered || state.focused ? 1 : 0,
          child: GlacierFocusRing(
            visible: state.focused,
            offset: -2,
            radius: t.radius('sm'),
            child: Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: ExcludeSemantics(child: lucide(icon, size: 15, strokeWidth: 2.2, color: t.color(state.hovered ? 'app-ink' : 'app-ink-3'))),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's row: in from the edge by its depth, its fold, its mark, its name with who else is on it and its sync,
/// and its + and …; the open page in a ring, a carried page over it said by a line above or below or a ring.
class _PageRowFace extends StatelessWidget {
  const _PageRowFace({
    required this.look,
    required this.title,
    required this.untitled,
    required this.depth,
    required this.lead,
    required this.foldable,
    required this.open,
    required this.active,
    required this.coarse,
    required this.note,
    required this.zone,
    required this.onOpen,
    required this.onToggle,
    required this.onAdd,
    required this.onMore,
    required this.onMenu,
    required this.renaming,
    required this.onRenamed,
  });

  final _Look look;
  final String title;
  final bool untitled;
  final int depth;
  final Widget lead;
  final bool foldable;
  final bool open;
  final bool active;
  final bool coarse;
  final Note? note;
  final _Drop? zone;
  final VoidCallback? onOpen;
  final VoidCallback? onToggle;
  final VoidCallback? onAdd;
  final ValueChanged<Offset>? onMore;

  /// A mouse's right-click: the note's own menu (lib/notes/note_menu.dart), as on the folders' rows.
  final ValueChanged<Offset>? onMenu;
  final bool renaming;
  final ValueChanged<String?> onRenamed;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final ink = t.color('app-ink');
    final style = look.rowTitle(untitled: untitled, weight: 'medium');
    final markSize = ((style.fontSize ?? look.em) * 0.8).roundToDouble();
    final words = Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
    final note = this.note;
    final name = note == null ? words : PresenceMarked(noteId: note.id, child: NoteSyncMarked(note: note, size: markSize, child: words));
    final chevron = SizedBox(
      width: coarse ? 28 : 18,
      child: foldable
          ? GlacierPressable(
              key: const ValueKey('page-fold'),
              onPressed: onToggle,
              semanticLabel: open ? 'Fold $title' : 'Unfold $title',
              builder: (context, state) => Container(
                height: coarse ? 44 : 24,
                alignment: Alignment.center,
                child: AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 140),
                  curve: t.curve('glacier-ease-out'),
                  child: lucide(Lucide.chevronRight, size: 14, strokeWidth: 2.2, color: t.color(state.hovered ? 'app-ink' : 'app-ink-3')),
                ),
              ),
            )
          : null,
    );
    final line = BorderSide(color: ink, width: 2);
    return _Hover(
      builder: (context, hovered) => Listener(
        onPointerDown: onMenu == null
            ? null
            : (event) {
                if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) onMenu!(event.position);
              },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: zone == _Drop.into || active
                ? Border.all(color: zone == _Drop.into ? ink : t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)'), width: zone == _Drop.into ? 2 : snapBorder(context, t.len('app-line')))
                : Border(top: zone == _Drop.before ? line : BorderSide.none, bottom: zone == _Drop.after ? line : BorderSide.none),
            borderRadius: zone == _Drop.before || zone == _Drop.after ? null : BorderRadius.circular(t.radius('md')),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: hovered && !active ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('md'))),
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: _indent(look, depth) + 0.2 * look.em, end: 0.2 * look.em),
              child: Row(
                children: [
                  chevron,
                  Expanded(
                    child: renaming
                        ? Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _RenameField(title: untitled ? '' : title, onDone: onRenamed))
                        : GlacierPressable(
                            onPressed: onOpen,
                            selected: active ? true : null,
                            semanticLabel: title,
                            builder: (context, state) => GlacierFocusRing(
                              visible: state.focused,
                              offset: -2,
                              radius: t.radius('md'),
                              child: Container(
                                constraints: BoxConstraints(minHeight: coarse ? 44 : 28),
                                padding: EdgeInsets.symmetric(vertical: 0.3 * look.em, horizontal: 0.3 * look.em),
                                child: ExcludeSemantics(child: Row(spacing: 0.5 * look.em, children: [lead, Expanded(child: name)])),
                              ),
                            ),
                          ),
                  ),
                  if (onAdd != null && !renaming) _RowButton(look: look, coarse: coarse, rowHovered: hovered, label: 'Add a page inside $title', icon: Lucide.plus, onPressed: (_) => onAdd!()),
                  if (onMore != null && !renaming) _RowButton(look: look, coarse: coarse, rowHovered: hovered, label: 'More for $title', icon: Lucide.ellipsis, onPressed: onMore!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's name being changed on its row: Enter or leaving keeps it, Escape leaves it as it was.
class _RenameField extends StatefulWidget {
  const _RenameField({required this.title, required this.onDone});

  final String title;
  final ValueChanged<String?> onDone;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _text = TextEditingController(text: widget.title)..selection = TextSelection(baseOffset: 0, extentOffset: widget.title.length);
  bool _done = false;

  void _finish(String? text) {
    if (_done) return;
    _done = true;
    widget.onDone(text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlacierInput(
        key: const ValueKey('page-rename'),
        size: GlacierFieldSize.sm,
        controller: _text,
        autoFocus: true,
        ariaLabel: 'Rename ${widget.title.isEmpty ? 'Untitled' : widget.title}',
        onSubmitted: _finish,
        onBlur: () => _finish(_text.text),
        onKeyDown: (event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _finish(null);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
      );
}

/// A page's row, carried: a mouse drags it at once, a finger holds it first so a scroll stays a scroll.
class _PageCarrySource extends StatelessWidget {
  const _PageCarrySource({required this.node, required this.enabled, required this.child});

  final PageNode node;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final feedback = FolderCarryPill(label: node.title.trim().isEmpty ? 'Untitled' : node.title, folder: node.isFolder, tokens: context.tokens);
    final dimmed = Opacity(opacity: 0.4, child: child);
    Offset anchor(Draggable<Object> d, BuildContext context, Offset position) => _pageGrip;
    final data = _PageCarry(node);
    return mousePointer
        ? Draggable<_PageCarry>(data: data, feedback: feedback, childWhenDragging: dimmed, dragAnchorStrategy: anchor, child: child)
        : LongPressDraggable<_PageCarry>(data: data, feedback: feedback, childWhenDragging: dimmed, dragAnchorStrategy: anchor, hapticFeedbackOnStart: true, child: child);
  }
}

/// A page's row taking a carried page: before it over its top, after it over its foot, into it over its middle.
class _PageDropTarget extends StatefulWidget {
  const _PageDropTarget({required this.target, required this.onDrop, required this.builder});

  final PageNode target;
  final void Function(PageNode moved, _Drop where) onDrop;
  final Widget Function(BuildContext context, _Drop? zone) builder;

  @override
  State<_PageDropTarget> createState() => _PageDropTargetState();
}

class _PageDropTargetState extends State<_PageDropTarget> {
  _Drop? _zone;

  /// The zone under the pointer, the pill's corner and the grip it is held by.
  _Drop _zoneAt(Offset corner) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height == 0) return _Drop.into;
    final y = box.globalToLocal(corner + _pageGrip).dy / box.size.height;
    if (y < 0.28) return _Drop.before;
    if (y > 0.72) return _Drop.after;
    return _Drop.into;
  }

  void _show(_Drop? zone) {
    if (zone != _zone && mounted) setState(() => _zone = zone);
  }

  @override
  Widget build(BuildContext context) => DragTarget<_PageCarry>(
        onWillAcceptWithDetails: (details) => details.data.node.id != widget.target.id,
        onMove: (details) {
          if (details.data.node.id != widget.target.id) _show(_zoneAt(details.offset));
        },
        onLeave: (_) => _show(null),
        onAcceptWithDetails: (details) {
          final zone = _zoneAt(details.offset);
          _show(null);
          widget.onDrop(details.data.node, zone);
        },
        builder: (context, candidates, _) => widget.builder(context, candidates.isEmpty ? null : _zone),
      );
}
