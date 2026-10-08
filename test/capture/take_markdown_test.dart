import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/take.dart';
import 'package:ghost_md/capture/take_types.dart';

import 'support/take_host.dart';

/// A take as markdown (lib/capture/take.dart `takeMarkdown`): the one way the page it is spoken onto and the note
/// saved at Done are made from it, so the two cannot disagree. Case for case with the web's
/// `capture/takeMarkdown.test.ts`.

Segment said(String text, int startMs) => Segment(text: text, startMs: startMs, endMs: startMs + 900);

void main() {
  group('a take’s markdown', () {
    test('lays the words out by their cues, with the phrase still being guessed after them and marked as pending', () {
      final shown = takeMarkdown([said('Grocery run.', 0), said('Bullet point, eggs.', 1000)], titled: true, partial: 'and milk');
      expect(shown.markdown, '# Grocery run\n\n- Eggs\n\nand milk');
      expect(shown.pendingFrom, shown.markdown.indexOf('and milk'));
    });

    test('keeps an opening sentence as a sentence when the words go on the end of a note that has a title', () {
      expect(takeMarkdown([said('Grocery run.', 0)], titled: false).markdown, 'Grocery run.');
    });
  });

  group('what a take has to save', () {
    test('is words that come to something', () {
      final take = Take<TakeNote>(quietHost());
      expect(take.hasContent, false);
      take.listen(said('Hello.', 0));
      expect(take.hasContent, true);
    });

    test('is not a cue said on its own, which is held for a sentence that never comes', () {
      final take = Take<TakeNote>(quietHost());
      take.listen(said('Bullet point.', 0));
      expect(take.segments, hasLength(1));
      expect(take.hasContent, false);
    });
  });
}
