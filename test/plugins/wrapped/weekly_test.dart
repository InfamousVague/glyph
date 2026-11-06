// Wrapped's weekly report (lib/plugins/wrapped/weekly.dart, service.dart, weekly_section.dart, home_card.dart;
// docs/WRAPPED.md, "The weekly report"; Matt, 2026-11-06: "Wrapped should also give weekly reports and work using the
// attached AI such as Claude"): the counts of a week of invented notes, the week's bounds by the locale's first day,
// a missed week made at the next look and never twice, the AI asked being the one connected (Claude through a fake
// Messages API, nothing sent anywhere), Which AI, the note's Markdown and its journal, the notification only where
// allowed, the home card's This week, the settings, Simple, and the analytics' allow-list. Nobody in it is real.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isJournalBody;
import 'package:ghost_md/core/library_config.dart' show MemoryConfigFile;
import 'package:ghost_md/core/metrics.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/phone_notices.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart' show CleanupAi, connectedAis;
import 'package:ghost_md/plugins/wrapped/wrapped.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart' show Asked, scriptedAi, testPacing;

// ---- the week ---------------------------------------------------------------------------------------------------------

/// Monday 26 October 2026 to Sunday 1 November: the week the fixture's notes are in.
final DateTime weekStart = DateTime(2026, 10, 26);

/// Thursday 5 November, noon: three days after that week's report was due (Monday 2 November, 8:00).
final DateTime thursday = DateTime(2026, 11, 5, 12);

int at(int year, int month, int day, [int hour = 9]) => DateTime(year, month, day, hour).millisecondsSinceEpoch;

Note n(String id, String body, {required int written, int? edited, int revision = 1, NoteSource source = NoteSource.editor}) =>
    Note(id: id, body: body, createdAt: written, updatedAt: edited ?? written, revision: revision, source: source);

/// The week's notes: a launch plan and a meeting on the Tuesday, a recording on the Thursday, two older notes come back
/// to, one that crossed the stale line on the Tuesday, one from the week before, and last week's report itself.
List<Note> weekNotes() => [
      n('plan', '# Launch plan\n\nThe post goes out on Friday with the screenshots.\n\n- [ ] Ship the launch post\n- [x] Draft the launch post', written: at(2026, 10, 27, 10)),
      n('meet', '---\nmeeting: weekly\n---\n# Launch sync\n\nAgreed the date.', written: at(2026, 10, 27, 14)),
      n('voice', '# A thought on the walk\n\nThe garden needs a path.', written: at(2026, 10, 29, 18), source: NoteSource.capture),
      n('old', '# Reading list\n\n- [x] Call the bank\n- [ ] Return the library books', written: at(2026, 3, 1), edited: at(2026, 10, 27, 20), revision: 5),
      n('older', '# Garden ideas\n\nA path along the fence.', written: at(2026, 1, 1), edited: at(2026, 10, 30), revision: 2),
      n('stale', '# Tax forms', written: at(2026, 1, 10), edited: at(2026, 1, 30)),
      n('before', '# Last week\n\n- [ ] Water the plants', written: at(2026, 10, 20)),
      n('report-old', '---\ntitle: "Week of 19 Oct 2026"\ndate: 2026-10-19\nwrapped-week: 2026-10-19\n---\n# Week of 19 Oct 2026\n\n- [[Launch plan]]', written: at(2026, 10, 27, 8)),
    ];

class Told implements NoticesHost {
  Told([this.now = NoticesState.on]);
  NoticesState? now;
  final List<PhoneNotice> posted = [];

  @override
  Future<NoticesState?> state() async => now;

  @override
  Future<bool> post(PhoneNotice notice) async {
    if (now == NoticesState.blocked) return false;
    posted.add(notice);
    return true;
  }

  @override
  Future<NoticesState?> watch(String json) async => now;

  @override
  Future<bool> allow() async => true;
}

/// An AI that gives each note the gist "About <title>", and the week a summary, two themes and three steps: the
/// launch post's to-do checked off, the stale note archived, the garden notes linked.
String weeklyAnswer(String system, String prompt) {
  if (system == weeklySystem) {
    final todo = RegExp(r'^\[(t\d+)\] Ship the launch post', multiLine: true).firstMatch(prompt)?.group(1);
    final refs = {for (final m in RegExp(r'^\[(n\d+)\] “(.*?)”', multiLine: true).allMatches(prompt)) m.group(2)!: m.group(1)!};
    return jsonEncode({
      'summary': 'You spent the week on the launch. The plan came together on Tuesday. The garden came back too.',
      'themes': ['Launch', 'garden'],
      'steps': [
        {'kind': 'check_off', 'todos': [todo], 'words': 'The launch post looks shipped'},
        {'kind': 'link', 'from': refs['A thought on the walk'], 'to': refs['Garden ideas'], 'words': 'Two notes about the garden path'},
        {'kind': 'look', 'notes': ['n99'], 'words': 'A note that is not there'},
        {'kind': 'look', 'notes': [refs['Launch sync']], 'words': 'The sync is worth a second look'},
      ],
    });
  }
  final refs = {for (final m in RegExp(r'^\[(n\d+)\] (?:“(.*)”|\(no title\)) ·', multiLine: true).allMatches(prompt)) m.group(2) ?? '': m.group(1)!};
  return jsonEncode({
    'notes': [
      for (final MapEntry(key: title, value: ref) in refs.entries) {'ref': ref, 'gist': 'About $title', 'themes': ['life']},
    ],
  });
}

class World {
  World({List<Note>? notes, DateTime? now}) : now = now ?? thursday {
    library = SampleLibrary(notes ?? weekNotes(), clock: () => this.now.millisecondsSinceEpoch);
  }

  DateTime now;
  late final SampleLibrary library;
  final MemoryTrash trash = MemoryTrash();
  late final WorkspaceStore workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'work', name: 'Work')])), trash: trash);
  final MemoryConfigFile file = MemoryConfigFile();
  final Told told = Told();

  WrappedService service({List<CleanupAi>? ais, Future<List<CleanupAi>> Function()? connected, int firstDay = DateTime.monday, AssistantChoice? choice}) => WrappedService(
        library: library,
        workspaces: workspaces,
        trash: trash,
        store: WrappedStore(file: file),
        choice: choice,
        ais: connected ?? () async => ais ?? const [],
        clock: () => now,
        busy: () => false,
        pacing: testPacing,
        wait: (_) async {},
        contradictions: () => null,
        notices: told,
        firstWeekday: () => firstDay,
      );

  List<Note> reports() => [for (final note in library.value) if (weekOfNote(note) != null && note.id != 'report-old') note];
}

Future<WrappedService> ready(WrappedService service) async {
  await service.store.reread();
  return service;
}

// ---- a fake Claude, and a fake OpenAI ------------------------------------------------------------------------------------

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

List<SseEvent> _said(String words) => [
      _e('message_start', {
        'message': {
          'model': 'm',
          'usage': {'input_tokens': 10},
        },
      }),
      _e('content_block_start', {
        'index': 0,
        'content_block': {'type': 'text', 'text': ''},
      }),
      _e('content_block_delta', {
        'index': 0,
        'delta': {'type': 'text_delta', 'text': words},
      }),
      _e('content_block_stop', {'index': 0}),
      _e('message_delta', {
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 5},
      }),
      _e('message_stop', {}),
    ];

String _answerFor(Map<String, Object?> body) => weeklyAnswer(body['system'] as String, ((body['messages']! as List).single as Map)['content'] as String);

class FakeClaude extends ClaudeApi {
  FakeClaude() : super(key: 'sk-ant-test');
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) => streamWith(body);

  @override
  ClaudeCall streamWith(Map<String, Object?> body, {List<String> betas = const []}) {
    asked.add(body);
    return ClaudeCall(Stream<SseEvent>.fromIterable(_said(_answerFor(body))), () {});
  }
}

class FakeOpenAi implements AiProvider {
  final List<Map<String, Object?>> asked = [];

  @override
  AiCall stream(Map<String, Object?> body) {
    asked.add(body);
    return AiCall(Stream<SseEvent>.fromIterable(_said(_answerFor(body))), () {});
  }

  @override
  Future<AiError?> check() async => null;

  @override
  Future<List<AiModelInfo>> models() async => const [AiModelInfo('gpt-test')];
}

void main() {
  final kept = <MetricEvent>[];
  setUp(() {
    kept.clear();
    useActivity(Activity());
  });

  group('the week', () {
    test('starts on the locale’s first day: Monday in most places, Sunday in the US, Saturday in the Emirates', () {
      expect(firstWeekdayOf('GB'), DateTime.monday);
      expect(firstWeekdayOf('DE'), DateTime.monday);
      expect(firstWeekdayOf(null), DateTime.monday);
      expect(firstWeekdayOf('US'), DateTime.sunday);
      expect(firstWeekdayOf('jp'), DateTime.sunday);
      expect(firstWeekdayOf('AE'), DateTime.saturday);
      expect(firstWeekdayOf('MV'), DateTime.friday);
      expect(weekStartOf(thursday, DateTime.monday), DateTime(2026, 11, 2));
      expect(weekStartOf(thursday, DateTime.sunday), DateTime(2026, 11, 1));
      expect(weekStartOf(thursday, DateTime.saturday), DateTime(2026, 10, 31));
      // A first day is its own week's start, at midnight.
      expect(weekStartOf(DateTime(2026, 11, 2, 23, 59), DateTime.monday), DateTime(2026, 11, 2));
      expect(weekStartOf(DateTime(2026, 11, 1, 0, 1), DateTime.monday), DateTime(2026, 10, 26));
      // Across the clock change (the US's on 1 November 2026) the week is seven calendar days.
      expect(weekEndOf(DateTime(2026, 10, 26)), DateTime(2026, 11, 2));
      expect(weekTitle(DateTime(2026, 11, 2)), 'Week of 2 Nov 2026');
      expect(weekSpanWords(DateTime(2026, 11, 2)), '2 to 8 November 2026');
      expect(weekSpanWords(DateTime(2026, 10, 26)), '26 October to 1 November 2026');
      expect(weekSpanWords(DateTime(2025, 12, 29)), '29 December 2025 to 4 January 2026');
    });

    test('a week’s report is due on the day and time chosen after it ends, and the latest due is the one made', () {
      const monday8 = WeeklySettings();
      expect(monday8.dueFor(DateTime(2026, 10, 26)), DateTime(2026, 11, 2, 8));
      // A Sunday-first week ends on Saturday night: Monday's report comes the day after.
      expect(monday8.dueFor(DateTime(2026, 10, 25)), DateTime(2026, 11, 2, 8));
      expect(const WeeklySettings(weekday: DateTime.wednesday, hour: 18).dueFor(DateTime(2026, 10, 26)), DateTime(2026, 11, 4, 18));
      // A minute before Monday 8:00 the week before last is still the latest due; at 8:00, last week.
      expect(dueWeek(DateTime(2026, 11, 2, 7, 59), monday8, DateTime.monday), DateTime(2026, 10, 19));
      expect(dueWeek(DateTime(2026, 11, 2, 8), monday8, DateTime.monday), DateTime(2026, 10, 26));
      expect(dueWeek(thursday, monday8, DateTime.sunday), DateTime(2026, 10, 25));
      expect(nextDue(thursday, monday8, DateTime.monday), DateTime(2026, 11, 9, 8));
      expect(nextDue(DateTime(2026, 11, 2, 7), monday8, DateTime.monday), DateTime(2026, 11, 2, 8));
    });

    test('the settings: Monday at 8:00, AI and notification on, unless changed; read back whole', () {
      const plain = WeeklySettings();
      expect((plain.on, plain.weekday, plain.hour, plain.minute, plain.ai, plain.notify), (true, DateTime.monday, 8, 0, true, true));
      expect(plain.words, 'Mondays at 8:00');
      final changed = plain.copyWith(on: false, weekday: DateTime.friday, hour: 17, ai: false, notify: false);
      expect(WeeklySettings.fromJson(jsonDecode(jsonEncode(changed.toJson()))), changed);
      expect(WeeklySettings.fromJson({'hour': 99, 'weekday': 0}), const WeeklySettings(hour: 23, weekday: 1));
      expect(WeeklySettings.fromJson('nonsense'), plain);
    });
  });

  group('the counts', () {
    test('for the fixture week, the first time: written, edited, words, to-dos, meetings, the busiest day and the lists', () {
      final c = weeklyCounts(weekNotes(), start: weekStart);
      expect(c.written, 3, reason: 'the plan, the meeting, the recording; last week’s report is never counted');
      expect(c.edited, 2, reason: 'the reading list and the garden ideas');
      expect(c.words, [for (final n in weekNotes().take(3)) noteWords(n.body)].reduce((a, b) => a + b));
      expect(c.todosAdded, 2, reason: 'the boxes of the notes written this week');
      expect(c.todosDone, 2, reason: 'the boxes ticked in the notes touched this week');
      expect(c.todosOpen, 3, reason: 'every open box now');
      expect((c.meetings, c.recordings), (1, 1));
      expect(c.busiestDay, (day: DateTime(2026, 10, 27), count: 3));
      expect([for (final b in c.cameBack) (b.title, b.count)], [('Reading list', 5), ('Garden ideas', 2)]);
      expect([for (final s in c.stale) s.title], ['Tax forms'], reason: 'last edited 30 January: 270 days on is 27 October');
      expect([for (final t in c.unfinished) t.words], ['Return the library books', 'Ship the launch post', 'Water the plants']);
      expect(c.line, '5 notes · 2 to-dos done');
    });

    test('against what the last report saw: a to-do added, one done, saves since', () {
      final before = weeklySnapshot(weekNotes());
      final notes = [
        for (final note in weekNotes())
          if (note.id == 'plan')
            note.copyWith(body: note.body.replaceFirst('- [ ] Ship', '- [x] Ship'))
          else if (note.id == 'old')
            note.copyWith(body: '${note.body}\n- [ ] Renew the card', revision: 8)
          else
            note,
      ];
      final c = weeklyCounts(notes, start: weekStart, todosBefore: before.todos, revsBefore: before.revs);
      expect(c.todosDone, 1, reason: 'the launch post');
      expect(c.todosAdded, 1, reason: 'the card');
      expect(c.cameBack.single, (id: 'old', title: 'Reading list', count: 3), reason: 'the garden ideas had no save since');
    });

    test('a to-do kept or a stale note kept in the review is not raised again', () {
      final todo = openTodos('old', weekNotes()[3].body).single;
      final c = weeklyCounts(weekNotes(), start: weekStart, dismissed: {'todo:${todo.key}', 'stale:stale'});
      expect([for (final t in c.unfinished) t.words], isNot(contains('Return the library books')));
      expect(c.stale, isEmpty);
    });

    test('a week with nothing written or edited is empty', () {
      expect(weeklyCounts(weekNotes(), start: DateTime(2026, 8, 3)).empty, isTrue);
    });
  });

  group('the report', () {
    test('is a note in the Weekly reports journal, plain Markdown: the numbers, the lists as links, no boxes', () async {
      final world = World();
      final service = await ready(world.service());
      final report = await service.lookWeekly();
      expect(report, isNotNull);
      expect(report!.week, '2026-10-26');
      final note = world.library.noteOf(report.noteId)!;
      expect(noteTitle(note.body), 'Week of 26 Oct 2026');
      expect(note.body, startsWith('---\ntitle: "Week of 26 Oct 2026"\ndate: 2026-10-26\nwrapped-week: 2026-10-26\n---\n# Week of 26 Oct 2026\n'));
      expect(note.body, contains('## In numbers\n\n- 3 notes written, 2 older notes edited\n'));
      expect(note.body, contains('- 2 to-dos done, 2 added, 3 still open\n- 1 meeting, 1 recording\n- Busiest day: Tuesday 27 October, 3 notes'));
      expect(note.body, contains('## Came back to\n\n- [[Reading list]], 5 saves\n- [[Garden ideas]], 2 saves'));
      expect(note.body, contains('## Gone stale this week\n\n- [[Tax forms]], not edited since 30 Jan 2026'));
      expect(note.body, contains('## Worth a look\n\n- Return the library books, in [[Reading list]]'));
      expect(note.body, isNot(contains('[ ]')), reason: 'a report’s lines are never to-dos');
      expect(note.body, isNot(contains('What it was about')), reason: 'no AI is connected');
      // Filed in the journal, which it made, and the journal and the report are not counted as the person's notes.
      final journal = world.library.value.singleWhere((n) => isJournalBody(n.body));
      expect(noteTitle(journal.body), 'Weekly reports');
      expect(journal.body, contains('wrapped: weekly'));
      expect([for (final c in chaptersOf(journal.body)) c.title], ['Week of 26 Oct 2026']);
      expect(service.ownNotes.map((n) => n.id), isNot(anyOf(contains(note.id), contains(journal.id), contains('report-old'))));
      service.dispose();
    });

    test('a second week goes in the same journal, with what the last report saw to compare with', () async {
      final world = World();
      final service = await ready(world.service());
      await service.lookWeekly();
      world.library.value = [
        ...world.library.value,
        n('next', '# Next week\n\n- [ ] Book the hall', written: at(2026, 11, 3)),
      ];
      world.now = DateTime(2026, 11, 9, 9);
      final second = await service.lookWeekly();
      expect(second!.week, '2026-11-02');
      final journal = world.library.value.singleWhere((n) => isJournalBody(n.body));
      expect([for (final c in chaptersOf(journal.body)) c.title], ['Week of 26 Oct 2026', 'Week of 2 Nov 2026']);
      expect(world.library.noteOf(second.noteId)!.body, contains('- 0 to-dos done, 1 added, 4 still open'));
      service.dispose();
    });

    test('a missed week is made at the next look, and only the latest: a month away brings one report', () async {
      final world = World(now: DateTime(2026, 11, 30, 10));
      world.library.value = [
        ...world.library.value,
        n('late', '# Late November\n\nStill here.', written: at(2026, 11, 25)),
      ];
      final service = await ready(world.service());
      final report = await service.lookWeekly();
      expect(report!.week, '2026-11-23');
      expect(world.reports(), hasLength(1));
      expect(await service.lookWeekly(), isNull);
      service.dispose();
    });

    test('is never made twice: not again here, not when its note came from another device, not while one is made', () async {
      final world = World();
      final service = await ready(world.service());
      final both = await Future.wait([service.lookWeekly(), service.lookWeekly()]);
      expect(both.whereType<WeeklyReport>(), hasLength(1));
      expect(await service.lookWeekly(), isNull);
      expect(await service.makeWeekly(weekStart), isNull);
      expect(world.reports(), hasLength(1));
      service.dispose();

      // Another device made it; it synced here before this one looked.
      final other = World();
      other.library.value = [...other.library.value, n('synced', '---\ntitle: "Week of 26 Oct 2026"\nwrapped-week: 2026-10-26\n---\n# Week of 26 Oct 2026', written: at(2026, 11, 2, 8))];
      final here = await ready(other.service());
      expect(await here.lookWeekly(), isNull);
      expect(other.reports().map((n) => n.id), ['synced']);
      expect(here.state.weekly.made('2026-10-26'), isTrue);
      here.dispose();
    });

    test('nothing is made with weekly reports off, with Wrapped off, or for an empty week', () async {
      final world = World();
      final service = await ready(world.service());
      service.setWeekly(service.weeklySettings.copyWith(on: false));
      expect(await service.lookWeekly(), isNull);
      service.setWeekly(service.weeklySettings.copyWith(on: true));
      // A week with nothing in it: no note, and not looked at again.
      world.now = DateTime(2026, 8, 12);
      expect(await service.lookWeekly(), isNull);
      expect(world.reports(), isEmpty);
      expect(service.state.weekly.made('2026-08-03'), isTrue);
      service.dispose();
      final off = WrappedService(library: world.library, workspaces: world.workspaces, trash: world.trash, store: WrappedStore(file: MemoryConfigFile()), on: () => false, clock: () => thursday, ais: () async => const []);
      await off.store.reread();
      expect(await off.lookWeekly(), isNull);
      off.dispose();
    });

    test('says so with a notification only where the phone allows it and Notify me is on', () async {
      final world = World();
      final service = await ready(world.service());
      final report = await service.lookWeekly();
      expect(world.told.posted.single, (id: 'wrapped-weekly-2026-10-26', title: 'Your week in notes is ready', text: '5 notes · 2 to-dos done', link: 'ghostmd://note/${report!.noteId}'));
      service.dispose();

      final blocked = World()..told.now = NoticesState.blocked;
      final kept = await ready(blocked.service());
      expect(await kept.lookWeekly(), isNotNull);
      expect(blocked.told.posted, isEmpty);
      kept.dispose();

      final quiet = World();
      final hush = await ready(quiet.service());
      hush.setWeekly(hush.weeklySettings.copyWith(notify: false));
      expect(await hush.lookWeekly(), isNotNull);
      expect(quiet.told.posted, isEmpty);
      hush.dispose();
    });
  });

  group('the AI', () {
    late ClaudeSettings claude;
    late AiProviderSettings openAi;
    late AssistantChoice choice;
    late FakeClaude claudeApi;
    late FakeOpenAi openAiApi;

    setUp(() async {
      claude = ClaudeSettings(MemorySecureStore());
      openAi = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI', fallbackModels: const [AiModelInfo('gpt-test')]);
      claudeApi = FakeClaude();
      openAiApi = FakeOpenAi();
      choice = AssistantChoice(
        store: MemorySecureStore(),
        claude: claude,
        claudeOn: () => true,
        claudeSwitchedOn: () => true,
        others: [AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi, switchedOn: () => true, allowed: () => true, client: (settings) => openAiApi)],
      );
      await choice.load();
      await claude.setKey('sk-ant-test-0123456789abcdef');
    });

    Future<List<CleanupAi>> connected() => connectedAis(choice: choice, localOnly: false, deviceModel: () async => null, claudeApi: (_) => claudeApi);

    test('with Claude connected on the person’s key, Wrapped’s asks go to Claude: the gists, then the week’s one ask', () async {
      final world = World();
      final service = await ready(world.service(connected: connected, choice: choice));
      service.store.change((now) => now.copyWith(weekly: now.weekly.copyWith(allowed: {'claude'})));
      final report = await service.lookWeekly();
      expect(service.ai!.name, 'Claude');
      expect(claudeApi.asked.where((b) => b['system'] == readSystem), isNotEmpty, reason: 'the week’s notes read for their gists');
      final weekly = claudeApi.asked.singleWhere((b) => b['system'] == weeklySystem);
      final sent = ((weekly['messages']! as List).single as Map)['content'] as String;
      expect(sent, contains('“Launch plan” · no folder · new · About Launch plan'));
      expect(sent, contains('Ship the launch post (in “Launch plan”)'));
      expect(sent, isNot(contains('The post goes out on Friday')), reason: 'gists and counts, never a note’s words');
      expect(openAiApi.asked, isEmpty);
      expect(report!.ai, isTrue);
      expect(report.summary, startsWith('You spent the week on the launch.'));
      expect(report.steps.map((s) => s.kind), [WeeklyStepKind.checkOff, WeeklyStepKind.link, WeeklyStepKind.look], reason: 'the step naming no real note left out');
      final body = world.library.noteOf(report.noteId)!.body;
      expect(body, contains('## What it was about\n\nYou spent the week on the launch.'));
      expect(body, contains('Themes: launch, garden'));
      expect(body, contains('## Next steps\n\n1. The launch post looks shipped\n2. Two notes about the garden path: [[A thought on the walk]], [[Garden ideas]]\n3. The sync is worth a second look: [[Launch sync]]'));
      service.dispose();
    });

    test('Which AI: OpenAI chosen on the page is asked instead, and the choice is kept in Wrapped’s file', () async {
      await openAi.setKey('sk-test-0123456789abcdef');
      final world = World();
      final service = await ready(world.service(connected: connected, choice: choice));
      await service.readAis();
      expect([for (final ai in service.ais) ai.name], ['Claude', 'OpenAI']);
      expect(service.ai!.id, 'claude', reason: 'the app’s own choice first');
      service.chooseAi('openai');
      service.store.change((now) => now.copyWith(weekly: now.weekly.copyWith(allowed: {'openai'})));
      await service.lookWeekly();
      expect(openAiApi.asked.where((b) => b['system'] == weeklySystem), hasLength(1));
      expect(claudeApi.asked, isEmpty);
      await service.store.written;
      expect(WrappedState.decode(await world.file.read()).chosenAi, 'openai');
      service.dispose();
    });

    test('a cloud AI not yet said yes to: the report is the counts alone, and says the AI summary can be added', () async {
      final world = World();
      final service = await ready(world.service(connected: connected, choice: choice));
      final report = await service.lookWeekly();
      expect(service.weeklyAsks, isTrue);
      expect(claudeApi.asked, isEmpty, reason: 'nothing spent before the yes');
      expect(report!.ai, isFalse);
      expect(world.library.noteOf(report.noteId)!.body, contains('Add the AI summary in Wrapped to have Claude write what the week was about.'));
      expect(service.weeklyCostWords, matches(RegExp(r'^~\d+k? tokens · about \$\d+\.\d\d a week$')));
      service.dispose();
    });

    test('Include AI summary off: the counts alone, nothing sent', () async {
      final world = World();
      final service = await ready(world.service(connected: connected, choice: choice));
      service.store.change((now) => now.copyWith(weekly: now.weekly.copyWith(allowed: {'claude'}, settings: const WeeklySettings(ai: false))));
      final report = await service.lookWeekly();
      expect(report!.ai, isFalse);
      expect(claudeApi.asked, isEmpty);
      expect(world.library.noteOf(report.noteId)!.body, isNot(contains('Add the AI summary')));
      service.dispose();
    });

    testWidgets('Add the AI summary (the device’s own model asks nothing first) writes it into the report, edits kept', (tester) async {
      final world = World();
      final asked = <Asked>[];
      final device = scriptedAi(weeklyAnswer, id: 'device', name: 'On this device', local: true, asked: asked);
      final service = world.service(ais: [device]);
      late BuildContext at;
      await tester.runAsync(() async {
        await service.store.reread();
        service.setWeekly(service.weeklySettings.copyWith(ai: false));
        await service.lookWeekly();
      });
      final report = service.weeklyReport!;
      final note = world.library.noteOf(report.noteId)!;
      await tester.runAsync(() => world.library.update(note.id, '${note.body}\nMy own line.\n', note.revision));
      service.setWeekly(service.weeklySettings.copyWith(ai: true));
      await tester.pumpWidget(Builder(builder: (context) {
        at = context;
        return const SizedBox.shrink();
      }));
      await tester.runAsync(() => service.allowWeeklyAi(at));
      final body = world.library.noteOf(report.noteId)!.body;
      expect(body, contains('## What it was about'));
      expect(body.indexOf('## What it was about'), lessThan(body.indexOf('## In numbers')));
      expect(body, contains('My own line.'));
      expect(body, contains('## Next steps'));
      expect(service.weeklyReport!.ai, isTrue);
      expect(service.state.weekly.allowed, contains('device'));
      service.dispose();
    });

    test('a next step is Wrapped’s own press, and Undo takes it back', () async {
      final world = World();
      final device = scriptedAi(weeklyAnswer, id: 'device', name: 'On this device', local: true);
      final service = await ready(world.service(ais: [device]));
      final report = await service.lookWeekly();
      expect(report!.steps.first.kind, WeeklyStepKind.checkOff);
      final done = await service.applyStep(0);
      expect(done.done, 1);
      expect(world.library.noteOf('plan')!.body, contains('- [x] Ship the launch post'));
      expect(service.weeklyReport!.steps.first.record, isNotNull);
      expect(await service.undoStep(0), 'Undone.');
      expect(world.library.noteOf('plan')!.body, contains('- [ ] Ship the launch post'));
      await service.applyStep(1);
      expect(world.library.noteOf('voice')!.body, contains('[[Garden ideas]]'));
      service.dismissStep(2);
      expect(service.weeklyReport!.steps[2].dismissed, isTrue);
      service.dispose();
    });

    test('the estimate: tokens a week, dollars where Claude’s price table knows the model, nothing on the device', () {
      final cloud = scriptedAi(weeklyAnswer, id: 'openai', name: 'OpenAI');
      expect(weeklyEstimate(cloud, toGist: 6, notes: 6, todos: 4).words, matches(RegExp(r'^~\d+k? tokens on your OpenAI key a week$')));
      final device = scriptedAi(weeklyAnswer, id: 'device', name: 'On this device', local: true);
      expect(weeklyEstimate(device, toGist: 6, notes: 6, todos: 4).words, 'on this device, nothing sent');
    });
  });

  group('on screen', () {
    Widget paper(Widget child) => Builder(
          builder: (context) => Material(
            type: MaterialType.transparency,
            child: ColoredBox(color: context.tokens.color('app-paper'), child: BackScope(child: SettingsPaneScope(finder: SettingsFinder(), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)))),
          ),
        );

    Future<void> away(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> settle(WidgetTester tester, [int beats = 6]) async {
      for (var i = 0; i < beats; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<WrappedService> made(WidgetTester tester, World world, {List<CleanupAi>? ais}) async {
      final service = world.service(ais: ais);
      await tester.runAsync(() async {
        await service.store.reread();
        await service.lookWeekly();
      });
      return service;
    }

    testWidgets('the home card reads This week with View report, which opens the note and is counted', (tester) async {
      final world = World();
      final service = await made(tester, world);
      final opened = <String>[];
      wrappedOpenNote = (id, _) => opened.add(id);
      addTearDown(() => wrappedOpenNote = null);
      expect(wrappedCardState(service), WrappedCardState.thisWeek);
      await pumpApp(tester, home: paper(WrappedHomeCard(service: service)));
      await settle(tester);
      expect(find.byKey(const ValueKey('wrapped-home-card-thisWeek')), findsOneWidget);
      expect(find.text('New · This week'), findsOneWidget);
      expect(find.text('Your week in notes: 5 notes · 2 to-dos done.'), findsOneWidget);
      await tester.tap(find.text('View report'));
      await tester.pump();
      expect(opened, [service.weeklyReport!.noteId]);
      expect(service.weeklyReport!.viewed, isTrue);
      expect(find.text('This week'), findsOneWidget);
      // A week on, with no new report, it reads as before.
      world.now = thursday.add(const Duration(days: 8));
      service.dispose();
      expect(wrappedCardState(service), WrappedCardState.notMade);
      await away(tester);
    });

    testWidgets('Which AI: the AI and its model, and a choice where more than one is connected', (tester) async {
      final world = World();
      final service = world.service(ais: [scriptedAi(weeklyAnswer, id: 'claude', name: 'Claude'), scriptedAi(weeklyAnswer, id: 'device', name: 'On this device', local: true)]);
      await tester.runAsync(() async {
        await service.store.reread();
        await service.readAis();
      });
      await pumpApp(tester, home: paper(ListenableBuilder(listenable: service, builder: (_, _) => WrappedWhichAi(service: service))));
      await settle(tester);
      final row = find.byKey(const ValueKey('wrapped-which-ai'));
      expect(find.descendant(of: row, matching: find.text('Claude')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('fake-1 · With your key')), findsOneWidget);
      await tester.tap(find.descendant(of: row, matching: find.text('Change')));
      await settle(tester, 2);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-ai-device')), matching: find.byType(Pick)));
      await settle(tester, 2);
      expect(service.ai!.id, 'device');
      expect(service.state.chosenAi, 'device');
      expect(find.descendant(of: row, matching: find.text('On this device')), findsOneWidget);
      service.dispose();
      await away(tester);
    });

    testWidgets('one AI: shown, with nothing to choose', (tester) async {
      final world = World();
      final service = world.service(ais: [scriptedAi(weeklyAnswer, id: 'claude', name: 'Claude')]);
      await tester.runAsync(service.readAis);
      await pumpApp(tester, home: paper(WrappedWhichAi(service: service)));
      await settle(tester);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      service.dispose();
      await away(tester);
    });

    testWidgets('the settings: on, the day, the time, the AI summary and Notify me, each kept', (tester) async {
      final world = World();
      final service = world.service(ais: [scriptedAi(weeklyAnswer, id: 'claude', name: 'Claude')]);
      await tester.runAsync(() async {
        await service.store.reread();
        await service.readAis();
      });
      await pumpApp(tester, size: const Size(430, 2000), home: paper(ListenableBuilder(listenable: service, builder: (_, _) => WrappedWeeklySettings(service: service))));
      await settle(tester);
      expect(find.textContaining('Mondays at 8:00'), findsOneWidget);
      await tester.tap(find.text('Day'));
      await settle(tester, 2);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-weekly-day-5')), matching: find.byType(Pick)));
      await settle(tester, 2);
      await tester.tap(find.text('Time'));
      await settle(tester, 2);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-weekly-hour-17')), matching: find.byType(Pick)));
      await settle(tester, 2);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-weekly-ai')), matching: find.byType(GlacierSwitch)));
      await settle(tester, 2);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-weekly-notify')), matching: find.byType(GlacierSwitch)));
      await settle(tester, 2);
      expect(service.weeklySettings, const WeeklySettings(weekday: DateTime.friday, hour: 17, ai: false, notify: false));
      expect(find.textContaining('Fridays at 17:00'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-weekly-on')), matching: find.byType(GlacierSwitch)));
      await settle(tester, 2);
      expect(service.weeklySettings.on, isFalse);
      expect(find.text('Day'), findsNothing);
      await tester.runAsync(() => service.store.written);
      expect(WrappedState.decode(await tester.runAsync<String?>(() => world.file.read())).weekly.settings.weekday, DateTime.friday);
      service.dispose();
      await away(tester);
    });

    for (final simple in [false, true]) {
      testWidgets('its Settings page${simple ? ' in Simple: This week shows, the weekly settings behind More' : ': This week, Which AI and the weekly settings'}', (tester) async {
        final world = World();
        final service = await made(tester, world, ais: [scriptedAi(weeklyAnswer, id: 'device', name: 'On this device', local: true)]);
        WrappedService.current = service;
        addTearDown(() => WrappedService.current = null);
        await pumpApp(tester, size: const Size(430, 3000), prefs: AppPreferences(theme: 'light', experience: simple ? 'simple' : 'advanced'), home: paper(WrappedPane(service: service)));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await settle(tester);
        expect(find.byKey(const ValueKey('wrapped-week')), findsOneWidget);
        expect(find.textContaining('You spent the week on the launch.'), findsOneWidget);
        expect(find.byKey(const ValueKey('wrapped-step-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('wrapped-which-ai')), findsOneWidget);
        expect(find.byKey(const ValueKey('wrapped-weekly-settings')), simple ? findsNothing : findsOneWidget);
        if (simple) {
          await tester.tap(find.descendant(of: find.byKey(const ValueKey('wrapped-pane-more')), matching: find.text('Show')));
          await settle(tester, 2);
          expect(find.byKey(const ValueKey('wrapped-weekly-settings')), findsOneWidget);
        }
        service.dispose();
        await away(tester);
      });
    }
  });

  test('the analytics: wrapped_weekly_made and wrapped_weekly_viewed carry count buckets only', () async {
    expect(MetricEvent.wrappedWeeklyMade.wire, 'wrapped_weekly_made');
    expect(MetricEvent.wrappedWeeklyViewed.wire, 'wrapped_weekly_viewed');
    expect(MetricEvent.wrappedWeeklyMade.props.keys.toSet(), {'notes', 'todos', 'steps'});
    expect(MetricEvent.wrappedWeeklyViewed.props.keys.toSet(), {'steps'});
    for (final event in [MetricEvent.wrappedWeeklyMade, MetricEvent.wrappedWeeklyViewed]) {
      for (final prop in event.props.values) {
        for (final bucket in countBuckets) {
          expect(prop.allows(bucket), isTrue);
        }
        expect(prop.allows(5), isFalse);
        expect(prop.allows('Week of 2 Nov 2026'), isFalse);
      }
    }
    // What a report made, and viewed, sends.
    final metrics = Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: (_, _) async => true, sendEvery: const Duration(hours: 1), batchSize: 1000);
    useMetrics(metrics);
    addTearDown(() => useMetrics(Metrics.off()));
    // What the tests before tracked into the client that was off is handed to this one: only what follows is read.
    final earlier = metrics.queued.length;
    final world = World();
    final service = await ready(world.service());
    await service.lookWeekly();
    service.viewWeekly();
    Map<Object?, Object?> sent(String wire) => metrics.queued.skip(earlier).singleWhere((e) => e['event'] == wire)['properties']! as Map;
    expect(sent('wrapped_weekly_made'), allOf(containsPair('notes', '2-5'), containsPair('todos', '2-5'), containsPair('steps', '0')));
    expect(sent('wrapped_weekly_viewed'), containsPair('steps', '0'));
    for (final wire in ['wrapped_weekly_made', 'wrapped_weekly_viewed']) {
      expect(sent(wire).keys.where((k) => !(k as String).startsWith(r'$') && k != 'distinct_id').toSet(), isNot(contains('title')));
    }
    service.dispose();
  });
}
