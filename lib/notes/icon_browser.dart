/// The icon view: a workspace's folders and notes as large tiles, like a file browser's (GHST-107; Matt, 2026-10-19:
/// "support showing a icon file browser based view in addition to the list views"). The port's own.
///
/// A grid of tiles about a hundred pixels wide, more across a wide window, laid out as the cards' grid is: the
/// folders first (lib/notes/folder_strip.dart `folderTiles`), then the notes in the page's own order. The notes are
/// the level's own, as a file browser's are (`notesAt`): those filed in the chosen workspace itself, a folder's in
/// its tile; at All, where the folders are the workspaces at the top, an organization's with its mark, the notes
/// filed in none. So a note carried onto a folder's tile leaves the level (2026-10-20). A search shows every note it
/// found. A folder's tile
/// is the folder glyph, large, on a faint rounded square, in the folder's hue where it wears one, its name under it
/// on up to two lines and its count small under that; a note's is its kind's glyph the same way - a notebook, a
/// canvas, a cassette, a page of words, as the rows mark them (lib/home/home_rows.dart `KindMark`) - its title on up
/// to two lines, and when it was touched. A tap on a folder enters it, as the strip's chip does; a tap on a note
/// opens it; a mouse's right-click on a note asks for its menu, as the cards do. The keyboard's focus rings a tile.
///
/// Cards or icons is chosen at a level and carries down (Matt, 2026-10-20: "When navigating into a folder sub folders
/// should share the same ability to have icons or list keeping the parents selection"): a level's view is the one
/// chosen at it, or else at the nearest level above it where one was chosen, or else the one chosen at the top (All
/// notes with no workspace chosen), which is the device's view as before folders had their own ([browseViewAt]).
/// Choosing at a level sets it for that level and everything under it: what the folders below had chosen of their
/// own is let go ([chooseBrowseView]), so a choice made higher up is never hidden under one made lower down. The
/// top's choice is kept under [browseViewKey], the others by workspace under [browseViewsKey], on the device. Cards
/// unless chosen, so a page looks as it always did. The toggle ([BrowseViewToggle], a segmented toggle with a glyph
/// each) stands at every level: All notes' line of order words, an organization's Notes heading, and home's folders'
/// heading while a workspace is chosen. The empty page's words stay the page's own.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/stored.dart';
import '../core/workspaces.dart' show Workspace, WorkspaceStore, isOrgWorkspace, workspaceFamily, workspacePath;
import '../home/home_icons.dart';
import '../home/home_layout.dart' show HomeKind, kindOf;
import '../home/home_text.dart';
import 'folder_drag.dart';
import 'folder_strip.dart' show FolderCount;
import 'note_menu.dart' show NoteMenuArea;
import 'org_mark.dart';
import 'when.dart';

/// How a page draws its notes: as the cards it always has, or as icons.
enum BrowseView {
  cards('cards', 'Cards'),
  icons('icons', 'Icons');

  const BrowseView(this.id, this.label);

  /// The word kept on the device.
  final String id;

  /// The word on the page.
  final String label;
}

/// The view chosen at the top, kept on the device: what every level shows where none above it has a choice of its
/// own.
const String browseViewKey = 'glyph-browse-view';

/// The views chosen at levels below the top, by workspace id: `{"work": "icons", "clients": "cards"}`.
const String browseViewsKey = 'glyph-browse-views';

/// Nothing kept, or storage that cannot be read: cards, as the pages always were. The top's choice.
BrowseView readBrowseView([Stored? from]) => (from ?? stored).readText(browseViewKey) == BrowseView.icons.id ? BrowseView.icons : BrowseView.cards;

/// Storage that cannot be written: the choice holds for this page, and is asked again next time.
void writeBrowseView(BrowseView view, [Stored? to]) => (to ?? stored).writeText(browseViewKey, view.id);

BrowseView? _viewOf(Object? id) => id == BrowseView.icons.id ? BrowseView.icons : (id == BrowseView.cards.id ? BrowseView.cards : null);

/// The levels' own choices, as kept; none where nothing is, or what is kept is not a map of views.
Map<String, BrowseView> _levelViews(Stored from) => from.readShared<Map<String, BrowseView>>(browseViewsKey, const {}, (raw) {
      if (raw is! Map) return null;
      return {
        for (final entry in raw.entries)
          if (entry.key is String && _viewOf(entry.value) != null) entry.key as String: _viewOf(entry.value)!,
      };
    });

/// The view at level [id] (null for the top): its own choice, else the nearest above it with one, else the top's.
BrowseView browseViewAt(List<Workspace> list, String? id, [Stored? from]) {
  final kept = from ?? stored;
  if (id != null) {
    final levels = _levelViews(kept);
    if (levels.isNotEmpty) {
      // Where it is, from the level itself up to the workspace at the top.
      for (final at in workspacePath(list, id).reversed) {
        final view = levels[at.id];
        if (view != null) return view;
      }
      // A level the list no longer has, kept for nothing but itself.
      final own = levels[id];
      if (own != null) return own;
    }
  }
  return readBrowseView(kept);
}

/// [view] chosen at level [id] (null for the top), for it and every level under it: the choices of the folders under
/// it are let go, and those of workspaces the list no longer has. A choice that is what the level would show anyway
/// is not kept as its own, so it follows its parent's next time.
void chooseBrowseView(List<Workspace> list, String? id, BrowseView view, [Stored? to]) {
  final kept = to ?? stored;
  if (id == null) {
    writeBrowseView(view, kept);
    kept.writeText(browseViewsKey, null);
    return;
  }
  final under = workspaceFamily(list, id).toSet();
  final known = {for (final w in list) w.id};
  final levels = {
    for (final entry in _levelViews(kept).entries)
      if (!under.contains(entry.key) && known.contains(entry.key)) entry.key: entry.value,
  };
  final parent = list.where((w) => w.id == id).firstOrNull?.parent;
  // What the level shows with no choice of its own: its parent's, with the choices below it let go.
  BrowseView inherited() {
    for (final at in parent == null ? const <Workspace>[] : workspacePath(list, parent).reversed) {
      final view = levels[at.id];
      if (view != null) return view;
    }
    return readBrowseView(kept);
  }

  if (view != inherited()) levels[id] = view;
  kept.write(browseViewsKey, levels.isEmpty ? null : {for (final entry in levels.entries) entry.key: entry.value.id});
}

/// Cards or icons, as a segmented toggle with a glyph each (Matt, 2026-10-19: "use a segmented toggle with iconography
/// for the different modes"): the kit's [GlacierSegmentedControl] at its small size, its thumb springing between the
/// two, a list of cards' glyph for Cards and a grid's for Icons, each named for a screen reader. The glyph takes the
/// label's own colour, so the chosen one is ink and the other muted. Each label keeps the key the words had (`view-cards`,
/// `view-icons`). One control a page: All notes' line of order words, an organization's Notes heading, and home's
/// folders' heading.
class BrowseViewToggle extends StatelessWidget {
  const BrowseViewToggle({super.key, required this.view, required this.onView});

  final BrowseView view;
  final ValueChanged<BrowseView> onView;

  static LucideIcon _glyph(BrowseView view) => view == BrowseView.icons ? Lucide.layoutGrid : Lucide.layoutList;

  @override
  Widget build(BuildContext context) {
    return GlacierSegmentedControl(
      ariaLabel: 'View',
      size: GlacierSegmentedSize.sm,
      value: view.id,
      onValueChange: (id) => onView(BrowseView.values.firstWhere((each) => each.id == id)),
      options: [
        for (final each in BrowseView.values)
          GlacierSegmentedOption(
            value: each.id,
            // The glyph alone, named for a screen reader: with the words beside them the line of order words ran
            // over a phone's width (21px, the tally and Archived beside it).
            label: Builder(
              key: ValueKey('view-${each.id}'),
              builder: (context) => Semantics(
                label: each.label,
                child: AppIcon(_glyph(each), size: 16, color: DefaultTextStyle.of(context).style.color),
              ),
            ),
          ),
      ],
    );
  }
}

/// The folders and the notes as tiles.
class IconBrowser extends StatelessWidget {
  const IconBrowser({super.key, required this.folders, required this.notes, required this.onFolder, required this.onOpen, this.onNoteMenu, this.now, this.onNewFolder, this.onNewNote, this.store});

  /// The folders first, each with its count.
  final List<FolderCount> folders;

  /// Then the notes, in the page's order.
  final List<Note> notes;

  /// A folder's tile tapped: the page shows that folder.
  final ValueChanged<String> onFolder;

  /// A note's tile tapped: the note.
  final ValueChanged<String> onOpen;

  /// A note's menu asked for by a mouse's right-click: which note, and where in the window.
  final void Function(Note note, Offset at)? onNoteMenu;

  /// The moment "20 min ago" is counted from.
  final int? now;

  /// A New folder tile after the folders, where folders can be made here (Matt, 2026-10-19: "It's also not clear how
  /// to add a folder"): inside the place shown, or a folder at the top where nothing is chosen.
  final VoidCallback? onNewFolder;

  /// A New note tile after New folder (Matt, 2026-10-20: "we should be able to nest folders and files this way"): a
  /// note filed in the place shown, opened ready to type.
  final VoidCallback? onNewNote;

  /// The workspaces, so a note's tile or a folder's can be carried onto a folder's (lib/notes/folder_drag.dart):
  /// a mouse drags, a finger holds first. None, and nothing is carried here.
  final WorkspaceStore? store;

  /// How many tiles go across a grid [width] wide: as many of at least [least] as fit, and never fewer than three,
  /// so a phone shows a row of three a touch narrower.
  static int columnsFor(double width, {required double gap, required double least}) => math.max(3, ((width + gap) / (least + gap)).floor());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final folderAt = onNewFolder == null ? -1 : folders.length;
    final noteAt = onNewNote == null ? -1 : folders.length + (onNewFolder == null ? 0 : 1);
    final adds = (onNewFolder == null ? 0 : 1) + (onNewNote == null ? 0 : 1);
    final count = folders.length + adds + notes.length;
    if (count == 0) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Folders and notes',
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = columnsFor(box.maxWidth, gap: gap, least: t.lenOf('7rem'));
          Widget tile(int at) {
            final store = this.store;
            if (at < folders.length) {
              final each = folders[at];
              final Widget tile = _FolderTile(key: ValueKey('tile-folder-${each.folder.id}'), folder: each, onPressed: () => onFolder(each.folder.id));
              if (store == null) return tile;
              // A place to drop a note or a folder, and itself carried into another; an organization's own stays.
              return FolderCarrySource(
                store: store,
                carry: FolderCarry.folder(each.folder.id, each.folder.name),
                enabled: !isOrgWorkspace(each.folder.id),
                child: FolderDropZone(key: ValueKey('drop-${each.folder.id}'), store: store, target: each.folder.id, decorate: true, radius: t.radius('md'), builder: (context, _) => tile),
              );
            }
            if (at == folderAt) return _NewTile(key: const ValueKey('tile-folder-new'), glyph: Lucide.folderPlus, name: 'New folder', onPressed: onNewFolder!);
            if (at == noteAt) return _NewTile(key: const ValueKey('tile-note-new'), glyph: Lucide.filePlus, name: 'New note', onPressed: onNewNote!);
            final note = notes[at - folders.length - adds];
            final onMenu = onNoteMenu;
            final Widget tile = _NoteTile(key: ValueKey('tile-note-${note.id}'), note: note, now: now, onPressed: () => onOpen(note.id), onMenu: onMenu == null ? null : (at) => onMenu(note, at));
            if (store == null) return tile;
            final title = NoteFacts.of(note).title.trim();
            return FolderCarrySource(store: store, carry: FolderCarry.note(note.id, title.isEmpty ? 'Untitled' : title), child: tile);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row * columns < count; row += 1) ...[
                if (row > 0) SizedBox(height: gap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < columns; column += 1) ...[
                      if (column > 0) SizedBox(width: gap),
                      Expanded(child: row * columns + column < count ? tile(row * columns + column) : const SizedBox.shrink()),
                    ],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A folder's tile, in its hue where it has one.
class _FolderTile extends StatelessWidget {
  const _FolderTile({super.key, required this.folder, required this.onPressed});

  final FolderCount folder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hue = folder.folder.hue;
    final count = folder.count;
    final meta = count == 1 ? '1 note' : '$count notes';
    final tile = Builder(
      builder: (context) {
        final t = context.tokens;
        final ink = hue == null ? t.color('app-ink-2') : t.color('app-space');
        final org = isOrgWorkspace(folder.folder.id);
        return _Tile(
          glyph: AppIcon(Lucide.folder, size: _Tile.glyphSize(t), strokeWidth: 1.75, color: ink),
          wash: t.colorOf('color-mix(in oklch, ${hue == null ? 'var(--app-ink)' : 'var(--app-space)'} 7%, transparent)'),
          name: folder.folder.name,
          // An organization's workspace wears the small mark before its name, as its pill does.
          org: org,
          meta: meta,
          said: '${folder.folder.name}, ${org ? 'organization' : 'folder'}, $meta',
          onPressed: onPressed,
        );
      },
    );
    return hue == null ? tile : GlacierScope(attrs: {'hue': hue}, child: tile);
  }
}

/// New folder or New note, as a tile after the folders: the folder-plus or file-plus glyph on a faint square, no
/// count.
class _NewTile extends StatelessWidget {
  const _NewTile({super.key, required this.glyph, required this.name, required this.onPressed});

  final LucideIcon glyph;
  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Tile(
      glyph: AppIcon(glyph, size: _Tile.glyphSize(t), strokeWidth: 1.75, color: t.color('app-ink-3')),
      wash: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
      name: name,
      meta: '',
      said: name,
      onPressed: onPressed,
    );
  }
}

/// A note's tile: its kind's glyph, its title, and when it was touched.
class _NoteTile extends StatelessWidget {
  const _NoteTile({super.key, required this.note, required this.onPressed, this.onMenu, this.now});

  final Note note;
  final VoidCallback onPressed;
  final ValueChanged<Offset>? onMenu;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final facts = NoteFacts.of(note);
    final title = facts.title.trim().isEmpty ? 'Untitled' : facts.title;
    final kind = kindOf(note);
    final glyph = switch (kind) {
      HomeKind.book => HomeGlyph.bookOpen,
      HomeKind.canvas => HomeGlyph.canvas,
      HomeKind.tape => HomeGlyph.tape,
      HomeKind.note => HomeGlyph.note,
    };
    final touched = when(note.updatedAt, now);
    return NoteMenuArea(
      onMenu: onMenu,
      child: _Tile(
        // The cassette is wide and low, so it is drawn a touch larger, as a row's mark is (`.rowMarkTape`).
        glyph: HomeIcon(glyph, size: kind == HomeKind.tape ? 1.1 * _Tile.glyphSize(t) : _Tile.glyphSize(t), strokeWidth: 1.75, color: t.color('app-ink-2')),
        wash: t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)'),
        name: title,
        meta: touched,
        said: [title, if (note.starred) 'pinned', touched].join(', '),
        onPressed: onPressed,
      ),
    );
  }
}

/// One tile: the glyph on its square, the name under it, the small line under that.
class _Tile extends StatelessWidget {
  const _Tile({required this.glyph, required this.wash, required this.name, this.org = false, required this.meta, required this.said, required this.onPressed});

  final Widget glyph;
  final Color wash;
  final String name;

  /// An organization's workspace: its mark before the name.
  final bool org;
  final String meta;
  final String said;
  final VoidCallback onPressed;

  /// The glyph's size: 2.5rem, forty pixels at the app's own text size.
  static double glyphSize(Tokens t) => t.lenOf('2.5rem');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final square = t.lenOf('4rem');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: said,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space(1), vertical: t.space(2)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius('md')),
            color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(width: square, height: square, alignment: Alignment.center, decoration: BoxDecoration(color: wash, borderRadius: BorderRadius.circular(t.radius('md'))), child: glyph),
                SizedBox(height: t.space(2)),
                Text.rich(
                  TextSpan(children: [if (org) OrgMark.span(em: sm, color: t.color('app-ink-2')), TextSpan(text: name)]),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')),
                ),
                const SizedBox(height: 2),
                Text(meta, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tabular(pageText(t, xs, color: t.color('app-ink-3')))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
