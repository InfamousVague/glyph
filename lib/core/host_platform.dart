/// `dart:io`'s [Platform], or in the web build the browser's stand-in for it (docs/WEB.md).
///
/// Matt, 2026-10-26: "update the web version of the app it's very behind". The web build is this app compiled to
/// WebAssembly, where `dart:io` still compiles and every `Platform` getter throws the moment it is read: the Mac
/// app's own test (`runsAsMacApp`) stopped the page before its first frame. So the files that ask which device
/// they are on import [Platform] from here, and hide `dart:io`'s. On a phone and a Mac this IS `dart:io`'s, the
/// one export; in a browser it is host_platform_web.dart's, which answers as a device that is none of them.
library;

export 'host_platform_io.dart' if (dart.library.js_interop) 'host_platform_web.dart';
