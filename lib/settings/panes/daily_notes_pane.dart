import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/book.dart' show isTemplatesBook;
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/preferences.dart';
import '../../core/workspaces.dart';
import '../../notes/daily_notes.dart';
import '../../notes/note_templates.dart';
import '../../notes/own_templates.dart' show templatesOf;
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'pane_parts.dart';
import 'settings_host.dart';

/// The library the page lists the notebooks and your templates from, handed over once by the app's root
/// (lib/root/organize.dart). Without one the page lists the built-in templates and no notebook.
ValueListenable<List<Note>>? dailyNotesLibrary;

/// What Settings' search finds on Daily notes.
const List<SettingsFindable> dailyNotesFindable = [
  SettingsFindable('Where they go', 'daily note today folder workspace date'),
  SettingsFindable('Starts from', 'daily note today template day'),
  SettingsFindable('In a notebook', 'daily note today notebook index page'),
];

/// The row's reading: where today's note goes.
String dailyNotesSummary(Preferences prefs, List<Workspace> spaces) {
  final folder = dailyNotesIn(prefs).folder;
  if (folder == null) return 'In $dailyFolderName';
  if (folder.isEmpty) return 'In no folder';
  final named = spaces.where((w) => w.id == folder).firstOrNull;
  return named == null ? 'In $dailyFolderName' : 'In ${named.name}';
}

/// Settings › Daily notes (the port's own, 2026-10-16; lib/notes/daily_notes.dart): where Today's note is filed,
/// what it starts from, and a notebook it can be a page of. Each is a choice among a list, the chosen one's ring
/// filled, kept in the preferences, so it follows the account.
class DailyNotesPane extends StatelessWidget {
  const DailyNotesPane({super.key, required this.workspaces, this.prefs, this.library});

  final WorkspaceStore workspaces;

  /// The preferences it reads and writes; the app's own when left out.
  final PreferencesStore? prefs;

  /// The notes, for the notebooks and your templates; [dailyNotesLibrary] when left out.
  final ValueListenable<List<Note>>? library;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return DailyNotesPane(workspaces: host?.workspaces ?? WorkspaceStore());
  }

  @override
  Widget build(BuildContext context) {
    final store = prefs ?? preferences;
    final notes = library ?? dailyNotesLibrary;
    return ListenableBuilder(
      listenable: Listenable.merge([store, workspaces, ?notes]),
      builder: (context, _) {
        final setup = dailyNotesIn(store.value);
        void set(DailyNotesSetup next) => store.update((now) => withDailyNotes(now, next));
        final all = notes?.value ?? const <Note>[];
        final templates = templatesOf(all) ?? builtIns;
        final chosenTemplate = dailyTemplate(setup, templates);
        final notebooks = [
          for (final note in all)
            if ((note.archivedAt ?? 0) == 0 && NoteFacts.of(note).isBook && !NoteFacts.of(note).isJournal && !isTemplatesBook(note.body)) note,
        ]..sort((a, b) => NoteFacts.of(a).title.toLowerCase().compareTo(NoteFacts.of(b).title.toLowerCase()));
        final list = workspaces.value.list;
        final personal = [for (final w in list) if (w.org == null) w];
        // The Daily notes folder, once it is made, is the first row's, not a row of its own.
        final made = personal.where((w) => w.name.toLowerCase() == dailyFolderName.toLowerCase() && w.parent == null).firstOrNull;
        final folder = setup.folder;
        final inMade = folder == null || (made != null && folder == made.id);

        SettingRow pick(String key, String label, String? hint, bool checked, VoidCallback onPress, {Widget? icon}) => SettingRow(
              key: ValueKey(key),
              icon: icon,
              label: label,
              hint: hint == null ? null : Text(hint),
              control: Pick(checked: checked, label: label, onPress: onPress),
            );

        return PaneBody(
          children: [
            PaneSection(
              title: 'Where they go',
              description: const Text('Today opens the note named by the day’s date, and makes it the first time. A new one is filed here.'),
              children: [
                pick('daily-folder-own', dailyFolderName, made == null ? 'A folder of their own, made with the first one.' : 'A folder of their own.', inMade, () => set(setup.copyWith(folder: () => null)), icon: HueMark(hue: made?.hue)),
                for (final w in personal)
                  if (w.id != made?.id) pick('daily-folder-${w.id}', workspacePathName(list, w.id), null, folder == w.id, () => set(setup.copyWith(folder: () => w.id)), icon: HueMark(hue: w.hue)),
                pick('daily-folder-none', 'No folder', 'Filed as a new note is: in the workspace you are looking at, or none.', folder != null && folder.isEmpty, () => set(setup.copyWith(folder: () => ''))),
              ],
            ),
            PaneSection(
              title: 'Starts from',
              description: Text(templatesOf(all) == null ? 'A template, filled for the day. Your templates, once you keep them, are listed here too.' : 'One of your templates, filled for the day.'),
              children: [
                for (final template in templates)
                  pick('daily-template-${template.name}', template.name, template.sentence, identical(template, chosenTemplate) || template.name == chosenTemplate.name, () => set(setup.copyWith(template: () => template.name))),
              ],
            ),
            PaneSection(
              title: 'In a notebook',
              description: const Text('A daily note can be a page of a notebook too: its line goes on the notebook’s index when it is made.'),
              children: [
                pick('daily-book-none', 'None', null, setup.notebook == null, () => set(setup.copyWith(notebook: () => null))),
                for (final book in notebooks)
                  pick('daily-book-${book.id}', NoteFacts.of(book).title.isEmpty ? 'Untitled notebook' : NoteFacts.of(book).title, null, setup.notebook == book.id, () => set(setup.copyWith(notebook: () => book.id))),
              ],
            ),
            const SettingsFootnote(
              child: Text(
                'A journal keeps entries by the minute, as many a day as you write. A daily note is one page a date, found again by its name. Today is in the +, in the command palette, and on a Mac under Command-Shift-D.',
              ),
            ),
          ],
        );
      },
    );
  }
}
