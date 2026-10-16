/// What the root does for the 2026-10-16 organizing features, in one object the root makes and hands round
/// (docs/FEATURES_2_1.md, organize): the smart notebooks and their sheet, the Tags page and a tag's, a tag renamed
/// across the library, and today's note.
///
/// Kept out of the root's own files, so the root holds one field of this and a line where each piece is put on
/// screen: [Organize] does the work over what the root hands it (its library, workspaces, shell and its way of
/// making a note), and [OrganizeSheets] draws the smart notebook's sheet over the app while one is up.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/book.dart' show withChapter;
import '../core/library.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/smart_notebooks.dart';
import '../core/tag_index.dart' show renameTagIn;
import '../core/workspaces.dart';
import '../note/note_screen.dart' show NoteScreenState;
import '../notes/daily_notes.dart';
import '../notes/note_templates.dart' show NoteTemplate, builtIns;
import '../notes/smart_notebook_sheet.dart';
import '../settings/panes/daily_notes_pane.dart' show dailyNotesLibrary;
import '../shell/app_shell.dart';
import '../shell/screen.dart';

/// A note made by the root and opened: its words, where the caret goes, and the workspace it is filed in.
typedef MakeNote = Note Function(String body, {Caret? caret, String? into});

/// Which smart notebook sheet is up: one to keep [query] as, or one [editing].
typedef SmartSheet = ({String? query, SmartNotebook? editing});

class Organize extends ChangeNotifier {
  Organize({
    required this.library,
    required this.workspaces,
    required this.shell,
    required this.notes,
    required this.make,
    required this.screenOf,
    required this.templates,
    required this.say,
    PreferencesStore? prefs,
    SmartNotebookStore? smart,
  })  : _prefs = prefs ?? preferences,
        smart = smart ?? SmartNotebookStore(prefs: prefs) {
    // Settings › Daily notes lists the notebooks and your templates from the library.
    dailyNotesLibrary = library;
  }

  final NoteLibrary library;
  final WorkspaceStore workspaces;

  /// The shell, once it is up.
  final AppShellState? Function() shell;

  /// The notes a screen shows: the trash and a pending delete left out.
  final List<Note> Function() notes;
  final MakeNote make;

  /// The screen of the note being read, where it is the one asked about: its words are its own to change.
  final NoteScreenState? Function(String id) screenOf;

  /// The templates a new note can start from: your own where you keep them, else the ones built in.
  final List<NoteTemplate>? Function() templates;
  final void Function(String message) say;
  final PreferencesStore _prefs;

  /// The smart notebooks, kept in the preferences.
  final SmartNotebookStore smart;

  SmartSheet? _sheet;

  /// The smart notebook's sheet that is up, or null.
  SmartSheet? get sheet => _sheet;

  /// The Save under a search: a sheet to name it.
  void saveSearch(String query) {
    if (query.trim().isEmpty) return;
    _sheet = (query: query.trim(), editing: null);
    notifyListeners();
  }

  /// A smart notebook's sheet, from its More.
  void editSmart(SmartNotebook notebook) {
    _sheet = (query: null, editing: notebook);
    notifyListeners();
  }

  void closeSheet() {
    if (_sheet == null) return;
    _sheet = null;
    notifyListeners();
  }

  // ---- the pages ----------------------------------------------------------------------------------------------

  void showTags() => shell()?.showCollection(CollectionKind.tags);

  /// A tag's page: [fromTags] where the Tags page opened it, so its way back goes there.
  void showTag(String tag, {bool fromTags = false}) {
    final name = tag.toLowerCase().replaceFirst(RegExp(r'^#+'), '');
    if (name.isEmpty) return;
    final now = shell()?.screen;
    // From a tag's page to another's, the way back stays the first one's.
    final back = fromTags || (now is ScreenCollection && now.kind != CollectionKind.smart && (now.kind == CollectionKind.tags || now.fromTags));
    shell()?.showCollection(CollectionKind.tag, key: name, fromTags: back);
  }

  void showSmart(String id) => shell()?.showCollection(CollectionKind.smart, key: id);

  // ---- a tag renamed ------------------------------------------------------------------------------------------

  /// [from] called [to] in every note that has it (lib/core/tag_index.dart `renameTagIn`), the archive's and the
  /// Trash's too, so a note brought back reads the same: each written over the revision the library has now, as a
  /// change from outside a note is, and the note being read through its own screen, whose next save would
  /// otherwise write the old words back. Answers how many notes were changed.
  Future<int> renameTag(String from, String to) async {
    var changed = 0, failed = 0;
    String? change(String body) {
      final next = renameTagIn(body, from, to);
      return identical(next, body) || next == body ? null : next;
    }

    for (final note in [...library.value]) {
      if (change(note.body) == null) continue;
      final open = screenOf(note.id);
      if (open != null) {
        open.writeNotebook((body) => change(body) ?? body);
        changed += 1;
        continue;
      }
      try {
        final fresh = await library.get(note.id);
        final next = fresh == null ? null : change(fresh.body);
        if (fresh == null || next == null) continue;
        await library.update(note.id, next, fresh.revision);
        changed += 1;
      } catch (_) {
        failed += 1;
      }
    }
    await library.refresh().catchError((Object _) {});
    if (failed > 0) {
      say(failed == 1 ? 'One note was changing elsewhere and kept #$from. Try the rename again.' : '$failed notes were changing elsewhere and kept #$from. Try the rename again.');
    } else {
      say(changed == 1 ? '#$from is #$to in 1 note.' : '#$from is #$to in $changed notes.');
    }
    return changed;
  }

  // ---- today's note -------------------------------------------------------------------------------------------

  /// Today's note (lib/notes/daily_notes.dart): opened where there is one, else made from the template Settings
  /// names, filed in its folder (the Daily notes folder made the first time), put on a notebook's index where
  /// Settings names one, and opened with the caret where the template leaves it.
  void today({DateTime? now}) {
    final day = now ?? DateTime.now();
    final had = dailyNoteOf(notes(), day);
    if (had != null) {
      shell()?.openNote(had.id);
      return;
    }
    final setup = dailyNotesIn(_prefs.value);
    final made = dailyNoteBody(dailyTemplate(setup, templates() ?? builtIns), day);
    final folder = setup.folder;
    String? into;
    if (folder == null) {
      into = workspaces.addWorkspace(dailyFolderName)?.id;
    } else if (folder.isNotEmpty && workspaces.value.list.any((w) => w.id == folder)) {
      into = folder;
    }
    make(made.body, caret: Caret.at(made.caret), into: into);
    final book = setup.notebook;
    if (book == null) return;
    String chapter(String body) => withChapter(body, made.title);
    final open = screenOf(book);
    if (open != null) {
      open.writeNotebook(chapter);
      return;
    }
    unawaited(() async {
      try {
        final fresh = await library.get(book);
        if (fresh == null) return;
        final next = chapter(fresh.body);
        if (next != fresh.body) await library.update(book, next, fresh.revision);
        await library.refresh();
      } catch (_) {
        // The notebook was changing elsewhere: today's note is made, and its line can be added from the index.
      }
    }());
  }

  @override
  void dispose() {
    if (identical(dailyNotesLibrary, library)) dailyNotesLibrary = null;
    smart.dispose();
    super.dispose();
  }
}

/// The smart notebook's sheet over the app, while [Organize.sheet] says one is up.
class OrganizeSheets extends StatelessWidget {
  const OrganizeSheets({super.key, required this.organize});

  final Organize organize;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: organize,
        builder: (context, _) {
          final sheet = organize.sheet;
          if (sheet == null) return const SizedBox.shrink();
          final editing = sheet.editing == null ? null : organize.smart.byId(sheet.editing!.id);
          return SmartNotebookSheet(
            key: ValueKey('smart-sheet:${editing?.id ?? 'new'}'),
            store: organize.smart,
            query: sheet.query,
            editing: editing,
            onClose: organize.closeSheet,
            onMade: (made) => organize.say('Saved as ${made.name}, under Smart notebooks in the sidebar.'),
          );
        },
      );
}
