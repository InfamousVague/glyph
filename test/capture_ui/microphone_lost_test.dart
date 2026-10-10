import 'package:flutter_test/flutter_test.dart';

import '../support/render.dart';
import 'support/harness.dart';

/// The recorder when its microphone closes without being asked to (docs/PARITY.md, Differs 6): nothing more will be
/// heard, so the take is saved as Done would save it, which is what the screen going off does. Before, the phone
/// closed the device whenever the app left the screen and nothing was told: the recorder stayed up, counting, and
/// what was said after coming back was lost.
void main() {
  setUpAll(loadAppFonts);

  const house = '# House TODOs\n\n- [ ] Fix the gutter\n';

  testWidgets('keeps what was heard, in the note it was going to, and ends', (tester) async {
    final capture = Capture(tester)
      ..microphone = true
      ..stopSays(null);
    capture.notes.create('house', house);
    await capture.open();
    await capture.say('Hey Ghost, add call Sam to House TODOs.', 0);
    expect(capture.finished, isEmpty);

    capture.micLost.complete('error');
    await capture.untilFinished();
    expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    expect(capture.stops, hasLength(1), reason: 'stopped as Done stops it, once');
    expect(capture.cancels, 0, reason: 'never discarded');
    await capture.close();
  });

  testWidgets('a new note is kept with the words said before it closed', (tester) async {
    final capture = Capture(tester)
      ..microphone = true
      ..stopSays(null);
    await capture.open();
    await capture.say('Buy oat milk on the way home.', 0);
    capture.micLost.complete('background');
    await capture.untilFinished();
    expect(capture.notes.bodies.single, contains('Buy oat milk on the way home.'));
    await capture.close();
  });

  testWidgets('goes on recording while the microphone is there: nothing ends a take that was not asked to', (tester) async {
    final capture = Capture(tester)
      ..microphone = true
      ..stopSays(null);
    await capture.open();
    await capture.say('Still here.', 0);
    await tester.pump(const Duration(seconds: 3));
    expect(capture.finished, isEmpty);
    expect(capture.stops, isEmpty);
    await capture.doneAndFinished();
    // Closed by the recorder itself as it ended: not a loss, and nothing is saved twice.
    expect(capture.stops, hasLength(1));
    await capture.close();
  });
}
