/// A tape's geometry, kept apart from its drawing so it can be tested. A port of `src/app/capture/tape.ts`.
///
/// What differs: nothing of its own. The port was already made, whole, beside the drawing it serves
/// (`lib/tapes/tape.dart`: `tapeMs`, `hubR`, `packMinR`, `packMaxR`, `reelY`, `leftX`, `rightX`, `packRadii`,
/// `reelTurn`, `counter`), so this library is that one under the name the capture files look for, and nothing is
/// written twice. The web's `Packs` is a record there, `({double supply, double takeup})`.
library;

export '../tapes/tape.dart';
