// The model's output, read into answers. A port of src/app/ai/fills/read.test.ts, case for case, and `readAsks`,
// which the page tests through its lane.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/read.dart';

void main() {
  group('the model’s output, read into answers', () {
    test('reads [N] lines by blank', () {
      final read = readFill('[1] Kazuo Ishiguro\n[2] 1989', [1, 2]);
      expect(read[1], ['Kazuo Ishiguro']);
      expect(read[2], ['1989']);
    });

    test('reads a repeated number as an items blank’s items, and passes over a number not asked', () {
      final read = readFill('[1] Rail pass\n[1] Walking shoes\n[4] Nonsense\n[1] Cash in yen', [1]);
      expect(read[1], ['Rail pass', 'Walking shoes', 'Cash in yen']);
      expect(read.containsKey(4), isFalse);
    });

    test('never reads a note’s own numbered list as an answer', () {
      final read = readFill('3. Rail pass\n[1] Rail pass', [1, 2]);
      expect(read[1], ['Rail pass']);
      expect(read[2], isEmpty);
      expect(readFill('1. Passport\n2. Plug adapter\n3. Rail pass', [1, 2, 3])[3], isEmpty);
    });

    test('reads a bare answer when one blank was asked', () {
      expect(readFill('Canberra', [1])[1], ['Canberra']);
      expect(readFill('Rail pass\nWalking shoes', [1])[1], ['Rail pass', 'Walking shoes']);
      expect(readFill('Canberra', [1, 2])[1], isEmpty);
    });

    test('says whether every line was an [N] line for an asked blank', () {
      expect(allNumbered('[1] a\n[2] b', [1, 2]), isTrue);
      expect(allNumbered('[1] a\nb', [1]), isFalse);
      expect(allNumbered('[3] a', [1, 2]), isFalse);
    });
  });

  group('what the port adds', () {
    test('each ask’s lines by the numbers it was written with, and a bare answer for one ask', () {
      expect(
        readAsks('[1] Rail pass\n[3] Lima\n[2] Walking shoes\n[9] Nonsense', [
          [1, 2],
          [3],
        ]),
        [
          ['Rail pass', 'Walking shoes'],
          ['Lima'],
        ],
      );
      expect(
        readAsks(' Rail pass \n\nWalking shoes', [
          [1, 2, 3],
        ]),
        [
          ['Rail pass', 'Walking shoes'],
        ],
      );
      expect(readAsks('Canberra', [[1], [2]]), [<String>[], <String>[]]);
      expect(readFill('[1] Canberra\r\n[2]  Lima \r\n', [1, 2]), {
        1: ['Canberra'],
        2: ['Lima'],
      });
    });
  });
}
