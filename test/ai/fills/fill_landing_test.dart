// A fill's answers into the open note (lib/ai/fills/fill_landing.dart, a port of `src/app/ai/fills/useFillLanding.ts`).
// The web has no test of the hook by itself: the queue's own test stands a string in for the editor, and the shots
// showed the two together. These are the port's own: a real editor with the squares, the fills' queue with a model
// the test answers (`simulateRuns`, as in queue_test.dart), and the landing between them.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/fills/edits.dart';
import 'package:ghost_md/ai/fills/fill_landing.dart';
import 'package:ghost_md/ai/fills/queue.dart';
import 'package:ghost_md/editor/ai/blanks.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart' show WispKind, wisp;
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../editor_ai/blanks_support.dart';

const String tokyo = '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}\n\nThe capital of Australia is {?}.';

/// Waits for the queue to reach a state: every step of it is a future.
Future<void> until(bool Function() test) async {
  for (var i = 0; i < 200 && !test(); i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(test(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFills fills;
  final landed = <Transaction>[];

  /// The note's editor, with what it was sent kept.
  EditorView open(String doc, Given given) => editor(
        doc,
        given: given,
        more: <Extension>[
          EditorViewLike.updateListener.of((update) => landed.addAll(update.transactions.where((tr) => tr.docChanged))),
        ],
      );

  setUp(() {
    landed.clear();
    fills = FakeFills()..start();
  });

  tearDown(() => fills.stop());

  group('a fill landing in the note on screen', () {
    test('lands a press’s answers in one change, signed, told from the person’s own edits, with no smoke where the wisp is off', () async {
      final view = open(tokyo, fills.given());
      final landing = FillLanding('n1', view, wisp: () => false, owner: () => null);
      addTearDown(landing.dispose);
      expect(fillAll(view), 2);
      await until(() => fills.models.length == 1);
      fills.models[0].finish('[1] midweek\n[2] Canberra');
      await until(() => landed.isNotEmpty);
      expect(landed, hasLength(1));
      final tr = landed.single;
      expect(tr.annotation(aiEdit), AiEdit.land);
      expect(tr.annotation(wisp), isNull);
      expect(tr.isUserEvent('ai.land'), isTrue);
      final doc = view.state.doc.toString();
      expect(doc, contains('Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)'));
      expect(doc, contains('The capital of Australia is ??Canberra??(Qwen3.5 4B from memory, 2026-09-28).'));
      // The AI's signature, in the same change.
      expect(doc, matches(RegExp(r'^---\nauthors: Ghost\n---')));
      await until(() => fillStatus('n1', blankKey('', 0)) == null);
    });

    test('arrives out of smoke where the wisp is on, and signs with the owner the screen knows', () async {
      final view = open(tokyo, fills.given());
      var smoke = true;
      final landing = FillLanding('n1', view, wisp: () => smoke, owner: () => 'matt');
      addTearDown(landing.dispose);
      fillAll(view);
      await until(() => fills.models.length == 1);
      fills.models[0].finish('[1] midweek\n[2] Canberra');
      await until(() => landed.isNotEmpty);
      expect(landed.single.annotation(wisp), WispKind.rewrite);
      final doc = view.state.doc.toString();
      final signed = signatureChange(tokyo, 'matt')!;
      expect(doc.startsWith(signed.insert), isTrue, reason: doc.substring(0, 40));
      expect(signed.insert, contains('matt'));
      smoke = false;
    });

    test('finds a blank where the person’s typing has moved it since the press', () async {
      final view = open(tokyo, fills.given());
      final landing = FillLanding('n1', view, wisp: () => false, owner: () => null);
      addTearDown(landing.dispose);
      fillAll(view);
      await until(() => fills.models.length == 1);
      // Typed while the model works: the ranges tracked since the press move with it.
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'A line above.\n\n'), userEvent: 'input.type'));
      landed.clear();
      final key = blankKey('what day / time?', 0);
      expect(landing.host.rangeOf(key), (from: tokyo.indexOf('{?what') + 15, to: tokyo.indexOf('{?what') + 15 + '{?what day / time?}'.length));
      fills.models[0].finish('[1] midweek\n[2] Canberra');
      await until(() => landed.isNotEmpty);
      final doc = view.state.doc.toString();
      expect(doc, contains('A line above.\n\n# Tokyo trip'));
      expect(doc, contains('on ??midweek??('));
      expect(doc, contains('is ??Canberra??('));
    });

    test('is the note’s host while it lives: its words, its tracked ranges, and nothing written once it is disposed of', () {
      final view = open(tokyo, Given());
      final landing = FillLanding('n2', view, wisp: () => false, owner: () => null);
      final host = landing.host;
      expect(host.text(), tokyo);
      expect(host.rangeOf('k'), isNull);
      host.track([(key: 'k', from: 3, to: 9)]);
      expect(host.rangeOf('k'), (from: 3, to: 9));
      expect(view.state.field(blanksField)['k'], (from: 3, to: 9));
      // Several changes, given in any order, land in one transaction; the note after is the answer.
      final after = host.land(const [TextChange(from: 8, to: 12, insert: 'TRIP'), TextChange(from: 2, to: 7, insert: 'Kyoto')], null);
      expect(after, '# Kyoto TRIP\n\nFlights are cheapest to Tokyo on {?what day / time?}\n\nThe capital of Australia is {?}.');
      expect(view.state.doc.toString(), after);
      expect(landed, hasLength(1));
      landing.dispose();
      expect(host.land(const [TextChange(from: 0, to: 1, insert: 'X')], null), isNull);
      expect(view.state.doc.toString(), after);
      landing.dispose();
    });

    test('a press after the note is left is not landed through an editor that has gone', () async {
      final view = open(tokyo, fills.given());
      FillLanding('n1', view, wisp: () => false, owner: () => null).dispose();
      fillAll(view);
      // The queue reads the note from the store then, which this test's store does not have: nothing is asked of the
      // editor either way.
      for (var i = 0; i < 20; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      for (final model in fills.models) {
        model.finish('[1] midweek\n[2] Canberra');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(landed, isEmpty);
      expect(view.state.doc.toString(), tokyo);
    });
  });
}
