import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/take.dart';
import 'package:ghost_md/capture/take_host.dart';
import 'package:ghost_md/capture/take_types.dart';

import 'support/take_host.dart';

/// The host a recorder hands its take (lib/capture/take_host.dart `hostThrough`): always the newest render's. Case
/// for case with the web's `capture/takeHost.test.ts`.

void main() {
  group('a host through a ref', () {
    test('reaches whichever host the ref holds when the take asks, not the one it held when the take was made', () {
      var first = 0;
      var second = 0;
      final ref = TakeHostRef<TakeNote>(quietHost(changed: () => first += 1));
      final take = Take(hostThrough(ref));
      take.listen(const Segment(text: 'One.', startMs: 0, endMs: 500));
      ref.current = quietHost(changed: () => second += 1);
      take.listen(const Segment(text: 'Two.', startMs: 600, endMs: 900));
      expect(first, 1);
      expect(second, 1);
    });
  });
}
