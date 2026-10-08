import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/live_take.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/refine.dart' show RefineJob;
import 'package:ghost_md/capture/refine_text.dart';
import 'package:ghost_md/capture/take_host.dart' show RouteViewTookBack;
import 'package:ghost_md/capture/take_types.dart' show Span;

/// The better words, as the note will read with them (lib/capture/refine_text.dart), case for case with the web's
/// `capture/refineText.test.ts`.

RefineJob job({
  int fromMs = 0,
  String baseBody = '',
  bool titled = true,
  List<Segment> priorSegments = const [],
  List<Span>? skip,
  List<Span>? keywordAt,
  List<Segment>? live,
  Placing? placing,
}) =>
    RefineJob(
      id: 'n1',
      fromMs: fromMs,
      recordingMs: 4000,
      baseBody: baseBody,
      savedBody: '# Grocery run\n\nIt has to happen before Saturday.',
      titled: titled,
      priorSegments: priorSegments,
      promptTail: '',
      skip: skip,
      keywordAt: keywordAt,
      live: live,
      placing: placing,
      tries: 0,
    );

Segment seg(String text, int startMs, int endMs) => Segment(text: text, startMs: startMs, endMs: endMs);

void main() {
  group('the better words after a recording', () {
    test('renders a first take with a title, from the better phrases', () {
      final body = refinedBody(job(), [
        seg('Grocery run.', 0, 1000),
        seg('It has to happen before Saturday morning.', 1300, 3000),
      ]);
      expect(body, '# Grocery run\n\nIt has to happen before Saturday morning.');
    });

    test('puts a later take under the note it continued, without a new title', () {
      final body = refinedBody(
        job(baseBody: '# Grocery run\n\nBook the cabin.', fromMs: 10000, titled: false),
        [seg('Ask Sam about the dog.', 10000, 12000)],
      );
      expect(body, '# Grocery run\n\nBook the cabin.\n\nAsk Sam about the dog.');
    });

    test("replaces only the take's phrases in the recording's list", () {
      final prior = [
        seg('Book the cabin.', 0, 2000),
        seg('live guess of the take', 10000, 12000),
      ];
      final merged = refinedSegments(job(fromMs: 10000, priorSegments: prior), [
        seg('Ask Sam about the dog.', 10000, 12000),
      ]);
      expect(merged.map((s) => s.text), ['Book the cabin.', 'Ask Sam about the dog.']);
    });
  });

  group('the better words leave commands out', () {
    test('drops phrases inside a command’s stretch and cuts a phrase at “hey Ghost”', () {
      final refined = [seg('Pick up the parcel.', 0, 1800), seg('Pick up milk, hey Ghost, add eggs to', 2000, 4000), seg('work.', 4000, 4800), seg('Yes.', 5200, 5600), seg('Call Sam.', 6000, 7000)];
      final kept = withoutCommands(
        refined,
        skip: const [Span(startMs: 3950, endMs: 4900), Span(startMs: 5100, endMs: 5700)],
        keywordAt: const [Span(startMs: 2100, endMs: 3900)],
      );
      expect(kept.map((s) => s.text), ['Pick up the parcel.', 'Pick up milk', 'Call Sam.']);
    });

    test('keeps everything for a job from before commands were kept out', () {
      final refined = [seg('Ghost is the app.', 0, 1000)];
      expect(withoutCommands(refined), refined);
    });
  });

  group('voice memos in the better words', () {
    final clip = seg('![voice 0:05](tape:12000-17000)', 12000, 17000);
    final refined = [
      seg('Before the memo.', 8000, 11000),
      seg('After it.', 18000, 20000),
    ];

    test('puts each memo back where it was spoken', () {
      expect(withClips(refined, clips: [clip]).map((s) => s.text), ['Before the memo.', '![voice 0:05](tape:12000-17000)', 'After it.']);
    });

    test('leaves a take with no memo exactly as it was', () {
      expect(withClips(refined), refined);
      expect(withClips(refined, clips: []), refined);
    });
  });

  group('the better words for a take the live reader read', () {
    final live = [seg('Kevin owns the release.', 0, 1500), seg('Check box: call the electrician.', 2000, 4000), seg('The budget is Friday.', 4200, 5500)];
    const skip = [Span(startMs: 2000, endMs: 4000)];

    test('keeps the live item where a better phrase ran the command and its item together, and never the command', () {
      final refined = [seg('Kevin owns the release.', 0, 1500), seg('Hey Ghost, add call the electrician to house to-dos.', 1900, 4100), seg('The budget is Friday.', 4200, 5500)];
      expect(
        withoutCommands(refined, skip: skip, keywordAt: const [], live: live).map((s) => s.text),
        ['Kevin owns the release.', 'Check box: call the electrician.', 'The budget is Friday.'],
      );
    });

    test('drops a better phrase that is only the command, where no live phrase kept anything', () {
      final refined = [seg('Hey Ghost, move this to work.', 2000, 4000)];
      expect(withoutCommands(refined, skip: const [Span(startMs: 2000, endMs: 4000)], live: const []), isEmpty);
    });

    test('puts the better words into the list the live ones went into', () {
      final body = refinedBody(
        job(baseBody: '# House TODOs\n\n- [ ] Fix the gutter\n', titled: false, placing: const PlacingLists(task: true, heading: null, fresh: null)),
        [seg('Call an electrician to fix the light sockets.', 0, 3000)],
      );
      expect(body, '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n');
    });

    test('keeps a spoken entry on its time line, as the live page and Done wrote it', () {
      const baseBody = '---\ntitle: "2026-09-28 14.05"\n---\n# Monday 28 September\n\n';
      const placing = PlacingEnd(lead: '**14:05** ');
      final said = placeTake(baseBody, 'Walked along the river.', placing).body;
      expect(said, '$baseBody**14:05** Walked along the river.');
      expect(
        refinedBody(job(baseBody: baseBody, titled: false, placing: placing), [seg('Walked along the river after lunch.', 0, 2000)]),
        '$baseBody**14:05** Walked along the river after lunch.',
      );
    });

    test('still lands an old job, with no placing, at the end', () {
      expect(
        refinedBody(job(baseBody: '# House TODOs\n\n- [ ] Fix the gutter\n', titled: false), [seg('Call Sam.', 0, 1000)]),
        '# House TODOs\n\n- [ ] Fix the gutter\n\nCall Sam.',
      );
    });
  });

  /// A take played through the live reader (lib/capture/live_take.dart), then its better words, as the model would
  /// hear the same phrases: what the live reader changed or sent elsewhere must not come back raw.
  group('the better words of what the live reader changed', () {
    const house = '# House TODOs\n\n- [ ] Fix the gutter\n';
    const library = [MemoryNote(id: 'house', body: house), MemoryNote(id: 'groceries', body: '# Groceries\n\n- Eggs\n')];
    ({LiveTake take, List<Segment> heard}) play(List<String> lines, [List<MemoryNote> notes = library]) {
      final take = LiveTake(notes);
      final heard = [for (var i = 0; i < lines.length; i += 1) seg(lines[i], i * 1000, i * 1000 + 900)];
      for (var i = 0; i < heard.length; i += 1) {
        take.phrase(heard[i], i * 1000);
      }
      take.close(lines.length * 1000);
      return (take: take, heard: heard);
    }

    String refined(LiveTake take, List<Segment> heard, {required String baseBody, bool titled = false}) => refinedBody(
          job(titled: titled, skip: take.commandSpans, keywordAt: take.keywordSpans, live: take.segments, placing: take.placing, baseBody: baseBody),
          heard,
        );

    test('keeps "The note is" out of the to-do written after a switch', () {
      final (:take, :heard) = play(["Hey Ghost, add a note to house to do's.", 'The note is call an electrician to fix the light sockets.']);
      expect(refined(take, heard, baseBody: house), '$house- [ ] Call an electrician to fix the light sockets\n');
    });

    test('keeps things said as a list as the items they were written as', () {
      const base = '# Groceries\n\n- Eggs\n';
      final (:take, :heard) = play(['Hey Ghost, add a note to groceries.', 'Milk, butter and bread.']);
      expect(refined(take, heard, baseBody: base), '# Groceries\n\n- Eggs\n- Milk\n- Butter\n- Bread\n');
    });

    test('leaves what was taken back out, keeps what replaced it, and never brings “scratch that” back', () {
      final dropped = play(['Pick up the parcel.', 'Call Sam.', 'Scratch that.']);
      expect(refined(dropped.take, dropped.heard, baseBody: '', titled: true), '# Pick up the parcel');
      // The larger model heard the drop and the sentence after it as one phrase.
      final merged = [seg('Scratch that. We need eggs and milk.', 1900, 4000)];
      final after = play(['Pick up the parcel.', 'Call Sam.', 'Scratch that.', 'We need eggs and milk.']);
      expect(
        refinedBody(job(titled: true, skip: after.take.commandSpans, keywordAt: after.take.keywordSpans, live: after.take.segments), [after.heard[0], ...merged]),
        '# Pick up the parcel\n\nWe need eggs and milk.',
      );

      final replaced = play(['Pick up the parcel.', 'The meeting is at three.', 'Actually, the meeting is at four.']);
      expect(refined(replaced.take, replaced.heard, baseBody: '', titled: true), '# Pick up the parcel\n\nThe meeting is at four.');

      final changed = play(['Pick up the parcel.', 'The meeting is at three.', 'No wait, four.']);
      expect(refined(changed.take, changed.heard, baseBody: '', titled: true), '# Pick up the parcel\n\nThe meeting is at four.');
    });

    test('after Undo, keeps the sentence and the opener as words, and leaves the keyword out', () {
      final take = LiveTake(const [MemoryNote(id: 'groceries', body: '# Groceries\n\n- Eggs\n')]);
      final heard = [
        seg('Call Sam.', 0, 900),
        seg('Hey Ghost, scratch that.', 1000, 1900),
      ];
      for (var i = 0; i < heard.length; i += 1) {
        take.phrase(heard[i], i * 1000);
      }
      final chip = take.chips.isEmpty ? null : take.chips.last;
      take.undo(chip is RouteViewTookBack ? chip.undo! : -1);
      take.close(2000);
      expect(take.segments.map((s) => s.text), ['Call Sam.', 'Scratch that.']);
      expect(refined(take, heard, baseBody: '', titled: true), '# Call Sam\n\nScratch that.');
    });

    test('leaves what a one-shot sent to another note out of the take’s own', () {
      final (:take, :heard) = play(['Kevin owns the release.', 'Hey Ghost, add to House TODOs.', 'Call the electrician.', 'Buy fuses.', 'Ring the plumber.', 'Next, the budget review is Friday.']);
      expect(refined(take, heard, baseBody: '', titled: true), '# Kevin owns the release\n\nNext, the budget review is Friday.');
    });
  });
}
