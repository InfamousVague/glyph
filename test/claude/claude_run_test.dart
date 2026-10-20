// The app's own Claude (docs/CLAUDE_APP.md): a run against a scripted stream, its tools over a library of a map, and
// its writing played out in an editor as the tool's input streams.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart' show ClaudeSettings, defaultClaudeEffort;
import 'package:ghost_md/claude/claude_spend.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/claude/live_typing.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// One reply: [words] said, then a tool called with its input in [pieces], or no tool.
List<SseEvent> _turn({String words = '', String? tool, String id = 'toolu_1', List<String> pieces = const []}) => [
      _e('message_start', {'type': 'message_start'}),
      if (words.isNotEmpty) ...[
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        for (final part in [words.substring(0, words.length ~/ 2), words.substring(words.length ~/ 2)])
          _e('content_block_delta', {
            'index': 0,
            'delta': {'type': 'text_delta', 'text': part},
          }),
        _e('content_block_stop', {'index': 0}),
      ],
      if (tool != null) ...[
        _e('content_block_start', {
          'index': 1,
          'content_block': {'type': 'tool_use', 'id': id, 'name': tool, 'input': <String, Object?>{}},
        }),
        for (final piece in pieces)
          _e('content_block_delta', {
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': piece},
          }),
        _e('content_block_stop', {'index': 1}),
      ],
      _e('message_delta', {
        'delta': {'stop_reason': tool == null ? 'end_turn' : 'tool_use'},
      }),
      _e('message_stop', {'type': 'message_stop'}),
    ];

/// [json] in pieces of [size], as the API cuts a tool's input.
List<String> _cut(String json, int size) => [for (var i = 0; i < json.length; i += size) json.substring(i, i + size > json.length ? json.length : i + size)];

class _Api extends ClaudeApi {
  _Api(this.turns) : super(key: 'sk-ant-test');

  final List<List<SseEvent>> turns;
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    final events = turns[asked.length - 1];
    return ClaudeCall(Stream<SseEvent>.fromIterable(events), () {});
  }
}

class _Notes implements ClaudeNotes {
  final Map<String, String> bodies = {};
  _Desk? desk;
  int _made = 0;

  String _now(String id) => desk?.views[id]?.state.doc.toString() ?? bodies[id]!;

  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async => [for (final id in bodies.keys) NoteBrief(id: id, title: noteTitle(_now(id)))];

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async => [
        for (final id in bodies.keys)
          if (_now(id).contains(query)) NoteHit(id: id, title: noteTitle(_now(id)), snippet: query),
      ];

  @override
  Future<NoteRead?> read({String? id, String? title}) async {
    final found = id ?? bodies.keys.where((key) => noteTitle(_now(key)) == title).firstOrNull;
    if (found == null || !bodies.containsKey(found)) return null;
    return NoteRead(id: found, title: noteTitle(_now(found)), body: _now(found));
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

class _Desk implements ClaudeDesk {
  _Desk(this.notes, {this.screen = true}) {
    notes.desk = this;
  }

  final _Notes notes;

  /// Whether notes can be shown at all.
  final bool screen;
  final Map<String, EditorView> views = {};
  final List<String> opened = [];

  @override
  Future<EditorViewLike?> open(String noteId) async {
    opened.add(noteId);
    if (!screen) return null;
    return views[noteId] ??= EditorView(wholeDocument: true, state: EditorState.create(doc: notes.bodies[noteId] ?? '', extensions: claudeTyping));
  }

  @override
  bool showing(String noteId, EditorViewLike view) => identical(views[noteId], view);

  @override
  Future<void> change(String noteId, String Function(String body) change) async {
    final view = views[noteId];
    if (view != null) {
      final now = view.state.doc.toString();
      view.dispatch(TransactionSpec(changes: Change(from: 0, to: now.length, insert: change(now))));
    } else {
      notes.bodies[noteId] = change(notes.bodies[noteId] ?? '');
    }
  }

  @override
  bool get smoke => false;
}

void main() {
  group('a run of the app\'s own Claude', () {
    testWidgets('makes a note, opened and typed into as its body streams, answers the tool and ends on Claude\'s words', (tester) async {
      final notes = _Notes();
      final desk = _Desk(notes);
      final body = '# Weekend plan\n\n- [ ] Pack\n- [ ] Book the train “early”\n';
      final api = _Api([
        _turn(words: 'Making it.', tool: ClaudeTool.create, pieces: _cut(jsonEncode({'body': body}), 5)),
        _turn(words: 'Wrote [[Weekend plan]].'),
      ]);
      final run = ClaudeRun(api: api, model: 'claude-sonnet-5-5', notes: notes, desk: desk, prompt: 'Plan my weekend');
      final states = <ClaudeState>[];
      run.addListener(() => states.add(run.state));
      await tester.runAsync(run.run);

      expect(run.state, ClaudeState.done);
      expect(states, containsAllInOrder([ClaudeState.thinking, ClaudeState.writing, ClaudeState.done]));
      expect(desk.opened, ['n1']);
      expect(desk.views['n1']!.state.doc.toString(), body);
      // The caret went with the run.
      expect(claudeCaretOf(desk.views['n1']!.state), isNull);
      expect(run.touched, {'n1': 'Weekend plan'});
      expect(run.answer, 'Wrote [[Weekend plan]].');
      expect([for (final step in run.steps) (step.kind, step.words)], [
        ('asked', 'Plan my weekend'),
        ('said', 'Making it.'),
        ('tool', 'Wrote Weekend plan'),
        ('said', 'Wrote [[Weekend plan]].'),
      ]);
      // The second request carries the tool's answer, and every tool is told to stream its input.
      final second = api.asked[1]['messages']! as List;
      final results = (second.last as Map)['content'] as List;
      expect((results.single as Map)['tool_use_id'], 'toolu_1');
      expect(jsonDecode((results.single as Map)['content'] as String), {'id': 'n1', 'title': 'Weekend plan', 'done': true});
      final tools = api.asked.first['tools']! as List;
      expect([for (final tool in tools) if ((tool as Map)['eager_input_streaming'] == true) tool['name']], [ClaudeTool.create, ClaudeTool.append, ClaudeTool.replace, ClaudeTool.rewrite]);
    });

    // Matt, 2026-10-17: "add a model and effort selector to the agent page". A chosen effort goes with the request as
    // `output_config.effort`; none chosen leaves the model to its own.
    testWidgets('asks with the effort chosen, and with none when it is the model\'s own', (tester) async {
      final notes = _Notes();
      final desk = _Desk(notes);
      final chosen = _Api([_turn(words: 'Done.')]);
      await tester.runAsync(ClaudeRun(api: chosen, model: 'claude-opus-5-5', effort: 'xhigh', notes: notes, desk: desk, prompt: 'x').run);
      expect(chosen.asked.single['model'], 'claude-opus-5-5');
      expect(chosen.asked.single['output_config'], {'effort': 'xhigh'});
      final left = _Api([_turn(words: 'Done.')]);
      await tester.runAsync(ClaudeRun(api: left, model: 'claude-sonnet-5-5', notes: notes, desk: desk, prompt: 'x').run);
      expect(left.asked.single.containsKey('output_config'), isFalse);
      expect((defaultClaudeEffort('claude-sonnet-5-5'), defaultClaudeEffort('claude-opus-5-5'), defaultClaudeEffort('claude-haiku-5-5')), ('high', 'medium', 'medium'));
    });

    // Matt, 2026-10-17: "show claudes or whatever AI agent were using thought process". Every request asks for
    // adaptive thinking with its summary shown, the summary arrives as it is thought, is kept as a step, and every
    // thinking block goes back as it came, its signature and a sealed one too, in the turn that called the tool.
    testWidgets('asks for Claude\'s thinking, shows it as it comes, and sends each block back as it came', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk\n';
      final desk = _Desk(notes);
      final thought = [
        _e('message_start', {'type': 'message_start'}),
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'The person wants '},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'their groceries read.'},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig-1'},
        }),
        _e('content_block_stop', {'index': 0}),
        _e('content_block_start', {
          'index': 1,
          'content_block': {'type': 'redacted_thinking', 'data': 'sealed'},
        }),
        _e('content_block_stop', {'index': 1}),
        _e('content_block_start', {
          'index': 2,
          'content_block': {'type': 'tool_use', 'id': 'toolu_9', 'name': ClaudeTool.read, 'input': <String, Object?>{}},
        }),
        _e('content_block_delta', {
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': jsonEncode({'id': 'g'})},
        }),
        _e('content_block_stop', {'index': 2}),
        _e('message_delta', {
          'delta': {'stop_reason': 'tool_use'},
        }),
      ];
      final api = _Api([thought, _turn(words: 'Milk.')]);
      final run = ClaudeRun(api: api, model: 'claude-opus-5-5', notes: notes, desk: desk, prompt: 'what is on my list');
      final seen = <String>[];
      run.addListener(() {
        if (run.thinking.isNotEmpty && (seen.isEmpty || seen.last != run.thinking)) seen.add(run.thinking);
      });
      await tester.runAsync(run.run);

      expect(api.asked.first['thinking'], {'type': 'adaptive', 'display': 'summarized'});
      expect(seen, ['The person wants ', 'The person wants their groceries read.']);
      expect(run.thinking, '');
      expect(run.lastThought, 'The person wants their groceries read.');
      expect([for (final step in run.steps) step.kind], ['asked', 'thought', 'tool', 'said']);
      final turn = (api.asked[1]['messages']! as List)[1] as Map;
      expect(turn['role'], 'assistant');
      expect(turn['content'], [
        {'type': 'thinking', 'thinking': 'The person wants their groceries read.', 'signature': 'sig-1'},
        {'type': 'redacted_thinking', 'data': 'sealed'},
        {
          'type': 'tool_use',
          'id': 'toolu_9',
          'name': ClaudeTool.read,
          'input': {'id': 'g'},
        },
      ]);
      // A model id the app does not offer is sent no thinking at all.
      final other = _Api([_turn(words: 'Done.')]);
      await tester.runAsync(ClaudeRun(api: other, model: 'claude-sonnet-4-5', notes: notes, desk: desk, prompt: 'x').run);
      expect(other.asked.single.containsKey('thinking'), isFalse);
    });

    // The thinking blocks go back with a follow-up, and the API refuses one once the system prompt before it has
    // changed: a conversation keeps the day and the rules it began with, and New chat takes the new ones.
    testWidgets('keeps the system prompt a conversation began with for its follow-ups', (tester) async {
      final notes = _Notes()..bodies['r'] = '# Claude rules\n\nBe brief.';
      final api = _Api([_turn(words: 'One.'), _turn(words: 'Two.'), _turn(words: 'Three.')]);
      var day = DateTime(2026, 10, 17);
      final settings = ClaudeSettings(MemorySecureStore());
      await tester.runAsync(() => settings.setKey('sk-ant-test-0000000000'));
      final runner = ClaudeRunner(settings: settings, notes: notes, desk: _Desk(notes), api: (_) => api, now: () => day);
      Future<void> ask(String words) async {
        final run = await runner.ask(words);
        while (run.working || run.state == ClaudeState.idle) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await tester.runAsync(() => ask('first'));
      day = DateTime(2026, 10, 18);
      notes.bodies['r'] = '# Claude rules\n\nBe long.';
      await tester.runAsync(() => ask('second'));
      expect(api.asked[1]['system'], api.asked[0]['system']);
      expect(api.asked[1]['system'] as String, allOf(contains('2026-10-17'), contains('Be brief.')));
      runner.newChat();
      await tester.runAsync(() => ask('third'));
      expect(api.asked[2]['system'] as String, allOf(contains('2026-10-18'), contains('Be long.')));
      runner.dispose();
    });

    testWidgets('changes one passage of an open note in place, the old words taken out and the new typed in', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk\n- eggs\n\nThe end.';
      final desk = _Desk(notes);
      final api = _Api([
        _turn(tool: ClaudeTool.replace, pieces: _cut(jsonEncode({'id': 'g', 'old_text': '- eggs', 'new_text': '- eggs\n- bread'}), 3)),
        _turn(words: 'Added bread.'),
      ]);
      final run = ClaudeRun(api: api, model: 'm', notes: notes, desk: desk, prompt: 'add bread');
      await tester.runAsync(run.run);
      expect(desk.views['g']!.state.doc.toString(), '# Groceries\n\n- milk\n- eggs\n- bread\n\nThe end.');
      expect(run.steps.where((s) => s.kind == 'tool').single.words, 'Changed Groceries');
    });

    testWidgets('says so when the old words are not in the note, and changes nothing', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk';
      final desk = _Desk(notes);
      final api = _Api([
        _turn(tool: ClaudeTool.replace, pieces: [jsonEncode({'id': 'g', 'old_text': '- eggs', 'new_text': '- bread'})]),
        _turn(words: 'Sorry.'),
      ]);
      final run = ClaudeRun(api: api, model: 'm', notes: notes, desk: desk, prompt: 'x');
      await tester.runAsync(run.run);
      expect(desk.views['g']!.state.doc.toString(), '# Groceries\n\n- milk');
      final results = ((api.asked[1]['messages']! as List).last as Map)['content'] as List;
      expect((results.single as Map)['is_error'], isTrue);
    });

    testWidgets('writes behind the screen where a note cannot be shown', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk';
      final desk = _Desk(notes, screen: false);
      final api = _Api([
        _turn(tool: ClaudeTool.append, pieces: _cut(jsonEncode({'id': 'g', 'text': '- bread'}), 4)),
        _turn(words: 'Done.'),
      ]);
      final run = ClaudeRun(api: api, model: 'm', notes: notes, desk: desk, prompt: 'x');
      await tester.runAsync(run.run);
      expect(notes.bodies['g'], '# Groceries\n\n- milk\n- bread');
    });

    // Matt, 2026-10-18: a note Claude made was never opened. Where the screen cannot show a new note, its words are
    // still written into it, and the run says so rather than losing them quietly.
    testWidgets('writes a new note behind the screen where it cannot be opened, and says so', (tester) async {
      final notes = _Notes();
      final desk = _Desk(notes, screen: false);
      const body = '# Packing list\n\n- [ ] Passport\n';
      final api = _Api([
        _turn(tool: ClaudeTool.create, pieces: _cut(jsonEncode({'body': body}), 4)),
        _turn(words: 'Done.'),
      ]);
      final run = ClaudeRun(api: api, model: 'm', notes: notes, desk: desk, prompt: 'x');
      await tester.runAsync(run.run);
      expect(run.state, ClaudeState.done);
      expect(desk.opened, ['n1']);
      expect(notes.bodies['n1'], body);
      expect(run.steps.where((step) => step.kind == 'tool').single.words, 'Wrote Packing list, out of sight: it could not be opened');
      final results = ((api.asked[1]['messages']! as List).last as Map)['content'] as List;
      final said = jsonDecode((results.single as Map)['content'] as String) as Map;
      expect(said['id'], 'n1');
      expect(said['shown'], startsWith('No:'));
    });

    testWidgets('reads with its tools, and fails in words a person reads', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk';
      final desk = _Desk(notes);
      final api = _Api([
        _turn(tool: ClaudeTool.read, pieces: [jsonEncode({'title': 'Groceries'})]),
        [
          _e('message_start', {'type': 'message_start'}),
          _e('error', {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          }),
        ],
      ]);
      final run = ClaudeRun(api: api, model: 'm', notes: notes, desk: desk, prompt: 'x');
      await tester.runAsync(run.run);
      expect(run.steps.where((s) => s.kind == 'tool').single.words, 'Read Groceries');
      final results = ((api.asked[1]['messages']! as List).last as Map)['content'] as List;
      expect(jsonDecode((results.single as Map)['content'] as String)['body'], '# Groceries\n\n- milk');
      expect(run.state, ClaudeState.failed);
      expect(run.problem, 'Overloaded');
    });

    testWidgets('keeps Claude\'s caret where it last typed while the run goes on, and shows it there when followed again', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk';
      final desk = _Desk(notes);
      final view = (await desk.open('g'))!;
      final typer = NoteTyper(view, follow: () => true, smoke: () => false, open: () => true, frame: const Duration(milliseconds: 1));
      await tester.runAsync(() async {
        typer.begin(view.state.doc.length);
        typer.type('\n- bread');
        await typer.end();
      });
      expect(view.state.doc.toString(), '# Groceries\n\n- milk\n- bread');
      expect(claudeCaretOf(view.state), view.state.doc.length);
      // The person types above it: Claude's caret rides along.
      view.dispatch(TransactionSpec(changes: const Change(from: 0, insert: 'X'), userEvent: 'input.type'));
      expect(claudeCaretOf(view.state), view.state.doc.length);
      clearClaudeCaret(view);
      expect(claudeCaretOf(view.state), isNull);
      showClaudeCaret(view, 4);
      expect(claudeCaretOf(view.state), 4);
    });
  });

  // Matt, 2026-10-20: "Also enable setting spending limits in claude settings in the app" (lib/claude/claude_spend.dart).
  group('the spending limit', () {
    /// [turn] as the API reports what it used: [input] in message_start, [output] in message_delta.
    List<SseEvent> paid(List<SseEvent> turn, {int input = 0, required int output}) => [
          for (final event in turn)
            if (event.event == 'message_start')
              _e('message_start', {
                'type': 'message_start',
                'message': {
                  'model': 'claude-opus-5-5',
                  'usage': {'input_tokens': input, 'output_tokens': 1},
                },
              })
            else if (event.event == 'message_delta')
              _e('message_delta', {...jsonDecode(event.data) as Map<String, Object?>, 'usage': {'output_tokens': output}})
            else
              event,
        ];

    Future<ClaudeSpend> limited(double limit, {double spent = 0}) async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      await spend.setOn(true);
      await spend.setLimit(limit);
      // Opus 5.5's output is $20 a million tokens: 50,000 of them a dollar.
      if (spent > 0) spend.record('claude-opus-5-5', ClaudeUsage(output: (spent * 50000).round()));
      return spend;
    }

    testWidgets('counts every request of a run, each turn of its tool loop', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk\n';
      final api = _Api([
        paid(_turn(words: 'Reading.', tool: ClaudeTool.read, pieces: [jsonEncode({'id': 'g'})]), input: 10000, output: 2000),
        paid(_turn(words: 'Milk.'), input: 12000, output: 500),
      ]);
      final spend = await tester.runAsync(() => limited(10));
      final run = ClaudeRun(api: api, model: 'claude-opus-5-5', notes: notes, desk: _Desk(notes), prompt: 'What is on the list?', spend: spend);
      await tester.runAsync(run.run);
      expect(run.state, ClaudeState.done);
      expect(spend!.requests, 2);
      expect(spend.spent, closeTo((22000 * 4 + 2500 * 20) / 1e6, 1e-12));
    });

    testWidgets('sends nothing once the month\'s limit is reached, and says so', (tester) async {
      final notes = _Notes();
      final api = _Api([_turn(words: 'Never.')]);
      final spend = await tester.runAsync(() => limited(5, spent: 5));
      final run = ClaudeRun(api: api, model: 'claude-opus-5-5', notes: notes, desk: _Desk(notes), prompt: 'x', spend: spend);
      await tester.runAsync(run.run);
      expect(api.asked, isEmpty);
      expect(run.state, ClaudeState.failed);
      expect(run.problem, 'Monthly spending limit reached (\$5). Change it in Settings › Claude.');

      // The root's runner refuses the ask before it makes a run; the chat and the voice sheet say its words.
      final settings = ClaudeSettings(MemorySecureStore());
      await tester.runAsync(() async {
        await settings.setKey('sk-ant-test-0000000000');
        await settings.spend.setOn(true);
        await settings.spend.setLimit(5);
        settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 250000));
      });
      final runner = ClaudeRunner(settings: settings, notes: notes, desk: _Desk(notes), api: (_) => api);
      expect(runner.limited, isTrue);
      Object? refused;
      await tester.runAsync(() async {
        try {
          await runner.ask('x');
        } catch (error) {
          refused = error;
        }
      });
      expect(refused, isA<ClaudeError>().having((e) => e.message, 'message', 'Monthly spending limit reached (\$5). Change it in Settings › Claude.').having((e) => e.type, 'type', claudeLimitType));
      expect(api.asked, isEmpty);
      // Raised, it is asked again.
      await tester.runAsync(() => settings.spend.setLimit(10));
      expect(runner.limited, isFalse);
      runner.dispose();
    });

    testWidgets('a run that crosses the limit finishes its request, its tool answered, and starts no other', (tester) async {
      final notes = _Notes()..bodies['g'] = '# Groceries\n\n- milk\n';
      final api = _Api([
        // $4.90 so far; this request costs $0.20 more.
        paid(_turn(words: 'Reading.', tool: ClaudeTool.read, pieces: [jsonEncode({'id': 'g'})]), output: 10000),
        _turn(words: 'Never asked.'),
      ]);
      final spend = await tester.runAsync(() => limited(5, spent: 4.9));
      final run = ClaudeRun(api: api, model: 'claude-opus-5-5', notes: notes, desk: _Desk(notes), prompt: 'What is on the list?', spend: spend);
      await tester.runAsync(run.run);
      expect(api.asked, hasLength(1));
      expect(spend!.reached, isTrue);
      expect(run.state, ClaudeState.failed);
      expect(run.problem, 'Monthly spending limit reached (\$5). Change it in Settings › Claude.');
      // At 98% before it began, the run warned first.
      expect([for (final step in run.steps) step.kind], ['asked', 'notice', 'said', 'tool']);
      // The tool was answered in the conversation, so a follow-up once the limit is raised is whole.
      final last = run.messages.last;
      expect(last['role'], 'user');
      expect(((last['content']! as List).single as Map)['type'], 'tool_result');
    });

    testWidgets('warns once a month in the chat past 80%', (tester) async {
      final notes = _Notes();
      final spend = await tester.runAsync(() => limited(10, spent: 7.9));
      // This request costs $0.20: $8.10, past 80%.
      final first = ClaudeRun(api: _Api([paid(_turn(words: 'Done.'), output: 10000)]), model: 'claude-opus-5-5', notes: notes, desk: _Desk(notes), prompt: 'x', spend: spend);
      await tester.runAsync(first.run);
      expect(first.state, ClaudeState.done);
      expect([for (final step in first.steps) (step.kind, step.words)], [
        ('asked', 'x'),
        ('said', 'Done.'),
        ('notice', 'You’ve used \$8.10 of your \$10 monthly limit for Claude (81%). Change it in Settings › Claude.'),
      ]);
      final second = ClaudeRun(api: _Api([paid(_turn(words: 'Again.'), output: 10000)]), model: 'claude-opus-5-5', notes: notes, desk: _Desk(notes), prompt: 'y', spend: spend);
      await tester.runAsync(second.run);
      expect(second.steps.where((step) => step.kind == 'notice'), isEmpty);
    });
  });
}
