import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// What the app asks of iOS (DeskChannels.swift): kept for as long as the app runs.
  private var desk: DeskChannels?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // What a previous run left of videos and recordings goes first (DeskVideo.swift).
    DeskVideo.sweep()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GhostMessaging") else { return }
    let messenger = registrar.messenger()
    desk = DeskChannels(messenger: messenger)
    // The microphone's processing in calls (VoiceFx.swift).
    VoiceFx.shared.register(messenger: messenger)
  }
}
