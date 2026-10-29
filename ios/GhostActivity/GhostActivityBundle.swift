import SwiftUI
import WidgetKit

/// The iPhone app's widget extension: its Live Activities (GhostJobLiveActivity.swift), the app's running work on the
/// lock screen and in the Dynamic Island (docs/ACTIVITY.md, OS surfaces). It draws what the app started
/// (ios/Runner/JobsChannel.swift) and reads nothing of the app's own: no App Group, no files, no network.
@main
struct GhostActivityBundle: WidgetBundle {
  var body: some Widget {
    GhostJobLiveActivity()
  }
}
