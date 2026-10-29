import ActivityKit
import SwiftUI
import WidgetKit

/// A job of the app's record as a Live Activity (ios/Runner/GhostJobAttributes.swift): a meeting's write-up, a
/// summary, a recording's upload.
///
/// - **Lock screen**: the job's glyph on a disc of its kind's colour, its title, what it does now, and a bar where it
///   says how far (or the time it has run where it cannot).
/// - **Dynamic Island**: compact, the glyph and how far ("40%", or the time); minimal, the glyph in a ring filling
///   as far as it is; expanded, the glyph, the title, how far, and what it does now over a bar.
///
/// Its glyphs are the SF Symbols nearest the tray's (lib/activity/activity_look.dart): reels for audio, the sparkle
/// for writing, and so on; its colours the ring's (`--activity-*`), or the ink in Calm. A tap opens the app at the
/// job (`ghostmd://activity?id=…`).
struct GhostJobLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GhostJobAttributes.self) { context in
      LockScreenJob(attributes: context.attributes, state: context.state)
        .widgetURL(link(context.attributes))
    } dynamicIsland: { context in
      let state = context.state
      let colour = JobLook.colour(state, dark: true)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          JobGlyph(kind: context.attributes.kind, state: state, size: 22)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          HowFar(state: state)
            .font(.title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(colour)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(state.title)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(state.line)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            if let fraction = state.fraction {
              ProgressView(value: min(max(fraction, 0), 1))
                .tint(colour)
            }
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        JobGlyph(kind: context.attributes.kind, state: state, size: 16)
      } compactTrailing: {
        HowFar(state: state)
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(colour)
          .frame(maxWidth: 44)
      } minimal: {
        ZStack {
          if let fraction = state.fraction {
            ProgressView(value: min(max(fraction, 0), 1))
              .progressViewStyle(.circular)
              .tint(colour)
          }
          JobGlyph(kind: context.attributes.kind, state: state, size: state.fraction == nil ? 15 : 10)
        }
      }
      .widgetURL(link(context.attributes))
      .keylineTint(colour)
    }
  }

  private func link(_ attributes: GhostJobAttributes) -> URL? {
    var parts = URLComponents()
    parts.scheme = "ghostmd"
    parts.host = "activity"
    parts.queryItems = [URLQueryItem(name: "id", value: attributes.id)]
    return parts.url
  }
}

/// The lock screen's banner.
private struct LockScreenJob: View {
  let attributes: GhostJobAttributes
  let state: GhostJobAttributes.ContentState
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let colour = JobLook.colour(state, dark: scheme == .dark)
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        Circle().fill(colour.opacity(0.18))
        JobGlyph(kind: attributes.kind, state: state, size: 20)
      }
      .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(state.title)
          .font(.headline)
          .lineLimit(1)
        Text(state.line)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if let fraction = state.fraction, state.state != "failed" {
          ProgressView(value: min(max(fraction, 0), 1))
            .tint(colour)
            .padding(.top, 2)
        }
      }
      Spacer(minLength: 4)
      HowFar(state: state)
        .font(.title3.monospacedDigit().weight(.semibold))
        .foregroundStyle(colour)
    }
    .padding(16)
  }
}

/// How far, in a few letters: "40%", the time it has run where it cannot say, a tick once done.
private struct HowFar: View {
  let state: GhostJobAttributes.ContentState

  var body: some View {
    switch state.state {
    case "done":
      Image(systemName: "checkmark")
    case "failed":
      Image(systemName: "exclamationmark")
    case "waiting", "queued":
      Image(systemName: "pause.fill")
    default:
      if let fraction = state.fraction {
        Text("\(Int((min(max(fraction, 0), 1) * 100).rounded()))%")
      } else {
        Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
          .multilineTextAlignment(.trailing)
      }
    }
  }
}

/// A job's glyph in its colour, dimmed while it waits.
private struct JobGlyph: View {
  let kind: String
  let state: GhostJobAttributes.ContentState
  let size: CGFloat
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    Image(systemName: JobLook.symbol(state.state == "failed" ? "needsYou" : state.state == "done" ? "done" : kind))
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(JobLook.colour(state, dark: scheme == .dark))
      .opacity(state.look == "waiting" ? 0.5 : 1)
  }
}

private enum JobLook {
  /// The SF Symbol nearest each kind's glyph in the tray (lib/activity/activity_look.dart).
  static func symbol(_ kind: String) -> String {
    switch kind {
    case "sync": return "arrow.triangle.2.circlepath"
    case "ai": return "sparkles"
    case "images": return "paintbrush.pointed"
    case "audio": return "recordingtape"
    case "meetings": return "person.2"
    case "downloads": return "arrow.down.circle"
    case "needsYou": return "exclamationmark.circle.fill"
    case "done": return "checkmark.circle.fill"
    default: return "circle.dashed"
    }
  }

  /// The kind's colour as the app told it, or the ink (Calm).
  static func colour(_ state: GhostJobAttributes.ContentState, dark: Bool) -> Color {
    guard let argb = (dark ? state.colourDark ?? state.colour : state.colour) else { return .primary }
    let value = UInt32(truncatingIfNeeded: argb)
    return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: Double((value >> 24) & 0xFF) / 255)
  }
}
