// A cleanup's run (lib/plugins/cleanup/run.dart; docs/CLEANUP.md, "Large folders"): the folder asked about in batches
// by a scripted AI, Tidy's asks with the whole note, an ask that fails said and the run going on, Stop keeping what the
// finished asks found, the estimate, and the service's job on the Activity tray with Stop. No real AI is asked.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';

import 'support.dart';

void main() {
  late CleanupWorld world;
  setUp(() => world = CleanupWorld());

  /// The scripted answer: a title for the untitled call, Plan to tidy, Clients for the call, and Tidy's own answer.
  String answer(String system, String prompt) {
    if (system.startsWith('You fix the Markdown')) return '# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.';
    final n = noteRefs(prompt), f = folderRefs(prompt);
    return answerJson({
      'titles': [
        if (n['Untitled'] != null) {'note': n['Untitled'], 'title': 'Kiln spring menu call', 'why': 'It had none'},
      ],
      'moves': [
        if (n['Untitled'] != null) {'note': n['Untitled'], 'to': f['Work › Clients'], 'why': 'About a client'},
      ],
      'tidy': [
        if (n['Plan'] != null) {'note': n['Plan'], 'why': 'A stray #'},
      ],
    });
  }

  test('a folder read in one ask, Tidy asked about Plan whole, the plan joined with the app’s own duplicates', () async {
    final asked = <Asked>[];
    final steps = <String>[];
    final plan = await runCleanup(scope: world.scope('work'), ai: scriptedAi(answer, asked: asked), options: const CleanupOptions(), progress: (done, total, line) => steps.add('$line $done/$total'));
    expect(asked, hasLength(2));
    expect(asked.first.prompt, isNot(contains('kiln-call')));
    expect(asked.last.system, contains('Do not change, add, remove or reorder'));
    expect(asked.last.prompt, contains(world.library.noteOf('messy')!.body));
    expect(plan.items.map((i) => i.id), ['move:kiln-call', 'title:kiln-call', 'merge:standup', 'tidy:messy']);
    expect(plan.asks, 2);
    expect(plan.failures, isEmpty);
    expect(steps, ['Reading with Fake AI 0/8', 'Reading with Fake AI 8/8', 'Tidying with Fake AI 0/1']);
  });

  test('an organization’s folders are never asked about duplicates, and the app finds none there either', () async {
    // Two copies of one team note, word for word.
    final copy = world.library.noteOf('team-plan')!;
    await world.library.createNote(copy.body.replaceFirst('# Team plan', '# Team plan (shared)'), id: 'team-plan-copy');
    world.workspaces.fileNote('team-plan-copy', world.plansId);
    final asked = <Asked>[];
    final plan = await runCleanup(
      scope: world.scope('org-o1'),
      ai: scriptedAi((_, prompt) {
        final n = noteRefs(prompt);
        return answerJson({
          'duplicates': [
            {'keep': n['Team plan'], 'others': [n['Team plan (shared)']]},
          ],
        });
      }, asked: asked),
      options: const CleanupOptions(passes: {CleanupPass.duplicates, CleanupPass.titles}),
    );
    expect(asked.single.system, isNot(contains('"duplicates"')));
    expect(plan.items.whereType<MergeItem>(), isEmpty);
    // The same folder's notes, personal, would have been found.
    expect(duplicateGroups([for (final n in world.scope('org-o1').notes) (id: n.id, title: n.title, body: n.body, updatedAt: n.updatedAt)]), isNotEmpty);
    final service = world.service();
    service.choose(world.plansId);
    for (final pass in CleanupPass.values) {
      service.setPass(pass, pass == CleanupPass.duplicates);
    }
    expect(service.inOrg, isTrue);
    expect(service.cannotLook, 'Duplicates isn’t offered in an organization’s folders: turn on something else to do.');
  });

  test('the device’s model is sent 12 notes an ask and 400 characters of each', () async {
    final asked = <Asked>[];
    await runCleanup(scope: world.scope('work'), ai: scriptedAi((_, _) => '{}', local: true, asked: asked), options: const CleanupOptions(passes: {CleanupPass.titles}));
    expect(asked.single.maxTokens, 1500);
    expect(sentWords('On this device', CleanupSizes.device, local: true, options: const CleanupOptions()), contains('first 400 characters go to the model on this device, and nothing leaves it, 12 notes at a time'));
    expect(sentWords('Claude', CleanupSizes.cloud, local: false, options: const CleanupOptions()), allOf(contains('to Claude, with your key'), contains('40 notes at a time'), contains('only when Tidy asks')));
  });

  test('an ask that fails is said and the run goes on; an answer with no JSON is a batch that gave nothing', () async {
    final many = CleanupScope(
      rootId: 'work',
      org: null,
      folders: world.scope('work').folders,
      notes: [for (var i = 0; i < 30; i += 1) CleanupNote(id: 'n$i', title: 'Note ${i.toString().padLeft(2, '0')}', body: 'Words $i', revision: 1, folderId: 'work', updatedAt: 0)],
    );
    var asks = 0;
    final plan = await runCleanup(
      scope: many,
      ai: scriptedAi((_, prompt) {
        asks += 1;
        if (asks == 1) throw StateError('Fake AI is out of credit');
        if (asks == 2) return 'Sorry, I can’t.';
        final n = noteRefs(prompt);
        return answerJson({
          'stale': [
            {'note': n.values.first, 'why': 'Empty'},
          ],
        });
      }, local: true),
      options: const CleanupOptions(passes: {CleanupPass.stale}),
    );
    expect(plan.asks, 3);
    expect(plan.failures, ['Bad state: Fake AI is out of credit', 'the answer had no JSON in it']);
    expect(plan.items.single, isA<ArchiveItem>());
  });

  test('Stop ends the run after the ask in flight is cancelled, keeping what the finished asks found', () async {
    final many = CleanupScope(
      rootId: 'work',
      org: null,
      folders: world.scope('work').folders,
      notes: [for (var i = 0; i < 30; i += 1) CleanupNote(id: 'n$i', title: 'Note ${i.toString().padLeft(2, '0')}', body: 'Words $i', revision: 1, folderId: 'work', updatedAt: 0)],
    );
    final stop = CleanupStop();
    final second = Completer<void>();
    var asks = 0;
    final ai = CleanupAi(
      id: 'fake',
      name: 'Fake AI',
      local: true,
      ask: (system, prompt, {required maxTokens}) {
        asks += 1;
        if (asks == 1) {
          final n = noteRefs(prompt);
          return CleanupAsking(Future.value(answerJson({
            'stale': [
              {'note': n.values.first},
            ],
          })), () {});
        }
        // The second waits until stopped (the tray's Stop, pressed while it is in flight), then fails as a cancelled
        // ask does.
        Future(stop.stop);
        return CleanupAsking(second.future.then((_) => throw StateError('cancelled')), () => second.complete());
      },
    );
    final plan = await runCleanup(scope: many, ai: ai, options: const CleanupOptions(passes: {CleanupPass.stale}), stop: stop);
    expect(asks, 2);
    expect(plan.stopped, isTrue);
    expect(plan.items, hasLength(1));
    expect(plan.failures, isEmpty, reason: 'a cancelled ask is the Stop, not a failure');
  });

  test('the estimate: notes, asks and about how long; over two minutes it asks first', () {
    final scope = world.scope('work');
    final cloud = cleanupEstimate(scope, scriptedAi((_, _) => '{}', name: 'Claude'), const CleanupOptions());
    expect(cloud.words, '8 notes · 3 asks of Claude · ~35 s');
    expect(cloud.job.asks, isFalse);
    final big = CleanupScope(rootId: 'work', org: null, folders: scope.folders, notes: [for (var i = 0; i < 300; i += 1) CleanupNote(id: 'n$i', title: 'N$i', body: '', revision: 1, folderId: 'work', updatedAt: 0)]);
    final slow = cleanupEstimate(big, scriptedAi((_, _) => '{}', local: true), const CleanupOptions());
    expect(slow.asks, 25);
    expect(slow.job.asks, isTrue);
  });

  group('the service', () {
    test('Look for changes runs on the Activity tray with Stop, wearing the AI’s mark, and ends in the review', () async {
      final record = Activity(clock: () => DateTime.fromMillisecondsSinceEpoch(cleanupNow));
      final service = CleanupService(
        library: world.library,
        workspaces: world.workspaces,
        trash: world.trash,
        records: CleanupRecords(),
        activity: record,
        ais: () async => [scriptedAi(answer, id: 'openai', name: 'OpenAI').withPlugin('openai')],
      );
      final seen = <Job>[];
      final heard = record.events.listen((event) {
        if (event.job != null) seen.add(event.job!);
      });
      service.choose('work');
      expect(service.cannotLook, isNull);
      expect(await service.look(), isTrue);
      await heard.cancel();
      expect(service.stage, CleanupStage.review);
      expect(service.plan!.items, isNotEmpty);
      expect(service.ticked, service.plan!.startTicked);
      final started = seen.first;
      expect((started.id, started.kind, started.title, started.plugin, started.onStop != null, started.personStarted), ('cleanup:work', JobKind.ai, 'Cleaning up Work', 'openai', true, true));
      expect(seen.last.state, JobState.done);
      expect(seen.last.result!.words, '4 suggestions to review');
    });

    test('under Local only a cloud AI is never asked, even one handed in: the run does not start', () async {
      final asked = <Asked>[];
      final service = world.service(ais: [scriptedAi(answer, id: 'claude', name: 'Claude', asked: asked)], localOnly: true);
      service.choose('work');
      expect(await service.look(), isFalse);
      expect(asked, isEmpty);
      expect(service.stage, CleanupStage.choosing);
      expect(service.problem, 'Local only is on, and there is no model on this device yet.');
    });

    test('nothing to look at says why: no folder, no pass, no AI, an empty folder', () async {
      final service = world.service(ais: const []);
      expect(service.cannotLook, 'Choose a folder first.');
      service.choose('home');
      service.setPass(CleanupPass.sort, false);
      service.setPass(CleanupPass.titles, false);
      service.setPass(CleanupPass.duplicates, false);
      service.setPass(CleanupPass.tidy, false);
      expect(service.cannotLook, 'Turn on at least one thing to do.');
      service.setPass(CleanupPass.titles, true);
      await service.readAis();
      expect(service.cannotLook, 'No AI is connected yet.');
      final local = world.service(ais: const [], localOnly: true);
      local.choose('home');
      await local.readAis();
      expect(local.cannotLook, 'Local only is on, and there is no model on this device yet.');
      final empty = world.service();
      world.workspaces.addWorkspace('Empty');
      empty.choose(world.workspaces.value.list.firstWhere((w) => w.name == 'Empty').id);
      await empty.readAis();
      expect(empty.cannotLook, 'Empty has no notes in it.');
      expect(await empty.look(), isFalse);
    });
  });
}

extension on CleanupAi {
  CleanupAi withPlugin(String plugin) => CleanupAi(id: id, name: name, ask: ask, local: local, plugin: plugin, model: model);
}
