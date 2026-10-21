import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_spend.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/claude/claude_voice.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/editor/editor.dart' show EditorViewLike;
import 'package:ghost_md/settings/panes/watch_section.dart';
import 'package:ghost_md/watch/watch_claude.dart';
import 'package:ghost_md/watch/watch_link.dart';
import 'package:ghost_md/watch/watch_notes.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../support/render.dart';
import 'fakes.dart';

/// A short take from the watch sent to Claude (lib/watch/watch_notes.dart, "To Claude"), as the dock's microphone
/// sends what it hears: no voice note of its own, asked once, and a voice note after all wherever Claude could not.

const _heard = [Segment(startMs: 0, endMs: 2000, text: 'Add oat milk to my shopping list.')];

/// Claude as a test answers for it.
class _Claude implements WatchClaude {
  bool shown = true;
  final List<({String words, String prompt, String take})> asked = [];
  WatchAsked Function() answer = () => const WatchAskedDone('Added oat milk to Shopping.');

  @override
  Future<bool> ready() async => shown;

  @override
  Future<WatchAsked> ask({required String words, required String prompt, required WatchTake take}) async {
    asked.add((words: words, prompt: prompt, take: take.id));
    return answer();
  }
}

/// An inbox whose `done` fails the first time it is asked.
class _ForgetfulHost extends FakeHost {
  int failures = 1;

  @override
  Future<void> done(String id) async {
    if (failures > 0) {
      failures -= 1;
      throw StateError('the bridge went away');
    }
    return super.done(id);
  }
}

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// A Claude that says [words] and is done.
class _Api extends ClaudeApi {
  _Api({this.fail}) : super(key: 'sk-ant-test');

  final ClaudeError? fail;
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    final events = StreamController<SseEvent>();
    scheduleMicrotask(() {
      if (fail != null) {
        events.addError(fail!);
        unawaited(events.close());
        return;
      }
      for (final event in [
        _e('message_start', {'type': 'message_start'}),
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Added oat milk.'},
        }),
        _e('content_block_stop', {'index': 0}),
        _e('message_delta', {
          'delta': {'stop_reason': 'end_turn'},
        }),
        _e('message_stop', {'type': 'message_stop'}),
      ]) {
        events.add(event);
      }
      unawaited(events.close());
    });
    return ClaudeCall(events.stream, () {});
  }
}

class _Notes implements ClaudeNotes {
  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async => const [];

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async => const [];

  @override
  Future<NoteRead?> read({String? id, String? title}) async => null;

  @override
  Future<String> create(String body) async => 'n1';

  @override
  Future<void> write(String id, String body) async {}
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

void main() {
  late Directory dir;
  late FakeHost host;
  late FakeStore store;
  late List<String> listened;
  late Heard Function(String id) answer;
  late Preferences prefs;
  late _Claude claude;
  late FileWatchAsks asks;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('watch-claude');
    host = FakeHost();
    store = FakeStore();
    listened = [];
    answer = (_) => const HeardWords(_heard);
    prefs = const Preferences();
    claude = _Claude();
    asks = FileWatchAsks(File('${dir.path}/watch-claude.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  WatchTake take(String id, {int at = 1760961900000, int ms = 4200}) {
    final wav = File('${dir.path}/$id.wav')..writeAsBytesSync([82, 73, 70, 70, ...List.filled(60, 0)]);
    return WatchTake(id: id, recordedAt: at, durationMs: ms, watch: 'Galaxy Watch9', wav: wav.path);
  }

  WatchNotes notesOver({WatchClaude? to, WatchAsks? kept, List<String>? writeUps}) => WatchNotes(
        host: host,
        store: store,
        listen: (id, ms) async {
          listened.add(id);
          return answer(id);
        },
        preferences: () => prefs,
        writeUp: writeUps?.add,
        markMeeting: (_, _) {},
        claude: to,
        asks: kept,
        retry: const Duration(hours: 1),
      );

  test('Claude shown: the words heard are asked of Claude, saying when and on which watch, and no voice note is made', () async {
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 0, reason: 'no note was made');

    final id = watchNoteId('t1');
    expect(listened, [id], reason: 'heard by the phone’s Whisper exactly as before');
    expect(claude.asked, hasLength(1));
    expect(claude.asked.single.words, 'Add oat milk to my shopping list.');
    final at = DateTime.fromMillisecondsSinceEpoch(1760961900000);
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    expect(claude.asked.single.prompt, startsWith('Add oat milk to my shopping list.\n\n(Said into my watch (Galaxy Watch9) at $time on '));
    expect(store.notes, isEmpty);
    expect(store.dropped, [id], reason: 'the microphone keeps no audio, and neither does this');
    expect(store.recordings, isEmpty);
    expect(host.doneIds, ['t1']);
    expect((await asks.of('t1'))?.state, WatchAskState.asked);
    notes.dispose();
  });

  test('Claude not shown (off, or no key): a voice note as today, nothing asked', () async {
    claude.shown = false;
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    expect(store.notes[watchNoteId('t1')]!.body, watchNoteBody(_heard, 1760961900000));
    expect(store.dropped, isEmpty);
    expect(await asks.of('t1'), isNull);
    notes.dispose();
  });

  test('Local only on: a voice note, nothing asked', () async {
    prefs = const Preferences(localOnly: true);
    host.takes.add(take('local'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    expect(store.notes, hasLength(1));
    notes.dispose();
  });

  test('without the record that keeps a take asked once, nothing is asked', () async {
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude);
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    notes.dispose();
  });

  test('Claude failing (the network, a key refused): a voice note after all, saying why, and never asked again', () async {
    claude.answer = () => const WatchAskFailed('Claude could not be reached. Check the connection.');
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 1);
    final note = store.notes[watchNoteId('t1')]!;
    expect(note.body, startsWith(watchNoteBody(_heard, 1760961900000).trimRight()));
    expect(note.body, endsWith('\n\n*Not done by Claude: Claude could not be reached. Check the connection. Kept as a voice note.*\n'));
    expect(note.recordingMs, 4200);
    expect(store.recordings, contains(watchNoteId('t1')), reason: 'the recording is the voice note’s');
    expect(store.dropped, isEmpty);
    expect(host.doneIds, ['t1']);
    expect((await asks.of('t1'))?.state, WatchAskState.failed);

    // The same take again (the watch sent it twice): one note, and Claude not asked again.
    host.takes.add(take('t1'));
    await notes.kick();
    expect(claude.asked, hasLength(1));
    expect(store.notes, hasLength(1));
    notes.dispose();
  });

  test('a note that could not be written after Claude failed is written on the next pass, saying the same, Claude not asked again', () async {
    claude.answer = () => const WatchAskFailed('Monthly spending limit reached (\$5). Change it in Settings › Claude.');
    store.failMaking = StateError('disk full');
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 0);
    store.failMaking = null;
    expect(await notes.kick(), 1);
    expect(claude.asked, hasLength(1));
    expect(store.notes[watchNoteId('t1')]!.body, contains('*Not done by Claude: Monthly spending limit reached (\$5). Change it in Settings › Claude. Kept as a voice note.*'));
    notes.dispose();
  });

  test('exactly once: a take Claude did whose inbox entry was not let go is only let go on the next pass', () async {
    host = _ForgetfulHost();
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: asks);
    await notes.kick();
    expect(claude.asked, hasLength(1));
    expect(host.takes, hasLength(1), reason: 'the bridge refused the first done');

    await notes.kick();
    expect(claude.asked, hasLength(1), reason: 'never asked twice');
    expect(store.notes, isEmpty, reason: 'and never a voice note as well');
    expect(host.doneIds, ['t1']);
    notes.dispose();
  });

  test('exactly once across a restart: a take asked whose run never ended (the app closed) is a voice note, not asked again', () async {
    await asks.mark('t1', WatchAskState.asking);
    host.takes.add(take('t1'));
    // A new run of the app: the record is the file's.
    final notes = notesOver(to: claude, kept: FileWatchAsks(File('${dir.path}/watch-claude.json')));
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    expect(store.notes[watchNoteId('t1')]!.body, contains('*Not done by Claude: the app was closed before Claude finished, and Claude may have done some of it. Kept as a voice note.*'));
    notes.dispose();
  });

  test('exactly once across a restart: a take Claude did is only let go', () async {
    await asks.mark('t1', WatchAskState.asked);
    host.takes.add(take('t1'));
    final notes = notesOver(to: claude, kept: FileWatchAsks(File('${dir.path}/watch-claude.json')));
    expect(await notes.kick(), 0);
    expect(claude.asked, isEmpty);
    expect(listened, isEmpty);
    expect(store.notes, isEmpty);
    expect(host.doneIds, ['t1']);
    notes.dispose();
  });

  test('past ten minutes it is a meeting as before, never asked', () async {
    final writeUps = <String>[];
    host.takes.add(take('talk', ms: meetingFromMs + 1));
    final notes = notesOver(to: claude, kept: asks, writeUps: writeUps);
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    expect(writeUps, [watchNoteId('talk')]);
    notes.dispose();
  });

  test('nothing heard: a voice note keeping the tape, nothing asked', () async {
    answer = (_) => const HeardWords([]);
    host.takes.add(take('quiet'));
    final notes = notesOver(to: claude, kept: asks);
    expect(await notes.kick(), 1);
    expect(claude.asked, isEmpty);
    notes.dispose();
  });

  test('the record keeps a month, written whole', () async {
    var now = 1000;
    final file = File('${dir.path}/kept.json');
    final kept = FileWatchAsks(file, now: () => now);
    await kept.mark('old', WatchAskState.asked);
    now += 31 * 24 * 60 * 60 * 1000;
    await kept.mark('new', WatchAskState.failed, why: 'no network');
    expect(await kept.of('old'), isNull);
    expect(await kept.of('new'), (state: WatchAskState.failed, why: 'no network'));
    expect(File('${file.path}.new').existsSync(), isFalse);
    file.writeAsStringSync('not json');
    expect(await kept.of('new'), isNull);
  });

  group('over the app’s own runner', () {
    late ClaudeSettings settings;

    Future<ClaudeRunner> runnerWith(_Api api, {bool key = true}) async {
      settings = ClaudeSettings(MemorySecureStore());
      if (key) await settings.setKey('sk-ant-test-0000000000');
      await settings.load();
      return ClaudeRunner(settings: settings, notes: _Notes(), desk: _Desk(), api: (_) => api);
    }

    test('the words go to Claude as one said to the microphone, and Claude’s run over is done', () async {
      final api = _Api();
      final runner = await runnerWith(api);
      host.takes.add(take('t1'));
      final notes = notesOver(to: RunnerWatchClaude(runner: runner, shown: () => settings.hasKey), kept: asks);
      expect(await notes.kick(), 0);
      final content = ((api.asked.single['messages']! as List).last as Map)['content'] as List;
      expect((content.single as Map)['text'], startsWith('Add oat milk to my shopping list.\n\n(Said into my watch'));
      expect(runner.conversation, hasLength(1), reason: 'in the chat’s conversation, as Talk to Claude asks');
      expect(store.notes, isEmpty);
      expect(host.doneIds, ['t1']);
      notes.dispose();
      runner.dispose();
    });

    test('Settings’ switch off: a voice note, nothing sent; on again, the next take is asked', () async {
      final api = _Api();
      final runner = await runnerWith(api);
      expect(settings.watch, isTrue, reason: 'on by default');
      await settings.setWatch(false);
      host.takes.add(take('off'));
      final notes = notesOver(to: RunnerWatchClaude(runner: runner, shown: () => settings.hasKey), kept: asks);
      expect(await notes.kick(), 1);
      expect(api.asked, isEmpty);
      expect(store.notes.keys, [watchNoteId('off')]);

      await settings.setWatch(true);
      host.takes.add(take('on', at: 1760961900001));
      expect(await notes.kick(), 0);
      expect(api.asked, hasLength(1));
      expect(store.notes, hasLength(1));
      notes.dispose();
      runner.dispose();
    });

    test('the switch is kept on this device with the key', () async {
      final store = MemorySecureStore();
      final first = ClaudeSettings(store);
      await first.load();
      await first.setWatch(false);
      final again = ClaudeSettings(store);
      await again.load();
      expect(again.watch, isFalse);
    });

    test('at the month’s spending limit nothing is sent, and the take is a voice note saying so', () async {
      final api = _Api();
      final runner = await runnerWith(api);
      settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 250000)); // $5
      await settings.spend.setOn(true);
      await settings.spend.setLimit(5);
      expect(runner.limited, isTrue);
      host.takes.add(take('t1'));
      final notes = notesOver(to: RunnerWatchClaude(runner: runner, shown: () => settings.hasKey), kept: asks);
      expect(await notes.kick(), 1);
      expect(api.asked, isEmpty);
      expect(store.notes[watchNoteId('t1')]!.body, contains('*Not done by Claude: ${claudeLimitMessage(5).replaceAll(RegExp(r'\.$'), '')}. Kept as a voice note.*'));
      notes.dispose();
      runner.dispose();
    });

    test('a run that fails is a voice note, saying why', () async {
      final api = _Api(fail: const ClaudeError('Claude could not be reached. Check the connection.'));
      final runner = await runnerWith(api);
      host.takes.add(take('t1'));
      final notes = notesOver(to: RunnerWatchClaude(runner: runner, shown: () => settings.hasKey), kept: asks);
      expect(await notes.kick(), 1);
      expect(api.asked, hasLength(1));
      expect(store.notes[watchNoteId('t1')]!.body, contains('*Not done by Claude: Claude could not be reached. Check the connection. Kept as a voice note.*'));
      notes.dispose();
      runner.dispose();
    });

    test('the talk’s sheet takes words already heard: nothing is listened to, and a failure says the voice note is kept', () async {
      final runner = await runnerWith(_Api());
      final talk = ClaudeVoice(runner: runner, ear: (_) => throw StateError('not listened to'), fromWatch: true);
      await talk.sendHeard('Add oat milk', prompt: 'Add oat milk\n\n(Said into my watch.)');
      expect(talk.words, 'Add oat milk');
      final run = talk.run!;
      expect(run.prompt, 'Add oat milk\n\n(Said into my watch.)');
      expect(await watchRunOutcome(run), isA<WatchAskedDone>());
      talk.dispose();

      final keyless = await runnerWith(_Api(), key: false);
      final refused = ClaudeVoice(runner: keyless, ear: (_) => throw StateError('not listened to'), fromWatch: true);
      await refused.sendHeard('Add oat milk');
      expect(refused.run, isNull);
      expect(refused.stage, ClaudeVoiceStage.failed);
      expect(refused.problem, endsWith('The recording is kept as a voice note.'));
      refused.dispose();
      runner.dispose();
      keyless.dispose();
    });
  });

  group('Settings › Recording › Watch', () {
    setUpAll(loadAppFonts);

    Future<void> section(WidgetTester tester, {required bool claude, required bool on, ValueChanged<bool>? changed}) async {
      await pumpApp(
        tester,
        home: SingleChildScrollView(
          child: WatchSection(status: const WatchStatus(watches: [(name: 'Galaxy Watch9', nearby: true)]), claude: claude, toClaude: on, onToClaude: changed),
        ),
      );
    }

    testWidgets('the switch is there with Claude shown, and turning it says so', (tester) async {
      final changes = <bool>[];
      await section(tester, claude: true, on: true, changed: changes.add);
      expect(find.text(watchClaudeLabel), findsOneWidget);
      final toggle = find.byType(GlacierSwitch);
      expect(toggle, findsOneWidget);
      expect(tester.widget<GlacierSwitch>(toggle).checked, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(changes, [false]);
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with Claude not shown the line says how, and there is no switch', (tester) async {
      await section(tester, claude: false, on: true);
      expect(find.text(watchClaudeLabel), findsOneWidget);
      expect(find.byType(GlacierSwitch), findsNothing);
      expect(find.textContaining('add your Anthropic API key'), findsOneWidget);
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
