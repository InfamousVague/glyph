/// The Trash, as a section of its own (Matt, 2026-10-23: "add a "trash" section in the app where deleted notes go
/// before getting perma deleted"). The port's own: the web's trash is the sidebar's last folder only, which this
/// app keeps (lib/notes/note_tree.dart), and that folder, All notes' Trash word and the palette's Trash open this.
///
/// A sheet, as a workspace's is (lib/notes/workspace_sheet.dart), over whatever is on screen: from the foot on a
/// phone, a window in the middle on a Mac. Its first page lists the notes in the trash, the last thrown away first,
/// each with when it went in and how long it has left; Empty Trash under them; and the rule at the foot, that a note
/// is deleted for good thirty days after it goes in (lib/core/trash.dart `trashKeeps`), an organization's excepted.
/// A note's row opens its own page: Restore, which puts it back where it was, its folder and all, since a note in
/// the trash keeps its filing (and says where that is); Delete for good, which asks once; and Back. Emptying asks
/// once too. The words are the sidebar folder's, the web's: Restore, Delete for good, "Delete 3 for good?".
///
/// Nothing is done here: what each row does is the caller's, the app's own note actions (lib/notes/note_actions.dart),
/// so a note restored says so in a toast, and one deleted for good has its Undo, as from the sidebar. In simple mode
/// (GHST-103) a note's page offers Restore, with Delete for good behind a More row that opens in place.
library;

import 'package:flutter/widgets.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/trash.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'when.dart';

/// When a note went into the trash, as its row says it: "Deleted 2 hr ago", "Deleted yesterday", "Deleted on
/// Tuesday".
String deletedWhen(int at, int now) {
  final said = when(at, now);
  if (said == 'Just now' || said == 'Yesterday') return 'Deleted ${said.toLowerCase()}';
  if (said.endsWith(' ago')) return 'Deleted $said';
  return 'Deleted on $said';
}

/// How long a note has left in the trash, as its row says it after when it went in.
String trashLeft(int at, int now, {required bool team}) {
  if (team) return 'kept until you empty the Trash';
  final days = trashDaysLeft(at, now);
  if (days <= 0) return 'deleted for good today';
  return days == 1 ? 'deleted for good tomorrow' : 'deleted for good in $days days';
}

/// The Trash's sheet.
class TrashSheet extends StatefulWidget {
  const TrashSheet({
    super.key,
    required this.notes,
    required this.held,
    required this.onRestore,
    required this.onDestroy,
    required this.onEmpty,
    required this.onClose,
    this.open,
    this.teamNote,
    this.placeOf,
    this.simple = false,
    this.now,
  });

  /// The notes in the trash, the last thrown away first (lib/core/trash.dart `inTrash`), less any deleted for good
  /// whose Undo still stands.
  final List<Note> notes;

  /// When each went in.
  final TrashHeld held;

  /// Out of the trash, back where it was.
  final ValueChanged<Note> onRestore;

  /// Deleted for good, once asked.
  final ValueChanged<Note> onDestroy;

  /// Every note in it deleted for good, once asked.
  final VoidCallback onEmpty;
  final VoidCallback onClose;

  /// The note whose page the sheet opens on, by id: one pressed in the sidebar's Trash folder.
  final String? open;

  /// Whether a note is an organization's, which waits for the person's own Empty (lib/core/trash.dart
  /// `expiredInTrash`).
  final bool Function(String id)? teamNote;

  /// Where a note is filed, as Restore's hint says it: "Work › Clients"; null for none.
  final String? Function(String id)? placeOf;

  /// Simple mode (GHST-103): Delete for good behind More on a note's page.
  final bool simple;

  /// The moment "2 hr ago" is counted from; this one where it is left out.
  final int Function()? now;

  @override
  State<TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends State<TrashSheet> {
  /// The note whose page is open, by id; null for the list.
  late String? _note = widget.open;

  /// Delete for good pressed on a note's page: the sheet asks first.
  bool _destroying = false;

  /// Empty Trash pressed: the sheet asks first.
  bool _emptying = false;

  /// Simple mode's More, opened on a note's page.
  bool _more = false;

  int get _now => widget.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  static String _title(Note note) {
    final title = NoteFacts.of(note).title.trim();
    return title.isEmpty ? 'Untitled' : title;
  }

  bool _team(String id) => widget.teamNote?.call(id) ?? false;

  void _list() => setState(() {
        _note = null;
        _destroying = false;
        _emptying = false;
        _more = false;
      });

  String _hint(Note note, int now) {
    final at = widget.held[note.id] ?? now;
    return '${deletedWhen(at, now)} · ${trashLeft(at, now, team: _team(note.id))}';
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final notes = widget.notes;
    final open = _note == null ? null : notes.where((note) => note.id == _note).firstOrNull;

    if (_emptying && notes.isNotEmpty) {
      final count = notes.length;
      return Sheet(
        label: 'Empty the Trash',
        onBack: _list,
        onClose: widget.onClose,
        children: [
          SheetTitle.text('Delete $count for good?'),
          SheetNote(count == 1 ? 'The note in the Trash is deleted for good. It cannot be restored.' : 'The $count notes in the Trash are deleted for good. They cannot be restored.'),
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('trash-empty-yes'),
                label: 'Empty Trash',
                danger: true,
                onPress: () {
                  widget.onEmpty();
                  widget.onClose();
                },
              ),
              SheetRow(label: 'Cancel', onPress: _list),
            ],
          ),
        ],
      );
    }

    if (open != null) {
      final title = _title(open);
      if (_destroying) {
        return Sheet(
          label: 'Delete $title for good',
          onBack: () => setState(() => _destroying = false),
          onClose: widget.onClose,
          children: [
            SheetTitle.text('Delete “$title” for good?'),
            SheetNote(_team(open.id) ? 'It is deleted for every member of its organization too.' : 'It cannot be restored from the Trash after this.'),
            SheetGroup(
              children: [
                SheetRow(
                  key: const ValueKey('trash-destroy-yes'),
                  label: 'Delete for good',
                  danger: true,
                  onPress: () {
                    widget.onDestroy(open);
                    _list();
                  },
                ),
                SheetRow(label: 'Cancel', onPress: () => setState(() => _destroying = false)),
              ],
            ),
          ],
        );
      }
      final place = widget.placeOf?.call(open.id);
      final destroy = SheetRow(key: const ValueKey('trash-destroy'), label: 'Delete for good', danger: true, onPress: () => setState(() => _destroying = true));
      return Sheet(
        label: title,
        onBack: _list,
        onClose: widget.onClose,
        children: [
          SheetTitle.text(title),
          SheetNote('${_hint(open, now)}.'),
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('trash-restore'),
                label: 'Restore',
                hint: place == null ? 'Back in your notes.' : 'Back in $place.',
                onPress: () {
                  widget.onRestore(open);
                  if (notes.length <= 1) {
                    widget.onClose();
                  } else {
                    _list();
                  }
                },
              ),
              if (!widget.simple)
                destroy
              else if (_more)
                destroy
              else
                SheetRow(key: const ValueKey('trash-more'), label: 'More', onPress: () => setState(() => _more = true)),
              SheetRow(label: 'Back', onPress: _list),
            ],
          ),
        ],
      );
    }

    final team = notes.any((note) => _team(note.id));
    return Sheet(
      label: 'Trash',
      onClose: widget.onClose,
      children: [
        const SheetTitle(child: Text('Trash')),
        SheetNote(notes.isEmpty ? 'Nothing in the Trash.' : 'Deleted notes wait here. Restore one to put it back where it was.'),
        if (notes.isNotEmpty) ...[
          SheetGroup(
            children: [
              for (final note in notes) SheetRow(key: ValueKey('trash-note-${note.id}'), label: _title(note), hint: _hint(note, now), onPress: () => setState(() => _note = note.id)),
            ],
          ),
          SheetGroup(
            children: [
              SheetRow(key: const ValueKey('trash-empty'), label: 'Empty Trash', hint: notes.length == 1 ? 'Deletes 1 note for good.' : 'Deletes ${notes.length} notes for good.', danger: true, onPress: () => setState(() => _emptying = true)),
            ],
          ),
        ],
        SheetNote(
          team
              ? 'Notes are deleted for good ${trashKeeps.inDays} days after they go in the Trash. An organization’s notes wait until you empty it.'
              : 'Notes are deleted for good ${trashKeeps.inDays} days after they go in the Trash.',
        ),
      ],
    );
  }
}
