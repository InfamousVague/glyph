/// The motor under the editor: `fireFelt` and `fireMicroTick` of the web's `core/haptics.ts`, which feel.dart is
/// handed.
///
/// Every haptic the editor makes of its own accord comes through here and is held to one every 28 ms: typing is
/// the worst case there is for a motor (`**bold**` alone offers several moments inside a second), and a flood is
/// played back as mush. 28 ms is the web app's floor, AttackFM's before it.
///
/// What differs: the web's micro tick is the Taptic Engine's `soft` impact, which Flutter's services do not name;
/// here it is the selection click, the lightest thing a phone says.
library;

import 'package:glacier/glacier.dart';

import '../commands/feel.dart';
import '../state/state.dart';

const int _floorMs = 28;
int _lastFireAt = -_floorMs;
final Stopwatch _clock = Stopwatch()..start();

HapticKind? _kind(String name) {
  for (final kind in HapticKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// A haptic of the kit's vocabulary, by name, unless one fired within the floor.
void fireFelt([String kind = 'light']) {
  final at = _clock.elapsedMilliseconds;
  if (at - _lastFireAt < _floorMs) return;
  _lastFireAt = at;
  final known = _kind(kind);
  if (known != null) fireMotor(known);
}

/// The tier below the kit's kinds: texture rather than news (a list continuing itself).
void fireMicroTick() {
  final at = _clock.elapsedMilliseconds;
  if (at - _lastFireAt < _floorMs) return;
  _lastFireAt = at;
  fireMotor(HapticKind.selection);
}

/// What a transaction is worth to the hand (feel.dart), fired. Not asked at all while the motor is off: the answer
/// reads the syntax tree either side of the change, and nothing would be done with it.
void feel(Transaction tr) {
  if (!hapticsEnabled()) return;
  feelTransaction(tr, fireFelt: fireFelt, fireMicroTick: fireMicroTick);
}
