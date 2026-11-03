// Note decay alerts' AI half and its controller (lib/plugins/note_decay/ai.dart, decay.dart, note_decay.dart;
// docs/NOTE_DECAY.md §1.2, §2): the model's quotes checked against the page, Update with AI as edits that change
// nothing until accepted, the renames heard as the library changes, and Local only keeping everything on the phone.
// The model is a fake's: no test reaches a network or a model.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/note_decay/ai.dart';
import 'package:ghost_md/plugins/note_decay/dismissals.dart';
import 'package:ghost_md/plugins/note_decay/lookups.dart';
import 'package:ghost_md/plugins/note_decay/note_decay.dart';
import 'package:ghost_md/plugins/note_decay/signals.dart';

/// A model that answers what it is told, and keeps what it was asked.
class FakeModel implements DecayModel {
  FakeModel(this.answers, {this.ready = true});
  final List<String> answers;
  final List<String> prompts = [];
  @override
  final bool ready;
  @override
  String get name => 'Fake AI';
  @override
  bool get onDevice => false;
  @override
  Future<String> ask({required String system, required String prompt}) async {
    prompts.add(prompt);
    return answers.isEmpty ? '{}' : answers.removeAt(0);
  }
}

final DateTime now = DateTime(2026, 11, 2, 10);

Note note(String id, String body, {DateTime? edited, String? path, int? archivedAt}) {
  final at = (edited ?? DateTime(2026, 10, 20)).millisecondsSinceEpoch;
  return Note(id: id, body: body, createdAt: at, updatedAt: at, path: path, archivedAt: archivedAt);
}

void main() {
  const plan = '# Plan\n- Billing ships on Nov 1.\n- Search stays as it is.\n- Waits on [[GHO-12]]';
  final decayNote = DecayNote(id: 'p', title: 'Plan', body: plan, edited: DateTime(2026, 10, 20));

  group('the AI pass', () {
    test('marks the lines it quotes, and drops a quote the page does not have', () async {
      final model = FakeModel(['Here: ```json\n{"outOfDate": true, "lines": [{"quote": "Billing ships on  Nov 1.", "why": "GHO-12 moved billing to December."}, {"quote": "Payments launch in March.", "why": "Made up."}]}\n```']);
      final signals = await aiSignalsOf(decayNote, const [DecaySource(what: 'GHO-12', says: 'Moved to December')], model);
      expect([for (final s in signals) (s.kind, s.line, s.reason, s.quote)], [(DecayKind.ai, 1, 'AI: GHO-12 moved billing to December.', '- Billing ships on Nov 1.')]);
      expect(model.prompts.single, contains('- GHO-12: Moved to December'));
      expect(model.prompts.single, contains(plan));
    });

    test('says nothing where the model says the page is right, answers no JSON, or is not ready', () async {
      expect(await aiSignalsOf(decayNote, const [], FakeModel(['{"outOfDate": false, "lines": [{"quote": "Billing ships on Nov 1.", "why": "x"}]}'])), isEmpty);
      expect(await aiSignalsOf(decayNote, const [], FakeModel(['I think it is fine.'])), isEmpty);
      final idle = FakeModel(['{"outOfDate": true}'], ready: false);
      expect(await aiSignalsOf(decayNote, const [], idle), isEmpty);
      expect(idle.prompts, isEmpty);
    });

    test('an AI mark’s key is the same on every run, so a Still right of it holds', () {
      expect(stableHash('- billing ships on nov 1.'), stableHash('- billing ships on nov 1.'));
      expect(stableHash('a'), isNot(stableHash('b')));
      expect(stableHash('a'), hasLength(8));
    });
  });

  group('Update with AI', () {
    test('proposes edits for lines the page has, applied only once accepted', () async {
      final signal = DecaySignal(kind: DecayKind.date, key: 'Nov 1', stamp: '2026-11-01', reason: 'Nov 1 has passed', line: 1, quote: '- Billing ships on Nov 1.');
      final model = FakeModel([
        '{"edits": [{"quote": "Billing ships on Nov 1.", "replacement": "Billing shipped on Nov 1.", "why": "It has shipped."}, {"quote": "Not on the page", "replacement": "x"}, {"quote": "- Search stays as it is.", "replacement": "- Search stays as it is."}]}',
      ]);
      final edits = await proposeEdits(decayNote, [signal], const [], model);
      expect([for (final e in edits) (e.line, e.before, e.after, e.why)], [(1, '- Billing ships on Nov 1.', '- Billing shipped on Nov 1.', 'It has shipped.')]);
      expect(model.prompts.single, contains('"- Billing ships on Nov 1.": Nov 1 has passed'));
      // Nothing is changed by proposing: the page is as it was until the edits are applied.
      expect(decayNote.body, plan);
      expect(applyEdits(plan, edits), '# Plan\n- Billing shipped on Nov 1.\n- Search stays as it is.\n- Waits on [[GHO-12]]');
      expect(applyEdits(plan, const []), plan);
    });

    test('keeps a line’s list sign, takes a line out for an empty replacement, and never writes over a newer line', () async {
      final model = FakeModel(['{"edits": [{"quote": "- Billing ships on Nov 1.", "replacement": "Billing shipped on Nov 1."}, {"quote": "Search stays as it is.", "replacement": ""}]}']);
      final edits = await proposeEdits(decayNote, const [], const [], model);
      expect([for (final e in edits) e.after], ['- Billing shipped on Nov 1.', '']);
      expect(applyEdits(plan, edits), '# Plan\n- Billing shipped on Nov 1.\n- Waits on [[GHO-12]]');
      final whole = await proposeEdits(decayNote, const [], const [], FakeModel(['{"edits": [{"quote": "- Search stays as it is.", "replacement": ""}]}']));
      expect(applyEdits(plan, whole), '# Plan\n- Billing ships on Nov 1.\n- Waits on [[GHO-12]]');
      // The line was typed over since the edit was proposed: the edit is left.
      expect(applyEdits(plan.replaceFirst('Billing ships', 'Billing now ships'), edits.take(1).toList()), plan.replaceFirst('Billing ships', 'Billing now ships'));
    });
  });

  group('the app’s note decay', () {
    test('hears a rename as the library changes, and marks the links to the old title', () {
      final notes = ValueNotifier<List<Note>>([note('a', '# Plan\nSee [[Spec]].'), note('s', '# Spec\nThe spec.')]);
      var renames = <String, String>{};
      final decay = NoteDecay(notes: () => notes.value, changes: notes, renames: () => renames, keepRenames: (kept) => renames = kept, clock: () => now);
      addTearDown(decay.dispose);
      expect(decay.signalsFor('a'), isEmpty);
      notes.value = [notes.value.first, note('s', '# Spec v2\nThe spec.')];
      expect(renames, {'Spec': 'Spec v2'});
      expect([for (final s in decay.signalsFor('a')) s.reason], ['[[Spec]] was renamed to [[Spec v2]]']);
      // The open editor's words are read in place of the saved ones: the link fixed there, the mark goes at once.
      expect(decay.signalsFor('a', body: '# Plan\nSee [[Spec v2]].'), isEmpty);
      // Off, nothing anywhere.
      final off = NoteDecay(notes: () => notes.value, renames: () => renames, on: () => false, clock: () => now);
      addTearDown(off.dispose);
      expect(off.signalsFor('a'), isEmpty);
      expect(off.pages(), isEmpty);
    });

    test('Still right in the page keeps a mark away, and the pages list leaves it out', () {
      final notes = [note('a', '# Plan\nBilling ships on Nov 1.'), note('b', '# Other\nAll good.')];
      final decay = NoteDecay(notes: () => notes, clock: () => now);
      addTearDown(decay.dispose);
      final signal = decay.signalsFor('a').single;
      expect([for (final p in decay.pages()) p.title], ['Plan']);
      notes[0] = note('a', withStillRight(notes[0].body, signal));
      decay.settingsChanged();
      expect(decay.signalsFor('a'), isEmpty);
      expect(decay.pages(), isEmpty);
    });

    test('a pass asks the lookups, then the AI where its switch is on, and keeps what they said for the page as it reads', () async {
      final notes = [note('a', '# Plan\nBilling ships on Nov 1.\nhttps://github.com/acme/app/pull/12')];
      final lookups = AppDecayLookups(githubOn: () => true, figmaOn: () => false, askGithub: (ref) async => GithubState(GithubStateKind.merged, at: DateTime(2026, 10, 30)), askFigma: (_) async => null, clock: () => now);
      final model = FakeModel(['{"outOfDate": true, "lines": [{"quote": "Billing ships on Nov 1.", "why": "Already marked."}, {"quote": "# Plan", "why": "The plan is old."}]}']);
      var ai = true;
      final decay = NoteDecay(notes: () => notes, lookups: () => lookups, model: () => model, aiOn: () => ai, clock: () => now);
      addTearDown(decay.dispose);
      await decay.look('a');
      expect([for (final s in decay.signalsFor('a')) s.reason], ['Nov 1 has passed; this still speaks of it as ahead', 'PR #12 in acme/app was merged on Oct 30', 'AI: The plan is old.']);
      // The model was told what changed.
      expect(model.prompts.single, contains('PR #12 in acme/app was merged on Oct 30'));
      // The AI's switch off: its marks go, the others stay.
      ai = false;
      expect(decay.signalsFor('a'), hasLength(2));
      // The pull request's line typed away in the editor: its mark goes with it.
      expect(decay.signalsFor('a', body: '# Plan\nBilling ships on Nov 1.'), hasLength(1));
    });

    test('Update with AI asks the model with the page as the editor has it', () async {
      final notes = [note('a', '# Plan\nBilling ships on Nov 1.')];
      final model = FakeModel(['{"edits": [{"quote": "Billing ships on Nov 1, maybe.", "replacement": "Billing shipped on Nov 1."}]}']);
      final decay = NoteDecay(notes: () => notes, model: () => model, clock: () => now);
      addTearDown(decay.dispose);
      final edits = await decay.propose('a', '# Plan\nBilling ships on Nov 1, maybe.', decay.signalsFor('a'));
      expect([for (final e in edits) e.after], ['Billing shipped on Nov 1.']);
      expect(model.prompts.single, contains('Billing ships on Nov 1, maybe.'));
    });
  });

  group('Local only', () {
    setUp(() => preferences.startWithoutStorage());
    tearDown(() => preferences.value = const Preferences());

    test('asks nothing outside the phone, and the AI is the phone’s own model', () async {
      preferences.value = const Preferences(localOnly: true);
      const model = AppDecayModel();
      expect((model.onDevice, model.name), (true, 'the phone’s model'));
      // This test's phone has no model: nobody to ask, and asking fails without reaching anything.
      expect(model.ready, isFalse);
      await expectLater(model.ask(system: 's', prompt: 'p'), throwsA(isA<StateError>()));
      final lookups = appDecayLookups();
      expect((lookups.githubOn, lookups.figmaOn), (false, false));
      expect(await lookups.github(const GithubRef(owner: 'acme', repo: 'app', pull: true, number: 1)), isNull);
      expect(await lookups.figmaGone('https://www.figma.com/design/AbC/Home'), isNull);
    });

    test('a GitHub issue’s JSON is read as merged, closed or open', () {
      expect(githubStateOf({'state': 'closed', 'closed_at': '2026-10-30T10:00:00Z', 'pull_request': {'merged_at': '2026-10-30T09:00:00Z'}})?.state, GithubStateKind.merged);
      expect(githubStateOf({'state': 'closed', 'closed_at': '2026-10-30T10:00:00Z', 'pull_request': {'merged_at': null}})?.state, GithubStateKind.closed);
      expect(githubStateOf({'state': 'open'})?.state, GithubStateKind.open);
      expect(githubStateOf('nonsense'), isNull);
    });
  });
}
