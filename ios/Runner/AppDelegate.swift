import Flutter
import UIKit

/// The iPhone app's delegate: the engine Flutter makes for the storyboard's one view, and the iPhone's half of the
/// app's channels attached to it (GhostChannels.swift), before the first Dart runs.
///
/// Links that open the app (`ghostmd://…`, claimed in Info.plist as the real iPhone app claims it) come to the
/// scene, not here: an app with a scene delegate is handed them there, and Flutter's passes them to whoever asked
/// to hear the scene (`addSceneDelegate`), which is the channels.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channels: GhostChannels?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channels = GhostChannels(messenger: engineBridge.applicationRegistrar.messenger())
    engineBridge.pluginRegistry.registrar(forPlugin: "GhostLinks")?.addSceneDelegate(channels)
    self.channels = channels
  }
}
