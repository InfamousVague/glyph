import 'dart:io' show Platform;

/// Where there is `dart:io` (lib/platform_info.dart): `Platform`'s own answers, each handed on as it is. The one file
/// in lib/ that asks `Platform`.
abstract final class PlatformInfo {
  /// Running in a browser: never, here.
  static const bool isWeb = false;

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;

  static String get operatingSystem => Platform.operatingSystem;
  static String get operatingSystemVersion => Platform.operatingSystemVersion;
  static String get localHostname => Platform.localHostname;
  static int get numberOfProcessors => Platform.numberOfProcessors;
  static String get pathSeparator => Platform.pathSeparator;
  static Map<String, String> get environment => Platform.environment;
  static String get resolvedExecutable => Platform.resolvedExecutable;
}
