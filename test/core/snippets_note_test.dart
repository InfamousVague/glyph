import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/snippets_note.dart';

import '../library/support.dart';

/// Snippets as a note (lib/core/snippets_note.dart): the ```snippets fence read and written, the source over the
/// note and the preferences, and the one-time move of the old list into a note.
void main() {
  const sig = Snippet(id: 'sig', trigger: ';sig', text: 'Matt\nmatt@example.com');
  const addr = Snippet(id: 'addr', trigger: ';addr', text: '1 Main St\n\nTown');

  group('the fence', () {
    test('writes each trigger on its line and its words indented under it, and reads them back', () {
      final fence = snippetsFence([sig, addr, ...defaultSnippets]);
      expect(fence, '```snippets\n;sig\n  Matt\n  matt@example.com\n;addr\n  1 Main St\n\n  Town\n;date\n  {date}\n;time\n  {time}\n```');
      expect(snippetsFromBody('# Snippets\n\n$fence\n'), [sig, addr, ...defaultSnippets]);
      expect(snippetsFromBody('# Plain\n\nno fence\n'), isNull);
      expect(snippetsFromBody('# Snippets\n\n```snippets\n```\n'), isEmpty, reason: 'emptied on purpose');
    });

    test('passes over a line that is neither a trigger nor indented words, and a trigger twice keeps the first', () {
      expect(snippetsFromBody('```snippets\nnot a trigger\n;Sig\n  one\n;sig\n  two\n;empty\n;ok\n  fine\n```'), [const Snippet(id: 'sig', trigger: ';Sig', text: 'one'), const Snippet(id: 'ok', trigger: ';ok', text: 'fine')]);
    });

    test('is replaced in place in a note that has one, and put at the end of one that has not', () {
      final note = '# Snippets\n\nwords above\n\n```snippets\n;old\n  gone\n```\n\nwords below\n';
      expect(withSnippetsFence(note, [sig]), '# Snippets\n\nwords above\n\n```snippets\n;sig\n  Matt\n  matt@example.com\n```\n\nwords below\n');
      expect(withSnippetsFence('# Snippets\n', [sig]), '# Snippets\n\n```snippets\n;sig\n  Matt\n  matt@example.com\n```\n');
      expect(isSnippetsNote(snippetsNoteBody([sig])), isTrue);
      expect(isSnippetsNote('# Snippets\n\nno fence\n'), isFalse);
    });
  });

  group('the source', () {
    test('reads the preferences until there is a note, moves the person’s own list into one once, then reads the note', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      await library.load();
      final prefs = PreferencesStore()..startWithoutStorage();
      final source = SnippetsSource(library: library, prefs: prefs);
      expect(source.value, defaultSnippets);
      await source.migrate();
      expect(library.value, isEmpty, reason: 'the two built in make no note');

      prefs.update((now) => now.copyWith(snippets: const [sig, ...defaultSnippets]));
      expect(source.value, [sig, ...defaultSnippets]);
      await source.migrate();
      final note = library.value.single;
      expect(isSnippetsNote(note.body), isTrue);
      expect(prefs.value.more[snippetsNoteKey], note.id);
      expect(core.files, ['Inbox/Snippets.md']);

      // The note is the truth from here: edited by hand, the list follows; set, both the note and the preferences do.
      var told = 0;
      source.addListener(() => told += 1);
      final whole = (await library.get(note.id))!;
      await library.update(note.id, withSnippetsFence(whole.body, [addr]), whole.revision);
      expect(source.value, [addr]);
      expect(told, 1);
      await source.set([addr, sig]);
      expect(snippetsFromBody((await library.get(note.id))!.body), [addr, sig]);
      expect(prefs.value.snippets, [addr, sig], reason: 'the builds before the note read this');
      source.dispose();
    });

    test('finds a Snippets note written by hand, with no id remembered', () async {
      final (core: _, :library, waits: _, said: _) = libraryOver();
      await library.createNote('# Snippets\n\n```snippets\n;hi\n  Hello there\n```\n');
      final source = SnippetsSource(library: library, prefs: PreferencesStore()..startWithoutStorage());
      expect(source.value, [const Snippet(id: 'hi', trigger: ';hi', text: 'Hello there')]);
      source.dispose();
    });
  });
}
