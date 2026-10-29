// What the AI providers' tests share (docs/AI_PROVIDERS.md, "Tests"): a library of a map for the run's tools, and a
// desk with no screen, so a note a tool writes is written behind it, as the run does where nothing can be shown.
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/editor/editor.dart' show EditorViewLike;

class MemoryNotes implements ClaudeNotes {
  final Map<String, String> bodies = {};
  int _made = 0;

  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async => [for (final id in bodies.keys) NoteBrief(id: id, title: noteTitle(bodies[id]!))];

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async => [
        for (final id in bodies.keys)
          if (bodies[id]!.contains(query)) NoteHit(id: id, title: noteTitle(bodies[id]!), snippet: query),
      ];

  @override
  Future<NoteRead?> read({String? id, String? title}) async {
    final found = id ?? bodies.keys.where((key) => noteTitle(bodies[key]!) == title).firstOrNull;
    if (found == null || !bodies.containsKey(found)) return null;
    return NoteRead(id: found, title: noteTitle(bodies[found]!), body: bodies[found]!);
  }

  @override
  Future<String> create(String body) async {
    final id = 'n${++_made}';
    bodies[id] = body;
    return id;
  }

  @override
  Future<void> write(String id, String body) async => bodies[id] = body;
}

class BlindDesk implements ClaudeDesk {
  BlindDesk(this.notes);
  final MemoryNotes notes;
  final List<String> opened = [];

  @override
  Future<EditorViewLike?> open(String noteId) async {
    opened.add(noteId);
    return null;
  }

  @override
  bool showing(String noteId, EditorViewLike view) => false;

  @override
  Future<void> change(String noteId, String Function(String body) change) async => notes.bodies[noteId] = change(notes.bodies[noteId] ?? '');

  @override
  bool get smoke => false;
}
