// Wrapped's presses (lib/plugins/wrapped/actions.dart; docs/WRAPPED.md, "The review"): a to-do checked off and removed
// through the note's own write over the revision read, a stale note archived and put in the Trash, a move (a filed note
// by Cleanup's apply, an unfiled one by the drag's move), a new folder, a merge and a link applied; each kept and taken
// back whole by Undo; Keep, Later and Dismiss remembered; and nothing changed by a pass, nor by reading every list.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/metrics.dart' show wrappedActionKinds;
import 'package:ghost_md/plugins/wrapped/wrapped.dart';

import 'support.dart';

void main() {
  late WrappedWorld world;
  late WrappedService service;
  setUp(() async {
    world = WrappedWorld();
    useActivity(Activity());
    service = world.service(ais: [fakeAi()]);
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
  });

  String body(String id) => world.library.noteOf(id)!.body;
  String? filed(String id) => world.workspaces.workspaceOf(id)?.id;

  test('nothing changes without a press: a whole pass and every list read leave the notes as they were', () async {
    final fresh = WrappedWorld();
    final before = {for (final n in fresh.library.value) n.id: (n.body, n.revision, n.archivedAt)};
    final quiet = fresh.service(ais: [fakeAi()]);
    quiet.store.set(quiet.state.copyWith(wanted: true));
    await quiet.resume();
    expect(quiet.todos, isNotEmpty);
    expect(quiet.stale, isNotEmpty);
    expect(quiet.suggestions, isNotEmpty);
    quiet.stats();
    quiet.forgotten;
    expect({for (final n in fresh.library.value) n.id: (n.body, n.revision, n.archivedAt)}, before);
    expect(fresh.trash.value, isEmpty);
    expect(fresh.workspaces.value.list.map((w) => w.name), isNot(contains('Garden')));
  });

  test('the to-dos, oldest note first, the organization’s left out', () {
    final rows = service.todos;
    expect([for (final r in rows) r.todo.words], ['Book the ferry', 'Boots', 'Rain coat', 'Send the draft menu']);
    expect(rows.first.title, 'Coast trip');
    expect(rows.any((r) => r.todo.words == 'Hire a designer'), isFalse);
  });

  test('checked off through the note’s write, and Undo puts the box back', () async {
    final ferry = service.todos.first.todo;
    final revision = world.library.noteOf('trip')!.revision;
    final done = await service.checkOff([ferry]);
    expect(done.done, 1);
    expect(body('trip'), contains('- [x] Book the ferry'));
    expect(world.library.noteOf('trip')!.revision, revision + 1, reason: 'a write over the revision read, an edit like any other');
    expect(service.todos.any((r) => r.todo.words == 'Book the ferry'), isFalse);
    expect(service.state.records.first.changes.single.before, contains('- [ ] Book the ferry'));
    expect(await service.undo(done.record!.id), 'Undone.');
    expect(body('trip'), contains('- [ ] Book the ferry'));
    expect(service.state.records.first.undone, isTrue);
  });

  test('two of one note removed in one write; Undo brings both back', () async {
    final packing = [for (final r in service.todos) if (r.todo.noteId == 'packing') r.todo];
    final revision = world.library.noteOf('packing')!.revision;
    final done = await service.removeTodos(packing);
    expect(done.done, 2);
    expect(body('packing'), '# Packing list\n\n- [x] Map');
    expect(world.library.noteOf('packing')!.revision, revision + 1, reason: 'one write for the note');
    await service.undo(done.record!.id);
    expect(body('packing'), '# Packing list\n\n- [ ] Boots\n- [ ] Rain coat\n- [x] Map');
  });

  test('a note changed since is not written over by Undo', () async {
    final done = await service.checkOff([service.todos.first.todo]);
    final trip = world.library.noteOf('trip')!;
    await world.library.update('trip', '${trip.body}\nMore.', trip.revision);
    final said = await service.undo(done.record!.id);
    expect(said, contains('changed since'));
    expect(body('trip'), endsWith('More.'));
  });

  test('Keep: never listed again while its words stay', () {
    final boots = service.todos.firstWhere((r) => r.todo.words == 'Boots').todo;
    service.keepTodos([boots]);
    expect(service.todos.any((r) => r.todo.words == 'Boots'), isFalse);
    expect(body('packing'), contains('- [ ] Boots'), reason: 'kept as it is');
  });

  test('a stale note archived, and back with Undo; to the Trash, and back', () async {
    expect([for (final s in service.stale) s.note.id], ['draft']);
    final archived = await service.archive(['draft']);
    expect(world.library.noteOf('draft')!.archivedAt, isNotNull);
    expect(service.stale, isEmpty);
    await service.undo(archived.record!.id);
    expect(world.library.noteOf('draft')!.archivedAt, isNull);
    final trashed = await service.putInTrash(['draft']);
    expect(world.trash.isTrashed('draft'), isTrue);
    expect(world.library.noteOf('draft'), isNotNull, reason: 'never deleted');
    await service.undo(trashed.record!.id);
    expect(world.trash.isTrashed('draft'), isFalse);
  });

  test('Later puts a stale note off for a month, and it is read again next time', () {
    service.later(['draft']);
    expect(service.stale, isEmpty);
    expect(service.state.reads.containsKey('draft'), isFalse);
  });

  test('a move of an unfiled note into Work, by the drag’s own move, and back to no folder', () async {
    final move = service.suggestions.firstWhere((s) => s.kind == SuggestionKind.move);
    expect(filed('meeting'), isNull);
    final done = await service.apply(move);
    expect(done.done, 1);
    expect(filed('meeting'), 'work');
    expect(service.suggestions.any((s) => s.id == move.id), isFalse, reason: 'done: not offered again');
    await service.undo(done.record!.id);
    expect(filed('meeting'), isNull);
  });

  test('a filed note moved by Cleanup’s apply, checked where it lands, and back', () async {
    final s = const WrappedSuggestion(kind: SuggestionKind.move, notes: ['menu'], folderId: 'travel', why: 'test');
    final done = await service.apply(s);
    expect(filed('menu'), 'travel');
    expect(done.skipped, isEmpty);
    await service.undo(done.record!.id);
    expect(filed('menu'), 'work');
  });

  test('a new folder at the top for the walk, then Undo takes the note out and the folder away', () async {
    final s = service.suggestions.firstWhere((s) => s.kind == SuggestionKind.newFolder);
    final done = await service.apply(s);
    final garden = world.workspaces.value.list.firstWhere((w) => w.name == 'Garden');
    expect(garden.parent, isNull);
    expect(filed('voice'), garden.id);
    await service.undo(done.record!.id);
    expect(filed('voice'), isNull);
    expect(world.workspaces.value.list.any((w) => w.name == 'Garden'), isFalse);
  });

  test('a merge of the copy: its lines into the kept note, the copy to the Trash, both back with Undo', () async {
    final s = service.suggestions.firstWhere((s) => s.kind == SuggestionKind.merge);
    final done = await service.apply(s);
    expect(world.trash.isTrashed('standup-copy'), isTrue);
    expect(world.library.noteOf('standup-copy'), isNotNull);
    await service.undo(done.record!.id);
    expect(world.trash.isTrashed('standup-copy'), isFalse);
  });

  test('a link: a Related line on the first note, taken off by Undo', () async {
    final s = service.suggestions.firstWhere((s) => s.kind == SuggestionKind.link);
    final before = body('trip');
    final done = await service.apply(s);
    expect(body('trip'), endsWith('Related: [[Weekly sync]]\n'));
    await service.undo(done.record!.id);
    expect(body('trip'), before);
  });

  test('Dismiss is remembered in the Library’s file', () async {
    final s = service.suggestions.first;
    service.dismiss(s);
    expect(service.suggestions.any((x) => x.id == s.id), isFalse);
    await service.store.written;
    expect(WrappedState.decode(world.file.text).dismissed, contains('suggestion:${s.id}'));
  });

  test('every kind of press is one the analytics allow, and nothing else', () {
    expect({for (final kind in WrappedActionKind.values) kind.wire}, wrappedActionKinds);
  });
}
