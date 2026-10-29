import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// A job of the app's record as a Live Activity (docs/ACTIVITY.md, OS surfaces): compiled into the app, which starts,
/// moves and ends it (JobsChannel.swift), and into the GhostActivity extension, which draws it on the lock screen and
/// in the Dynamic Island (ios/GhostActivity). What it says is the record's (lib/activity/activity_surfaces.dart
/// `surfaceJob`), nothing more.
@available(iOS 16.1, *)
struct GhostJobAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// "Writing up Standup".
    var title: String
    /// What it does now: "Transcribing", "Waiting for Wi-Fi", or how it ended.
    var line: String
    /// How far, 0 to 1; nil while nobody can say.
    var fraction: Double?
    /// `running`, `waiting`, `queued`, `done` or `failed`.
    var state: String
    /// What it is drawn as: its kind, `needsYou` or `waiting`.
    var look: String
    /// The kind's colour, 0xAARRGGBB on paper and in the dark; nil in Calm (the ink).
    var colour: Int?
    var colourDark: Int?
    /// When it began, for the time it has run.
    var startedAt: Date
  }

  /// The job's id on the record (`write-up:<note>`, `share-audio:<note>`, `summary:<note>`).
  var id: String
  /// Its kind: `audio`, `ai`, …, which is its glyph.
  var kind: String
}
#endif
