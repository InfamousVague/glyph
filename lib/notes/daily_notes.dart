/// Today's note: one note a day, found by its date and made the first time it is asked for (Matt, 2026-10-16,
/// after a look at Obsidian's Daily notes and what Evernote keeps).
///
/// **One note a date.** A daily note is the note named by the day, `2026-10-16`, the name the built-in "A day"
/// template already gives (lib/notes/note_templates.dart), and the name Obsidian's Daily notes give theirs, so a
/// library carried there or from there finds the same notes. Today opens the note of that name where there is one
/// (not one in the archive or the Trash), and otherwise makes it: from the template Settings › Daily notes names,
/// your own page of that name where you keep Your templates, else the one built in; the template's words filled for
/// today. A template whose heading is not the date gets `title: "2026-10-16"` in its front matter, so the note is
/// still named by its day and found again tomorrow as yesterday's.
///
/// **Not a journal.** A journal (guide chapter 14) keeps entries by the minute, as many a day as are written, each
/// a line in its index; it is a diary of moments. A daily note is one page per date that a day's notes, to-dos and
/// links gather on, reached the same way every day: it needs no index, and two taps on Today never make two. A
/// person who wants both has both: a journal for entries, and Today for the day's page.
///
/// **Where it goes.** Into the Daily notes folder (a workspace of that name, made the first time a daily note is),
/// another workspace, or none, as Settings › Daily notes says; and, if Settings names a notebook, onto its index as
/// a page. Kept in the preferences under [dailyNotesKey], so the choice follows the account:
///
///     "dailyNotes": {"folder": "w-k3f9x2", "notebook": "<a notebook's note id>", "template": "A day"}
///
/// `folder` left out is the Daily notes folder, and `""` is none. Carried in [Preferences.more], as the smart
/// notebooks are (lib/core/smart_notebooks.dart), so the shared class is untouched.
library;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show quotedTitle;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/preferences.dart';
import '../core/title_key.dart' show titleKey;
import 'note_templates.dart';

/// The preference the choices are kept under.
const String dailyNotesKey = 'dailyNotes';

/// The folder daily notes go in until another is chosen.
const String dailyFolderName = 'Daily notes';

/// The template a daily note starts from until another is chosen: the built-in day's.
const String dailyTemplateName = 'A day';

/// What Settings › Daily notes chose.
@immutable
class DailyNotesSetup {
  const DailyNotesSetup({this.folder, this.notebook, this.template});

  /// The workspace a daily note is filed in, by id: null for the Daily notes folder, made the first time one is
  /// needed; empty for none.
  final String? folder;

  /// A notebook whose index a daily note is put on, by its note's id; null for none.
  final String? notebook;

  /// The template's name; null for [dailyTemplateName].
  final String? template;

  factory DailyNotesSetup.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    String? word(String key) => map[key] is String ? map[key] as String : null;
    return DailyNotesSetup(folder: word('folder'), notebook: (word('notebook') ?? '').isEmpty ? null : word('notebook'), template: (word('template') ?? '').isEmpty ? null : word('template'));
  }

  Map<String, Object?> toJson() => {if (folder != null) 'folder': folder, if (notebook != null) 'notebook': notebook, if (template != null) 'template': template};

  /// The same choices with one changed; each is a function so null can be said.
  DailyNotesSetup copyWith({String? Function()? folder, String? Function()? notebook, String? Function()? template}) => DailyNotesSetup(
        folder: folder == null ? this.folder : folder(),
        notebook: notebook == null ? this.notebook : notebook(),
        template: template == null ? this.template : template(),
      );

  @override
  bool operator ==(Object other) => other is DailyNotesSetup && other.folder == folder && other.notebook == notebook && other.template == template;

  @override
  int get hashCode => Object.hash(folder, notebook, template);
}

/// The choices a set of preferences keeps.
DailyNotesSetup dailyNotesIn(Preferences prefs) => DailyNotesSetup.fromJson(prefs.more[dailyNotesKey]);

/// [prefs] keeping [setup].
Preferences withDailyNotes(Preferences prefs, DailyNotesSetup setup) => prefs.copyWith(more: {...prefs.more, dailyNotesKey: setup.toJson()});

/// A day's note's name: `2026-10-16`.
String dailyTitle(DateTime day) => formatStamp(day, 'YYYY-MM-DD');

/// The note named by [day], not in the archive; the one made first where two are.
Note? dailyNoteOf(Iterable<Note> notes, DateTime day) {
  final key = titleKey(dailyTitle(day));
  Note? found;
  for (final note in notes) {
    if ((note.archivedAt ?? 0) != 0 || NoteFacts.of(note).key != key) continue;
    if (found == null || note.createdAt < found.createdAt) found = note;
  }
  return found;
}

/// The template a daily note starts from: the one [setup] names among [templates] (your own, where you keep Your
/// templates, else the built-ins), else the day's of them, else the built-in day.
NoteTemplate dailyTemplate(DailyNotesSetup setup, List<NoteTemplate> templates) {
  final named = (setup.template ?? dailyTemplateName).toLowerCase();
  for (final template in templates) {
    if (template.name.toLowerCase() == named) return template;
  }
  for (final template in templates) {
    if (template.kind == TemplateId.day || template.name.toLowerCase() == dailyTemplateName.toLowerCase()) return template;
  }
  return builtIns.first;
}

/// A daily note's words for [day] from [template], and where its caret goes: named by the date, whatever the
/// template's heading says.
({String body, int caret, String title}) dailyNoteBody(NoteTemplate template, DateTime day) {
  final title = dailyTitle(day);
  final filled = fillNoteTemplate(template, day, const {}, title: title);
  if (titleKey(filled.title) == titleKey(title)) return (body: filled.body, caret: filled.caret, title: title);
  final named = withFrontMatterValue(filled.body, 'title', quotedTitle(title, title));
  // The caret where it was in the words, which the front matter now stands further in front of.
  return (body: named, caret: filled.caret + (named.length - filled.body.length), title: title);
}
