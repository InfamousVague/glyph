/// The notes live with another device right now (docs/LIVE.md, "Living with the pass sync"). A port of
/// `src/app/core/live/shared.ts`.
///
/// The pass sync leaves such a note alone: two people typing hold words that differ by a few characters in flight
/// at every instant, and a pass in the middle would take the difference for a conflict and split the note. Kept
/// apart from the sessions, with no document in it, so the pass sync can ask without live sync being there at all.
///
/// What differs: the page's module set is a [SharedLive] made once with the account (lib/root/live_wiring.dart)
/// and handed to the hub and to the pass.
library;

/// Which notes are live with another device.
class SharedLive {
  final Set<String> _shared = {};

  /// `markShared`.
  void mark(String noteId, bool on) {
    if (on) {
      _shared.add(noteId);
    } else {
      _shared.remove(noteId);
    }
  }

  /// `isSharedLive`.
  bool isShared(String noteId) => _shared.contains(noteId);
}
