/// Which tapes' audio is on this device, as Settings › Recording's Tapes card counts them: what the page's `Tapes`
/// kept as `elsewhere` (src/app/settings/RecordingPane.tsx), with the effect that filled it. A tape is counted
/// unless its audio was removed here by the row itself, or its file says it is not on this device, which is a
/// synced note whose audio stayed on the device that made it.
///
/// What differs: the page asked the `rec` scheme with a HEAD for each file and read a 404 (tapes/useTape.ts
/// `headStatus`); here the asking is a seam, which the app gives as its player's (lib/tapes/player.dart
/// `TapePlayer.onDevice`, the phone's file itself in TapePlayer.kt). The page asked only where a HEAD read nothing
/// (native generation 20); the phone's answer never reads the file, so it is asked wherever there is one to ask.
/// And the card's state is held by whoever holds the notes, the app's root, since Settings is handed its sums
/// (lib/settings/panes/settings_host.dart `SettingsFeatures.tapes`) and not the notes.
library;

import '../core/note.dart';
import '../tapes/player.dart' show audioRemoved;
import 'tapes.dart';

class TapesHere {
  TapesHere(this._onDevice);

  /// Whether a note's recording is a file on this device: false is the page's 404, null is not knowing. Null where
  /// nothing can say, and then every tape not removed here is counted.
  final Future<bool?> Function(String noteId)? _onDevice;

  /// Tapes whose file said it is not on this device (`elsewhere`).
  Set<String> _elsewhere = const {};

  /// Asks each tape among [notes] whether its audio is on this device, all at once, as the card is put up. A tape
  /// the row removed the audio of is not asked, and one that cannot be asked is taken to be here.
  Future<void> ask(Iterable<Note> notes) async {
    final onDevice = _onDevice;
    if (onDevice == null) return;
    final answers = await Future.wait([
      for (final note in tapesHere(notes, audioRemoved))
        Future<bool?>.sync(() => onDevice(note.id)).then<(String, bool?)>((here) => (note.id, here), onError: (Object _) => (note.id, null)),
    ]);
    _elsewhere = {
      for (final (id, here) in answers)
        if (here == false) id,
    };
  }

  /// Only the tapes whose audio is here: not one the row removed, nor one whose file says it is elsewhere (`taped`).
  List<Note> here(Iterable<Note> notes) => tapesHere(notes, (id) => audioRemoved(id) || _elsewhere.contains(id));
}
