/// The home page over a library: [HomeScreen] with its swipes, its pull and its + done to a [NoteLibrary], so the
/// page is alive wherever it is put up, over the sample library today and the real one when it arrives.
///
/// Stands for what `src/app/App.tsx` wires round the web's HomeScreen: `notes/useNoteActions.ts` (pin, archive and
/// delete, each with its Undo in a toast: "Archived “Flat”.", "Moved “Flat” to the Trash."), `core/workspaces.ts`
/// `fileNewNote` (a note made while a workspace is chosen is filed there) and `forgetNote`, and the refresh a pull
/// asks for.
///
/// What differs: a note deleted here is taken out of the library and handed back by Undo ([NoteLibrary.restore]);
/// the web's goes to the Trash, which is the library's to port. Everything that leaves the page (a note opened, the
/// palette, Speak, All notes, a workspace's sheet, an organization) is still a callback: this goes nowhere itself.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/note_text.dart';
import '../core/sample_library.dart';
import '../core/swipe.dart';
import '../core/workspaces.dart';
import 'home_layout.dart';
import 'home_organizations.dart';
import 'home_screen.dart';

/// How long an Undo is offered (`UNDO_MS`).
const Duration _undo = Duration(milliseconds: 5000);

/// A note as a toast names it (`label`): its title in quotes, or "the note" where it has none or a long one.
String _label(Note note) {
  final title = noteTitle(note.body);
  return title.isNotEmpty && title.length <= 28 ? '“$title”' : 'the note';
}

/// [HomeScreen] over a [NoteLibrary] and a [WorkspaceStore]: the part of the web's `App.tsx` and
/// `notes/useNoteActions.ts` that makes the home page's swipes, pull and + do something. A deleted note is handed
/// back by Undo from the library itself, where the web's waits in the Trash.
class LibraryHome extends StatelessWidget {
  const LibraryHome({
    super.key,
    required this.library,
    required this.workspaces,
    this.layout = HomeLayout.spotlight,
    required this.onOpen,
    this.onNew,
    this.onCapture,
    this.onSearch,
    required this.onAllNotes,
    this.onManageWorkspace,
    this.onNewOrganization,
    this.onOrganization,
    this.onOrganizationSettings,
    this.onNoteMenu,
    this.organizations = const [],
    this.clock,
    this.headerEdge,
    this.dockHalo,
    this.ghost,
  });

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final HomeLayout layout;
  final ValueChanged<String> onOpen;

  /// The dock's +. Left out, a new note is made in the library, filed where the page is, and opened.
  final VoidCallback? onNew;
  final VoidCallback? onCapture;
  final VoidCallback? onSearch;
  final VoidCallback onAllNotes;
  final ValueChanged<Workspace?>? onManageWorkspace;
  final VoidCallback? onNewOrganization;
  final ValueChanged<String>? onOrganization;
  final ValueChanged<String>? onOrganizationSettings;
  final ValueChanged<String>? onNoteMenu;
  final List<HomeOrg> organizations;
  final int Function()? clock;
  final HomeEdgeBuilder? headerEdge;
  final HomeDockHaloBuilder? dockHalo;
  final HomeGhostBuilder? ghost;

  void _swipe(BuildContext context, Note note, NoteSwipe action) {
    final toast = GlacierToast.of(context);
    final fire = HapticsProvider.of(context);
    switch (action) {
      case NoteSwipe.pin:
        library.pin(note.id, pinned: !note.starred);
        fire(HapticKind.success);
      case NoteSwipe.archive:
        library.archive(note.id, archived: true);
        fire(HapticKind.success);
        toast.toast(
          message: Text('Archived ${_label(note)}.'),
          duration: _undo,
          action: GlacierToastAction(label: 'Undo', onPress: () => library.archive(note.id, archived: false)),
        );
      case NoteSwipe.delete:
        final gone = library.delete(note.id);
        if (gone == null) return;
        final filed = workspaces.workspaceOf(note.id)?.id;
        workspaces.forgetNote(note.id);
        fire(HapticKind.warning);
        toast.toast(
          message: Text('Moved ${_label(note)} to the Trash.'),
          duration: _undo,
          action: GlacierToastAction(
            label: 'Undo',
            onPress: () {
              library.restore(gone);
              if (filed != null) workspaces.fileNote(gone.id, filed);
              fire(HapticKind.success);
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Note>>(
      valueListenable: library,
      builder: (context, notes, _) => HomeScreen(
        notes: notes,
        workspaces: workspaces,
        layout: layout,
        onOpen: onOpen,
        onNew: onNew ??
            () {
              final note = library.create('');
              workspaces.fileNewNote(note.id);
              onOpen(note.id);
            },
        onCapture: onCapture,
        onSearch: onSearch,
        onAllNotes: onAllNotes,
        onSwipe: (note, action) => _swipe(context, note, action),
        onRefresh: library.refresh,
        onManageWorkspace: onManageWorkspace,
        onNewOrganization: onNewOrganization,
        onOrganization: onOrganization,
        onOrganizationSettings: onOrganizationSettings,
        onNoteMenu: onNoteMenu,
        organizations: organizations,
        clock: clock,
        headerEdge: headerEdge,
        dockHalo: dockHalo,
        ghost: ghost,
      ),
    );
  }
}
