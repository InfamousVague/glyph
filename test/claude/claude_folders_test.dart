// The app's own Claude over the folders (GHST-108; Matt, 2026-10-19: "Make it so the AI can manage folders and
// sorting of files into folders and organize all my organizations into neat logical folders"): each tool run through
// a scripted conversation against a real WorkspaceStore, a folder found by id, path or bare name, and the guard that
// keeps a note from being filed into or out of an organization, which would share or unshare it with the team.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/claude_folders.dart';
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart' show EditorViewLike;

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// One reply: a tool called with [input], or, without a tool, [words] said and the run's end.
List<SseEvent> _turn({String words = '', String? tool, Map<String, Object?> input = const {}}) => [
      _e('message_start', {'type': 'message_start'}),
      if (words.isNotEmpty) ...[
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': words},
        }),
        _e('content_block_stop', {'index': 0}),
      ],
      if (tool != null) ...[
        _e('content_block_start', {
          'index': 1,
          'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': tool, 'input': <String, Object?>{}},
        }),
        _e('content_block_delta', {
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': jsonEncode(input)},
        }),
        _e('content_block_stop', {'index': 1}),
      ],
      _e('message_delta', {
        'delta': {'stop_reason': tool == null ? 'end_turn' : 'tool_use'},
      }),
    ];

class _Api extends ClaudeApi {
  _Api(this.turns) : super(key: 'sk-ant-test');

  final List<List<SseEvent>> turns;
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    return ClaudeCall(Stream<SseEvent>.fromIterable(turns[asked.length - 1]), () {});
  }
}

class _Notes implements ClaudeNotes {
  _Notes(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async => [for (final id in bodies.keys) NoteBrief(id: id, title: noteTitle(bodies[id]!))];

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async => const [];

  @override
  Future<NoteRead?> read({String? id, String? title}) async {
    final body = bodies[id];
    return body == null ? null : NoteRead(id: id!, title: noteTitle(body), body: body);
  }

  @override
  Future<String> create(String body) async => throw UnimplementedError();

  @override
  Future<void> write(String id, String body) async => bodies[id] = body;
}

class _Desk implements ClaudeDesk {
  @override
  Future<EditorViewLike?> open(String noteId) async => null;

  @override
  bool showing(String noteId, EditorViewLike view) => false;

  @override
  Future<void> change(String noteId, String Function(String body) change) async {}

  @override
  bool get smoke => false;
}

/// A library of folders: Work › Clients and Home personal; the organization Ghost.md with its folder Design; notes
/// filed about them; and what the store told its files to do.
class _World {
  _World() {
    store = WorkspaceStore(
      storage: MemoryWorkspaceStorage(const WorkspaceSheet(
        list: [
          Workspace(id: 'w-work', name: 'Work'),
          Workspace(id: 'w-clients', name: 'Clients', parent: 'w-work'),
          Workspace(id: 'w-home', name: 'Home'),
          Workspace(id: 'org-o1', name: 'Ghost.md'),
          Workspace(id: 'w-design', name: 'Design', parent: 'org-o1'),
          Workspace(id: 'w-oclients', name: 'Clients', parent: 'org-o1'),
        ],
        notes: {'acme': 'w-clients', 'spec': 'w-design', 'team': 'org-o1'},
      )),
      onFiled: (ids, to) => moves.add((ids, to?.id)),
    );
  }

  late final WorkspaceStore store;
  final List<(List<String>, String?)> moves = [];
  final notes = _Notes({
    'acme': '# Acme\n',
    'spec': '# Spec\n',
    'team': '# Team plan\n',
    'loose': '# Loose ends\n',
    'groceries': '# Groceries\n',
  });

  /// One run of Claude calling [tool] with [input] and then ending; answers the tool's result as Claude got it.
  Future<({Map<String, Object?> result, ClaudeRun run, _Api api})> call(WidgetTester tester, String tool, Map<String, Object?> input) async {
    final api = _Api([_turn(tool: tool, input: input), _turn(words: 'Done.')]);
    final run = ClaudeRun(api: api, model: 'claude-sonnet-5-5', notes: notes, desk: _Desk(), folders: ClaudeFolders(store), prompt: 'Tidy my folders');
    await tester.runAsync(run.run);
    final turn = (api.asked[1]['messages']! as List).last as Map;
    final result = ((turn['content'] as List).single as Map).cast<String, Object?>();
    return (result: result, run: run, api: api);
  }

  Workspace byId(String id) => store.value.list.firstWhere((w) => w.id == id);
}

/// What the store last told the files to do: the notes and where to.
List<Object?> _last(_World world) => [world.moves.last.$1, world.moves.last.$2];

Map<String, Object?> _said(Map<String, Object?> result) => (jsonDecode(result['content']! as String) as Map).cast<String, Object?>();

void main() {
  group('Claude over the folders', () {
    testWidgets('offers the folder tools only where the run has the folders, and says so in its prompt', (tester) async {
      final world = _World();
      final made = await world.call(tester, ClaudeFolderTool.list, const {});
      final names = [for (final tool in made.api.asked.first['tools']! as List) (tool as Map)['name']];
      expect(names, containsAll(ClaudeFolderTool.all));
      final bare = _Api([_turn(words: 'Done.')]);
      await tester.runAsync(ClaudeRun(api: bare, model: 'claude-sonnet-5-5', notes: world.notes, desk: _Desk(), prompt: 'x').run);
      expect([for (final tool in bare.asked.first['tools']! as List) (tool as Map)['name']], isNot(contains(ClaudeFolderTool.list)));
      expect(claudeSystem(now: DateTime(2026, 10, 19), folders: true), contains('file_notes'));
      expect(claudeSystem(now: DateTime(2026, 10, 19)), isNot(contains('file_notes')));
    });

    testWidgets('list_folders gives each folder its path, its organization and its counts', (tester) async {
      final world = _World();
      final done = await world.call(tester, ClaudeFolderTool.list, const {});
      final said = _said(done.result);
      expect(said['count'], 6);
      final folders = {for (final f in said['folders']! as List) (f as Map)['id']: f};
      expect(folders['w-clients'], {'id': 'w-clients', 'name': 'Clients', 'path': 'Work › Clients', 'parent': 'w-work', 'notes': 1, 'notes_under': 1});
      expect(folders['w-work'], {'id': 'w-work', 'name': 'Work', 'path': 'Work', 'notes': 0, 'notes_under': 1});
      expect(folders['org-o1'], {'id': 'org-o1', 'name': 'Ghost.md', 'path': 'Ghost.md', 'organization': 'Ghost.md', 'organization_root': true, 'notes': 1, 'notes_under': 2});
      expect(folders['w-design'], {'id': 'w-design', 'name': 'Design', 'path': 'Ghost.md › Design', 'parent': 'org-o1', 'organization': 'Ghost.md', 'notes': 1, 'notes_under': 1});
      expect(done.run.steps.map((s) => s.words), contains('Looked through the folders'));
    });

    test('a folder is found by id, by path with › or /, or by a name only one has', () {
      final folders = ClaudeFolders(_World().store);
      expect(folders.resolve('w-home').id, 'w-home');
      expect(folders.resolve('Work › Clients').id, 'w-clients');
      expect(folders.resolve('work/clients').id, 'w-clients');
      expect(folders.resolve(' Ghost.md /  Clients ').id, 'w-oclients');
      expect(folders.resolve('design').id, 'w-design');
      expect(
        () => folders.resolve('Clients'),
        throwsA(isA<ClaudeFolderProblem>().having((p) => p.message, 'message', allOf(contains('“Work › Clients” (w-clients)'), contains('“Ghost.md › Clients” (w-oclients)')))),
      );
      expect(() => folders.resolve('Garden'), throwsA(isA<ClaudeFolderProblem>().having((p) => p.message, 'message', contains('No folder “Garden”'))));
      expect(() => folders.resolve('Home › Clients'), throwsA(isA<ClaudeFolderProblem>()));
    });

    testWidgets('create_folder makes one inside its parent, and answers the same one when asked again', (tester) async {
      final world = _World();
      final first = _said((await world.call(tester, ClaudeFolderTool.create, {'name': 'Acme', 'parent': 'Work › Clients'})).result);
      expect(first['path'], 'Work › Clients › Acme');
      expect(first['made'], isTrue);
      final again = _said((await world.call(tester, ClaudeFolderTool.create, {'name': 'acme', 'parent': 'w-clients'})).result);
      expect((again['id'], again['made']), (first['id'], false));
      // Inside an organization, the team's.
      final team = _said((await world.call(tester, ClaudeFolderTool.create, {'name': 'Research', 'parent': 'Ghost.md'})).result);
      expect((team['path'], team['organization']), ('Ghost.md › Research', 'Ghost.md'));
      final top = _said((await world.call(tester, ClaudeFolderTool.create, {'name': 'Garden'})).result);
      expect((top['path'], top.containsKey('parent')), ('Garden', false));
      expect(world.store.value.list.where((w) => w.name.toLowerCase() == 'acme'), hasLength(1));
    });

    testWidgets('rename_folder renames a folder, its notes following, never an organization\'s own', (tester) async {
      final world = _World();
      final done = await world.call(tester, ClaudeFolderTool.rename, {'folder': 'Work › Clients', 'name': 'Customers'});
      expect(_said(done.result)['path'], 'Work › Customers');
      expect(world.byId('w-clients').name, 'Customers');
      expect(_last(world), [['acme'], 'w-clients']);
      final refused = await world.call(tester, ClaudeFolderTool.rename, {'folder': 'Ghost.md', 'name': 'Ghosts'});
      expect(refused.result['is_error'], isTrue);
      expect(refused.result['content'], contains('organization’s own workspace'));
      expect(world.byId('org-o1').name, 'Ghost.md');
      final clash = await world.call(tester, ClaudeFolderTool.rename, {'folder': 'Home', 'name': 'work'});
      expect(clash.result['is_error'], isTrue);
      expect(world.byId('w-home').name, 'Home');
    });

    testWidgets('move_folder moves within its side of an organization\'s edge, never across it nor into itself', (tester) async {
      final world = _World();
      final moved = await world.call(tester, ClaudeFolderTool.move, {'folder': 'Work › Clients', 'parent': 'Home'});
      expect(_said(moved.result)['path'], 'Home › Clients');
      expect(world.byId('w-clients').parent, 'w-home');
      expect(_last(world), [['acme'], 'w-clients']);
      final top = await world.call(tester, ClaudeFolderTool.move, {'folder': 'w-clients'});
      expect(_said(top.result)['path'], 'Clients');
      // Within the organization.
      final inside = await world.call(tester, ClaudeFolderTool.move, {'folder': 'Design', 'parent': 'Ghost.md › Clients'});
      expect(_said(inside.result)['path'], 'Ghost.md › Clients › Design');

      Future<String> refused(Map<String, Object?> input) async {
        final done = await world.call(tester, ClaudeFolderTool.move, input);
        expect(done.result['is_error'], isTrue, reason: '$input');
        return done.result['content']! as String;
      }

      expect(await refused({'folder': 'Home', 'parent': 'Ghost.md'}), contains('share its notes with the team'));
      expect(await refused({'folder': 'Design'}), contains('take its notes from the team'));
      expect(await refused({'folder': 'Design', 'parent': 'Work'}), contains('take its notes from the team'));
      expect(await refused({'folder': 'Work', 'parent': 'Work'}), contains('cannot go inside itself'));
      expect(await refused({'folder': 'Ghost.md', 'parent': 'Work'}), contains('always at the top'));
      expect(world.byId('w-design').parent, 'w-oclients');
      expect(world.byId('w-home').parent, isNull);
    });

    testWidgets('delete_folder keeps every note: a personal folder\'s unfiled, an organization\'s handed up', (tester) async {
      final world = _World();
      final personal = _said((await world.call(tester, ClaudeFolderTool.delete, {'folder': 'Work'})).result);
      expect(personal['folders_moved_up'], ['Clients']);
      expect(world.byId('w-clients').parent, isNull);
      expect(world.store.workspaceOf('acme')?.id, 'w-clients');
      final clients = _said((await world.call(tester, ClaudeFolderTool.delete, {'folder': 'w-clients'})).result);
      expect((clients['notes_moved'], clients['notes_now_in']), (1, null));
      expect(world.store.workspaceOf('acme'), isNull);
      expect(_last(world), [['acme'], null]);
      // The organization's: its note goes to the organization's workspace, still the team's.
      final team = _said((await world.call(tester, ClaudeFolderTool.delete, {'folder': 'Design'})).result);
      expect((team['notes_moved'], team['notes_now_in']), (1, 'Ghost.md'));
      expect(world.store.workspaceOf('spec')?.id, 'org-o1');
      expect(world.notes.bodies, hasLength(5));
      final own = await world.call(tester, ClaudeFolderTool.delete, {'folder': 'Ghost.md'});
      expect(own.result['is_error'], isTrue);
      expect(world.store.value.list.any((w) => w.id == 'org-o1'), isTrue);
    });

    testWidgets('file_notes files notes in a folder and out of every one, their files following', (tester) async {
      final world = _World();
      final done = await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['loose', 'groceries', 'acme', 'nope'],
        'folder': 'Home',
      });
      final said = _said(done.result);
      expect(said['folder'], 'Home');
      expect([for (final n in said['filed']! as List) (n as Map)['id']], ['loose', 'groceries', 'acme']);
      expect(said['missing'], ['nope']);
      expect(world.store.workspaceOf('loose')?.id, 'w-home');
      expect(world.store.workspaceOf('acme')?.id, 'w-home');
      expect(_last(world), [['loose', 'groceries', 'acme'], 'w-home']);
      expect(done.run.steps.map((s) => s.words), contains('Filed 3 notes in Home'));
      final out = _said((await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['groceries'],
        'unfile': true,
      })).result);
      expect(out['filed'], [
        {'id': 'groceries', 'title': 'Groceries', 'was': 'Home'},
      ]);
      expect(world.store.workspaceOf('groceries'), isNull);
      // Within an organization: freely.
      _said((await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['team'],
        'folder': 'Ghost.md › Design',
      })).result);
      expect(world.store.workspaceOf('team')?.id, 'w-design');
      final both = await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['loose'],
        'folder': 'Home',
        'unfile': true,
      });
      expect(both.result['is_error'], isTrue);
    });

    testWidgets('file_notes never files a note into or out of an organization: it is left where it is', (tester) async {
      final world = _World();
      final into = await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['loose', 'acme'],
        'folder': 'Ghost.md › Design',
      });
      final said = _said(into.result);
      expect(said['filed'], isEmpty);
      expect([for (final n in said['refused']! as List) (n as Map)['id']], ['loose', 'acme']);
      expect(((said['refused']! as List).first as Map)['why'], contains('share it with the team'));
      expect(((said['refused']! as List).first as Map)['why'], contains('Workspace picker'));
      expect(world.store.workspaceOf('loose'), isNull);
      expect(world.store.workspaceOf('acme')?.id, 'w-clients');
      expect(into.run.steps.map((s) => s.words), contains(startsWith('Left 2 notes where they were')));

      final out = _said((await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['spec', 'team'],
        'unfile': true,
      })).result);
      expect([for (final n in out['refused']! as List) (n as Map)['why']], everyElement(contains('take it from the team')));
      final across = _said((await world.call(tester, ClaudeFolderTool.file, {
        'ids': ['spec', 'loose'],
        'folder': 'Home',
      })).result);
      expect([for (final n in across['filed']! as List) (n as Map)['id']], ['loose']);
      expect([for (final n in across['refused']! as List) (n as Map)['id']], ['spec']);
      expect(world.store.workspaceOf('spec')?.id, 'w-design');
      expect(world.store.workspaceOf('team')?.id, 'org-o1');
      expect(world.moves.where((m) => m.$1.contains('spec') || m.$1.contains('team')), isEmpty);
    });
  });
}
