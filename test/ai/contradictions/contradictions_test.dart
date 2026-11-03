// The contradiction finder's pure parts and its run (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder:
// spots when a newer note disagrees with an older one (e.g. 'release is Thursday' in one, 'release moved to Monday' in a
// later meeting) and flags the stale one inline"). No real AI is ever asked: ScriptedAi answers.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/contradictions/ai.dart';
import 'package:ghost_md/ai/contradictions/candidates.dart';
import 'package:ghost_md/ai/contradictions/compare.dart';
import 'package:ghost_md/ai/contradictions/findings.dart';
import 'package:ghost_md/ai/contradictions/runner.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';

import 'support.dart';

final DateTime now = DateTime.utc(2026, 11, 9, 10);

ContradictionRunner runnerOver(List<Note> notes, ContradictionAi? ai, {MemoryStored? store, Activity? activity, ContradictionSettings? settings}) {
  final memory = store ?? MemoryStored();
  final runner = ContradictionRunner(notes: () => notes, pickAi: () async => ai, store: memory, clock: () => now, activity: activity ?? Activity(clock: () => now));
  if (settings != null) runner.setSettings(settings);
  return runner;
}

void main() {
  group('candidates', () {
    test('a note is read for its links, tags, people, title words, dates and numbers', () {
      final keys = noteKeys('# Pricing review\n\nSee [[Launch plan]]. @sam says \$40k by Nov 12, or 2026-11-20, on Thursday. 12% off. v2.4.1 #pricing');
      expect(keys.links, {'launch plan'});
      expect(keys.tags, {'pricing'});
      expect(keys.people, {'sam'});
      expect(keys.titleWords, {'pricing', 'review'});
      expect(keys.dates, containsAll(['nov 12', '2026-11-20', 'thursday']));
      expect(keys.facts, containsAll([r'$40k', '12%', 'v2.4.1']));
    });

    test('the plan and the standup that moved its release are a pair, older first', () {
      final pairs = candidatePairs([standup, plan]);
      expect(pairs, hasLength(1));
      expect(pairs.single.older.id, 'plan');
      expect(pairs.single.newer.id, 'standup');
      expect(pairs.single.score, greaterThanOrEqualTo(pairNeeds));
    });

    test('notes that share nothing, or have no facts, are not paired', () {
      final shopping = note('shop', '# Shopping\n\n- Eggs\n- Milk on Thursday', day: 3);
      final poem = note('poem', '# Release\n\nA release of breath #release', day: 4);
      expect(candidatePairs([plan, shopping]), isEmpty);
      expect(candidatePairs([plan, poem]), isEmpty, reason: 'the poem has no date or number');
    });

    test('a team’s notes are never paired with personal ones, nor with another team’s', () {
      final teamPlan = note('team-plan', plan.body, day: 1, path: 'orgs/HelloTrade/Plans/Release plan.md');
      final otherTeam = note('other', standup.body, day: 8, path: 'orgs/Acme/Standup.md');
      final teamStandup = note('team-standup', standup.body, day: 9, path: 'orgs/HelloTrade/Standup.md');
      final pairs = candidatePairs([plan, standup, teamPlan, otherTeam, teamStandup]);
      final ids = {for (final p in pairs) '${p.older.id}>${p.newer.id}'};
      expect(ids, {'plan>standup', 'team-plan>team-standup'});
      expect(candidatePairs([plan, standup, teamPlan, teamStandup], allowed: (scope) => scope.personal).map((p) => p.older.id), ['plan']);
    });

    test('Within each folder only keeps personal pairs inside a top folder', () {
      final work = note('work', standup.body, day: 7, path: 'workspaces/Work/Standup.md');
      expect(candidatePairs([plan, work]), hasLength(1));
      expect(candidatePairs([plan, work], byFolder: true), isEmpty);
    });

    test('a pair checked at the same revisions is skipped; an edit since brings it back', () {
      expect(candidatePairs([plan, standup], checked: {'plan|standup': '1:1'}), isEmpty);
      expect(candidatePairs([plan, note('standup', standup.body, day: 7, revision: 2)], checked: {'plan|standup': '1:1'}), hasLength(1));
    });

    test('archived and trashed notes are left out, and When a note is saved asks only of its pairs', () {
      final archived = Note(id: 'standup', body: standup.body, createdAt: 0, updatedAt: standup.updatedAt, archivedAt: 5, path: 'Inbox/s.md');
      expect(candidatePairs([plan, archived]), isEmpty);
      expect(candidatePairs([plan, note('standup', standup.body, day: 7, path: '.trash/Inbox/standup.md')]), isEmpty);
      final third = note('retro', '# Retro\n\nRelease is Monday Nov 16 #release', day: 9);
      expect(candidatePairs([plan, standup, third], touching: {'retro'}).every((p) => p.older.id == 'retro' || p.newer.id == 'retro'), isTrue);
    });

    test('the cap keeps the strongest pairs', () {
      final many = [for (var i = 0; i < 20; i++) note('n$i', '# Release $i\n\nRelease is Nov ${i + 1} #release @sam', day: i)];
      expect(candidatePairs(many, limit: 5), hasLength(5));
    });

    test('an excerpt sends the lines with facts or shared keys, numbered, and never the front matter', () {
      final withFront = note('f', '---\nsecret: yes 2026-01-01\n---\n# Release plan\n\nRelease is Thursday Nov 12.\nThe sky is blue.', day: 0);
      final excerpt = excerptOf(withFront, {'release'});
      expect(excerpt, contains('Title: Release plan'));
      expect(excerpt, contains('6: Release is Thursday Nov 12.'));
      expect(excerpt, isNot(contains('secret')));
      expect(excerpt, isNot(contains('sky')));
    });
  });

  group('the AI’s answer', () {
    final pairs = candidatePairs([plan, standup]);

    test('the prompt names A as the older and B as the newer, with their days', () {
      final prompt = comparePrompt(pairs);
      expect(prompt, contains('Pair 1'));
      expect(prompt, contains('A (older, edited 2026-11-01)'));
      expect(prompt, contains('B (newer, edited 2026-11-08)'));
      expect(prompt, contains('Release is Thursday'));
    });

    test('a good finding is read, inside a code fence and words around it too', () {
      for (final answer in [releaseMoved(), 'Sure!\n```json\n${releaseMoved()}\n```', 'Here: ${releaseMoved()} done']) {
        final found = readFindings(answer, pairs, now: now);
        expect(found, hasLength(1), reason: answer);
        expect(found.single.olderId, 'plan');
        expect(found.single.newerId, 'standup');
        expect(found.single.olderTitle, 'Release plan');
        expect(found.single.newerTitle, 'Standup');
      }
    });

    test('every way an answer can be wrong is dropped', () {
      String with_(String field, Object value) {
        final base = {'pair': 1, 'older': 'A', 'older_quote': 'Release is Thursday', 'newer': 'B', 'newer_quote': 'Release moved to Monday', 'what': 'Moved.', 'confidence': 0.9};
        base[field] = value;
        return '{"findings": [${_json(base)}]}';
      }

      final wrong = {
        'not JSON': 'no idea',
        'no findings list': '{"found": []}',
        'an unknown pair': with_('pair', 2),
        'pair zero': with_('pair', 0),
        'a fractional pair': with_('pair', 1.5),
        'older and newer swapped': with_('older', 'B'),
        'an invented older quote': with_('older_quote', 'Release is Friday'),
        'an invented newer quote': with_('newer_quote', 'Release cancelled'),
        'a quote too short to mean anything': with_('older_quote', 'is'),
        'confidence as words': with_('confidence', 'high'),
        'confidence over 1': with_('confidence', 1.5),
        'confidence under the threshold': with_('confidence', 0.6),
        'no what': with_('what', '  '),
      };
      for (final MapEntry(:key, :value) in wrong.entries) {
        expect(readFindings(value, pairs, now: now), isEmpty, reason: key);
      }
    });

    test('quotes are matched with spaces, case and curly quotes made alike', () {
      final found = readFindings(releaseMoved(older: 'release  IS thursday', newer: 'release moved to monday'), pairs, now: now);
      expect(found, hasLength(1));
      expect(quoteIn('It’s “done” now', 'it\'s "done"'), isTrue);
    });

    test('the threshold is the person’s, and one finding a line, the surest', () {
      expect(readFindings(releaseMoved(confidence: 0.75), pairs, now: now), isEmpty);
      expect(readFindings(releaseMoved(confidence: 0.75), pairs, now: now, threshold: 0.7), hasLength(1));
      final two = '{"findings": [${_finding(0.85)}, ${_finding(0.95)}]}';
      final found = readFindings(two, pairs, now: now);
      expect(found, hasLength(1));
      expect(found.single.confidence, 0.95);
    });
  });

  group('kept in the files', () {
    final finding = readFindings(releaseMoved(), candidatePairs([plan, standup]), now: now).single;

    test('a book is written and read back, findings and checks', () {
      final book = const FindingsBook().adding([finding], checked: {'plan|standup': '1:1'});
      final again = FindingsBook.decode(book.encode());
      expect(again.findings.single.key, finding.key);
      expect(again.findings.single.what, finding.what);
      expect(again.checked, {'plan|standup': '1:1'});
      expect(book.encode(), contains('"version": 1'));
      expect(FindingsBook.decode('not json').findings, isEmpty);
    });

    test('a dismissed finding stays dismissed when it is found again', () {
      final dismissed = const FindingsBook().adding([finding]).setting(finding.key, FindingState.dismissed);
      expect(dismissed.settled(finding), isTrue);
      final again = dismissed.adding([finding]);
      expect(again.open, isEmpty);
      expect(again.findings.single.state, FindingState.dismissed);
    });

    test('a personal book is in the Library’s .glyph, a team’s in its own folder', () {
      expect(const ContradictionScope.personal().fileIn('/L'), '/L/.glyph/contradictions.json');
      expect(const ContradictionScope.org('HelloTrade').fileIn('/L'), '/L/orgs/HelloTrade/.glyph/contradictions.json');
      expect(scopeOfPath('orgs/HelloTrade/Plans/a.md').org, 'HelloTrade');
      expect(scopeOfPath('workspaces/Work/Clients/a.md', byFolder: true).folder, 'workspaces/Work');
      expect(scopeOfPath('Inbox/a.md').personal, isTrue);
    });
  });

  group('Mark superseded', () {
    final finding = readFindings(releaseMoved(), candidatePairs([plan, standup]), now: now).single;

    test('writes one readable blockquote under the stale line', () {
      final body = withSuperseded(plan.body, finding, now);
      expect(body.split('\n'), [
        '# Release plan',
        '',
        'Release is Thursday Nov 12.',
        '> Superseded by [[Standup]] (2026-11-09): “Release moved to Monday”',
        '- Owner: @sam',
        '#release',
      ]);
    });

    test('under a list item it is indented into the item, so the list holds', () {
      final listed = note('l', '# Plan\n\n- [ ] Release is Thursday Nov 12\n- Next', day: 0);
      final body = withSuperseded(listed.body, finding, now);
      expect(body.split('\n')[3], '      > Superseded by [[Standup]] (2026-11-09): “Release moved to Monday”');
    });

    test('a marked line is not found again, nor marked twice', () {
      final once = withSuperseded(plan.body, finding, now);
      expect(lineOfQuote(once, finding.olderQuote), isNull);
      expect(withSuperseded(once, finding, now), once);
    });
  });

  group('which AI', () {
    final device = ScriptedAi([], onDevice: true, name: 'this device');
    final cloud = ScriptedAi([], name: 'Claude');

    test('Local only takes the model on the device and never a cloud one', () {
      expect(pickContradictionAi(localOnly: true, chatBy: 'claude', deviceReady: true, device: () => device, cloud: (_) => cloud), same(device));
      expect(pickContradictionAi(localOnly: true, chatBy: 'claude', deviceReady: false, device: () => device, cloud: (_) => cloud), isNull);
      expect(noAiWords(localOnly: true), contains('Local only'));
    });

    test('otherwise whoever answers the chat, then the device', () {
      expect(pickContradictionAi(localOnly: false, chatBy: 'openai', deviceReady: true, device: () => device, cloud: (by) => by == 'openai' ? cloud : device), same(cloud));
      expect(pickContradictionAi(localOnly: false, chatBy: null, deviceReady: true, device: () => device, cloud: (_) => cloud), same(device));
      expect(pickContradictionAi(localOnly: false, chatBy: null, deviceReady: false, device: () => device, cloud: (_) => cloud), isNull);
    });
  });

  group('the run', () {
    test('finds, keeps in the book, and says it in the tray', () async {
      final activity = Activity(clock: () => now);
      final ai = ScriptedAi([releaseMoved()]);
      final store = MemoryStored();
      final runner = runnerOver([plan, standup], ai, store: store, activity: activity);
      final events = <JobEventKind>[];
      final heard = activity.events.listen((event) {
        if (event.job?.id == contradictionsJobId) events.add(event.kind);
      });
      expect(await runner.run(personStarted: true), RunEnd.done);
      await heard.cancel();
      expect(events, containsAllInOrder([JobEventKind.started, JobEventKind.ended]));
      expect(runner.open.single.olderQuote, 'Release is Thursday');
      expect(runner.openOn('plan'), hasLength(1));
      expect(runner.staleNotes, 1);
      expect(runner.settings.ranOnce, isTrue);
      expect(store.readText('${contradictionsBookKey}personal'), contains('Release is Thursday'));
      // Asked again, the pair was checked at these revisions: nothing is asked.
      expect(await runner.run(), RunEnd.nothing);
      expect(ai.asked, hasLength(1));
    });

    test('Not a conflict is remembered across a fresh runner and a fresh find', () async {
      final store = MemoryStored();
      final first = runnerOver([plan, standup], ScriptedAi([releaseMoved()]), store: store);
      await first.run(personStarted: true);
      await first.dismiss(first.open.single);
      expect(first.open, isEmpty);
      // Another device's restore, or an edit since: the same disagreement is found again, and stays dismissed.
      final edited = note('standup', standup.body, day: 7, revision: 2);
      final second = runnerOver([plan, edited], ScriptedAi([releaseMoved()]), store: store);
      await second.run();
      expect(second.open, isEmpty);
    });

    test('Mark superseded from the page writes the note and settles the finding', () async {
      String? written;
      final runner = ContradictionRunner(notes: () => [plan, standup], pickAi: () async => ScriptedAi([releaseMoved()]), store: MemoryStored(), clock: () => now, activity: Activity(clock: () => now), writeNote: (id, change) async => written = change(plan.body));
      await runner.run(personStarted: true);
      await runner.markSuperseded(runner.open.single);
      expect(written, contains('> Superseded by [[Standup]] (2026-11-09)'));
      expect(runner.open, isEmpty);
    });

    test('a team’s notes are never in a personal prompt, are read by default, and not with Organization notes off', () async {
      final teamPlan = note('team-plan', plan.body.replaceAll('Release', 'Launch'), day: 1, path: 'orgs/HelloTrade/Plan.md');
      final teamStandup = note('team-standup', standup.body.replaceAll('Release', 'Launch'), day: 9, path: 'orgs/HelloTrade/Standup.md');
      final notes = [plan, standup, teamPlan, teamStandup];

      final off = ScriptedAi([]);
      await runnerOver(notes, off, settings: const ContradictionSettings(orgs: false)).run(personStarted: true);
      expect(off.asked, hasLength(1));
      expect(off.asked.single, isNot(contains('Launch')));

      final on = ScriptedAi([], reply: (prompt) => prompt.contains('Launch') ? releaseMoved(older: 'Launch is Thursday', newer: 'Launch moved to Monday') : releaseMoved());
      final store = MemoryStored();
      final runner = runnerOver(notes, on, store: store);
      await runner.run(personStarted: true);
      expect(on.asked, hasLength(2));
      for (final prompt in on.asked) {
        expect(prompt.contains('Release') && prompt.contains('Launch'), isFalse, reason: 'one scope a prompt');
      }
      expect(store.readText('${contradictionsBookKey}org:HelloTrade'), contains('Launch is Thursday'));
      expect(store.readText('${contradictionsBookKey}personal'), isNot(contains('Launch')));
    });

    test('Stop ends a run in flight and keeps what was found before', () async {
      final ai = ScriptedAi([]);
      final runner = runnerOver([plan, standup], ai);
      ai.hold = Completer();
      final running = runner.run(personStarted: true);
      await Future<void>.delayed(Duration.zero);
      expect(runner.running, isTrue);
      runner.stop();
      expect(await running, RunEnd.stopped);
      expect(ai.cancelled, isTrue);
      expect(runner.running, isFalse);
    });

    test('with nobody to ask nothing is sent, and a failure is said', () async {
      expect(await runnerOver([plan, standup], null).run(personStarted: true), RunEnd.nobody);
      final failing = ContradictionRunner(notes: () => [plan, standup], pickAi: () async => _FailingAi(), store: MemoryStored(), clock: () => now, activity: Activity(clock: () => now));
      expect(await failing.run(personStarted: true), RunEnd.failed);
      expect(failing.problem, contains('No connection'));
    });

    test('nothing runs on its own until it was run once by hand, and Nightly is due once a day', () {
      final runner = runnerOver([plan, standup], ScriptedAi([]));
      runner.tick();
      expect(runner.running, isFalse);
      final ran = runnerOver([plan, standup], ScriptedAi([]), settings: ContradictionSettings(ranOnce: true, lastRun: DateTime(2026, 11, 8, 23)));
      expect(ran.nightlyDue(DateTime(2026, 11, 9, 2)), isFalse, reason: 'before three');
      expect(ran.nightlyDue(DateTime(2026, 11, 9, 3, 5)), isTrue);
      expect(ran.nightlyDue(DateTime(2026, 11, 8, 23, 30)), isFalse, reason: 'the same day');
    });

    test('the settings are kept and read back', () {
      final store = MemoryStored();
      runnerOver([], null, store: store).setSettings(const ContradictionSettings(schedule: ContradictionSchedule.saved, threshold: 0.9, orgs: false));
      final again = runnerOver([], null, store: store).settings;
      expect(again.schedule, ContradictionSchedule.saved);
      expect(again.threshold, 0.9);
      expect(again.orgs, isFalse, reason: 'turned off, kept off');
      expect(ContradictionSettings.fromJson(const {}).orgs, isTrue, reason: 'on unless turned off');
      expect(again.byFolder, isFalse);
    });
  });
}

class _FailingAi implements ContradictionAi {
  @override
  String get name => 'Claude';
  @override
  bool get onDevice => false;
  @override
  Duration get perRequest => const Duration(seconds: 10);
  @override
  ContradictionAsk ask({required String system, required String prompt}) => ContradictionAsk(Future.error(StateError('No connection')), () {});
}

String _finding(double confidence) => '{"pair": 1, "older": "A", "older_quote": "Release is Thursday", "newer": "B", "newer_quote": "Release moved to Monday", "what": "Moved.", "confidence": $confidence}';

String _json(Map<String, Object> map) => '{${map.entries.map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}').join(', ')}}';
