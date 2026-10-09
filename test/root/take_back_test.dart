import 'dart:convert';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/take_back.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

const String diary = '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\n---\n# Diary\n\n';
const String entryTitle = '2026-09-28 14.05';
const String entryWords = '# Monday 28 September\n\n**14:05** ';
const String entryHead = '---\ntitle: "$entryTitle"\ndate: 2026-09-28T14:05\n---\n';

Note note(String id, String body, {bool starred = false, int? archivedAt, int? recordingMs}) =>
    Note(id: id, body: body, createdAt: 1, updatedAt: 1, source: NoteSource.editor, starred: starred, archivedAt: archivedAt, recordingMs: recordingMs);

/// A store that does not answer.
class _Deaf extends SampleLibrary {
  _Deaf(super.notes);
  bool deaf = true;

  @override
  Future<Note?> get(String id) => deaf ? Future<Note?>.error(StateError('the store did not answer')) : super.get(id);
}

/// A store that will not list its notes.
class _Unlisted extends SampleLibrary {
  _Unlisted(super.notes);

  @override
  Future<void> refresh() => Future<void>.error(StateError('the store did not answer'));
}

/// An entry nobody has written in, and a new note given a name or a template, taken back once left
/// (lib/root/take_back.dart): `App.tsx`'s `takeBack`, held condition by condition, and through the app put together.
/// A take-back deletes with no Trash and no toast, so most of what is here is what must NOT be deleted.
void main() {
  group('the take-back alone', () {
    late SampleLibrary library;
    late MemoryTrash trash;
    late UntouchedNotes untouched;
    late Set<String> staying;
    late List<String> dropped;
    late List<String> tags;
    final now = DateTime(2026, 9, 28, 15).millisecondsSinceEpoch;

    TakeBack over(SampleLibrary notes) {
      library = notes;
      return TakeBack(
        library: notes,
        trash: trash,
        untouched: untouched,
        stays: staying.contains,
        writeJournal: JournalPages(notes).writeJournal,
        dropTab: dropped.add,
        forgetTag: tags.add,
      );
    }

    void entryRecord(String id, {String words = entryWords, int? at}) =>
        untouched.remember(id, UntouchedRecord(journalId: 'diary', title: entryTitle, words: words, at: at ?? now));
    void noteRecord(String id, String words, {String title = ''}) => untouched.remember(id, UntouchedRecord(title: title, words: words, at: now));
    String diaryBody() => library.noteOf('diary')!.body;

    setUp(() {
      trash = MemoryTrash();
      untouched = UntouchedNotes(kept: MemoryStored(), clock: () => now);
      staying = {};
      dropped = [];
      tags = [];
    });

    group('takes back', () {
      test('an entry left as it was made: the note, its line, its tab, its waiting place and its record', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        await back.look();
        expect(library.noteOf('left'), isNull);
        expect(diaryBody(), diary);
        expect(dropped, ['left']);
        expect(tags, ['left']);
        expect(untouched.records(), isEmpty);
        expect(trash.value, isEmpty, reason: 'not the Trash: nothing of the person\'s was lost');
      });

      test('a new note given a template and left, a look written into its front matter being no word', () async {
        final back = over(SampleLibrary([note('left', '---\nlook: reading\n---\n# \n\n- [ ] ')]));
        noteRecord('left', '# \n\n- [ ] ');
        await back.look();
        expect(library.noteOf('left'), isNull);
        expect(untouched.records(), isEmpty);
        expect(dropped, ['left']);
      });

      test('the line of an entry whose note is already gone, and nothing else', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('other', '# Other')]));
        entryRecord('gone', words: 'x');
        await back.look();
        expect(diaryBody(), diary);
        expect(untouched.records(), isEmpty);
        expect(library.value.map((each) => each.id), ['diary', 'other']);
        expect(dropped, isEmpty);
      });

      test('the entry and not its line when another note is named by it, whose line it is too', () async {
        final back = over(SampleLibrary([
          note('diary', '$diary- [[$entryTitle]]\n'),
          note('kept', '$entryHead${entryWords}Written in.'),
          note('left', '$entryHead$entryWords'),
        ]));
        entryRecord('left');
        await back.look();
        expect(library.noteOf('left'), isNull);
        expect(library.noteOf('kept'), isNotNull);
        expect(diaryBody(), '$diary- [[$entryTitle]]\n');
        expect(untouched.records(), isEmpty);
      });

      test('the entry and not its line when the store will not list its notes: the lesser harm', () async {
        final back = over(_Unlisted([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        await back.look();
        expect(library.noteOf('left'), isNull);
        expect(diaryBody(), '$diary- [[$entryTitle]]\n');
      });
    });

    group('does not delete', () {
      /// One entry, as it was made, with its line and its record; then [arrange], a look, and the note still there.
      Future<TakeBack> kept(Note left, {void Function()? arrange, bool record = true}) async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), left]));
        if (record) entryRecord(left.id);
        arrange?.call();
        await back.look();
        expect(library.noteOf(left.id), isNotNull, reason: 'the note is still there');
        expect(dropped, isEmpty);
        expect(tags, isEmpty);
        return back;
      }

      test('a note that stays: on screen, a capture aimed at it, or its tab open behind another note', () async {
        await kept(note('left', '$entryHead$entryWords'), arrange: () => staying.add('left'));
        expect(untouched.recordOf('left'), isNotNull, reason: 'still untouched: its record waits for it to be left');
        expect(diaryBody(), contains(entryTitle));
      });

      test('a note come back to while the store was being read', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        final looked = back.look();
        staying.add('left');
        await looked;
        expect(library.noteOf('left'), isNotNull);
        expect(untouched.recordOf('left'), isNotNull);
      });

      test('an entry still being made', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        back.making.add('left');
        await back.look();
        expect(library.noteOf('left'), isNotNull);
        expect(untouched.recordOf('left'), isNotNull);
        // Its note not in the store yet: neither its line nor its record goes.
        entryRecord('coming');
        back.making.add('coming');
        await back.look();
        expect(untouched.recordOf('coming'), isNotNull);
        expect(diaryBody(), contains(entryTitle));
      });

      test('an entry that began being made while the store was being read', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        final looked = back.look();
        back.making.add('left');
        await looked;
        expect(library.noteOf('left'), isNotNull);
      });

      test('a note with no record', () async {
        await kept(note('left', '$entryHead$entryWords'), record: false);
        expect(diaryBody(), contains(entryTitle));
      });

      test('a note written in: it is the person\'s, and its record goes', () async {
        await kept(note('left', '$entryHead${entryWords}A word.'));
        expect(untouched.records(), isEmpty);
        expect(diaryBody(), contains(entryTitle));
      });

      test('a note whose words were taken away: no longer the words it was given', () async {
        await kept(note('left', entryHead));
        expect(untouched.records(), isEmpty);
      });

      test('a pinned note', () async {
        await kept(note('left', '$entryHead$entryWords', starred: true));
        expect(untouched.records(), isEmpty);
      });

      test('an archived note', () async {
        await kept(note('left', '$entryHead$entryWords', archivedAt: 5));
        expect(untouched.records(), isEmpty);
      });

      test('a note with a recording', () async {
        await kept(note('left', '$entryHead$entryWords', recordingMs: 4000));
        expect(untouched.records(), isEmpty);
      });

      test('a note in the Trash: left there with its line, for Undo to bring both back', () async {
        await kept(note('left', '$entryHead$entryWords'), arrange: () => trash.trashNote('left'));
        expect(untouched.records(), isEmpty);
        expect(diaryBody(), contains(entryTitle));
        expect(trash.isTrashed('left'), isTrue);
      });

      test('a new note whose words its screen has not saved yet: the next look decides', () async {
        final back = over(SampleLibrary([note('early', '')]));
        noteRecord('early', '# 2026-09-28\n\n', title: '2026-09-28');
        await back.look();
        expect(library.noteOf('early'), isNotNull);
        expect(untouched.recordOf('early'), isNotNull);
        // The save lands, and the next look finds the words it was given.
        await library.save('early', '# 2026-09-28\n\n');
        await back.look();
        expect(library.noteOf('early'), isNull);
        expect(untouched.records(), isEmpty);
      });

      test('a new note named and then written in', () async {
        final back = over(SampleLibrary([note('kept', '# 2026-09-28\n\nA word.')]));
        noteRecord('kept', '# 2026-09-28\n\n', title: '2026-09-28');
        await back.look();
        expect(library.noteOf('kept'), isNotNull);
        expect(untouched.records(), isEmpty);
      });

      test('an emptied new note in the Trash', () async {
        final back = over(SampleLibrary([note('binned', '')]));
        noteRecord('binned', '# \n\n- [ ] ');
        trash.trashNote('binned');
        await back.look();
        expect(library.noteOf('binned'), isNotNull);
        expect(untouched.records(), isEmpty);
      });

      test('anything while the store does not answer, and the record waits', () async {
        final deaf = _Deaf([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]);
        final back = over(deaf);
        entryRecord('left');
        await back.look();
        expect(library.noteOf('left'), isNotNull);
        expect(untouched.recordOf('left'), isNotNull);
        expect(diaryBody(), contains(entryTitle));
        deaf.deaf = false;
        await back.look();
        expect(library.noteOf('left'), isNull);
      });

      test('a note whose record is older than a week, or of another build\'s shape', () async {
        final kept = MemoryStored({
          'glyph-entry-drafts': jsonEncode({
            'old': {'journalId': 'diary', 'title': entryTitle, 'words': entryWords, 'at': now - 8 * 24 * 60 * 60000},
            'odd': {'journalId': 'diary', 'title': entryTitle, 'words': 7, 'at': now},
          }),
        });
        untouched = UntouchedNotes(kept: kept, clock: () => now);
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('old', '$entryHead$entryWords'), note('odd', '$entryHead$entryWords')]));
        await back.look();
        expect(library.noteOf('old'), isNotNull);
        expect(library.noteOf('odd'), isNotNull);
        expect(diaryBody(), contains(entryTitle));
      });

      test('any other note: only the note the record names goes', () async {
        final back = over(SampleLibrary([
          note('diary', '$diary- [[$entryTitle]]\n- [[Another day]]\n'),
          note('left', '$entryHead$entryWords'),
          note('same', entryWords),
          note('day', '---\ntitle: "Another day"\n---\n$entryWords'),
          note('empty', ''),
        ]));
        entryRecord('left');
        await back.look();
        expect(library.value.map((each) => each.id), ['diary', 'same', 'day', 'empty']);
        expect(diaryBody(), '$diary- [[Another day]]\n');
      });

      test('twice: a second look while the first is still reading takes nothing more', () async {
        final back = over(SampleLibrary([note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')]));
        entryRecord('left');
        await Future.wait([back.look(), back.look()]);
        expect(dropped, ['left']);
        expect(diaryBody(), diary);
      });
    });
  });

  group('in the app', () {
    setUpAll(() async {
      await loadAppFonts();
      queriesWatchMidnight = false;
    });

    late UntouchedNotes untouched;
    late MemoryStored kept;

    Future<SampleLibrary> open(WidgetTester tester, List<Note> notes, {Map<String, Object?>? records}) async {
      final library = SampleLibrary(notes);
      kept = MemoryStored({if (records != null) 'glyph-entry-drafts': jsonEncode(records)});
      untouched = UntouchedNotes(kept: kept);
      await pumpApp(
        tester,
        prefs: const Preferences(theme: 'light'),
        home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), stored: kept, untouched: untouched),
      );
      await tester.pump(const Duration(milliseconds: 100));
      return library;
    }

    Future<void> settle(WidgetTester tester, [int beats = 6]) async {
      for (var i = 0; i < beats; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

    Future<void> close(WidgetTester tester) async {
      shellOf(tester).backToList();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    /// The journal opened and an entry made from its view; answers the entry.
    Future<Note> newEntry(WidgetTester tester, SampleLibrary library) async {
      shellOf(tester).openNote('diary');
      await settle(tester);
      await tester.runAsync(() async {
        tester.widget<JournalView>(find.byType(JournalView)).onNewEntry!('# {{date}}\n\n**{{time}}** ');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);
      final id = shellOf(tester).shown!;
      expect(id, isNot('diary'));
      return library.noteOf(id)!;
    }

    testWidgets('takes back at launch an entry the phone let go of, with its line', (tester) async {
      final library = await open(
        tester,
        [note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords')],
        records: {
          'left': {'journalId': 'diary', 'title': entryTitle, 'words': entryWords, 'at': DateTime.now().millisecondsSinceEpoch},
        },
      );
      await settle(tester);
      expect(library.noteOf('left'), isNull);
      expect(library.noteOf('diary')!.body, diary);
      expect(untouched.records(), isEmpty);
      await close(tester);
    });

    testWidgets('keeps an untouched entry while it is on screen and while its tab is open behind another note, and takes it back once the tab is closed', (tester) async {
      final library = await open(tester, [note('diary', diary), note('walk', '# Walk')]);
      shellOf(tester).openNote('walk');
      await settle(tester);
      shellOf(tester).backToList();
      await settle(tester);
      final entry = await newEntry(tester, library);
      final title = noteTitle(entry.body);
      expect(shellOf(tester).tabs.open, ['walk', entry.id], reason: 'the entry took the journal\'s tab');
      expect(library.noteOf(entry.id), isNotNull, reason: 'on screen');
      expect(library.noteOf('diary')!.body, contains(title));
      // Behind another note, its tab still open.
      shellOf(tester).openNote('walk');
      await settle(tester);
      expect(library.noteOf(entry.id), isNotNull);
      expect(untouched.recordOf(entry.id), isNotNull);
      // Closed from the tab row while Walk stays on screen: nothing on screen changes but the tabs.
      shellOf(tester).closeTab(entry.id);
      await settle(tester);
      expect(shellOf(tester).shown, 'walk');
      expect(library.noteOf(entry.id), isNull);
      expect(library.noteOf('diary')!.body, diary);
      expect(untouched.records(), isEmpty);
      await close(tester);
    });

    testWidgets('takes an untouched entry back when the person goes home, and keeps one written in', (tester) async {
      final library = await open(tester, [note('diary', diary)]);
      final left = await newEntry(tester, library);
      shellOf(tester).backToList();
      await settle(tester);
      expect(library.noteOf(left.id), isNull);
      expect(library.noteOf('diary')!.body, diary);
      expect(shellOf(tester).tabs.open, isNot(contains(left.id)));
      // Written in, it is the person's: it stays with its line, and its record goes.
      final written = await newEntry(tester, library);
      await tester.runAsync(() => library.save(written.id, '${written.body}A word.'));
      shellOf(tester).backToList();
      await settle(tester);
      expect(library.noteOf(written.id), isNotNull);
      expect(library.noteOf('diary')!.body, contains(noteTitle(written.body)));
      expect(untouched.records(), isEmpty);
      await close(tester);
    });

    testWidgets('gives the journal back the tab an untouched entry took, on Back, and takes the entry back', (tester) async {
      final library = await open(tester, [note('diary', diary)]);
      final entry = await newEntry(tester, library);
      expect(shellOf(tester).tabs.open, [entry.id]);
      shellOf(tester).goBack();
      await settle(tester);
      expect(shellOf(tester).shown, 'diary');
      expect(shellOf(tester).tabs.open, ['diary']);
      expect(library.noteOf(entry.id), isNull);
      expect(library.noteOf('diary')!.body, diary);
      await close(tester);
    });

    testWidgets('leaves an entry moved to the Trash there with its line', (tester) async {
      final library = await open(
        tester,
        [note('diary', '$diary- [[$entryTitle]]\n'), note('left', '$entryHead$entryWords'), note('walk', '# Walk')],
      );
      // Open, so the launch look leaves it; then binned from its tab and left.
      shellOf(tester).openNote('left');
      await settle(tester);
      untouched.remember('left', UntouchedRecord(journalId: 'diary', title: entryTitle, words: entryWords, at: DateTime.now().millisecondsSinceEpoch));
      tester.widget<AppShell>(find.byType(AppShell)).onDeleteNote!('left');
      shellOf(tester).dropTab('left');
      await settle(tester);
      expect(untouched.records(), isEmpty);
      expect(library.noteOf('diary')!.body, contains(entryTitle));
      // The Undo toast's hold is over within the test's close.
      await close(tester);
    });

    testWidgets('takes back a new note given a name and left without a word, and keeps one written in', (tester) async {
      final library = await open(tester, [note('a', '# Apples')]);
      Future<String> made() async {
        tester.widget<AppShell>(find.byType(AppShell)).onNew!();
        await settle(tester, 2);
        await tester.tap(find.byKey(const ValueKey('new-note')));
        await settle(tester);
        return shellOf(tester).shown!;
      }

      // As the note's screen writes a name: its record first, then its words.
      final left = await made();
      untouched.remember(left, UntouchedRecord(title: '2026-09-28', words: '# 2026-09-28\n\n', at: DateTime.now().millisecondsSinceEpoch));
      await tester.runAsync(() => library.save(left, '# 2026-09-28\n\n'));
      shellOf(tester).backToList();
      await settle(tester);
      expect(library.noteOf(left), isNull);
      expect(untouched.recordOf(left), isNull);
      expect(shellOf(tester).tabs.open, isNot(contains(left)));

      final kept = await made();
      untouched.remember(kept, UntouchedRecord(title: '2026-09-28', words: '# 2026-09-28\n\n', at: DateTime.now().millisecondsSinceEpoch));
      await tester.runAsync(() => library.save(kept, '# 2026-09-28\n\nA word.'));
      shellOf(tester).backToList();
      await settle(tester);
      expect(library.noteOf(kept), isNotNull);
      expect(untouched.recordOf(kept), isNull);
      expect(library.noteOf('a'), isNotNull);
      await close(tester);
    });
  });
}
