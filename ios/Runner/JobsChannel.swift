import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// The iPhone's half of `ghost_md/jobs` (lib/core/background_jobs.dart): the app's running work as Live Activities
/// (docs/ACTIVITY.md, OS surfaces; Matt, 2026-10-29: "iPhone Live Activities (Dynamic Island, lock screen) for
/// write-ups and uploads"). The record tells it (lib/activity/activity_surfaces.dart):
///
/// - `activityLook {calm}`, the app's first word as it starts: what an earlier run of the app left is ended (a Live
///   Activity outlives the app).
/// - `activity {event, job, jobs}`: a write-up, a summary or a recording's upload begun is a Live Activity started;
///   moved, it is moved; ended, it ends, showing how it ended for a while where it made something or failed, and at
///   once where it went quietly. One the app no longer says ends at once.
///
/// The extension (ios/GhostActivity) draws them: the job's glyph in its kind's colour, its title, what it does now,
/// a bar or the time it has run. A tap opens the app (`ghostmd://activity?id=…`, which GhostChannels.swift hands
/// here) and the job's own Open, said back as `activityOpen`. Live Activities need iOS 16.2; on an older iPhone, and
/// where the person turned them off for the app, nothing shows and nothing breaks.
///
/// The phone's foreground service and the Mac's App Nap (`running`, `ended`) have no half here: an iPhone app is not
/// kept running behind others.
final class JobsChannel {
  private let channel: FlutterMethodChannel
  private var live: AnyObject?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ghost_md/jobs", binaryMessenger: messenger)
    #if canImport(ActivityKit)
    if #available(iOS 16.2, *) { live = LiveActivities() }
    #endif
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "activity", "activityLook":
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *), let live = self?.live as? LiveActivities {
          live.told(call.method, call.arguments as? [String: Any])
        }
        #endif
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// A Live Activity tapped (`ghostmd://activity?id=…`): its job's Open, said to the app. False for any other link.
  func opened(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "ghostmd", url.host == "activity" else { return false }
    if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
      channel.invokeMethod("activityOpen", arguments: ["id": id])
    }
    return true
  }
}

#if canImport(ActivityKit)
/// The Live Activities the app has running, by job id.
@available(iOS 16.2, *)
private final class LiveActivities {
  private var running: [String: Activity<GhostJobAttributes>] = [:]
  private var swept = false

  func told(_ method: String, _ args: [String: Any]?) {
    if method == "activityLook" {
      if !swept {
        swept = true
        // What an earlier run of the app left: its jobs went with it.
        for left in Activity<GhostJobAttributes>.activities where running[left.attributes.id] == nil {
          Task { await left.end(nil, dismissalPolicy: .immediate) }
        }
      }
      return
    }
    let event = args?["event"] as? String ?? "changed"
    let job = args?["job"] as? [String: Any]
    let told = Set((args?["jobs"] as? [Any] ?? []).compactMap { ($0 as? [String: Any])?["id"] as? String })
    let id = job?["id"] as? String
    for (other, activity) in running where !told.contains(other) && other != id {
      running[other] = nil
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    guard let job = job, let id = id else { return }
    let state = LiveActivities.state(job)
    if event == "ended" {
      guard let activity = running.removeValue(forKey: id) else { return }
      // What it made, or why it failed, stays a while on the lock screen; one that went quietly goes now.
      let says = job["result"] != nil || state.state == "failed"
      Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: says ? .after(Date().addingTimeInterval(15 * 60)) : .immediate) }
      return
    }
    if let activity = running[id] {
      Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
      return
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      let attributes = GhostJobAttributes(id: id, kind: job["kind"] as? String ?? "sync")
      running[id] = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    } catch {
      // Too many at once, or the app not in front: the job runs anyway, and the app's own ring says it.
      NSLog("[ghost] no Live Activity for %@: %@", id, error.localizedDescription)
    }
  }

  static func state(_ job: [String: Any]) -> GhostJobAttributes.ContentState {
    let state = job["state"] as? String ?? "running"
    let ended = state == "done" ? job["result"] as? String : state == "failed" ? job["cause"] as? String : nil
    let started = (job["startedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? Date()
    return GhostJobAttributes.ContentState(
      title: job["title"] as? String ?? "Ghost.md",
      line: ended ?? job["line"] as? String ?? "",
      fraction: state == "done" ? 1 : (job["fraction"] as? NSNumber)?.doubleValue,
      state: state,
      look: job["look"] as? String ?? "sync",
      colour: (job["colour"] as? NSNumber)?.intValue,
      colourDark: (job["colourDark"] as? NSNumber)?.intValue,
      startedAt: started
    )
  }
}
#endif
