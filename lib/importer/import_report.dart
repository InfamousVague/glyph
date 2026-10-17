/// What an import did, counted, and said in the app's words at the end of it (Settings › Import).
library;

import 'import_paths.dart' show Renamed;

/// How far an import has got: what it is on, and how many of how many.
typedef ImportProgress = ({int done, int total, String? on});

/// What an import brought in and what it left out.
class ImportReport {
  ImportReport({required this.from});

  /// `Obsidian`, `Evernote`, `Todoist` or `Things`.
  final String from;

  /// The workspace the import made, which holds everything it brought in; null where it brought in nothing.
  String? groupId;
  String? groupName;

  /// The notes made, by id, the notebooks among them.
  final List<String> noteIds = [];

  int notes = 0;
  int canvases = 0;
  int notebooks = 0;
  int pictures = 0;
  int files = 0;

  /// The to-dos written into those notes (Todoist's tasks, Things' to-dos), sub-tasks and checklist items among them.
  int tasks = 0;

  /// What was left out, each a short line in the app's words: `.obsidian/, Obsidian's settings`.
  final List<String> skipped = [];

  /// Notes given another name because theirs was taken.
  final List<Renamed> renamed = [];

  /// References to a picture or a file that was not there to bring.
  int missing = 0;

  bool get empty => notes == 0 && canvases == 0 && notebooks == 0;
}

String _count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// What the import made, in one sentence: "42 notes, 2 canvases, 10 pictures and 3 files, in Imported from Obsidian
/// 2026-10-16." A list's import counts its to-dos beside its notes: "4 notes, 37 to-dos and 1 notebook, …".
String importDoneSaid(ImportReport report) {
  if (report.empty) return 'Nothing was imported.';
  final parts = [
    if (report.notes > 0) _count(report.notes, 'note'),
    if (report.tasks > 0) _count(report.tasks, 'to-do'),
    if (report.notebooks > 0) _count(report.notebooks, 'notebook'),
    if (report.canvases > 0) _count(report.canvases, 'canvas', 'canvases'),
    if (report.pictures > 0) _count(report.pictures, 'picture'),
    if (report.files > 0) _count(report.files, 'file'),
  ];
  final listed = parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return 'Imported $listed, in the workspace ${report.groupName}.';
}

/// The renames, a few by name: "Two notes were given new names because theirs were taken: Alpha.md is Alpha 2.md,
/// …". Null where none was.
String? importRenamedSaid(ImportReport report, {int most = 3}) {
  final renamed = report.renamed;
  if (renamed.isEmpty) return null;
  final named = [for (final each in renamed.take(most)) '${each.from} is now ${each.to}'].join('; ');
  final more = renamed.length > most ? '; and ${renamed.length - most} more' : '';
  return renamed.length == 1
      ? 'A name was taken, so one note has another: $named.'
      : '${renamed.length} names were taken, so those notes have others: $named$more.';
}

/// What was left out, in one sentence; null where nothing was.
String? importSkippedSaid(ImportReport report) {
  final lines = [...report.skipped, if (report.missing > 0) _count(report.missing, 'link to a missing file', 'links to missing files')];
  if (lines.isEmpty) return null;
  return 'Left out: ${lines.join('; ')}.';
}
