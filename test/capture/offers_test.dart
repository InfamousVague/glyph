import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/list_append.dart' show PlacedInto;
import 'package:ghost_md/capture/offers.dart';
import 'package:ghost_md/capture/take_types.dart';

/// What each plan read at Done comes to before its tap (lib/capture/offers.dart): the card's offer, or nothing. Case
/// for case with the web's `capture/offers.test.ts`.

TakeCandidate<TakeNote> named(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));
const leave = Placement(how: PlacementHow.leave, task: false, many: false);

PlanPlace<TakeCandidate<TakeNote>> place(TakeCandidate<TakeNote> note, String text) =>
    PlanPlace(note: note, text: text, how: leave.how, task: leave.task, many: leave.many);

void main() {
  group('a plan to put words in a note', () {
    test('offers the lines as they would land in its list', () {
      final work = named('w', 'Work', '# Work\n\n- Email Jo');
      final made = offerFor(place(work, 'call Sam'));
      // The web's offer carries the whole plan as its `placement`; here the plan's placing fields alone.
      expect(made, OfferPlace<TakeNote>(note: work.note, title: 'Work', text: 'call Sam', placement: leave, added: const ['- Call Sam'], into: PlacedInto.list));
    });

    test('offers nothing for words that would add nothing', () {
      expect(offerFor(place(named('w', 'Work', '# Work'), '  ')), isNull);
    });
  });

  group('a plan for a new list', () {
    test('offers the list with its items when some were said, and without lines when none were', () {
      expect(
        offerFor(const PlanCreateList<TakeCandidate<TakeNote>>(title: 'Comic books', items: ['Batman', 'Superman'])),
        const OfferNew<TakeNote>(title: 'Comic books', lines: ['Batman', 'Superman']),
      );
      expect(offerFor(const PlanCreateList<TakeCandidate<TakeNote>>(title: 'Comic books', items: [])), const OfferNew<TakeNote>(title: 'Comic books'));
    });
  });
}
