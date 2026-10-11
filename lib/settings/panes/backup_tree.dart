import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/backup.dart';
import '../kit/settings_type.dart';

String _filesSaid(int count) => count == 1 ? 'one file' : '$count files';

/// Port of `BackupTree` (src/app/settings/BackupTree.tsx with BackupTree.module.css; docs/DESIGN.md §213 of
/// tauri/): what a drive's Ghost.md folder holds, as a tree (Matt: "On the backup page, show a logical file tree of
/// all the files on the USB drive inside the ghost folder specifically"). The folder itself open, its folders -
/// Inbox, Workspaces, Organizations, Attachments - closed until tapped, each saying how many files are under it and
/// their size, and a file its own size. A library is hundreds of files, so only what is opened is drawn.
///
/// What differs from the web original: a folder's row is a [GlacierPressable], with the kit's press and its name for
/// a screen reader, where the page had a plain button; whether it is open is said as a toggle's state, where the
/// page said `aria-expanded`.
class BackupTree extends StatelessWidget {
  const BackupTree({super.key, required this.tree, this.toggled});

  final TreeFolder tree;

  /// The paths of the folders that were tapped, kept by whoever draws the tree so a folder stays as it was left
  /// when the tree is drawn again; the tree's own, for as long as it stands, when null.
  final Set<String>? toggled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `.tree`: `padding: space-2 space-3 space-3`.
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
      child: Semantics(label: 'Files in ${tree.name}', container: true, child: _FolderRows(folder: tree, open: true, toggled: toggled ?? {})),
    );
  }
}

class _FolderRows extends StatefulWidget {
  const _FolderRows({super.key, required this.folder, required this.open, required this.toggled});

  final TreeFolder folder;

  /// Whether it starts open: the folder on the drive does, the folders in it do not.
  final bool open;
  final Set<String> toggled;

  @override
  State<_FolderRows> createState() => _FolderRowsState();
}

class _FolderRowsState extends State<_FolderRows> {
  bool get _open => widget.open != widget.toggled.contains(widget.folder.path);

  void _toggle() => setState(() {
        if (!widget.toggled.remove(widget.folder.path)) widget.toggled.add(widget.folder.path);
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final folder = widget.folder;
    final mark = t.color('app-ink-3');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlacierPressable(
          onPressed: _toggle,
          toggled: _open,
          semanticLabel: '${folder.name}, ${_filesSaid(folder.files)}, ${sizeSaid(folder.size)}',
          builder: (context, state) => _Row(
            marks: [AppIcon(_open ? Lucide.chevronDown : Lucide.chevronRight, size: 14, color: mark), AppIcon(_open ? Lucide.folderOpen : Lucide.folder, size: 16, color: mark)],
            name: folder.name,
            medium: true,
            said: '${_filesSaid(folder.files)} · ${sizeSaid(folder.size)}',
          ),
        ),
        if (_open)
          // `.list .list`: set in under its folder, with a hairline down its side.
          Container(
            margin: EdgeInsetsDirectional.only(start: t.lenOf('0.55rem')),
            padding: EdgeInsetsDirectional.only(start: t.space(3)),
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline')))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final each in folder.folders) _FolderRows(key: ValueKey('folder ${each.path}'), folder: each, open: false, toggled: widget.toggled),
                for (final leaf in folder.leaves) _Row(key: ValueKey('file ${leaf.path}'), marks: [AppIcon(Lucide.file, size: 14, color: mark)], name: leaf.name, said: sizeSaid(leaf.size)),
              ],
            ),
          ),
      ],
    );
  }
}

/// `.row`: its marks, its name cut short with an ellipsis, and what is said at its end, at least 2rem tall.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.marks, required this.name, required this.said, this.medium = false});

  final List<Widget> marks;
  final String name;
  final String said;

  /// `.folder .name`: a folder's name is a weight heavier.
  final bool medium;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
      child: Row(
        children: [
          for (final mark in marks) ...[mark, SizedBox(width: gap)],
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: medium ? 'medium' : 'regular', color: t.color('app-ink')))),
          SizedBox(width: gap),
          Text(said, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
