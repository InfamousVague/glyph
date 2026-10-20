/// The icon view: a workspace's folders and notes as large tiles, like a file browser's (GHST-107; Matt, 2026-10-19:
/// "support showing a icon file browser based view in addition to the list views"). The port's own.
///
/// A grid of tiles about a hundred pixels wide, more across a wide window, laid out as the cards' grid is: the
/// folders first (lib/notes/folder_strip.dart `folderTiles`), then the notes in the page's own order. At All the
/// folders are the workspaces at the top, an organization's with its mark, and the notes are every note as All lists
/// them: All still means every note, and the folders are the way in. A folder's tile
/// is the folder glyph, large, on a faint rounded square, in the folder's hue where it wears one, its name under it
/// on up to two lines and its count small under that; a note's is its kind's glyph the same way - a notebook, a
/// canvas, a cassette, a page of words, as the rows mark them (lib/home/home_rows.dart `KindMark`) - its title on up
/// to two lines, and when it was touched. A tap on a folder enters it, as the strip's chip does; a tap on a note
/// opens it; a mouse's right-click on a note asks for its menu, as the cards do. The keyboard's focus rings a tile.
///
/// Cards or icons is one choice for the device ([BrowseView], kept in [Stored] under [browseViewKey]), made on All
/// notes' line of order words and on an organization's dashboard, and read by both ([BrowseViewToggle], a segmented toggle with a glyph each). Cards
/// unless chosen, so a page looks as it always did. The empty page's words stay the page's own.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/stored.dart';
import '../core/workspaces.dart' show isOrgWorkspace;
import '../home/home_icons.dart';
import '../home/home_layout.dart' show HomeKind, kindOf;
import '../home/home_text.dart';
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

/// The view chosen last time, kept on the device: one choice for every page that offers it.
const String browseViewKey = 'glyph-browse-view';

/// Nothing kept, or storage that cannot be read: cards, as the pages always were.
BrowseView readBrowseView([Stored? from]) => (from ?? stored).readText(browseViewKey) == BrowseView.icons.id ? BrowseView.icons : BrowseView.cards;

/// Storage that cannot be written: the choice holds for this page, and is asked again next time.
void writeBrowseView(BrowseView view, [Stored? to]) => (to ?? stored).writeText(browseViewKey, view.id);

/// Cards or icons, as a segmented toggle with a glyph each (Matt, 2026-10-19: "use a segmented toggle with iconography
/// for the different modes"): the kit's [GlacierSegmentedControl] at its small size, its thumb springing between the
/// two, a list of cards' glyph for Cards and a grid's for Icons, each named for a screen reader. The glyph takes the
/// label's own colour, so the chosen one is ink and the other muted. Each label keeps the key the words had (`view-cards`,
/// `view-icons`). One control a page: All notes' line of order words, and an organization's Notes heading.
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
  const IconBrowser({super.key, required this.folders, required this.notes, required this.onFolder, required this.onOpen, this.onNoteMenu, this.now, this.onNewFolder});

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

  /// How many tiles go across a grid [width] wide: as many of at least [least] as fit, and never fewer than three,
  /// so a phone shows a row of three a touch narrower.
  static int columnsFor(double width, {required double gap, required double least}) => math.max(3, ((width + gap) / (least + gap)).floor());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final adds = onNewFolder == null ? 0 : 1;
    final count = folders.length + adds + notes.length;
    if (count == 0) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Folders and notes',
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = columnsFor(box.maxWidth, gap: gap, least: t.lenOf('7rem'));
          Widget tile(int at) {
            if (at < folders.length) {
              final each = folders[at];
              return _FolderTile(key: ValueKey('tile-folder-${each.folder.id}'), folder: each, onPressed: () => onFolder(each.folder.id));
            }
            if (adds == 1 && at == folders.length) return _NewFolderTile(key: const ValueKey('tile-folder-new'), onPressed: onNewFolder!);
            final note = notes[at - folders.length - adds];
            final onMenu = onNoteMenu;
            return _NoteTile(key: ValueKey('tile-note-${note.id}'), note: note, now: now, onPressed: () => onOpen(note.id), onMenu: onMenu == null ? null : (at) => onMenu(note, at));
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

/// New folder, as a tile after the folders: the folder-plus glyph on a dashed-looking faint square, no count.
class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Tile(
      glyph: AppIcon(Lucide.folderPlus, size: _Tile.glyphSize(t), strokeWidth: 1.75, color: t.color('app-ink-3')),
      wash: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
      name: 'New folder',
      meta: '',
      said: 'New folder',
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
