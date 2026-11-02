// Cleanup's plan (lib/plugins/cleanup/plan.dart; docs/CLEANUP.md, "Validation"): the AI's JSON read past its thinking
// and fences, every ref mapped back and checked, what is wrong dropped with its reason and never a failed run, and the
// batches joined (one merge per note, at most three new folders, a merged-away note left alone otherwise).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';

import 'support.dart';

void main() {
  late CleanupWorld world;
  late CleanupScope scope;
  late CleanupBatch batch;
  late String prompt;
  late Map<String, String> n;
  late Map<String, String> f;

  const all = CleanupOptions(passes: {...CleanupPass.values});

  setUp(() {
    world = CleanupWorld();
    scope = world.scope('work');
    batch = cleanupBatches(scope, CleanupSizes.cloud).single;
    prompt = cleanupBatchPrompt(batch, CleanupSizes.cloud);
    n = noteRefs(prompt);
    f = folderRefs(prompt);
  });

  BatchPlan read(Map<String, Object?> answer, [CleanupOptions options = all]) => readBatch(answerJson(answer), batch, options);

  group('the scope and the prompt', () {
    test('the folder and every folder under it, its notes out of the Trash and the Archive, and the titles linked to', () {
      expect([for (final folder in scope.folders) folder.path], ['Work', 'Work › Clients']);
      expect([for (final note in scope.notes) note.id], unorderedEquals(['kiln-call', 'invoice', 'standup', 'standup-copy', 'messy', 'idea', 'packing', 'brief']));
      expect(scope.org, isNull);
      expect(scope.linkedTitles, contains('packing list'));
      world.trash.trashNote('idea');
      expect(world.scope('work').notes.map((n) => n.id), isNot(contains('idea')));
      expect(world.scope(world.plansId).org, 'o1');
      expect(world.scope('org-o1').notes.map((n) => n.id), unorderedEquals(['team-plan', 'team-standup']));
    });

    test('the prompt names notes and folders by ref, never by id, with their first characters', () {
      expect(f, {'Work': 'f0', 'Work › Clients': 'f1'});
      expect(n.keys, containsAll(['Untitled', 'Standup', 'Standup (shared)', 'Kiln brief']));
      expect(prompt, isNot(contains('kiln-call')));
      expect(prompt, contains('Call with the Kiln shop about the spring menu prices'));
      // Copies of one note meet side by side.
      final standup = int.parse(n['Standup']!.substring(1)), copy = int.parse(n['Standup (shared)']!.substring(1));
      expect((standup - copy).abs(), 1);
    });

    test('only the passes that are on are asked about, and the shape is JSON', () {
      final system = cleanupSystem(const CleanupOptions(passes: {CleanupPass.titles}));
      expect(system, contains('"titles"'));
      expect(system, isNot(contains('"moves"')));
      expect(system, isNot(contains('"stale"')));
      expect(cleanupSystem(all), allOf(contains('"moves"'), contains('"duplicates"'), contains('"tidy"'), contains('"tags"'), contains('"stale"')));
      expect(cleanupSystem(const CleanupOptions()), contains('directly inside f0'));
      expect(cleanupSystem(const CleanupOptions(deeper: true)), contains('inside f0 or one of its folders'));
    });

    test('notes are peeked at their first characters, cut at a word, front matter left out', () {
      expect(notePeek('---\ntitle: X\n---\n# X\n\nHello there friend', 10), '# X\n\nHello…');
      expect(notePeek('short', 600), 'short');
    });

    test('a big folder goes 40 notes an ask to a cloud model and 12 to the device’s', () {
      final many = CleanupScope(
        rootId: 'work',
        org: null,
        folders: scope.folders,
        notes: [for (var i = 0; i < 100; i += 1) CleanupNote(id: 'n$i', title: 'Note $i', body: 'Words $i', revision: 1, folderId: 'work', updatedAt: 0)],
      );
      expect(cleanupBatches(many, CleanupSizes.cloud).map((b) => b.notes.length), [40, 40, 20]);
      expect(cleanupBatches(many, CleanupSizes.device).map((b) => b.notes.length), [12, 12, 12, 12, 12, 12, 12, 12, 4]);
    });
  });

  group('reading an answer', () {
    test('JSON is found past thinking, a fence and words round it; none is a batch that gave nothing, not a failure', () {
      expect(jsonObjectIn('<think>{"no": 1}</think>Here:\n```json\n{"titles": []}\n```'), {'titles': <Object?>[]});
      expect(jsonObjectIn('a { broken then {"ok": "a } in a string"}'), {'ok': 'a } in a string'});
      final none = readBatch('I could not do it.', batch, all);
      expect(none.failed, 'the answer had no JSON in it');
      expect(none.items, isEmpty);
    });

    test('moves into existing folders and a new one, by ref; outside the folder, unknown refs and moves to where it is are dropped', () {
      final plan = read({
        'folders': [
          {'ref': 'new1', 'name': 'Meetings', 'parent': 'f0', 'why': 'Standups'},
          {'ref': 'new2', 'name': 'Clients', 'parent': 'f0'}, // there already: that one
          {'ref': 'new3', 'name': 'Deep', 'parent': 'f1'}, // more than one level down
          {'ref': 'new4', 'name': 'a/b'},
        ],
        'moves': [
          {'note': n['Standup'], 'to': 'new1', 'why': 'A standup'},
          {'note': n['Untitled'], 'to': 'new2'},
          {'note': n['October invoices'], 'to': 'f9'},
          {'note': 'n99', 'to': 'f0'},
          {'note': n['Kiln brief'], 'to': 'f1'}, // there already
          {'note': n['Idea'], 'to': 'f0'}, // there already
        ],
      });
      final folder = plan.items.whereType<NewFolderItem>().single;
      expect((folder.name, folder.parentId, folder.id), ('Meetings', 'work', 'folder:work/meetings'));
      final moves = {for (final m in plan.items.whereType<MoveItem>()) m.noteId: m.to};
      expect(moves, {'standup': 'folder:work/meetings', 'kiln-call': 'clients'});
      expect(plan.dropped, hasLength(4));
      expect(plan.dropped.join(' | '), allOf(contains('more than one level') .or(contains('directly inside Work')), contains('“a/b”'), contains('outside Work'), contains('isn’t in this folder')));
    });

    test('with Deeper folders a new folder may go inside one of its folders', () {
      final plan = read({
        'folders': [
          {'ref': 'new1', 'name': 'Kiln', 'parent': 'f1'},
        ],
        'moves': [
          {'note': n['Kiln brief'], 'to': 'new1'},
        ],
      }, const CleanupOptions(passes: {CleanupPass.sort}, deeper: true));
      expect(plan.items.whereType<NewFolderItem>().single.parentId, 'clients');
      expect(plan.items.whereType<MoveItem>().single.to, 'folder:clients/kiln');
    });

    test('titles: a heading’s hashes off; empty, too long, unchanged or of a note linked by its title are dropped', () {
      final plan = read({
        'titles': [
          {'note': n['Untitled'], 'title': '# Kiln spring menu call', 'why': 'Untitled'},
          {'note': n['Packing list'], 'title': 'Packing'},
          {'note': n['Idea'], 'title': ''},
          {'note': n['Standup'], 'title': 'Standup'},
          {'note': n['October invoices'], 'title': 'x' * 130},
        ],
      });
      final titles = plan.items.whereType<TitleItem>().toList();
      expect([for (final t in titles) (t.noteId, t.from, t.to)], [('kiln-call', 'Untitled', 'Kiln spring menu call')]);
      expect(plan.dropped.join(' | '), allOf(contains('other notes link to'), contains('empty'), contains('too long')));
    });

    test('duplicates: a keeper and others, never itself, never a note in two merges', () {
      final plan = read({
        'duplicates': [
          {'keep': n['Standup'], 'others': [n['Standup (shared)'], n['Standup'], 'n99'], 'why': 'The same standup'},
          {'keep': n['Idea'], 'others': [n['Standup (shared)']]},
          {'keep': n['Plan'], 'others': <Object?>[]},
        ],
      });
      final merge = plan.items.whereType<MergeItem>().single;
      expect(merge.keepId, 'standup');
      expect(merge.others, ['standup-copy']);
      expect(plan.dropped, hasLength(2));
    });

    test('tidy is a list of notes to ask about whole; tags are tag-shaped and links name notes of the batch', () {
      final plan = read({
        'tidy': [
          {'note': n['Plan'], 'why': 'A stray #'},
          {'note': n['Plan']},
        ],
        'tags': [
          {'note': n['October invoices'], 'tags': ['#admin', 'money matters', 'billing/2026', 'ok']},
        ],
        'links': [
          {'note': n['Untitled'], 'to': [n['Kiln brief'], n['Untitled'], 'n99']},
        ],
      });
      expect([for (final t in plan.tidy) (t.noteId, t.why)], [('messy', 'A stray #')]);
      final edits = {for (final e in plan.items.whereType<EditItem>()) e.noteId: e};
      expect(edits['invoice']!.tags, ['admin', 'billing/2026', 'ok']);
      expect(edits['invoice']!.after, startsWith('---\ntags: [admin, billing/2026, ok]\n---\n# October invoices'));
      expect(edits['kiln-call']!.links, ['Kiln brief']);
      expect(edits['kiln-call']!.after, endsWith('Related: [[Kiln brief]]\n'));
    });

    test('a pass that is off is not read, and stale is the Archive', () {
      final answer = {
        'titles': [
          {'note': n['Untitled'], 'title': 'Kiln call'},
        ],
        'stale': [
          {'note': n['Idea'], 'why': 'Empty since July'},
        ],
      };
      final only = read(answer, const CleanupOptions(passes: {CleanupPass.stale}));
      expect(only.items.map((i) => i.id), ['stale:idea']);
      expect(read(answer).items.map((i) => i.id), ['title:kiln-call', 'stale:idea']);
    });

    test('Tidy’s answer keeps every word, or is dropped; Rewrite for clarity lets the words change within reason', () {
      final messy = scope.note('messy')!;
      final tidied = readTidy('```markdown\n# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.\n```', messy, all);
      expect(tidied.item!.after, '# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.');
      expect(tidied.item!.pass, CleanupPass.tidy);
      final changed = readTidy('{"body": "# Plan\\n\\n- one\\n- two\\n\\nAll fine."}', messy, all);
      expect(changed.item, isNull);
      expect(changed.dropped, contains('changed the words'));
      final rewritten = readTidy('# Plan\n\n- one\n- two\n\nEverything is fine now.', messy, const CleanupOptions(rewrite: true));
      expect(rewritten.item, isNotNull);
      expect(readTidy(messy.body, messy, all).item, isNull);
    });
  });

  group('the batches joined', () {
    test('the app’s own duplicates first, a merged-away note left alone, new folders once each and at most three', () {
      final one = read({
        'folders': [
          for (final name in ['A', 'B', 'C', 'D']) {'ref': 'new$name', 'name': name, 'parent': 'f0'},
        ],
        'moves': [
          {'note': n['Untitled'], 'to': 'newA'},
          {'note': n['October invoices'], 'to': 'newB'},
          {'note': n['Plan'], 'to': 'newC'},
          {'note': n['Idea'], 'to': 'newD'},
          {'note': n['Standup (shared)'], 'to': 'newA'},
        ],
        'titles': [
          {'note': n['Standup (shared)'], 'title': 'Standup copy'},
        ],
        'duplicates': [
          {'keep': n['Standup (shared)'], 'others': [n['Standup']]},
        ],
      });
      final found = duplicateGroups([for (final note in scope.notes) (id: note.id, title: note.title, body: note.body, updatedAt: note.updatedAt)]);
      expect(found, [
        ['standup', 'standup-copy'],
      ]);
      final plan = CleanupPlan.join(scope: scope, options: all, batches: [one], found: found);
      expect([for (final item in plan.items.whereType<NewFolderItem>()) item.name], ['A', 'B', 'C']);
      final merge = plan.items.whereType<MergeItem>().single;
      expect(merge.keepId, 'standup');
      expect(merge.others, ['standup-copy']);
      expect(merge.found, isTrue);
      // The AI's merge the other way round is no second merge.
      expect(plan.dropped, contains('a merge of a note already in another'));
      expect(plan.byId('move:idea'), isNull);
      expect(plan.dropped, contains('a move into a folder that won’t be made'));
      // The copy merged away is neither moved nor retitled.
      expect(plan.byId('move:standup-copy'), isNull);
      expect(plan.byId('title:standup-copy'), isNull);
      expect(plan.byId('move:kiln-call'), isNotNull);
      // The review's order: the passes in theirs, a pass's new folders first.
      expect(plan.items.first, isA<NewFolderItem>());
    });

    test('everything starts ticked, but on a big plan the edits and merges wait for the person', () {
      final small = CleanupPlan(scope: scope, options: all, items: [
        const MoveItem(noteId: 'idea', from: 'work', to: 'clients'),
        const EditItem(noteId: 'messy', pass: CleanupPass.tidy, before: 'a', after: 'b'),
      ]);
      expect(small.startTicked, {'move:idea', 'tidy:messy'});
      final big = CleanupPlan(scope: scope, options: all, items: [
        for (var i = 0; i < 30; i += 1) MoveItem(noteId: 'n$i', from: 'work', to: 'clients'),
        const EditItem(noteId: 'messy', pass: CleanupPass.tidy, before: 'a', after: 'b'),
        const MergeItem(keepId: 'standup', others: ['standup-copy']),
      ]);
      expect(big.startTicked, hasLength(30));
      expect(big.startTicked, isNot(contains('tidy:messy')));
    });
  });

  group('the options', () {
    test('kept as JSON and read back; anything else is the default', () {
      const options = CleanupOptions(passes: {CleanupPass.sort, CleanupPass.stale}, deeper: true);
      final back = CleanupOptions.fromJson(options.toJson());
      expect(back.passes, {CleanupPass.sort, CleanupPass.stale});
      expect((back.deeper, back.rewrite), (true, false));
      expect(CleanupOptions.fromJson('nonsense').passes, const CleanupOptions().passes);
      expect(const CleanupOptions().passes, {for (final p in CleanupPass.values) if (p.onByDefault) p});
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
