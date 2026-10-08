import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/take.dart';
import 'package:ghost_md/capture/take_types.dart';

import 'support/take_host.dart';

/// The take (lib/capture/take.dart): carrying on in another note. Case for case with the web's
/// `capture/take.test.ts`.

void main() {
  group('carrying on in another note', () {
    test('starts the take afresh, and marks what it had said as commands for the better words to leave out', () {
      var changes = 0;
      final take = Take<TakeNote>(quietHost<TakeNote>(changed: () => changes += 1));
      take.listen(const Segment(text: 'For the soup.', startMs: 0, endMs: 900));
      take.listen(const Segment(text: 'Leeks and stock.', startMs: 1200, endMs: 2400));
      final before = changes;
      take.fork();
      expect(take.segments, <Segment>[]);
      expect(take.hasContent, false);
      expect(take.commandSpans, const [Span(startMs: 0, endMs: 900), Span(startMs: 1200, endMs: 2400)]);
      // The page is told, so the words said for the last note leave this one.
      expect(changes, before + 1);
      take.listen(const Segment(text: 'Call Sam.', startMs: 3000, endMs: 3900));
      expect(take.markdown(titled: true), '# Call Sam');
    });
  });
}
