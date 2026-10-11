import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';

/// A note to and from the core's JSON (lib/core/note_json.dart), over the shapes src-tauri/src/note.rs writes and
/// reads: its own tests' rows among them.
void main() {
  group('a note from the core', () {
    test('reads every field of a note fetched by id', () {
      final note = noteFromJson(jsonDecode(
        '{"id":"n1","body":"# Plan","createdAt":10,"updatedAt":20,"source":"capture","starred":true,"archivedAt":30,"recordingMs":900,'
        '"segments":[{"text":"hello","startMs":0,"endMs":400}],"formatted":"# Plan, tidied","formattedFor":77,"formattedModel":"qwen","path":"Inbox/Plan.md","revision":4}',
      ))!;
      expect(note.id, 'n1');
      expect(note.body, '# Plan');
      expect((note.createdAt, note.updatedAt), (10, 20));
      expect(note.source, NoteSource.capture);
      expect(note.sourceName, isNull);
      expect(note.starred, isTrue);
      expect(note.archivedAt, 30);
      expect(note.recordingMs, 900);
      expect(note.segments, [const Segment(text: 'hello', startMs: 0, endMs: 400)]);
      expect((note.formatted, note.formattedFor, note.formattedModel), ('# Plan, tidied', 77, 'qwen'));
      expect(note.path, 'Inbox/Plan.md');
      expect(note.revision, 4);
    });

    test('reads a note from the list, whose phrases and formatted version are null', () {
      final note = noteFromJson(jsonDecode(
        '{"id":"n1","body":"hi","createdAt":1,"updatedAt":2,"source":"editor","starred":false,"archivedAt":null,"recordingMs":null,'
        '"segments":null,"formatted":null,"formattedFor":null,"formattedModel":null,"path":"Inbox/hi.md","revision":1}',
      ))!;
      expect(note.segments, isNull);
      expect(note.formatted, isNull);
      expect(note.archivedAt, isNull);
      expect(note.source, NoteSource.editor);
    });

    test('reads a draft, which says nothing about a path, and a note from before revisions as revision 1', () {
      // note.rs `a_note_from_an_older_page_without_a_path_or_revision_still_reads`, and `Note::blank`.
      final note = noteFromJson(jsonDecode('{"id":"n1","body":"","createdAt":7,"updatedAt":7,"source":"capture","starred":false}'))!;
      expect(note.path, isNull);
      expect(note.revision, 1);
    });

    test('reads a note made in a browser without its pin as unpinned', () {
      // note.rs `a_note_made_in_a_browser_without_its_pin_reads_as_unpinned`.
      final note = noteFromJson(jsonDecode('{"id":"n1","body":"hi","createdAt":1,"updatedAt":2,"source":"editor","revision":1}'))!;
      expect(note.starred, isFalse);
      expect((note.archivedAt, note.recordingMs), (null, null));
    });

    test('keeps a source it does not know, and reads the note as typed', () {
      final note = noteFromJson({'id': 'n1', 'body': 'hi', 'createdAt': 1, 'updatedAt': 2, 'source': 'side-key'})!;
      expect(note.source, NoteSource.editor);
      expect(note.sourceName, 'side-key');
      expect(note.sourceWord, 'side-key');
      expect(noteToJson(note)['source'], 'side-key');
      // And it stays with the note through a change.
      expect(noteToJson(note.copyWith(body: 'more'))['source'], 'side-key');
    });

    test('reads what is not a note as none', () {
      expect(noteFromJson(null), isNull);
      expect(noteFromJson('a note'), isNull);
      expect(noteFromJson({'id': 'n1'}), isNull);
      expect(notesFromJson({'not': 'a list'}), isEmpty);
      expect(notesFromJson([null, {'id': 'a', 'body': 'words', 'createdAt': 1, 'updatedAt': 1, 'source': 'editor'}, 7]).map((n) => n.id), ['a']);
    });

    test('reads a time said with a fraction as a whole millisecond', () {
      final note = noteFromJson({'id': 'n1', 'body': 'hi', 'createdAt': 1.0, 'updatedAt': 2.9, 'source': 'editor'})!;
      expect((note.createdAt, note.updatedAt), (1, 2));
    });
  });

  group('a note to the core', () {
    test('says every field note.rs reads, the pin always and the path only when there is one', () {
      const note = Note(id: 'n1', body: '# Plan', createdAt: 10, updatedAt: 20);
      expect(noteToJson(note), {
        'id': 'n1',
        'body': '# Plan',
        'createdAt': 10,
        'updatedAt': 20,
        'source': 'editor',
        'starred': false,
        'archivedAt': null,
        'recordingMs': null,
        'segments': null,
        'formatted': null,
        'formattedFor': null,
        'formattedModel': null,
        'revision': 1,
      });
      expect(noteToJson(note.copyWith(path: () => 'Inbox/Plan.md'))['path'], 'Inbox/Plan.md');
    });

    test('comes back the note it was', () {
      const note = Note(
        id: 'n1',
        body: '# Plan',
        createdAt: 10,
        updatedAt: 20,
        source: NoteSource.capture,
        starred: true,
        archivedAt: 30,
        recordingMs: 900,
        segments: [Segment(text: 'hello', startMs: 0, endMs: 400)],
        formatted: 'tidied',
        formattedFor: 77,
        formattedModel: 'qwen',
        path: 'workspaces/Home/Plan.md',
        revision: 4,
      );
      final sent = jsonDecode(jsonEncode(noteToJson(note)));
      expect(noteToJson(noteFromJson(sent)!), noteToJson(note));
    });
  });
}
