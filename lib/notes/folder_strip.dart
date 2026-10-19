/// The folders inside the chosen workspace, above the flat lists (GHST-107; Matt, 2026-10-19: "I'd like to be able
/// to sort notes into folders and display them above the flat lists and support showing a icon file browser based
/// view in addition to the list views"). The port's own: the web app has no folders inside folders.
///
/// Under a small heading - "Folders", and how many - the folders directly inside the chosen workspace as a row of
/// chips that scrolls sideways: the folder's glyph, its name, and how many notes are in it and in the folders under
/// it, in the folder's hue where it wears one; then New folder at the end, where the page can make one. Above the
/// heading, when the chosen workspace is itself inside another, where it is: "Work › Clients", each part but the
/// last a way up (an organization's root is the first part of its folders' line, once an organization's workspace
/// holds folders). A tap on a chip chooses that folder as a pill does, and the page shows its notes.
///
/// Nothing is drawn for a workspace at the top with no folders inside it, so the lists look as they always did;
/// one inside another with none still has its line above, so there is a way up. Where it stands: on home under the
/// filters when a workspace is chosen, on All notes under the order words when a pill is, and on an organization's
/// dashboard above its Notes. In the icon view (lib/notes/icon_browser.dart) the folders are the first tiles and only
/// [FolderCrumbs] is drawn. Not in simple mode (GHST-103), whose pages have no workspaces to choose.
///
/// The folders and their counts are read from the workspaces as they stand ([foldersIn], [notesUnder]): a folder
/// is any workspace whose `parent` is the chosen one, whoever may hold folders - a personal workspace today, an
/// organization's once its workspace can be a parent.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/note.dart';
import '../core/workspaces.dart';
import '../home/home_text.dart';

/// A folder and how many notes are in it and under it.
typedef FolderCount = ({Workspace folder, int count});

/// The folders directly inside workspace [id], in the order they were made (`WorkspaceStore.childrenOf`, read from
/// a list rather than the store).
List<Workspace> foldersIn(List<Workspace> list, String id) => [for (final w in list) if (w.parent == id) w];

/// How many of [notes] are filed in workspace [id] or in a folder under it, the archive left out: what a folder's
/// chip counts.
int notesUnder(List<Workspace> list, Map<String, String> of, Iterable<Note> notes, String id) {
  final family = workspaceFamily(list, id).toSet();
  var count = 0;
  for (final note in notes) {
    if (note.archivedAt == null && family.contains(of[note.id])) count += 1;
  }
  return count;
}

/// The folders inside [chosen], each with its count: what the strip's chips and the icon view's first tiles draw.
List<FolderCount> folderTiles(List<Workspace> list, Map<String, String> of, Iterable<Note> notes, String chosen) =>
    [for (final folder in foldersIn(list, chosen)) (folder: folder, count: notesUnder(list, of, notes, folder.id))];

/// "Work › Clients": the parts of where [chosen] is, itself last; one part alone for a workspace at the top.
List<Workspace> folderPath(List<Workspace> list, String chosen) => workspacePath(list, chosen);

/// A chip's height, the pills' own: `min-block-size: 2rem`, or the word's line and the ring round it where that is
/// more (lib/notes/workspace_bar.dart `pillHeight`).
double _chipHeight(Tokens t) => math.max(t.lenOf('2rem'), 2.2 * t.fontSize('sm') + 2);

/// The folders inside the chosen workspace as chips under a heading, with where the workspace is above them.
class FolderStrip extends StatelessWidget {
  const FolderStrip({super.key, required this.list, required this.of, required this.notes, required this.chosen, required this.onChoose, this.onNewFolder, this.crumbs = true});

  /// Every workspace (`Workspaces.list`), and which workspace each filed note is in (`Workspaces.of`).
  final List<Workspace> list;
  final Map<String, String> of;

  /// Every note the page can show; the archive is left out of the counts.
  final List<Note> notes;

  /// The workspace chosen, whose folders are drawn.
  final String chosen;

  /// A folder chosen, or a part of the line above pressed: the page shows that workspace.
  final ValueChanged<String> onChoose;

  /// New folder pressed: a folder inside [chosen], through the page's workspace sheet. Absent, no New folder chip.
  final ValueChanged<String>? onNewFolder;

  /// Whether the line above is drawn here; the icon view draws [FolderCrumbs] itself.
  final bool crumbs;

  /// Whether there is anything to draw for [chosen]: a folder inside it, or a workspace above it.
  static bool shows(List<Workspace> list, String chosen) => foldersIn(list, chosen).isNotEmpty || folderPath(list, chosen).length > 1;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final folders = folderTiles(list, of, notes, chosen);
    final path = folderPath(list, chosen);
    final above = crumbs && path.length > 1;
    if (folders.isEmpty && !above) return const SizedBox.shrink();
    final sm = t.fontSize('sm');
    final ink3 = t.color('app-ink-3');
    return Column(
      key: const ValueKey('folder-strip'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (above) ...[
          FolderCrumbs(list: list, chosen: chosen, onChoose: onChoose),
          if (folders.isNotEmpty) SizedBox(height: t.space(2)),
        ],
        if (folders.isNotEmpty) ...[
          // The heading the page's sections wear: a mark, the word, how many.
          Semantics(
            header: true,
            label: 'Folders, ${folders.length}',
            excludeSemantics: true,
            child: Row(
              children: [
                AppIcon(Lucide.folder, size: 15, color: ink3),
                SizedBox(width: t.space(2)),
                Text('Folders', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))),
                SizedBox(width: t.space(2)),
                Text('${folders.length}', style: tabular(pageText(t, sm, color: ink3))),
              ],
            ),
          ),
          SizedBox(height: t.space(2)),
          Semantics(
            container: true,
            label: 'Folders',
            child: SizedBox(
              // The chips' height and the room a focus ring takes above and below.
              height: _chipHeight(t) + 4,
              child: SingleChildScrollView(
                key: const ValueKey('folder-chips'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  spacing: t.space(2),
                  children: [
                    for (final each in folders) _Chip(key: ValueKey('folder-chip-${each.folder.id}'), folder: each.folder, count: each.count, onPressed: () => onChoose(each.folder.id)),
                    if (onNewFolder != null) _NewChip(key: const ValueKey('folder-new'), onPressed: () => onNewFolder!(chosen)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Where the chosen workspace is, as a line: "Work › Clients", each part but the last a way up. Nothing for a
/// workspace at the top.
class FolderCrumbs extends StatelessWidget {
  const FolderCrumbs({super.key, required this.list, required this.chosen, required this.onChoose});

  final List<Workspace> list;
  final String chosen;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final path = folderPath(list, chosen);
    if (path.length < 2) return const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      container: true,
      label: 'In ${path.map((w) => w.name).join(' › ')}',
      child: SizedBox(
        key: const ValueKey('folder-crumbs'),
        height: normalLeading(sm) * sm + 2 * t.space(1),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (at, part) in path.indexed) ...[
                if (at > 0) ExcludeSemantics(child: Text(' › ', style: pageText(t, sm, color: t.color('app-ink-3')))),
                if (at == path.length - 1)
                  // The last part is where the page is: said, not pressed.
                  Padding(padding: EdgeInsets.symmetric(horizontal: t.space(1), vertical: t.space(1)), child: Text(part.name, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink'))))
                else
                  GlacierPressable(
                    key: ValueKey('crumb-${part.id}'),
                    onPressed: () => onChoose(part.id),
                    semanticLabel: 'Up to ${part.name}',
                    haptic: HapticKind.selection,
                    builder: (context, state) => GlacierFocusRing(
                      visible: state.focused,
                      radius: t.radius('sm'),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: t.space(1), vertical: t.space(1)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(t.radius('sm')),
                          color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
                        ),
                        child: Text(part.name, maxLines: 1, softWrap: false, style: pageText(t, sm, color: state.pressed ? t.color('app-ink') : t.color('app-ink-2'))),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One folder's chip: outlined as a pill is, in the folder's hue where it has one, with its glyph, its name and its
/// count.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.folder, required this.count, required this.onPressed});

  final Workspace folder;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hue = folder.hue;
    final chip = Builder(
      builder: (context) {
        final t = context.tokens;
        final sm = t.fontSize('sm');
        // Its hue where it wears one (ink.css `[data-hue]`, `--app-space`); else the quiet ink the pills rest in.
        final ink = hue == null ? t.color('app-ink-2') : t.color('app-space');
        final line = hue == null ? t.colorOf('color-mix(in oklch, var(--app-ink-3) 55%, transparent)') : t.colorOf('color-mix(in oklch, var(--app-space) 55%, transparent)');
        return GlacierPressable(
          onPressed: onPressed,
          semanticLabel: '${folder.name}, ${count == 1 ? '1 note' : '$count notes'}',
          haptic: HapticKind.selection,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            child: Container(
              constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
              // An even ring of space round the words, in ems so it holds at every text size, as a pill's is.
              padding: EdgeInsets.symmetric(horizontal: 0.7 * sm, vertical: 0.4 * sm),
              decoration: BoxDecoration(
                color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, ${hue == null ? 'var(--app-ink)' : 'var(--app-space)'} 6%, transparent)') : null,
                border: Border.all(color: line, width: 1),
                borderRadius: BorderRadius.circular(t.radius('full')),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 0.4 * sm,
                  children: [
                    AppIcon(Lucide.folder, size: 1.1 * sm, strokeWidth: 2.2, color: ink),
                    Text(folder.name, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: ink)),
                    Text('$count', maxLines: 1, softWrap: false, style: tabular(pageText(t, sm, color: t.color('app-ink-3')))),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return hue == null ? chip : GlacierScope(attrs: {'hue': hue}, child: chip);
  }
}

/// New folder, at the end of the row: the folder-plus glyph and the words, outlined in the faint ink.
class _NewChip extends StatelessWidget {
  const _NewChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final ink = t.color('app-ink-2');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'New folder',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
          padding: EdgeInsets.symmetric(horizontal: 0.7 * sm, vertical: 0.4 * sm),
          decoration: BoxDecoration(
            color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
            border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink-3) 35%, transparent)'), width: 1),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 0.4 * sm,
              children: [
                AppIcon(Lucide.folderPlus, size: 1.1 * sm, strokeWidth: 2.2, color: ink),
                Text('New folder', maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
