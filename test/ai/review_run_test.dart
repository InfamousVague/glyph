// The review's pure half (lib/ai/review.dart). A port of `src/app/ai/review.test.ts`, case for case. (test/ai/support
// has review_test.dart, the port of `review/review.test.ts`: the prompt, the findings and the diff.)

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/review.dart';
import 'package:ghost_md/ai/support/review_diff.dart';
import 'package:ghost_md/ai/support/review_findings.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/state/state.dart';

import 'ai_changes_test.dart' show TestView;
import 'fake_backend.dart';

TestView open(String doc) => TestView(EditorState.create(doc: doc, extensions: aiChangesState()));

Finding finding(FindingChange change, {String id = 'f'}) => Finding(id: id, check: Check.words, what: '', why: '', noteId: 'n', noteTitle: 'N', change: change);

void main() {
  group('a finding as an edit on the note', () {
    test('replaces the last place the words are, marking the old words inline', () {
      final edit = findingEdit('Fix the seat bar.\nThe seat bar again.\n', finding(const ReplaceChange(find: 'seat bar', replace: 'seek bar')), 'r', 'c')!;
      expect((edit.from, edit.to, edit.insert), (22, 30, 'seek bar'));
      expect((edit.record.from, edit.record.to, edit.record.removed, edit.record.block), (22, 30, 'seat bar', false));
    });

    test('adds a line where the note would take it, marked as a block', () {
      final edit = findingEdit('# Trip\n- eggs\n', finding(const AddChange(line: '- milk')), 'r', 'c')!;
      expect(edit.insert, matches(RegExp('milk', caseSensitive: false)));
      expect((edit.record.removed, edit.record.block), ('', true));
    });

    test('answers null for words no longer there', () {
      expect(findingEdit('nothing here\n', finding(const ReplaceChange(find: 'seat bar', replace: 'seek bar')), 'r', 'c'), isNull);
    });
  });

  group('landing findings in the note', () {
    test('lands each in turn as a tracked change, and counts them', () {
      final v = open('Fix the seat bar.\nCall Sam.\n');
      final landed = landFindings(
        v,
        [
          finding(const ReplaceChange(find: 'seat bar', replace: 'seek bar'), id: 'a'),
          finding(const ReplaceChange(find: 'Sam', replace: 'Sam about the dog'), id: 'b'),
          finding(const ReplaceChange(find: 'gone', replace: 'x'), id: 'c'),
        ],
        'run',
        wisp: false,
      );
      expect(landed, 2);
      expect(v.state.doc.toString(), 'Fix the seek bar.\nCall Sam about the dog.\n');
      expect([for (final c in v.state.field(aiChangesField)) c.removed], ['seat bar', 'Sam']);
    });
  });

  group('the careful model’s words alone', () {
    test('offers each change the note still has, as a replace', () {
      final findings = wordsOnly(const [WordChange(heard: 'seat bar.', careful: 'seek bar.', before: 'the', after: '')], const NoteText(id: 'n', title: 'N', body: 'Fix the seat bar.\n'));
      expect([for (final f in findings) (f.check, f.change)], [(Check.words, const ReplaceChange(find: 'seat bar', replace: 'seek bar'))]);
      expect(wordsOnly(const [WordChange(heard: 'gone', careful: 'x', before: '', after: '')], const NoteText(id: 'n', title: 'N', body: 'Fix.\n')), isEmpty);
    });
  });

  group('the model the review thinks with', () {
    late FakeAiBackend phone;

    /// These catalogue models on the phone, in this order.
    List<ModelInfo> on(List<String> ids, {bool present = true}) =>
        [for (final id in ids) ModelInfo(id: id, file: '$id.gguf', bytes: modelSpec(id)!.bytes, present: present, path: '/models/$id.gguf')];

    setUp(() {
      useStored(MemoryStored());
      phone = FakeAiBackend();
      useAiBackend(phone);
    });
    tearDown(() => preferences.update((_) => const Preferences()));

    void choose(String model) => preferences.update((now) => now.copyWith(formatModel: model));

    test('is the one chosen for formatting, when it is a Qwen and on the phone', () async {
      phone.answers['ai_models'] = on(['qwen3.5-9b', 'qwen3.5-2b']);
      choose('qwen3.5-2b');
      expect(await thinkingModel(), 'qwen3.5-2b');
    });

    test('is the largest Qwen on the phone when the chosen one does not reason, or is not there', () async {
      phone.answers['ai_models'] = on(['qwen3.5-2b', 'gemma-4-e4b', 'qwen3.5-4b']);
      choose('gemma-4-e4b');
      expect(await thinkingModel(), 'qwen3.5-4b');
      choose('qwen3.5-9b');
      expect(await thinkingModel(), 'qwen3.5-4b');
    });

    test('is the chosen model when no Qwen is on the phone, and none when that is not there either', () async {
      phone.answers['ai_models'] = on(['gemma-4-e4b']);
      choose('gemma-4-e4b');
      expect(await thinkingModel(), 'gemma-4-e4b');
      choose('qwen3.5-4b');
      expect(await thinkingModel(), isNull);
      // A model the catalogue knows but the phone has not downloaded is not there.
      phone.answers['ai_models'] = on(['qwen3.5-9b'], present: false);
      expect(await thinkingModel(), isNull);
      phone.answers['ai_models'] = () => throw StateError('no bridge');
      expect(await thinkingModel(), isNull);
    });
  });
}
