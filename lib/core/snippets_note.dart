/// The person's snippets as a note (docs/MARKDOWN_FIRST.md decision 19, 2026-10-31): a note titled Snippets holding a
/// ```snippets fence, which syncs between devices as any note does and is in the Library folder for git. Before this
/// the list was the `snippets` preference alone (lib/core/preferences.dart `Preferences.snippets`): synced, but not
/// in the folder, so a restored library came back with `;date` and `;time` and none of the person's own.
///
/// The fence, one snippet after another: its trigger on a line of its own, its words on the lines after, each
/// indented two spaces (a blank line inside the words is kept as an empty line). Readable as it is in any editor,
/// and typed by hand if a person likes:
///
///     ```snippets
///     ;sig
///       Matt
///       matt@example.com
///     ;date
///       {date}
///     ```
///
/// A snippet's id is its trigger without the semicolon, in lower case (`sig`): the fence names no ids, and the two
/// built in are `date` and `time` already. The preference is written too, from the note, for the builds before this,
/// and read where there is no note ([SnippetsSource]). The old list moves into the note once: the first time the
/// source is opened with snippets of the person's own in the preferences and no note, the note is made from them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'note.dart';
import 'note_text.dart' show noteTitle;
import 'preferences.dart';
import 'snippets.dart' show snippetTriggerRule;
import 'title_key.dart' show titleKey;

/// The note's title, and the fence's name.
const String snippetsNoteTitle = 'Snippets';
const String snippetsFenceName = 'snippets';

/// The preference key remembering which note it is, by id, so a renamed note is still the one.
const String snippetsNoteKey = 'snippetsNote';

final RegExp _fenceOpen = RegExp(r'^```[ \t]*snippets[ \t]*$', multiLine: true);
final RegExp _fenceClose = RegExp(r'^```[ \t]*$', multiLine: true);

/// Where the fence is in [body]: from its opening line to the end of its closing line, or null for none.
({int start, int end, int inner, int innerEnd})? _fenceIn(String body) {
  final open = _fenceOpen.firstMatch(body);
  if (open == null) return null;
  final inner = open.end + 1;
  final close = _fenceClose.firstMatch(body.substring(inner < body.length ? inner : body.length));
  if (close == null) return null;
  final innerEnd = inner + close.start;
  final end = inner + close.end;
  return (start: open.start, end: end < body.length && body[end] == '\n' ? end + 1 : end, inner: inner, innerEnd: innerEnd);
}

/// A snippet's id from its trigger: `;Sig` is `sig`.
String snippetIdOf(String trigger) => trigger.substring(1).toLowerCase();

/// The snippets a body's ```snippets fence holds, or null where the body has no fence. A fence with nothing in it is
/// an empty list: the person emptied it. A line that is neither a trigger nor indented words is passed over.
List<Snippet>? snippetsFromBody(String body) {
  final fence = _fenceIn(body);
  if (fence == null) return null;
  final out = <Snippet>[];
  final seen = <String>{};
  String? trigger;
  var words = <String>[];
  void close() {
    if (trigger != null && words.isNotEmpty && seen.add(snippetIdOf(trigger!))) {
      // The words end where the last written line ends: trailing blank lines are the fence's air.
      while (words.isNotEmpty && words.last.isEmpty) {
        words.removeLast();
      }
      if (words.isNotEmpty) out.add(Snippet(id: snippetIdOf(trigger!), trigger: trigger!, text: words.join('\n')));
    }
    trigger = null;
    words = [];
  }

  for (final line in body.substring(fence.inner, fence.innerEnd).split('\n')) {
    if (line.startsWith('  ')) {
      if (trigger != null) words.add(line.substring(2));
    } else if (line.trim().isEmpty) {
      if (trigger != null) words.add('');
    } else if (snippetTriggerRule.hasMatch(line.trim())) {
      close();
      trigger = line.trim();
    }
  }
  close();
  return List.unmodifiable(out);
}

/// The fence for [snippets], as the header draws it.
String snippetsFence(List<Snippet> snippets) => [
      '```$snippetsFenceName',
      for (final each in snippets) ...[each.trigger, for (final line in each.text.split('\n')) line.isEmpty ? '' : '  $line'],
      '```',
    ].join('\n');

/// [body] with its fence holding [snippets]: replaced where it is, else put at the end.
String withSnippetsFence(String body, List<Snippet> snippets) {
  final fence = _fenceIn(body);
  final text = '${snippetsFence(snippets)}\n';
  if (fence == null) {
    final before = body.trimRight();
    return before.isEmpty ? text : '$before\n\n$text';
  }
  return '${body.substring(0, fence.start)}$text${body.substring(fence.end)}';
}

/// A new Snippets note's words: the title, one line on what it is, the fence.
String snippetsNoteBody(List<Snippet> snippets) =>
    '# $snippetsNoteTitle\n\nYour text expansions: type a trigger like `;sig`, then a space, and it becomes its words. Each trigger is a line of its own, its words indented under it; `{date}`, `{time}`, `{datetime}` and `{cursor}` are filled as it is written. Settings › Snippets edits this note.\n\n${snippetsFence(snippets)}\n';

/// Whether [body] is a Snippets note: titled so, with the fence.
bool isSnippetsNote(String body) => titleKey(noteTitle(body)) == titleKey(snippetsNoteTitle) && _fenceIn(body) != null;

/// The snippets, read from the Snippets note where there is one and from the preferences where there is not, and
/// written to both. Listen to it: its value is the same list until it changes, here, in the note or on another
/// device.
class SnippetsSource extends ChangeNotifier implements ValueListenable<List<Snippet>> {
  SnippetsSource({required this.library, PreferencesStore? prefs, void Function(String message)? log})
      : _prefs = prefs ?? preferences,
        _log = log ?? debugPrint {
    _value = _read();
    library.addListener(_heard);
    _prefs.addListener(_heard);
  }

  final NoteLibrary library;
  final PreferencesStore _prefs;
  final void Function(String message) _log;
  late List<Snippet> _value;

  @override
  List<Snippet> get value => _value;

  /// The Snippets note as the list holds it: the one remembered by id, else the one titled so with a fence.
  Note? noteNow() {
    final id = _prefs.value.more[snippetsNoteKey];
    if (id is String) {
      final kept = library.noteOf(id);
      if (kept != null && snippetsFromBody(kept.body) != null) return kept;
    }
    for (final note in library.value) {
      if (isSnippetsNote(note.body)) return note;
    }
    return null;
  }

  List<Snippet> _read() {
    final note = noteNow();
    final said = note == null ? null : snippetsFromBody(note.body);
    return said ?? _prefs.value.snippets;
  }

  void _heard() {
    final next = _read();
    if (listEquals(next, _value)) return;
    _value = next;
    notifyListeners();
  }

  /// Moves the preferences' list into a note once, where the person has snippets of their own and no note yet.
  /// Asked as the library is opened; nothing happens for the two built in alone, so a fresh library gets no note it
  /// did not ask for.
  Future<void> migrate() async {
    if (noteNow() != null || listEquals(_prefs.value.snippets, defaultSnippets)) return;
    await set(_prefs.value.snippets);
  }

  /// Keeps [next] as the snippets: in the Snippets note, made where there is none, and in the preferences for the
  /// builds before the note.
  Future<void> set(List<Snippet> next) async {
    final list = List<Snippet>.unmodifiable(next);
    _value = list;
    _prefs.update((now) => now.copyWith(snippets: list));
    notifyListeners();
    try {
      final note = noteNow();
      if (note == null) {
        final made = await library.createNote(snippetsNoteBody(list));
        _prefs.update((now) => now.copyWith(more: {...now.more, snippetsNoteKey: made.id}));
        return;
      }
      final whole = await library.get(note.id) ?? note;
      final body = withSnippetsFence(whole.body, list);
      if (body != whole.body) await library.update(whole.id, body, whole.revision);
      if (_prefs.value.more[snippetsNoteKey] != whole.id) _prefs.update((now) => now.copyWith(more: {...now.more, snippetsNoteKey: whole.id}));
    } catch (failure) {
      _log('[glyph] the Snippets note was not written: $failure');
    }
  }

  @override
  void dispose() {
    library.removeListener(_heard);
    _prefs.removeListener(_heard);
    super.dispose();
  }
}

/// The app's source, once the root has made one; null in a test that draws Settings alone, where the pane reads the
/// preferences as before (the pattern of lib/notes/daily_notes.dart `dailyNotesLibrary`).
SnippetsSource? snippetsSource;
