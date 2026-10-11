
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/place.dart' show placingFor;
import 'package:ghost_md/capture/take_writer.dart';
import 'package:ghost_md/core/library.dart' as core show newNoteId;
import 'package:ghost_md/core/note.dart';

/// The recorder's writes (lib/capture/take_writer.dart), against a note store that keeps the rules of the web's own
/// browser half (`core/store.ts`): a new id or an error, a write over exactly the revision read, and a command's
/// change applied only to the body and the revision it was made from. So what is checked is what a note reads
/// afterwards. Case for case with the web's `capture/takeWriter.test.ts`. Each rule here is one a bug taught: drafts
/// that raced each other, a Discard that left the words behind, and the words written twice under a command's
/// change.

/// The web's browser store, in memory.
class Store implements TakeStore {
  final List<Note> notes = [];

  /// What happens to a note between `writeInto`'s read of it and its guarded write: someone typing, a sync, a
  /// delete.
  final List<Future<Object?> Function()> meanwhile = [];

  int _clock = 1;

  @override
  String newNoteId() => core.newNoteId();

  Future<List<Note>> listNotes() async => [...notes]..sort((a, b) => b.updatedAt - a.updatedAt);

  Note? _find(String id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<Note?> getNote(String id) async => _find(id);

  @override
  Future<Note> createNote(String id, String body, [NoteSource source = NoteSource.editor]) async {
    if (_find(id) != null) throw Exception('the note id already exists');
    final now = _clock++;
    final note = Note(id: id, body: body, createdAt: now, updatedAt: now, source: source);
    notes.insert(0, note);
    return note;
  }

  @override
  Future<Note> updateNote(String id, String body, int expectedRevision) async {
    final existing = _find(id);
    if (existing == null || existing.revision != expectedRevision) throw Exception('the note was deleted or changed');
    final note = existing.copyWith(body: body, updatedAt: _clock++, revision: expectedRevision + 1);
    notes[notes.indexOf(existing)] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id) async => notes.removeWhere((note) => note.id == id);

  Future<Note?> setNoteRecording(String id, int? recordingMs, List<Segment> segments) async {
    final note = _find(id);
    if (note == null) return null;
    final next = Note(
      id: note.id,
      body: note.body,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      source: note.source,
      starred: note.starred,
      recordingMs: recordingMs,
      segments: segments,
      revision: note.revision,
    );
    notes[notes.indexOf(note)] = next;
    return next;
  }

  @override
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request) async {
    if (meanwhile.isNotEmpty) await meanwhile.removeAt(0)();
    final current = _find(request.noteId);
    final matches = request.beforeRevision == null
        ? current == null && request.beforeBody == null
        : current?.revision == request.beforeRevision && current?.body == request.beforeBody;
    if (!matches) return CommandMutationResultConflict(current: current);
    final now = _clock++;
    final note = current != null
        ? current.copyWith(body: request.afterBody, updatedAt: now, revision: current.revision + 1)
        : Note(id: request.noteId, body: request.afterBody, createdAt: now, updatedAt: now, source: request.source);
    notes
      ..removeWhere((candidate) => candidate.id == note.id)
      ..insert(0, note);
    return CommandMutationResultApplied(mutationId: request.mutationId, note: note);
  }
}

void main() {
  var store = Store();

  ({TakeWriter writer, List<Note?> shown}) writerFor(String Function() words, [List<NamedNote> candidates = const []]) {
    final shown = <Note?>[];
    final writer = TakeWriter(
      TakeWriterHost(
        markdown: (_) => words(),
        hasWords: () => words() != '',
        candidates: () => candidates,
        targetChanged: shown.add,
      ),
      store: store,
    );
    return (writer: writer, shown: shown);
  }

  setUp(() => store = Store());

  group('a recording added to a note', () {
    test('writes its words once under the note’s own text, however many drafts race', () async {
      final trip = await store.createNote('trip', '# Trip\n\nBook the cabin.');
      final (:writer, shown: _) = writerFor(() => 'Ask Sam about the dog.');
      writer.aim(trip);
      await Future.wait([writer.flushDraft(), writer.flushDraft()]);
      expect((await store.getNote('trip'))?.body, '# Trip\n\nBook the cabin.\n\nAsk Sam about the dog.');
    });

    test('gives the note its own text back on Discard', () async {
      final trip = await store.createNote('trip', '# Trip\n\nBook the cabin.');
      final (:writer, shown: _) = writerFor(() => 'Ask Sam.');
      writer.aim(trip);
      await writer.flushDraft();
      await writer.undoDraft();
      expect((await store.getNote('trip'))?.body, '# Trip\n\nBook the cabin.');
      expect(writer.savedDraft, false);
    });

    test('puts a command’s change into the text under the words, and the words stay written once', () async {
      final shop = await store.createNote('shop', '# Shopping\n\n- Eggs');
      var words = 'Pick up the parcel.';
      final (:writer, :shown) = writerFor(() => words);
      writer.aim(shop);
      await writer.flushDraft();
      final changed = await writer.updateNote('shop', (body) => '$body\n- Milk');
      expect(changed, '# Shopping\n\n- Eggs\n- Milk');
      expect((await store.getNote('shop'))?.body, '# Shopping\n\n- Eggs\n- Milk\n\nPick up the parcel.');
      // The page is shown the change as it lands, above the words.
      expect(shown.last?.body, '# Shopping\n\n- Eggs\n- Milk');
      words = 'Pick up the parcel. And bin bags.';
      await writer.flushDraft();
      expect((await store.getNote('shop'))?.body, '# Shopping\n\n- Eggs\n- Milk\n\nPick up the parcel. And bin bags.');
    });

    test('says nothing changed when the change changes nothing', () async {
      final shop = await store.createNote('shop', '# Shopping');
      final (:writer, shown: _) = writerFor(() => 'Words.');
      writer.aim(shop);
      expect(await writer.updateNote('shop', (body) => body), isNull);
      expect(await writer.updateNote('gone', (_) => 'anything'), isNull);
      expect((await store.getNote('shop'))?.body, '# Shopping');
    });
  });

  group('a new recording', () {
    test('drafts into a note of its own id, and Discard takes it away', () async {
      final (:writer, shown: _) = writerFor(() => '# Grocery run');
      await writer.flushDraft();
      expect((await store.getNote(writer.noteId))?.body, '# Grocery run');
      await writer.undoDraft();
      expect(await store.getNote(writer.noteId), isNull);
    });

    test('writes nothing when nothing has been said', () async {
      final (:writer, shown: _) = writerFor(() => '');
      await writer.flushDraft();
      expect(await store.getNote(writer.noteId), isNull);
      expect(writer.savedDraft, false);
    });

    test('starts over under a fresh id when aimed at no note, and at the note’s own id when aimed at one', () async {
      final trip = await store.createNote('trip', '# Trip');
      final (:writer, :shown) = writerFor(() => 'Words.');
      final first = writer.noteId;
      writer.aim(trip);
      expect(writer.noteId, 'trip');
      writer.aim(null);
      expect(writer.noteId, isNot(first));
      expect(writer.noteId, isNot('trip'));
      expect(shown, [trip, null]);
    });
  });

  group('a recording that moves to another note', () {
    test('composes under the second note’s text, never the first’s, once it is aimed there', () async {
      final trip = await store.createNote('trip', '# Trip\n\nBook the cabin.');
      final work = await store.createNote('work', '# Work\n\n- Email Jo');
      final (:writer, shown: _) = writerFor(() => 'Call Sam.');
      writer.aim(trip);
      expect(await writer.compose('Call Sam.'), '# Trip\n\nBook the cabin.\n\nCall Sam.');
      writer.aim(work);
      expect(await writer.compose('Call Sam.'), '# Work\n\n- Email Jo\n\nCall Sam.');
      await writer.flushDraft();
      expect((await store.getNote('work'))?.body, '# Work\n\n- Email Jo\n\nCall Sam.');
      expect((await store.getNote('trip'))?.body, '# Trip\n\nBook the cabin.');
    });

    test('leaves what was said so far where it was said, beyond the reach of a later Discard', () async {
      final trip = await store.createNote('trip', '# Trip\n\nBook the cabin.');
      var words = 'For the dog.';
      final (:writer, shown: _) = writerFor(() => words);
      writer.aim(trip);
      await writer.flushDraft();
      expect(writer.savedDraft, true);
      writer.keepDraft();
      expect(writer.savedDraft, false);
      expect(writer.baseBody, isNull);
      words = 'Call Sam.';
      writer.aim(null);
      await writer.undoDraft();
      expect((await store.getNote('trip'))?.body, '# Trip\n\nBook the cabin.\n\nFor the dog.');
    });
  });

  group('commands on other notes', () {
    test('rewrite that note alone, and keep the command list’s copy of it current', () async {
      final trip = await store.createNote('trip', '# Trip');
      final work = await store.createNote('work', '# Work\n\n- Email Jo');
      final candidates = [NamedNote(id: 'work', title: 'Work', note: work)];
      final (:writer, shown: _) = writerFor(() => 'Words.', candidates);
      writer.aim(trip);
      await writer.updateNote('work', (body) => '$body\n- Call Sam');
      expect((await store.getNote('work'))?.body, '# Work\n\n- Email Jo\n- Call Sam');
      expect(candidates[0].note.body, '# Work\n\n- Email Jo\n- Call Sam');
      expect((await store.getNote('trip'))?.body, '# Trip');
    });
  });

  group('the chain', () {
    test('runs each write after the one before it, even one that failed', () async {
      final (:writer, shown: _) = writerFor(() => '');
      final order = <String>[];
      final failing = writer.queue<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add('first');
        throw Exception('the store said no');
      });
      final second = writer.queue(() async {
        order.add('second');
        return 'kept';
      });
      await expectLater(failing, throwsA(predicate((Object error) => '$error'.contains('the store said no'))));
      expect(await second, 'kept');
      await writer.settled();
      expect(order, ['first', 'second']);
    });
  });

  group('words written into a note a command named, once, at Done', () {
    const house = '# House TODOs\n\n- [ ] Fix the gutter\n';
    Future<Object?> Function() edit(String body) => () async {
          final now = await store.getNote('house');
          return store.updateNote('house', body, now!.revision);
        };

    test('goes onto the note as it is when written, and reads it again when it changed between the read and the write', () async {
      await store.createNote('house', house);
      store.meanwhile.add(edit('$house- [ ] Clear the drains\n'));
      final (:writer, shown: _) = writerFor(() => '');
      final written = await writer.writeInto('house', 'Call Sam.', placingFor(house), () => '# Call Sam');
      expect(written.own, false);
      expect(written.blocks, ['- [ ] Call Sam']);
      expect(written.mutationId, isA<String>());
      expect((await store.getNote('house'))?.body, '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clear the drains\n- [ ] Call Sam\n');
    });

    test('makes the words a note of their own when it changed twice, leaving both changes as they were', () async {
      await store.createNote('house', house);
      store.meanwhile.addAll([edit('$house- [ ] One\n'), edit('$house- [ ] One\n- [ ] Two\n')]);
      final (:writer, shown: _) = writerFor(() => '');
      final written = await writer.writeInto('house', 'Call Sam.', placingFor(house), () => '# Call Sam');
      expect(written.own, true);
      expect(written.mutationId, isNull);
      expect(written.saved.body, '# Call Sam');
      expect((await store.getNote('house'))?.body, '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] One\n- [ ] Two\n');
    });

    test('makes the words a note of their own when the note was deleted meanwhile', () async {
      await store.createNote('house', house);
      store.meanwhile.add(() async {
        await store.deleteNote('house');
        return null;
      });
      final (:writer, shown: _) = writerFor(() => '');
      final written = await writer.writeInto('house', 'Call Sam.', placingFor(house), () => '# Call Sam');
      expect(written.own, true);
      expect((await store.listNotes()).map((note) => note.body), ['# Call Sam']);
    });

    test('reads a note switched to again in the background, and keeps it only while the take is still aimed there', () async {
      final full = await store.createNote('house', house);
      final other = await store.createNote('other', '# Other');
      // The candidate the note was found as: no tape, no phrases.
      final candidate = full;
      final (:writer, shown: _) = writerFor(() => '');
      await store.setNoteRecording(full.id, 4000, const [Segment(text: 'Fix the gutter.', startMs: 0, endMs: 900)]);
      writer.aim(candidate, placingFor(house), true);
      writer.refresh('house');
      await writer.refreshed();
      expect((writer.target?.id, writer.target?.recordingMs), ('house', 4000));

      writer.aim(candidate, placingFor(house), true);
      writer.refresh('house');
      writer.aim(other);
      await writer.refreshed();
      expect(writer.target?.id, 'other');
    });
  });
}
