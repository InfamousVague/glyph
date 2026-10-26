/// host_platform.dart's in a browser: a [Platform] that is no phone, no Mac, no Windows and no Linux, with no
/// environment and `/` between a path's parts, so every `Platform.isAndroid ||` in the app reads false where
/// `dart:io`'s would throw. What the page does that a device would not is the web build's own (lib/web,
/// docs/WEB.md); where it shows which browser it is in, `defaultTargetPlatform` says, as Flutter reads the agent.
library;

abstract final class Platform {
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isFuchsia = false;

  /// No variables: a page is started by nobody's shell.
  static const Map<String, String> environment = <String, String>{};

  static const String pathSeparator = '/';
  static const String resolvedExecutable = '';
  static const String operatingSystem = 'web';
  static const String operatingSystemVersion = '';
  static const String version = '';

  /// One: the page draws on the thread it has, and the worker is the core's (web/core/ghost_core_worker.js).
  static const int numberOfProcessors = 1;
}
