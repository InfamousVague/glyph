// A port of src/app/ai/marks.test.ts, case for case.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/marks.dart';
import 'package:ghost_md/core/stored.dart';

void main() {
  setUp(() => useStored(MemoryStored()));

  group('the marks kept with a note', () {
    const change = AiChange(id: 'c', runId: 'r', from: 0, to: 3, removed: '', block: true);

    test('come back for the same body and not for another', () {
      saveMarks('n', 'abc\n', [change]);
      expect(hasMarks('n'), isTrue);
      expect(loadMarks('n', 'abc\n'), [change]);
      expect(loadMarks('n', 'abd\n'), isNull);
      expect(loadMarks('other', 'abc\n'), isNull);
    });

    test('go when there are none left, and with the note', () {
      saveMarks('n', 'abc\n', [change]);
      saveMarks('n', 'abc\n', []);
      expect(hasMarks('n'), isFalse);
      saveMarks('n', 'abc\n', [change]);
      forgetMarks('n');
      expect(hasMarks('n'), isFalse);
    });
  });
}
