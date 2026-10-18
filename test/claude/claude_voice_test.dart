// Talking to Claude (lib/claude/claude_voice.dart, claude_voice_sheet.dart): an ask said aloud, heard by an ear the
// test speaks into, sent to a Claude whose stream the test plays out a piece at a time, so each stage is seen as it
// comes: listening with the ripples, the words as they are heard, Claude's thinking as it comes, the sheet making way
// to a strip once Claude writes in a note, and the answer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/claude/claude_voice.dart';
import 'package:ghost_md/claude/claude_voice_sheet.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/editor/editor.dart' show EditorViewLike;

import '../support/render.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// A Claude whose every request is a stream the test adds to.
class _Api extends ClaudeApi {
  _Api() : super(key: 'sk-ant-test');

  final List<Map<String, Object?>> asked = [];
  final List<StreamController<SseEvent>> streams = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    final events = StreamController<SseEvent>();
    streams.add(events);
    return ClaudeCall(events.stream, () {});
  }
}

class _Notes implements ClaudeNotes {
  final Map<String, String> bodies = {};
  int _made = 0;

  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async => const [];

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async => const [];

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

/// A screen with no editor to show: the run writes behind it, and the test sees the note's words in [notes].
class _Desk implements ClaudeDesk {
  _Desk(this.notes);

  final _Notes notes;
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

/// An ear the test speaks into.
class _Ear implements ClaudeHearing {
  ClaudeHeard? heard;
  String last = '';
  bool cancelled = false;
  int finished = 0;

  ClaudeHearing open(ClaudeHeard given) {
    heard = given;
    return this;
  }

  @override
  Future<String> finish() async {
    finished += 1;
    return last;
  }

  @override
  void cancel() => cancelled = true;
}

void main() {
  setUpAll(loadAppFonts);

  late _Api api;
  late _Notes notes;
  late _Desk desk;
  late ClaudeSettings settings;
  late ClaudeRunner runner;
  late _Ear ear;
  late int ended;
  late int chats;

  Future<ClaudeVoice> talk(WidgetTester tester, {bool withKey = true, Future<void> Function(String)? inbox}) async {
    api = _Api();
    notes = _Notes();
    desk = _Desk(notes);
    settings = ClaudeSettings(MemorySecureStore());
    if (withKey) await settings.setKey('sk-ant-test-0000000000');
    await settings.load();
    runner = ClaudeRunner(settings: settings, notes: notes, desk: desk, api: (_) => api);
    ear = _Ear();
    ended = 0;
    chats = 0;
    final voice = ClaudeVoice(runner: runner, ear: ear.open, inbox: inbox, about: 'Groceries', onEnd: () => ended += 1)..start();
    await pumpApp(tester, home: Stack(children: [ClaudeVoiceSheet(voice: voice, onChat: () => chats += 1)]));
    return voice;
  }

  /// The sheet taken down, and the shadows the app's pictures draw put back as the binding wants them.
  Future<void> end(WidgetTester tester, ClaudeVoice voice) async {
    voice.dispose();
    runner.dispose();
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> beats(WidgetTester tester, [int n = 4]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('listens with the ripples and the words as they come, then shows Claude thinking as it thinks, makes way once Claude writes, and ends on its answer', (tester) async {
    final voice = await talk(tester);
    // Listening: the mic in Claude's orange, the recorder's rings going out from it, the words as they are heard.
    expect(voice.stage, ClaudeVoiceStage.listening);
    expect(find.byKey(const ValueKey('claude-voice-listening')), findsOneWidget);
    expect(find.byKey(const Key('voice-waves')), findsOneWidget);
    expect(find.text('Say what you would like Claude to do.'), findsOneWidget);
    ear.heard!.level(0.6, 0.08);
    ear.heard!.words('Add bread');
    await tester.pump();
    expect(find.text('Add bread'), findsOneWidget);
    ear.heard!.words('Add bread to my list');
    await tester.pump();
    expect(find.text('Add bread to my list'), findsOneWidget);

    // Done, by a tap on the mic: the transcriber's last and best words are what is asked, about the page's note.
    ear.last = 'Add bread to my list.';
    await tester.tap(find.byKey(const ValueKey('claude-voice-mic')));
    await beats(tester);
    expect(ear.finished, 1);
    expect(voice.stage, ClaudeVoiceStage.thinking);
    expect(find.byKey(const ValueKey('claude-voice-thinking')), findsOneWidget);
    expect(find.byKey(const Key('voice-waves')), findsNothing, reason: 'the ripples are the voice\'s, and it has stopped');
    final asked = ((api.asked.single['messages']! as List).last as Map)['content'] as List;
    expect((asked.single as Map)['text'], '[[Groceries]] Add bread to my list.');
    expect(api.asked.single['thinking'], {'type': 'adaptive', 'display': 'summarized'});

    // Claude's thinking, as it comes.
    final first = api.streams.single;
    first.add(_e('message_start', {'type': 'message_start'}));
    first.add(_e('content_block_start', {
      'index': 0,
      'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''},
    }));
    first.add(_e('content_block_delta', {
      'index': 0,
      'delta': {'type': 'thinking_delta', 'thinking': 'A new list, with bread on it.'},
    }));
    await beats(tester);
    expect(find.text('A new list, with bread on it.'), findsOneWidget);
    first.add(_e('content_block_delta', {
      'index': 0,
      'delta': {'type': 'signature_delta', 'signature': 's'},
    }));
    first.add(_e('content_block_stop', {'index': 0}));

    // Claude writes in a note: the sheet makes way, down to a strip, and the note is opened to be watched.
    first.add(_e('content_block_start', {
      'index': 1,
      'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': ClaudeTool.create, 'input': <String, Object?>{}},
    }));
    first.add(_e('content_block_delta', {
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': '{"body": "# List'},
    }));
    await beats(tester);
    expect(voice.stage, ClaudeVoiceStage.following);
    expect(find.byKey(const ValueKey('claude-voice-following')), findsOneWidget);
    expect(find.byKey(const ValueKey('claude-voice-thinking')), findsNothing);
    expect(find.text('Writing a new note'), findsOneWidget);
    expect(desk.opened, ['n1']);
    // Nothing but the strip is covered: no scrim.
    expect(find.byKey(const ValueKey('claude-voice-scrim')), findsNothing);
    first.add(_e('content_block_delta', {
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': '\\n\\n- bread\\n"}'},
    }));
    first.add(_e('content_block_stop', {'index': 1}));
    first.add(_e('message_delta', {
      'delta': {'stop_reason': 'tool_use'},
    }));
    await first.close();
    await beats(tester);
    expect(notes.bodies['n1'], '# List\n\n- bread\n');

    // The answer, on the strip; the conversation is the chat's.
    final second = api.streams.last;
    expect(api.streams, hasLength(2));
    second.add(_e('content_block_start', {
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }));
    second.add(_e('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Made [[List]].'},
    }));
    second.add(_e('content_block_stop', {'index': 0}));
    second.add(_e('message_delta', {
      'delta': {'stop_reason': 'end_turn'},
    }));
    await second.close();
    await beats(tester);
    expect(voice.stage, ClaudeVoiceStage.answered);
    expect(find.text('Made [[List]].'), findsOneWidget);
    expect(runner.conversation, hasLength(1));
    // A strip goes by itself (a press on it would keep it).
    await tester.pump(claudeLinger + const Duration(milliseconds: 100));
    expect(ended, 1);
    await tester.tap(find.byKey(const ValueKey('claude-voice-chat')));
    expect(chats, 1);
    await end(tester, voice);
  });

  testWidgets('ends by itself on a pause once something was said, and says so when nothing was', (tester) async {
    var voice = await talk(tester);
    ear.last = 'What is on my list?';
    ear.heard!.words('What is on my list');
    await tester.pump(const Duration(milliseconds: 200));
    // A voice keeps it listening; a pause past the wait ends it.
    for (var i = 0; i < 5; i++) {
      ear.heard!.level(0.5, 0.2);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(voice.stage, ClaudeVoiceStage.listening);
    await tester.pump(const Duration(milliseconds: claudeQuietMs + 400));
    await beats(tester);
    expect(ear.finished, 1);
    expect(voice.stage, ClaudeVoiceStage.thinking);
    await end(tester, voice);

    voice = await talk(tester);
    await tester.pump(const Duration(milliseconds: claudeNothingMs + 400));
    await beats(tester);
    expect(voice.stage, ClaudeVoiceStage.failed);
    expect(find.byKey(const ValueKey('claude-voice-problem')), findsOneWidget);
    expect(api.asked, isEmpty);
    await end(tester, voice);
  });

  testWidgets('without a key sends the words to the Ask Claude note, and without that says where the key goes', (tester) async {
    final sent = <String>[];
    var voice = await talk(tester, withKey: false, inbox: (request) async => sent.add(request));
    ear.last = 'Plan the weekend.';
    await tester.tap(find.byKey(const ValueKey('claude-voice-mic')));
    await beats(tester);
    expect(sent, ['[[Groceries]] Plan the weekend.']);
    expect(voice.stage, ClaudeVoiceStage.sent);
    expect(find.byKey(const ValueKey('claude-voice-sent')), findsOneWidget);
    expect(api.asked, isEmpty);
    await tester.pump(claudeLinger + const Duration(milliseconds: 100));
    expect(ended, 1);
    await end(tester, voice);

    voice = await talk(tester, withKey: false);
    ear.last = 'Plan the weekend.';
    await tester.tap(find.byKey(const ValueKey('claude-voice-mic')));
    await beats(tester);
    expect(voice.stage, ClaudeVoiceStage.failed);
    expect(voice.wantsKey, isTrue);
    expect(find.textContaining('Settings › Plugins › Claude'), findsOneWidget);
    await end(tester, voice);
  });

  testWidgets('closed while it listens keeps nothing and asks nothing', (tester) async {
    final voice = await talk(tester);
    ear.heard!.words('never mind');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('claude-voice-close')));
    await tester.pump();
    expect(ear.cancelled, isTrue);
    expect(ear.finished, 0);
    expect(ended, 1);
    expect(api.asked, isEmpty);
    await end(tester, voice);
  });
}
