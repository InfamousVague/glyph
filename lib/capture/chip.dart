/// What the chip at the foot of the recorder looks like, and how long it stays. A port of
/// `src/app/capture/chip.ts`.
///
/// The chip says where the words are going while a command is heard, and what came of it. It takes one of three
/// looks: outlined with dots while a note is being named or a command worked out, filled with a tick once something
/// has landed, dashed when a name matched no note. Pure, so each of the chip's views (capture/take_host.dart
/// `RouteView`) is a test.
///
/// What differs: nothing. `chipPhase` still answers the look as the web's word, since that word is a style's name.
library;

import 'command.dart' show findKeyword;
import 'take_host.dart';

/// The look a chip takes: still hearing, landed (`moved`), missed, taken back (its own: filled, with Undo and no
/// tick), or its own phase where that is one of them already.
String chipPhase(RouteView route) => switch (route) {
  RouteViewCommand() => 'hearing',
  RouteViewSaid() => 'missed',
  RouteViewDone() => 'moved',
  _ => route.phase,
};

/// How long a settled chip stays before it goes, or null for one still under way (a name being heard, a command
/// being said), which stays until the recorder says more. Words to read - a sentence said back, the items that
/// landed - stay longer than a tick, and a take-back with its Undo longer still, a second short of the reader's
/// window (live_route.dart `liveTiming.takeBackMs`), so a button drawn is a button that works.
int? lingerMs(RouteView? route) => switch (route) {
  null => null,
  RouteViewTookBack() => 4000,
  RouteViewAdded() || RouteViewSaid() => 3200,
  RouteViewMoved() || RouteViewMissed() || RouteViewDone() => 2200,
  RouteViewHearing() || RouteViewCommand() || RouteViewWaiting() => null,
};

/// The words of a command still being said, with the keyword taken off if it is in them.
String partialCommand(String text) => (findKeyword(text)?.after ?? text).trim();
