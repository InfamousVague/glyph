import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart' show Placement;
import 'package:ghost_md/capture/final_instruction.dart';
import 'package:ghost_md/capture/list_append.dart' show placeWords;
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/offers.dart' show placingOf;
import 'package:ghost_md/capture/take.dart';
import 'package:ghost_md/capture/take_types.dart';

import 'support/shapes.dart';
import 'support/take_host.dart';

/// A command read at Done, offered and confirmed through the take (lib/capture/final_instruction.dart and
/// take.dart), case for case with the web's `capture/instructionCapture.test.ts`.

/// The web's `TestNote`: a note a test's host writes into, so its body can change.
class TestNote implements TakeNote {
  TestNote({required this.id, required this.body});

  @override
  final String id;
  @override
  String body;
}

class Harness {
  Harness() {
    take = Take<TestNote>(
      quietHost<TestNote>(
        offer: (next) => offered = next,
        addItems: (note, spoken, placement) {
          added.add((note: note, spoken: spoken, placement: placement));
          note.body = placeWords(note.body, spoken, placingOf(placement)).body;
        },
      ),
    );
  }

  final TestNote todo = TestNote(id: 'todo', body: 'To-Do');
  Offer<TestNote>? offered;
  final List<({TestNote note, String spoken, Placement placement})> added = [];
  late final Take<TestNote> take;
}

void main() {
  group('instruction-aware final capture utterances', () {
    test('listens through every phrase, then offers and confirms a final To-Do append', () async {
      final h = Harness();
      h.take.listen(const Segment(text: 'add to the to do', startMs: 0, endMs: 1200));
      h.take.listen(const Segment(text: 'list wash dishes, take out trash, and fold clothes', startMs: 1200, endMs: 4200));

      expect(h.take.segments.map((segment) => segment.text).toList(), ['add to the to do', 'list wash dishes, take out trash, and fold clothes']);
      expect(h.offered, isNull);

      final read = await classifyFinalTranscript(h.take.segments.map((segment) => segment.text).join(' '), [
        TakeCandidate<TestNote>(id: 'todo', title: 'To-Do', note: h.todo),
      ]);
      expect(read, matchObject({'kind': 'offer', 'actions': [{'do': 'append', 'note': {'id': 'todo'}}]}));
      if (read is! FinalInstructionOffer<TakeCandidate<TestNote>>) throw StateError('expected offer');
      final append = read.actions.first;
      if (append is! VoiceAppend<TakeCandidate<TestNote>>) throw StateError('expected an append offer');
      h.take.offerChanges(heading: 'Add to To-Do', action: 'Add', lines: const []);
      expect(h.take.segments, <Segment>[]);
      expect(h.offered, isA<OfferPlan<TestNote>>().having((o) => o.heading, 'heading', 'Add to To-Do'));

      // Confirming a finished recording's changes is the recorder's to carry out (capture_screen.dart `_runFinalActions`).
      h.take.confirm();
      expect(h.added, isEmpty);
      h.todo.body = placeWords(h.todo.body, append.text, placingOf(append.placement)).body;
      expect(h.todo.body, 'To-Do\n\n- [ ] Wash dishes\n- [ ] Take out trash\n- [ ] Fold clothes\n');
    });

    for (final utterance in [
      'my thoughts about the new iPhone, I like the folding display and want to add more later',
      'I told Sam to add wash dishes to the to do list when he gets home',
      'The phrase create a list appears in this ordinary explanation',
    ]) {
      test('keeps near-miss prose as an ordinary new note: $utterance', () async {
        final h = Harness();
        h.take.listen(Segment(text: utterance, startMs: 0, endMs: 3000));
        expect(h.offered, isNull);
        expect(
          await classifyFinalTranscript(utterance, [const TakeCandidate<TakeNote>(id: 'todo', title: 'To-Do', note: TakeNote(id: 'todo', body: 'To-Do'))]),
          matchObject({'kind': 'ordinary'}),
        );
        expect(h.take.segments.map((segment) => segment.text).toList(), [utterance]);
      });
    }
  });
}
