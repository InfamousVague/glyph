/// The small sheet a share opens (Android's share sheet › Ghost.md): what was shared, in a line; a new note, named for
/// it, in a workspace or none; or added to a note that is there, found by its name with the notes last added to
/// first. Save keeps it and Cancel does not, and either way the person is back in the app they shared from.
///
/// The sheet is lib/sheet/sheet.dart with its rows from lib/sheet/kit.dart, as the + sheet is (lib/notes/new_sheet.dart).
/// The notes are read once as the sheet opens, their titles from the list's own cache ([NoteFacts]), and only that
/// is looked through as a name is typed.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/workspaces.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../share_in.dart';
import '../share_in_keep.dart';

/// A note the sheet can add a share to.
typedef ShareTarget = ({String id, String title, String folded});

/// The notes a share can go onto, as the sheet looks through them: every note but a canvas (whose words are its
/// JSON) and those in the trash, by its title, the newest edit first.
List<ShareTarget> shareTargets(Iterable<Note> notes, {bool Function(String id)? trashed}) {
  final out = <ShareTarget>[];
  for (final note in notes) {
    if (trashed?.call(note.id) ?? false) continue;
    final facts = NoteFacts.of(note);
    if (facts.isCanvas) continue;
    final title = facts.title.isEmpty ? 'Untitled' : facts.title;
    out.add((id: note.id, title: title, folded: title.toLowerCase()));
  }
  return out;
}

/// What a share is, in one line, for the top of its sheet.
String shareSaid(SharedIn share) {
  final pictures = share.items.where((item) => item.picture).length;
  final files = share.items.length - pictures;
  final link = sharedLink(share);
  final things = [
    if (link != null) 'A link',
    if (link == null && (share.text?.trim().isNotEmpty ?? false)) 'Some words',
    if (pictures > 0) pictures == 1 ? 'a picture' : '$pictures pictures',
    if (files > 0) files == 1 ? 'a file' : '$files files',
  ];
  if (things.isEmpty) return share.unread > 0 ? 'What was shared could not be read.' : 'Nothing to save.';
  var said = things.length == 1 ? things.first : '${things.sublist(0, things.length - 1).join(', ')} and ${things.last}';
  said = '${said[0].toUpperCase()}${said.substring(1)}.';
  if (share.unread > 0) said = '$said ${share.unread == 1 ? 'One file' : '${share.unread} files'} could not be read.';
  return said;
}

class ShareInSheet extends StatefulWidget {
  const ShareInSheet({super.key, required this.share, required this.keeper, required this.notes, required this.onDone, this.most = 8});

  final SharedIn share;
  final ShareKeeper keeper;

  /// The notes it can go onto ([shareTargets]), read as the sheet opened.
  final List<ShareTarget> notes;

  /// The sheet is finished: with the note the share went into, or null for Cancel.
  final void Function(Note? kept) onDone;

  /// How many notes are listed to add to.
  final int most;

  @override
  State<ShareInSheet> createState() => _ShareInSheetState();
}

class _ShareInSheetState extends State<ShareInSheet> {
  late String _title = sharedTitle(widget.share);
  bool _onto = false;
  String? _workspace;
  String _query = '';
  String? _picked;
  bool _busy = false;
  String? _problem;

  WorkspaceStore get _workspaces => widget.keeper.workspaces;

  /// The notes to offer: those added to last first, then the newest; or those whose title holds what is typed.
  List<ShareTarget> get _shown {
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      return [for (final note in widget.notes) if (note.folded.contains(query)) note].take(widget.most).toList();
    }
    final byId = {for (final note in widget.notes) note.id: note};
    final recent = [for (final id in widget.keeper.recent()) ?byId[id]];
    final ids = {for (final note in recent) note.id};
    return [...recent, for (final note in widget.notes) if (!ids.contains(note.id)) note].take(widget.most).toList();
  }

  Future<void> _save() async {
    if (_busy) return;
    final picked = _picked;
    if (_onto && picked == null) {
      setState(() => _problem = 'Choose the note to add it to.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final kept = _onto ? await widget.keeper.keepOnto(widget.share, picked!) : await widget.keeper.keepNew(widget.share, title: _title, workspaceId: _workspace);
      if (mounted) widget.onDone(kept.note);
    } catch (failure) {
      if (mounted) setState(() => _problem = failure is StateError ? failure.message : 'That could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    unawaited(widget.keeper.discard(widget.share));
    widget.onDone(null);
  }

  @override
  Widget build(BuildContext context) {
    final spaces = _workspaces.value.list;
    final can = !widget.share.empty;
    return Sheet(
      key: const ValueKey('share-in'),
      label: 'Save to Ghost.md',
      onClose: _cancel,
      children: [
        SheetTitle.text('Save to Ghost.md'),
        SheetNote(shareSaid(widget.share)),
        if (can) ...[
          SheetGroup(
            children: [
              SheetRow(key: const ValueKey('share-new'), icon: const AppIcon(Lucide.squarePen, size: 18), label: 'New note', chosen: !_onto, onPress: () => setState(() => _onto = false)),
              SheetRow(key: const ValueKey('share-onto'), icon: const AppIcon(Lucide.listPlus, size: 18), label: 'Add to a note', chosen: _onto, onPress: () => setState(() => _onto = true)),
            ],
          ),
          if (!_onto) ...[
            SheetGroup(
              children: [
                SheetField(key: const ValueKey('share-title'), label: 'Title', value: _title, onChange: (text) => setState(() => _title = text), autoCapitalize: TextCapitalization.sentences, onSubmitted: (_) => _save()),
              ],
            ),
            if (spaces.isNotEmpty) ...[
              const SheetHeading('Workspace'),
              SheetGroup(
                children: [
                  SheetRow(key: const ValueKey('share-space-none'), label: 'None', chosen: _workspace == null, onPress: () => setState(() => _workspace = null)),
                  for (final space in spaces)
                    SheetRow(key: ValueKey('share-space-${space.id}'), label: space.name, chosen: _workspace == space.id, onPress: () => setState(() => _workspace = space.id)),
                ],
              ),
            ],
          ] else ...[
            SheetGroup(
              children: [
                SheetField(key: const ValueKey('share-find'), label: 'Find a note', value: _query, placeholder: 'A note’s name', onChange: (text) => setState(() => _query = text)),
              ],
            ),
            SheetGroup(
              children: [
                for (final note in _shown)
                  SheetRow(key: ValueKey('share-to-${note.id}'), icon: const AppIcon(Lucide.fileText, size: 18), label: note.title, chosen: _picked == note.id, onPress: () => setState(() => _picked = note.id)),
                if (_shown.isEmpty) SheetRow(label: _query.trim().isEmpty ? 'No notes yet' : 'No note has that name'),
              ],
            ),
          ],
        ],
        if (_problem case final problem?) SheetNote(problem),
        SheetGroup(
          children: [
            if (can)
              SheetRow(
                key: const ValueKey('share-save'),
                icon: const AppIcon(Lucide.check, size: 18),
                label: _busy ? 'Saving…' : (_onto ? 'Add to the note' : 'Save as a new note'),
                onPress: _save,
                disabled: _busy || (_onto && _picked == null),
              ),
            SheetRow(key: const ValueKey('share-cancel'), icon: const AppIcon(Lucide.x, size: 18), label: 'Cancel', onPress: _cancel, disabled: _busy),
          ],
        ),
      ],
    );
  }
}
