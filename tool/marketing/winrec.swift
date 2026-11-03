// Records one window to a movie with ScreenCaptureKit, whether or not it is in front (tool/marketing; Matt,
// 2026-11-02: the marketing video). The window is found by its owning app's bundle id; the movie is the window's
// content at its pixel size, 60 frames a second, no cursor, no shadow.
//
//   swiftc -O tool/marketing/winrec.swift -o build/marketing/winrec
//   build/marketing/winrec <bundle id> <seconds> <out.mov>
import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

let args = CommandLine.arguments
guard args.count == 4, let seconds = Double(args[2]) else {
  print("usage: winrec <bundle id> <seconds> <out.mov>")
  exit(2)
}
let bundle = args[1]
// ScreenCaptureKit needs the window server set up, as an app has it.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let out = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: out)

final class Done: NSObject, SCRecordingOutputDelegate {
  func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { exit(0) }
  func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
    print("recording failed: \(error)")
    exit(1)
  }
}
let done = Done()

Task {
  do {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let window = content.windows.filter({ $0.owningApplication?.bundleIdentifier == bundle && $0.windowLayer == 0 && $0.frame.width > 200 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
      print("no window of \(bundle)")
      exit(1)
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.width = Int(filter.contentRect.width * scale)
    config.height = Int(filter.contentRect.height * scale)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    config.queueDepth = 8
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    let recording = SCRecordingOutputConfiguration()
    recording.outputURL = out
    recording.outputFileType = .mov
    recording.videoCodecType = .hevc
    let output = SCRecordingOutput(configuration: recording, delegate: done)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    print("recording \(config.width)x\(config.height) for \(seconds)s")
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    try await stream.stopCapture()
    try await Task.sleep(nanoseconds: 3_000_000_000)
    exit(0)
  } catch {
    print("error: \(error)")
    exit(1)
  }
}
RunLoop.main.run()
