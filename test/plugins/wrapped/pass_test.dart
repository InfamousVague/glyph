// Wrapped's slow pass (lib/plugins/wrapped/pass.dart, service.dart; docs/WRAPPED.md, "The pass"): a few notes an ask
// with a pause after each, held while the app is busy, every answer kept as it comes so a pass cut off goes on where
// it was, a note unchanged since it was read never sent again, the organization's notes never sent, the cost asked
// first, and the library's ask read into themes, tidying and the one you forgot. Against a scripted AI only.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/metrics.dart' show countBucket;
import 'package:ghost_md/plugins/cleanup/cleanup.dart' show CleanupAi;
import 'package:ghost_md/plugins/wrapped/wrapped.dart';

import 'support.dart';

/// [watch] told of each ask, [answer] answering it.
CleanupAi CleanupAiOf(CleanupAi watch, CleanupAi answer) => CleanupAi(
      id: answer.id,
      name: answer.name,
      model: answer.model,
      ask: (system, prompt, {required maxTokens}) {
        watch.ask(system, prompt, maxTokens: maxTokens);
        return answer.ask(system, prompt, maxTokens: maxTokens);
      },
    );

void main() {
  late WrappedWorld world;
  setUp(() {
    world = WrappedWorld();
    useActivity(Activity());
  });

  List<Asked> reads(List<Asked> asked) => [for (final a in asked) if (a.system == readSystem) a];

  test('the first Make asks first, and without a place to ask nothing runs', () async {
    final asked = <Asked>[];
    final service = world.service(ais: [fakeAi(asked: asked)]);
    expect(await service.make(), isFalse);
    expect(asked, isEmpty);
    expect(service.state.wanted, isFalse);
    expect(world.file.text, isNull, reason: 'nothing was kept either');
  });

  test('the pass: paced, every note read once, then the library asked once', () async {
    final asked = <Asked>[];
    final waited = <Duration>[];
    final service = world.service(ais: [fakeAi(asked: asked)], waited: waited);
    final states = <JobState>{};
    activity.addListener(() => states.addAll([for (final job in activity.value) if (job.id == wrappedJobId) job.state]));
    // Asked for already (the press and its question are the page's): the run goes on from here.
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    final notes = reads(asked);
    expect(notes, hasLength(5), reason: 'nine notes, two an ask');
    expect([for (final a in notes) readRefs(a.prompt).length], [2, 2, 2, 2, 1]);
    expect(waited, List.filled(4, const Duration(seconds: 1)), reason: 'a pause after each ask but the last');
    expect(asked.where((a) => a.system == librarySystem), hasLength(1));
    expect(asked.any((a) => a.prompt.contains('Team goals') || a.prompt.contains('Hire a designer')), isFalse, reason: 'an organization’s note is never sent');
    expect(service.state.reads, hasLength(9));
    expect(service.state.reads['standup']!.gist, 'About Standup');
    expect(service.state.made, isTrue);
    expect(service.state.wanted, isFalse);
    expect(service.state.themes, ['Travel plans', 'Work releases', 'Home']);
    // Kept in the Library's file as it went.
    expect(WrappedState.decode(world.file.text).reads, hasLength(9));
    expect(states, contains(JobState.running), reason: 'on the Activity tray while it read');
    expect(activity[wrappedJobId], isNull, reason: 'and done: off the tray, into the log');
  });

  test('what the library ask suggests, and what the app finds itself', () async {
    final service = world.service(ais: [fakeAi()]);
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    final kinds = {for (final s in service.suggestions) s.kind: s};
    expect(kinds[SuggestionKind.merge]!.notes, ['standup', 'standup-copy'], reason: 'the same words twice, found without the AI');
    expect(kinds[SuggestionKind.merge]!.found, isTrue);
    expect(kinds[SuggestionKind.move]!.notes, ['meeting']);
    expect(kinds[SuggestionKind.move]!.folderId, 'work');
    expect(kinds[SuggestionKind.newFolder]!.folderName, 'Garden');
    expect(kinds[SuggestionKind.newFolder]!.parentId, isNull);
    expect(kinds[SuggestionKind.link]!.notes, ['trip', 'meeting']);
    expect([for (final n in service.forgotten) n.id], ['recipe']);
    expect([for (final s in service.stale) s.note.id], ['draft']);
  });

  test('stopped part way, it goes on where it was: only the notes not yet read are sent', () async {
    final asked = <Asked>[];
    late WrappedService first;
    var asks = 0;
    final real = fakeAi(asked: asked);
    // The app closed after the second ask's answer came back.
    final cutting = scriptedAi((system, prompt) {
      asks += 1;
      if (asks == 2) first.stop();
      return '';
    });
    first = world.service(ais: [
      CleanupAiOf(cutting, real),
    ]);
    first.store.set(first.state.copyWith(wanted: true));
    await first.resume();
    final readFirst = first.state.reads.length;
    expect(readFirst, 2, reason: 'the first ask kept; the second cut off with the app');
    expect(first.state.wanted, isTrue, reason: 'still asked for: it goes on next time');
    asked.clear();
    // The app open again: a new service over the same file.
    final again = world.service(ais: [fakeAi(asked: asked)], store: WrappedStore(file: world.file));
    await again.store.reread();
    expect(again.state.reads, hasLength(2));
    await again.resume();
    final sent = {for (final a in reads(asked)) ...readRefs(a.prompt).keys};
    expect(sent.length, 7, reason: 'only what was not read');
    expect(again.state.reads, hasLength(9));
    expect(again.state.wanted, isFalse);
  });

  test('a second Wrapped sends only the notes that changed', () async {
    final asked = <Asked>[];
    final service = world.service(ais: [fakeAi(asked: asked)]);
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    asked.clear();
    await service.readAis();
    expect(service.estimate!.notes, 0, reason: 'nothing changed: nothing to send');
    final menu = world.library.noteOf('menu')!;
    await world.library.update('menu', '${menu.body}\n- [ ] Print it', menu.revision);
    await service.readAis();
    expect(service.estimate!.notes, 1);
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    expect([for (final a in reads(asked)) ...readRefs(a.prompt).keys], ['Spring menu']);
  });

  test('held while the app is busy, then on again', () async {
    var busy = 3;
    final waited = <Duration>[];
    final service = world.service(ais: [fakeAi()], waited: waited, busy: () => busy-- > 0);
    final heldSeen = <bool>[];
    service.addListener(() => heldSeen.add(service.held));
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    expect(waited.take(3), List.filled(3, const Duration(seconds: 5)), reason: 'looked again every busyCheck');
    expect(heldSeen, contains(true));
    expect(service.state.made, isTrue);
  });

  test('three failed asks in a row end it, saying why', () async {
    final service = world.service(ais: [scriptedAi((_, _) => throw StateError('Monthly spending limit reached'))]);
    service.store.set(service.state.copyWith(wanted: true));
    await service.resume();
    expect(service.problem, contains('spending limit'));
    expect(activity[wrappedJobId]!.state, JobState.failed);
    expect(service.state.made, isFalse);
  });

  test('the estimate: notes, asks, tokens and dollars for Claude, the key’s name for another', () async {
    final notes = world.service().passNotes;
    final claude = wrappedEstimate(notes, notes.length, fakeAi(), pacing: testPacing);
    expect(claude.notes, 9);
    expect(claude.asks, 6);
    expect(claude.costWords, startsWith('~'));
    final other = wrappedEstimate(notes, notes.length, fakeAi(id: 'openai', name: 'OpenAI'), pacing: testPacing);
    expect(other.dollars, isNull);
    expect(other.costWords, endsWith('on your OpenAI key'));
    expect(claude.job(first: true).asks, isTrue, reason: 'the first run always asks');
    expect(claude.job(first: true).words, contains('tokens'));
    expect(countBucket(claude.notes), '6-20');
  });

  test('the counts alone need no AI', () async {
    final service = world.service(ais: const []);
    expect(await service.make(), isTrue);
    expect(service.state.made, isTrue);
    expect(service.state.reads, isEmpty);
  });
}
