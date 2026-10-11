import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/shell/phone_tour.dart';

/// The iPhone's tour reads its script as the Mac's does: steps between semicolons, a name and what follows its
/// first colon. The walking itself is a debug build's, in the simulator (tool/ios-tour.sh).
void main() {
  test('a script is its steps, each a name and what follows the colon', () {
    expect(tourSteps('wait:6000; shot:home ;taplabel:Write a note;type:Theme: Light;enter;;swipe:60,400,330,400,200'), [
      (name: 'wait', arg: '6000'),
      (name: 'shot', arg: 'home'),
      (name: 'taplabel', arg: 'Write a note'),
      // Only the first colon divides: the words typed may hold one.
      (name: 'type', arg: 'Theme: Light'),
      (name: 'enter', arg: ''),
      (name: 'swipe', arg: '60,400,330,400,200'),
    ]);
    expect(tourSteps('  '), isEmpty);
  });

  test('nothing runs outside a debug build of the iPhone app', () async {
    // A test is neither an iPhone nor its simulator: it returns at once, with no file looked for.
    await runPhoneTour();
  });
}
