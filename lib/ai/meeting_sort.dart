/// Meetings sorted into workspaces by the AI (Matt, 2026-10-24: "Allow for AI inferred sorting of meetings based on
/// meeting context (to know where to place meetings under the right workspace in a meeting folder"). The port's own:
/// the web app has no such thing.
///
/// Once a meeting's note is written up (ai/summaries.dart `_said`, for a meeting's job alone, whether the app is on
/// the screen or not), the AI is asked which of the person's workspaces it belongs to, from the meeting's title, who
/// spoke in it, and its summary; and the note is filed into that workspace's "Meetings" folder, made where it is
/// missing (lib/core/workspaces.dart `addWorkspace`, whose id is the folder's place's, so every device makes the same
/// one). Matt's answers: filed automatically, with no question, an organization's workspace included, though filing
/// there shares the note with every member of it; and on by default, with its switch once for every kind of meeting
/// on Settings › Recording's Meetings card ([sortMeetingsKey]; lib/meet/ui/meeting_settings.dart; Matt, 2026-10-26:
/// "All meetings plugins should sort meetings to the same place on the recordings but have different settings"). The
/// meeting's kind is never asked: a Google Meet's, a Zoom's and a Discord call's are sorted alike.
///
/// The rules, each a test (test/ai/meeting_sort_test.dart):
/// - **Only a meeting the person has not filed.** One in no workspace (the Inbox: a meeting Ghost was in lands
///   there), or one the app itself filed as it was made, into the workspace the list was showing (lib/root/
///   capture_route.dart; [withAppFiled] remembers where), and still there. One the person moved anywhere is theirs.
/// - **Once.** A meeting asked about is remembered in [meetingSortsKey], whatever the answer, so a summary made again
///   does not move it again, nor one the person took back out of the folder. An ask that failed (no model, no
///   connection) is not remembered, and the next write-up asks again.
/// - **Only when the AI is sure.** "none", an answer that is not a workspace offered, or `"confident": false`, and the
///   meeting stays where it is.
/// - **The AI the summaries use.** Claude where it writes the meetings up ([MeetingClaude.enabled], which Local only
///   turns off), else the phone's own model ([askMeetingSort]); with neither, nothing is asked.
///
/// What is offered ([sortCandidates]): every workspace at the top, personal or an organization's, and the folders
/// directly inside each, each named by its path (`HelloTrade › Clients`) with a few of its notes' titles, so the AI
/// can tell a workspace by what is in it. A folder called Meetings is never offered: it is where a meeting goes, not
/// what it is about.
///
/// Both marks are kept in the preferences' unknown keys ([Preferences.more]) and travel with the account
/// (lib/sync/prefs.dart `syncedPrefs`); [meetingSortsKey] is a map, merged an entry at a time.
library;

import 'dart:async';
import 'dart:convert';

import '../core/note.dart' show Note;
import '../core/note_text.dart' show noteTitle;
import '../core/preferences.dart' show Preferences;
import '../core/workspaces.dart';
import '../meet/speakers.dart' show sectionOf, turnsOf;
import 'available.dart' show modelFor, presentIds;
import 'backend.dart' show RunOptions, aiBackend, generate, listModels;
import 'summary_claude.dart' show MeetingClaude;
import 'summary_text.dart' show summarySection;

/// The switch, in [Preferences.more]: false turns the sorting off; left out, or anything else, it is on.
const String sortMeetingsKey = 'sortMeetings';

/// What the sorting knows of each meeting, in [Preferences.more]: `{noteId: {"app": workspaceId}}` for a meeting the
/// app filed as it was made, and `{noteId: {"sorted": workspaceId}}` once it has been asked about (`""` where it was
/// left as it was).
const String meetingSortsKey = 'meetingSorts';

/// The folder a sorted meeting goes into, inside its workspace.
const String meetingsFolderName = 'Meetings';

/// Whether meetings are sorted: on unless the switch says false.
bool sortsMeetings(Preferences prefs) => prefs.more[sortMeetingsKey] != false;

/// The switch set.
Preferences withSortMeetings(Preferences prefs, bool on) => prefs.copyWith(more: {...prefs.more, sortMeetingsKey: on});

Map<String, Object?> _sorts(Preferences prefs) {
  final raw = prefs.more[meetingSortsKey];
  return raw is Map ? raw.cast<String, Object?>() : const {};
}

Map<String, Object?>? _markOf(Preferences prefs, String noteId) {
  final mark = _sorts(prefs)[noteId];
  return mark is Map ? mark.cast<String, Object?>() : null;
}

Preferences _marked(Preferences prefs, String noteId, Map<String, Object?> mark) =>
    prefs.copyWith(more: {...prefs.more, meetingSortsKey: {..._sorts(prefs), noteId: mark}});

/// A meeting the app filed as it was made, into [workspaceId] (the workspace the list was showing); nothing with
/// none, or once it has been sorted.
Preferences withAppFiled(Preferences prefs, String noteId, String? workspaceId) {
  if (workspaceId == null || _markOf(prefs, noteId)?.containsKey('sorted') == true) return prefs;
  return _marked(prefs, noteId, {'app': workspaceId});
}

/// The meeting asked about, filed into [workspaceId] or, with null, left where it was.
Preferences withSorted(Preferences prefs, String noteId, String? workspaceId) => _marked(prefs, noteId, {'sorted': workspaceId ?? ''});

/// Whether the meeting [noteId], filed in [filedIn] (null for none), is the sorting's to file: the switch on, not
/// asked about before, and in no workspace or still in the one the app filed it in.
bool sortable(Preferences prefs, String noteId, Workspace? filedIn) {
  if (!sortsMeetings(prefs)) return false;
  final mark = _markOf(prefs, noteId);
  if (mark != null && mark.containsKey('sorted')) return false;
  if (filedIn == null) return true;
  return mark != null && mark['app'] == filedIn.id;
}

/// A workspace offered to the AI: its [id], its [label] (the path's names), and a few [titles] of the notes in it.
class SortCandidate {
  const SortCandidate({required this.id, required this.label, this.titles = const []});

  final String id;
  final String label;
  final List<String> titles;
}

/// How many workspaces are offered at most, and how many titles each.
const int sortCandidatesMax = 40;
const int sortTitlesEach = 3;

bool _isMeetingsFolder(Workspace w) => w.name.trim().toLowerCase() == meetingsFolderName.toLowerCase();

/// The workspaces offered: those at the top, personal or an organization's, and the folders directly inside each,
/// none called Meetings, in the list's order with each top one's folders after it. [titlesIn] gives a workspace's
/// notes' titles, newest first.
List<SortCandidate> sortCandidates(List<Workspace> list, {List<String> Function(String workspaceId)? titlesIn}) {
  final ids = {for (final w in list) w.id};
  final top = [for (final w in list) if ((w.parent == null || !ids.contains(w.parent)) && !_isMeetingsFolder(w)) w];
  final out = <SortCandidate>[];
  SortCandidate offered(Workspace w) => SortCandidate(id: w.id, label: workspacePathName(list, w.id), titles: [...?titlesIn?.call(w.id).where((t) => t.trim().isNotEmpty).take(sortTitlesEach)]);
  for (final w in top) {
    out.add(offered(w));
    for (final child in list) {
      if (child.parent == w.id && !_isMeetingsFolder(child)) out.add(offered(child));
    }
  }
  return out.take(sortCandidatesMax).toList();
}

/// Who spoke in the meeting: the names of its `## Transcript` paragraphs (`**Name:** words`), else of its kept
/// captions, each once, in the order first heard.
List<String> attendeesOf(String body) {
  final names = <String>[];
  void add(String name) {
    final clean = name.trim();
    if (clean.isNotEmpty && !names.any((n) => n.toLowerCase() == clean.toLowerCase())) names.add(clean);
  }

  final transcript = sectionOf(body, '## Transcript');
  if (transcript != null) {
    for (final m in _speaker.allMatches(transcript)) {
      add(m.group(1)!);
    }
  }
  if (names.isEmpty) {
    for (final turn in turnsOf(body)) {
      add(turn.speaker);
    }
  }
  return names;
}

final RegExp _speaker = RegExp(r'^\*\*([^*:\n(]+?)(?:\s*\([\d:]+\))?:\*\*', multiLine: true);

/// The instruction the AI is given.
const String meetingSortPrompt = '''You file a meeting's notes into one of the person's workspaces.
You are given the meeting (its title, who spoke, and its summary) and a list of workspaces, each with its id, its name, and a few notes in it.
Answer with one JSON object and nothing else:
{"workspace":"<id>","confident":true} for the workspace the meeting clearly belongs to, or
{"workspace":"none"} when no workspace clearly fits, or you are unsure.
Use an id from the list exactly as written. Never invent one.''';

/// The question for one meeting: what it was, then the workspaces offered.
String meetingSortMessage({required String title, required List<String> attendees, required String summary, required List<SortCandidate> candidates}) {
  final spaces = [
    for (final c in candidates)
      '- id: ${c.id}\n  name: ${c.label}${c.titles.isEmpty ? '' : '\n  notes: ${c.titles.map((t) => '"${t.replaceAll('"', "'")}"').join(', ')}'}',
  ].join('\n');
  final said = summary.trim().length > 2400 ? '${summary.trim().substring(0, 2400)}…' : summary.trim();
  return 'Meeting\n'
      'Title: ${title.trim().isEmpty ? '(none)' : title.trim()}\n'
      'Attendees: ${attendees.isEmpty ? '(not known)' : attendees.join(', ')}\n'
      'Summary:\n${said.isEmpty ? '(none)' : said}\n\n'
      'Workspaces:\n${spaces.isEmpty ? '(none)' : spaces}';
}

final RegExp _think = RegExp(r'<think>[\s\S]*?</think>');
final RegExp _fence = RegExp(r'```(?:json)?');

/// The first JSON object in [output], if it wrote one (capture/understand.dart's `_objectIn`).
Map<String, Object?>? _objectIn(String output) {
  final start = output.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var quoted = false;
  for (var i = start; i < output.length; i += 1) {
    final ch = output[i];
    if (quoted) {
      if (ch == r'\') {
        i += 1;
      } else if (ch == '"') {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        try {
          final Object? value = jsonDecode(output.substring(start, i + 1));
          return value is Map ? value.cast<String, Object?>() : null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}

/// The workspace the AI chose, read back to one of [candidates] by its id exactly, else by its name or path in any
/// case; null for "none", an answer that is not sure (`"confident": false`), one that names nothing offered, or
/// rubbish. An answer with no JSON is read as an id or a name alone.
String? readMeetingSort(String output, List<SortCandidate> candidates) {
  final cleaned = output.replaceAll(_think, '').replaceAll(_fence, '').trim();
  final answer = _objectIn(cleaned);
  String said;
  if (answer != null) {
    if (answer['confident'] == false || answer['confident'] == 'false') return null;
    final chosen = answer['workspace'] ?? answer['id'];
    if (chosen is! String) return null;
    said = chosen.trim();
  } else {
    said = cleaned.split('\n').first.trim().replaceAll(RegExp(r'''^["'`]+|["'`.]+$'''), '');
  }
  if (said.isEmpty || said.toLowerCase() == 'none' || said.toLowerCase() == 'null') return null;
  for (final c in candidates) {
    if (c.id == said) return c.id;
  }
  final lower = said.toLowerCase();
  final byName = [for (final c in candidates) if (c.label.toLowerCase() == lower || c.label.split(' › ').last.toLowerCase() == lower) c];
  // A name two workspaces share says neither.
  return byName.length == 1 ? byName.first.id : null;
}

/// The AI asked one question: [system] and [prompt], answered with its words, or null where there is none to ask.
typedef MeetingSortAsk = Future<String?> Function(String system, String prompt);

/// The AI the summaries use: Claude where it writes meetings up (never under Local only, which [MeetingClaude.enabled]
/// reads), else the phone's own model; null where neither can answer.
MeetingSortAsk askMeetingSort({MeetingClaude? claude, required String Function() formatModel}) => (system, prompt) async {
      if (claude != null && claude.enabled && !claude.limited) return claude.write(system: system, prompt: prompt).done;
      if (!aiBackend.available) return null;
      final model = modelFor(presentIds(await listModels()), formatModel());
      if (model == null) return null;
      return (await generate(RunOptions(model: model, system: system, prompt: prompt, maxTokens: 96, temperature: 0.1, onProgress: (_) {})).done).text;
    };

/// The sorting, as the root wires it: given the workspaces, the preferences, the note store, the AI, and where to
/// say a meeting was filed.
class MeetingSorter {
  MeetingSorter({
    required this.workspaces,
    required this.preferences,
    required this.setPreferences,
    required this.getNote,
    required this.ask,
    this.titlesIn,
    this.filed,
    this.warn,
  });

  final WorkspaceStore workspaces;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;
  final Future<Note?> Function(String id) getNote;
  final MeetingSortAsk ask;

  /// A workspace's notes' titles, newest first, for the AI to tell it by.
  final List<String> Function(String workspaceId)? titlesIn;

  /// Told when a meeting was filed: its title and the folder's path (`Ghost.md › Meetings`).
  final void Function(String title, String where)? filed;

  final void Function(String message)? warn;

  final Set<String> _asking = <String>{};

  /// A meeting's note written up: sorted, if it is the sorting's to sort. [body] is the note as the summary left it;
  /// the note is read again, since an open note's editor lands the summary itself. Answers the workspace it was
  /// filed in, or null.
  Future<Workspace?> meetingSummarized(String noteId, String body) async {
    if (_asking.contains(noteId)) return null;
    if (!sortable(preferences(), noteId, workspaces.workspaceOf(noteId))) return null;
    _asking.add(noteId);
    try {
      Note? fresh;
      try {
        fresh = await getNote(noteId);
      } catch (_) {
        fresh = null;
      }
      final text = fresh != null && summarySection(fresh.body) != null ? fresh.body : (body.isNotEmpty ? body : fresh?.body ?? '');
      final candidates = sortCandidates(workspaces.value.list, titlesIn: titlesIn);
      if (candidates.isEmpty) return null;
      final title = noteTitle(text);
      final String? output;
      try {
        output = await ask(meetingSortPrompt, meetingSortMessage(title: title, attendees: attendeesOf(text), summary: summarySection(text)?.text ?? '', candidates: candidates));
      } catch (failure) {
        warn?.call('[ghost] the meeting was not sorted: $failure');
        return null;
      }
      if (output == null) return null;
      // Read again after the wait: the person may have filed it themselves, or turned the switch off, meanwhile.
      if (!sortable(preferences(), noteId, workspaces.workspaceOf(noteId))) return null;
      final chosenId = readMeetingSort(output, candidates);
      Workspace? chosen;
      for (final w in workspaces.value.list) {
        if (w.id == chosenId) chosen = w;
      }
      if (chosen == null) {
        setPreferences((now) => withSorted(now, noteId, null));
        return null;
      }
      final folder = workspaces.addWorkspace(meetingsFolderName, 'ink', chosen.id);
      if (folder == null) return null;
      workspaces.fileNote(noteId, folder.id);
      setPreferences((now) => withSorted(now, noteId, folder.id));
      filed?.call(title.isNotEmpty ? title : 'Untitled', workspacePathName(workspaces.value.list, folder.id));
      return folder;
    } finally {
      _asking.remove(noteId);
    }
  }
}
